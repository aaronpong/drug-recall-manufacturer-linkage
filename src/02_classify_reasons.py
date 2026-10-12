import argparse
import json

import anthropic
from dotenv import load_dotenv
from sqlalchemy import text

from db import get_engine

load_dotenv()

MODEL = "claude-haiku-5-5"
PROMPT_VERSION = "v2"
BATCH_SIZE = 25       # reasons per API call
MAX_CHARS = 600        # trim very long reason text

CATEGORIES = {
    "sterility_assurance": "Lack of sterility assurance or failed sterility testing for products that must be sterile",
    "microbial_contamination": "Bacteria, mold, yeast, or other microbes found in the product",
    "chemical_contamination": "Impurities, degradation products, nitrosamines, benzene, or other chemical contaminants",
    "particulate_foreign_matter": "Visible particles, glass, metal, fibers, or other foreign material in the product",
    "potency_dissolution": "Subpotent or superpotent drug, failed dissolution, content uniformity, or tablet/capsule specifications",
    "labeling_packaging": "Label mix-ups, missing or wrong label information, or defective containers and packaging",
    "cgmp_manufacturing": "Current Good Manufacturing Practice (CGMP) deviations or manufacturing process problems not covered above",
    "unapproved_or_undeclared": "Marketed without FDA approval, or contains undeclared drug ingredients",
    "storage_stability": "Temperature excursions, improper storage, or failed stability testing",
        "cross_contamination": "Contaminated with a different drug or product, such as penicillin, hormones, or other products made on shared equipment",
    "other": "Does not fit any category above",
}

SYSTEM_PROMPT = (
    "You classify FDA drug recall reasons into exactly one category.\n\n"
    "Categories:\n"
    + "\n".join(f"- {name}: {desc}" for name, desc in CATEGORIES.items())
    + "\n\nRules:\n"
    "- Pick the single category that best describes the main reason for the recall.\n"
    "- Use 'other' only if nothing else fits.\n"
    "- Many reasons start with a general heading like 'CGMP Deviations:' or 'Labeling:'. "
    "When a specific problem is described after the heading, classify by that problem.\n"
    "- confidence must be 'high', 'medium', or 'low'.\n"
    "- Respond with only a JSON array and no other text. Each item must be "
    '{"id": <id>, "category": <category>, "confidence": <confidence>}.'
)


def fetch_unclassified(engine, limit):
    """Distinct reasons not yet classified, most common first."""
    sql = text("""
        SELECT md5(reason_for_recall) AS reason_hash,
               reason_for_recall,
               COUNT(*) AS n_recalls
        FROM clean.recalls
        WHERE md5(reason_for_recall) NOT IN (SELECT reason_hash FROM llm.reason_categories)
        GROUP BY reason_for_recall
        ORDER BY n_recalls DESC
        LIMIT :limit
    """)
    with engine.connect() as conn:
        return conn.execute(sql, {"limit": limit}).mappings().all()


def classify_batch(client, batch):
    items = [{"id": i, "text": row["reason_for_recall"][:MAX_CHARS]}
             for i, row in enumerate(batch)]
    msg = client.messages.create(
        model=MODEL,
        max_tokens=4000,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": json.dumps(items)}],
    )
    # The response can include a thinking block first, so find the text block
    text_blocks = [b.text for b in msg.content if b.type == "text"]
    if not text_blocks:
        raise ValueError(f"no text block in response (stop_reason={msg.stop_reason})")
    raw = text_blocks[0]
    start, end = raw.find("["), raw.rfind("]")   # ignore anything outside the JSON array
    return json.loads(raw[start:end + 1])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None,
                        help="Only classify this many reasons (for testing)")
    args = parser.parse_args()

    engine = get_engine()
    client = anthropic.Anthropic()   # reads ANTHROPIC_API_KEY from .env

    rows = fetch_unclassified(engine, args.limit)
    print(f"Reasons to classify: {len(rows):,}")

    insert_sql = text("""
        INSERT INTO llm.reason_categories
            (reason_hash, reason_text, category, confidence, model, prompt_version)
        VALUES
            (:reason_hash, :reason_text, :category, :confidence, :model, :prompt_version)
        ON CONFLICT (reason_hash) DO NOTHING
    """)

    saved, skipped = 0, 0
    for start in range(0, len(rows), BATCH_SIZE):
        batch = rows[start:start + BATCH_SIZE]
        try:
            results = classify_batch(client, batch)
        except (anthropic.APIError, ValueError) as e:
            print(f"  Batch at {start} failed ({e}). It will be retried next run.")
            skipped += len(batch)
            continue

        # Keep only valid answers: real id, known category, valid confidence
        valid = {}
        for item in results:
            i = item.get("id")
            if (isinstance(i, int) and 0 <= i < len(batch)
                    and item.get("category") in CATEGORIES
                    and item.get("confidence") in ("high", "medium", "low")):
                valid[i] = {
                    "reason_hash": batch[i]["reason_hash"],
                    "reason_text": batch[i]["reason_for_recall"],
                    "category": item["category"],
                    "confidence": item["confidence"],
                    "model": MODEL,
                    "prompt_version": PROMPT_VERSION,
                }

        if valid:
            with engine.begin() as conn:
                conn.execute(insert_sql, list(valid.values()))
        saved += len(valid)
        skipped += len(batch) - len(valid)
        print(f"  {min(start + BATCH_SIZE, len(rows)):,} / {len(rows):,} processed")

    print(f"\nSaved: {saved:,}   Skipped (retried next run): {skipped:,}")


if __name__ == "__main__":
    main()
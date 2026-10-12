import json
import zipfile
from pathlib import Path

import pandas as pd
import requests
from sqlalchemy import text
from sqlalchemy.dialects.postgresql import JSONB

from db import get_engine

RAW_DIR = Path("data/raw")
RAW_DIR.mkdir(parents=True, exist_ok=True)

TEXT_COLUMNS = [
    "recall_number", "event_id", "recalling_firm", "product_description",
    "reason_for_recall", "classification", "status", "voluntary_mandated",
    "recall_initiation_date", "report_date", "termination_date",
    "city", "state", "country", "distribution_pattern",
    "product_quantity", "code_info",
]


def get_partition_urls():
    """Ask openFDA where the current bulk files for drug recalls are."""
    r = requests.get("https://api.fda.gov/download.json", timeout=60)
    r.raise_for_status()
    parts = r.json()["results"]["drug"]["enforcement"]["partitions"]
    return [p["file"] for p in parts]


def download(url):
    """Download a zip file once and reuse it on later runs."""
    dest = RAW_DIR / url.split("/")[-1]
    if not dest.exists():
        print("Downloading", url)
        r = requests.get(url, timeout=300)
        r.raise_for_status()
        dest.write_bytes(r.content)
    return dest


def read_records(zip_path):
    with zipfile.ZipFile(zip_path) as z:
        data = json.loads(z.read(z.namelist()[0]))
    return data["results"]


def to_rows(records, source_file):
    rows = []
    for rec in records:
        row = {col: rec.get(col) for col in TEXT_COLUMNS}
        row["openfda"] = rec.get("openfda") or None
        row["raw_record"] = rec
        row["source_file"] = source_file
        rows.append(row)
    return rows


def main():
    engine = get_engine()

    # Build the staging table fresh each run
    sql = Path("sql/01_create_staging.sql").read_text()
    with engine.begin() as conn:
        conn.exec_driver_sql(sql)

    total = 0
    for url in get_partition_urls():
        zip_path = download(url)
        records = read_records(zip_path)
        df = pd.DataFrame(to_rows(records, zip_path.name))
        df.to_sql(
            "fda_recalls_raw",
            engine,
            schema="staging",
            if_exists="append",
            index=False,
            chunksize=1000,
            method="multi",
            dtype={"openfda": JSONB, "raw_record": JSONB},
        )
        total += len(df)
        print(f"Loaded {len(df):,} records from {zip_path.name}")

    with engine.connect() as conn:
        n, n_distinct = conn.execute(text(
            "SELECT COUNT(*), COUNT(DISTINCT recall_number) "
            "FROM staging.fda_recalls_raw"
        )).one()
    print(f"\nRows in staging table: {n:,}")
    print(f"Distinct recall numbers: {n_distinct:,}")


if __name__ == "__main__":
    main()
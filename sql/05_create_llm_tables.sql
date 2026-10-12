-- LLM results live in their own schema so clean rebuilds never delete them
CREATE SCHEMA IF NOT EXISTS llm;

CREATE TABLE IF NOT EXISTS llm.reason_categories (
    reason_hash    TEXT PRIMARY KEY,          -- md5 of the reason text, links back to recalls
    reason_text    TEXT NOT NULL,
    category       TEXT NOT NULL,
    confidence     TEXT NOT NULL CHECK (confidence IN ('high', 'medium', 'low')),
    model          TEXT NOT NULL,
    prompt_version TEXT NOT NULL,
    classified_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
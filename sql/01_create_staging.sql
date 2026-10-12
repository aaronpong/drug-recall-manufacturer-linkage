CREATE SCHEMA IF NOT EXISTS staging;

DROP TABLE IF EXISTS staging.fda_recalls_raw;

CREATE TABLE staging.fda_recalls_raw (
    recall_number           TEXT,
    event_id                TEXT,
    recalling_firm          TEXT,
    product_description     TEXT,
    reason_for_recall       TEXT,
    classification          TEXT,
    status                  TEXT,
    voluntary_mandated      TEXT,
    recall_initiation_date  TEXT,
    report_date             TEXT,
    termination_date        TEXT,
    city                    TEXT,
    state                   TEXT,
    country                 TEXT,
    distribution_pattern    TEXT,
    product_quantity        TEXT,
    code_info               TEXT,
    openfda                 JSONB,
    raw_record              JSONB,
    source_file             TEXT,
    loaded_at               TIMESTAMPTZ DEFAULT now()
);
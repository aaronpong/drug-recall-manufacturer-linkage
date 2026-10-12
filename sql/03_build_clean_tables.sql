-- Rebuild the clean schema from scratch each run
DROP SCHEMA IF EXISTS clean CASCADE;
CREATE SCHEMA clean;

-- Reusable function: same light normalization used in profiling
CREATE OR REPLACE FUNCTION clean.normalize_firm(name TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT NULLIF(TRIM(REGEXP_REPLACE(
        UPPER(REGEXP_REPLACE(name, '[^A-Za-z0-9 ]', ' ', 'g')),
        '\s+', ' ', 'g')), '')
$$;

-- 1. Firm reference table: one row per normalized firm
CREATE TABLE clean.firms (
    firm_id      SERIAL PRIMARY KEY,
    firm_norm    TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,     -- most common raw spelling
    recall_count INTEGER NOT NULL,
    event_count  INTEGER NOT NULL
);

INSERT INTO clean.firms (firm_norm, display_name, recall_count, event_count)
SELECT
    firm_norm,
    MODE() WITHIN GROUP (ORDER BY recalling_firm),
    COUNT(*),
    COUNT(DISTINCT event_id)
FROM (
    SELECT clean.normalize_firm(recalling_firm) AS firm_norm,
           recalling_firm,
           event_id
    FROM staging.fda_recalls_raw
) s
GROUP BY firm_norm
ORDER BY firm_norm;

-- 2. Alias table: every raw spelling mapped to its firm
CREATE TABLE clean.firm_aliases (
    raw_name TEXT PRIMARY KEY,
    firm_id  INTEGER NOT NULL REFERENCES clean.firms(firm_id)
);

INSERT INTO clean.firm_aliases (raw_name, firm_id)
SELECT DISTINCT r.recalling_firm, f.firm_id
FROM staging.fda_recalls_raw r
JOIN clean.firms f
  ON f.firm_norm = clean.normalize_firm(r.recalling_firm);

-- 3. Clean recalls table: proper types, standardized missing values
CREATE TABLE clean.recalls (
    recall_number          TEXT PRIMARY KEY,
    event_id               TEXT,
    firm_id                INTEGER NOT NULL REFERENCES clean.firms(firm_id),
    recalling_firm_raw     TEXT NOT NULL,
    product_description    TEXT NOT NULL,
    reason_for_recall      TEXT NOT NULL,
    classification         TEXT NOT NULL
        CHECK (classification IN ('Class I', 'Class II', 'Class III', 'Not Yet Classified')),
    status                 TEXT,
    voluntary_mandated     TEXT,
    recall_initiation_date DATE NOT NULL,
    report_date            DATE NOT NULL,
    termination_date       DATE,
    city                   TEXT,
    state                  TEXT,
    country                TEXT,
    distribution_pattern   TEXT,
    product_quantity       TEXT,
    code_info              TEXT,
    openfda_manufacturer   TEXT,
    openfda_generic_name   TEXT,
    openfda_brand_name     TEXT
);

INSERT INTO clean.recalls (
    recall_number, event_id, firm_id, recalling_firm_raw,
    product_description, reason_for_recall, classification, status,
    voluntary_mandated, recall_initiation_date, report_date, termination_date,
    city, state, country, distribution_pattern, product_quantity, code_info,
    openfda_manufacturer, openfda_generic_name, openfda_brand_name
)
SELECT
    r.recall_number,
    r.event_id,
    a.firm_id,
    r.recalling_firm,
    TRIM(r.product_description),
    TRIM(r.reason_for_recall),
    r.classification,
    r.status,
    CASE WHEN TRIM(COALESCE(r.voluntary_mandated, '')) IN ('', 'N/A')
         THEN NULL ELSE r.voluntary_mandated END,
    TO_DATE(r.recall_initiation_date, 'YYYYMMDD'),
    TO_DATE(r.report_date, 'YYYYMMDD'),
    TO_DATE(NULLIF(TRIM(r.termination_date), ''), 'YYYYMMDD'),
    NULLIF(TRIM(r.city), ''),
    NULLIF(TRIM(r.state), ''),
    NULLIF(TRIM(r.country), ''),
    NULLIF(TRIM(r.distribution_pattern), ''),
    NULLIF(TRIM(r.product_quantity), ''),
    NULLIF(TRIM(r.code_info), ''),
    r.openfda -> 'manufacturer_name' ->> 0,   -- first value in the list
    r.openfda -> 'generic_name'      ->> 0,
    r.openfda -> 'brand_name'        ->> 0
FROM staging.fda_recalls_raw r
JOIN clean.firm_aliases a
  ON a.raw_name = r.recalling_firm;

-- Quick check: row counts across the tables
SELECT
    (SELECT COUNT(*) FROM staging.fda_recalls_raw) AS staging_rows,
    (SELECT COUNT(*) FROM clean.recalls)           AS clean_recalls,
    (SELECT COUNT(*) FROM clean.firms)             AS firms,
    (SELECT COUNT(*) FROM clean.firm_aliases)      AS aliases;
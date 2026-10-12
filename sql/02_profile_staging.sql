-- 1. Missing or blank values in key columns
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE recalling_firm IS NULL OR TRIM(recalling_firm) = '')           AS missing_firm,
    COUNT(*) FILTER (WHERE reason_for_recall IS NULL OR TRIM(reason_for_recall) = '')     AS missing_reason,
    COUNT(*) FILTER (WHERE product_description IS NULL OR TRIM(product_description) = '') AS missing_product,
    COUNT(*) FILTER (WHERE classification IS NULL OR TRIM(classification) = '')           AS missing_class,
    COUNT(*) FILTER (WHERE termination_date IS NULL OR TRIM(termination_date) = '')       AS missing_termination
FROM staging.fda_recalls_raw;

-- 2. Date format check (should be YYYYMMDD) and date range
SELECT
    MIN(recall_initiation_date) AS earliest,
    MAX(recall_initiation_date) AS latest,
    COUNT(*) FILTER (WHERE recall_initiation_date IS NULL
                     OR recall_initiation_date !~ '^[0-9]{8}$') AS bad_initiation_dates,
    COUNT(*) FILTER (WHERE report_date IS NULL
                     OR report_date !~ '^[0-9]{8}$') AS bad_report_dates
FROM staging.fda_recalls_raw;

-- 3. Category columns: what values actually show up
SELECT 'classification' AS field, classification AS value, COUNT(*) FROM staging.fda_recalls_raw GROUP BY classification
UNION ALL
SELECT 'status', status, COUNT(*) FROM staging.fda_recalls_raw GROUP BY status
UNION ALL
SELECT 'voluntary_mandated', voluntary_mandated, COUNT(*) FROM staging.fda_recalls_raw GROUP BY voluntary_mandated
ORDER BY field, count DESC;

-- 4. One recall event can cover many products
SELECT
    COUNT(DISTINCT event_id) AS events,
    ROUND(COUNT(*)::numeric / COUNT(DISTINCT event_id), 2) AS recalls_per_event
FROM staging.fda_recalls_raw;

-- 5. How messy are firm names? Raw vs. lightly normalized
WITH f AS (
    SELECT recalling_firm,
           TRIM(REGEXP_REPLACE(
               UPPER(REGEXP_REPLACE(recalling_firm, '[^A-Za-z0-9 ]', ' ', 'g')),
               '\s+', ' ', 'g')) AS firm_norm
    FROM staging.fda_recalls_raw
)
SELECT
    COUNT(DISTINCT recalling_firm) AS distinct_raw_names,
    COUNT(DISTINCT firm_norm)      AS distinct_after_normalizing
FROM f;

-- 6. Examples of the same firm spelled different ways
WITH f AS (
    SELECT recalling_firm,
           TRIM(REGEXP_REPLACE(
               UPPER(REGEXP_REPLACE(recalling_firm, '[^A-Za-z0-9 ]', ' ', 'g')),
               '\s+', ' ', 'g')) AS firm_norm
    FROM staging.fda_recalls_raw
)
SELECT
    firm_norm,
    COUNT(DISTINCT recalling_firm) AS spellings,
    COUNT(*) AS recalls,
    STRING_AGG(DISTINCT recalling_firm, ' | ') AS raw_versions
FROM f
GROUP BY firm_norm
HAVING COUNT(DISTINCT recalling_firm) > 1
ORDER BY spellings DESC, recalls DESC
LIMIT 25;

-- 7. How many recalls have FDA's own openfda product info attached
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE openfda IS NULL) AS no_openfda,
    COUNT(*) FILTER (WHERE openfda -> 'manufacturer_name' IS NOT NULL) AS has_manufacturer_name
FROM staging.fda_recalls_raw;

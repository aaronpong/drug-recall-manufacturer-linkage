-- Audit log lives outside the clean schema so it survives rebuilds
CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.validation_log (
    run_id      INTEGER     NOT NULL,
    run_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_name  TEXT        NOT NULL,
    expected    BIGINT      NOT NULL,
    actual      BIGINT      NOT NULL,
    passed      BOOLEAN     NOT NULL
);

-- Run every check and log the results under a new run_id
WITH run AS (
    SELECT COALESCE(MAX(run_id), 0) + 1 AS run_id
    FROM audit.validation_log
),
checks AS (
    -- Completeness: nothing lost between staging and clean
    SELECT 'recall row count matches staging' AS check_name,
           (SELECT COUNT(*) FROM staging.fda_recalls_raw) AS expected,
           (SELECT COUNT(*) FROM clean.recalls) AS actual

    UNION ALL
    SELECT 'firm recall counts add up to total recalls',
           (SELECT COUNT(*) FROM clean.recalls),
           (SELECT SUM(recall_count) FROM clean.firms)

    -- Uniqueness
    UNION ALL
    SELECT 'no duplicate recall numbers', 0,
           (SELECT COUNT(*) - COUNT(DISTINCT recall_number) FROM clean.recalls)

    -- Referential integrity: every link points to something real
    UNION ALL
    SELECT 'every raw firm name has an alias', 0,
           (SELECT COUNT(DISTINCT r.recalling_firm)
            FROM staging.fda_recalls_raw r
            LEFT JOIN clean.firm_aliases a ON a.raw_name = r.recalling_firm
            WHERE a.firm_id IS NULL)

    UNION ALL
    SELECT 'no recalls pointing to a missing firm', 0,
           (SELECT COUNT(*)
            FROM clean.recalls r
            LEFT JOIN clean.firms f ON f.firm_id = r.firm_id
            WHERE f.firm_id IS NULL)

    UNION ALL
    SELECT 'no firms without any recalls', 0,
           (SELECT COUNT(*)
            FROM clean.firms f
            LEFT JOIN clean.recalls r ON r.firm_id = f.firm_id
            WHERE r.recall_number IS NULL)

    -- Standardization: cleaning rules were applied
    UNION ALL
    SELECT 'voluntary_mandated has no N/A or blank values', 0,
           (SELECT COUNT(*) FROM clean.recalls
            WHERE voluntary_mandated = 'N/A' OR TRIM(voluntary_mandated) = '')

    UNION ALL
    SELECT 'text fields have no extra spaces', 0,
           (SELECT COUNT(*) FROM clean.recalls
            WHERE product_description <> TRIM(product_description)
               OR reason_for_recall   <> TRIM(reason_for_recall))

    -- Date logic: dates make sense together
    UNION ALL
    SELECT 'no recall start dates in the future', 0,
           (SELECT COUNT(*) FROM clean.recalls
            WHERE recall_initiation_date > CURRENT_DATE)

    UNION ALL
    SELECT 'termination date not before start date', 0,
           (SELECT COUNT(*) FROM clean.recalls
            WHERE termination_date < recall_initiation_date)

    UNION ALL
    SELECT 'report date not before start date', 0,
           (SELECT COUNT(*) FROM clean.recalls
            WHERE report_date < recall_initiation_date)

    UNION ALL
    SELECT 'terminated recalls have a termination date', 0,
           (SELECT COUNT(*) FROM clean.recalls
            WHERE status = 'Terminated' AND termination_date IS NULL)
)
INSERT INTO audit.validation_log (run_id, check_name, expected, actual, passed)
SELECT run.run_id, c.check_name, c.expected, c.actual, c.expected = c.actual
FROM checks c
CROSS JOIN run;

-- Show results of the latest run, failures first
SELECT
    check_name,
    expected,
    actual,
    CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM audit.validation_log
WHERE run_id = (SELECT MAX(run_id) FROM audit.validation_log)
ORDER BY passed, check_name;
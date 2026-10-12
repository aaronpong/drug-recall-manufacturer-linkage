-- One combined view for analysis
CREATE SCHEMA IF NOT EXISTS analysis;

CREATE OR REPLACE VIEW analysis.recalls_enriched AS
SELECT
    r.recall_number,
    r.event_id,
    r.firm_id,
    f.display_name                                AS firm_name,
    r.classification,
    r.status,
    r.recall_initiation_date,
    EXTRACT(YEAR FROM r.recall_initiation_date)::int AS recall_year,
    rc.category                                   AS reason_category,
    fm.mftr_id,
    m.mftr_name,
    m.spend_2024
FROM clean.recalls r
JOIN clean.firms f USING (firm_id)
LEFT JOIN llm.reason_categories rc     ON rc.reason_hash = md5(r.reason_for_recall)
LEFT JOIN linkage.firm_manufacturer fm USING (firm_id)
LEFT JOIN linkage.manufacturers m      ON m.mftr_id = fm.mftr_id;

-- 0. Sanity check: every recall present, every recall has a category
SELECT COUNT(*)                                       AS recalls,
       COUNT(*) FILTER (WHERE reason_category IS NULL) AS missing_category,
       COUNT(*) FILTER (WHERE mftr_id IS NOT NULL)     AS linked_recalls
FROM analysis.recalls_enriched;

-- Q1. Why do recalls happen? Part D manufacturers vs. everyone else (share of recall events)
WITH c AS (
    SELECT reason_category,
           COUNT(DISTINCT event_id) FILTER (WHERE mftr_id IS NOT NULL) AS mftr_events,
           COUNT(DISTINCT event_id) FILTER (WHERE mftr_id IS NULL)     AS other_events
    FROM analysis.recalls_enriched
    GROUP BY reason_category
)
SELECT reason_category,
       mftr_events,
       ROUND(100.0 * mftr_events  / SUM(mftr_events)  OVER (), 1) AS pct_of_mftr_events,
       other_events,
       ROUND(100.0 * other_events / SUM(other_events) OVER (), 1) AS pct_of_other_events
FROM c
ORDER BY mftr_events DESC;

-- Q2. Which reasons lead to the most serious (Class I) recalls?
SELECT reason_category,
       COUNT(DISTINCT event_id) AS events,
       COUNT(DISTINCT event_id) FILTER (WHERE classification = 'Class I') AS class1_events,
       ROUND(100.0 * COUNT(DISTINCT event_id) FILTER (WHERE classification = 'Class I')
             / COUNT(DISTINCT event_id), 1) AS pct_class1
FROM analysis.recalls_enriched
GROUP BY reason_category
ORDER BY pct_class1 DESC;

-- Q3. Part D manufacturers with the most recall events, with 2024 Medicare spending
SELECT mftr_name,
       ROUND(MAX(spend_2024) / 1e6, 1)                                    AS spend_2024_millions,
       COUNT(DISTINCT event_id)                                           AS recall_events,
       COUNT(DISTINCT event_id) FILTER (WHERE classification = 'Class I') AS class1_events,
       COUNT(DISTINCT event_id) FILTER (WHERE recall_year >= 2020)        AS events_since_2020
FROM analysis.recalls_enriched
WHERE mftr_id IS NOT NULL
GROUP BY mftr_name
ORDER BY recall_events DESC
LIMIT 20;

-- Q4. Do manufacturers with more Medicare spending have more recalls? (spending quartiles)
WITH m AS (
    SELECT m.mftr_id, m.spend_2024,
           COUNT(DISTINCT e.event_id) AS events
    FROM linkage.manufacturers m
    LEFT JOIN analysis.recalls_enriched e ON e.mftr_id = m.mftr_id
    WHERE m.spend_2024 > 0
    GROUP BY m.mftr_id, m.spend_2024
),
q AS (
    SELECT *, NTILE(4) OVER (ORDER BY spend_2024) AS spend_quartile
    FROM m
)
SELECT spend_quartile,
       COUNT(*)                                                    AS manufacturers,
       ROUND(MIN(spend_2024) / 1e6, 2)                             AS min_spend_millions,
       ROUND(MAX(spend_2024) / 1e6, 1)                             AS max_spend_millions,
       ROUND(100.0 * COUNT(*) FILTER (WHERE events > 0) / COUNT(*), 1) AS pct_with_any_recall,
       ROUND(AVG(events), 2)                                       AS avg_recall_events
FROM q
GROUP BY spend_quartile
ORDER BY spend_quartile;

-- Q5. Recall events per year by class (2012 onward, when openFDA reporting is complete)
SELECT recall_year,
       COUNT(DISTINCT event_id)                                             AS events,
       COUNT(DISTINCT event_id) FILTER (WHERE classification = 'Class I')   AS class1,
       COUNT(DISTINCT event_id) FILTER (WHERE classification = 'Class II')  AS class2,
       COUNT(DISTINCT event_id) FILTER (WHERE classification = 'Class III') AS class3
FROM analysis.recalls_enriched
WHERE recall_year BETWEEN 2012 AND 2025
GROUP BY recall_year
ORDER BY recall_year;
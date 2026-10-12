-- A. dash_class1_by_group: headline comparison
SELECT CASE WHEN mftr_id IS NULL THEN 'Other firms' ELSE 'Part D manufacturers' END AS firm_group,
       COUNT(DISTINCT event_id) AS events,
       COUNT(DISTINCT event_id) FILTER (WHERE classification = 'Class I') AS class1_events,
       ROUND(100.0 * COUNT(DISTINCT event_id) FILTER (WHERE classification = 'Class I')
             / COUNT(DISTINCT event_id), 1) AS pct_class1
FROM analysis.recalls_enriched
GROUP BY 1;

-- B. dash_reasons: reason mix by firm group + Class I rate per reason
WITH c AS (
    SELECT reason_category,
           COUNT(DISTINCT event_id) FILTER (WHERE mftr_id IS NOT NULL) AS mftr_events,
           COUNT(DISTINCT event_id) FILTER (WHERE mftr_id IS NULL)     AS other_events,
           COUNT(DISTINCT event_id)                                    AS all_events,
           COUNT(DISTINCT event_id) FILTER (WHERE classification = 'Class I') AS class1_events
    FROM analysis.recalls_enriched
    GROUP BY reason_category
)
SELECT reason_category,
       INITCAP(REPLACE(reason_category, '_', ' '))              AS reason_label,
       mftr_events,
       ROUND(100.0 * mftr_events  / SUM(mftr_events)  OVER (), 1) AS pct_of_mftr_events,
       other_events,
       ROUND(100.0 * other_events / SUM(other_events) OVER (), 1) AS pct_of_other_events,
       all_events,
       class1_events,
       ROUND(100.0 * class1_events / all_events, 1)               AS pct_class1
FROM c
ORDER BY all_events DESC;

-- C. dash_spend_quartiles: Medicare spending vs. recalls
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
       CASE spend_quartile WHEN 1 THEN 'Q1 (lowest)' WHEN 2 THEN 'Q2'
                           WHEN 3 THEN 'Q3' ELSE 'Q4 (highest)' END AS quartile_label,
       COUNT(*) AS manufacturers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE events > 0) / COUNT(*), 1) AS pct_with_any_recall,
       ROUND(AVG(events), 2) AS avg_recall_events
FROM q
GROUP BY spend_quartile
ORDER BY spend_quartile;

-- D. dash_trend: recall events per year by class (long format for Tableau)
SELECT recall_year,
       classification,
       COUNT(DISTINCT event_id) AS events
FROM analysis.recalls_enriched
WHERE recall_year BETWEEN 2012 AND 2025
  AND classification IN ('Class I', 'Class II', 'Class III')
GROUP BY recall_year, classification
ORDER BY recall_year, classification;

-- E. dash_top_manufacturers: top 20 Part D manufacturers by recall events
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
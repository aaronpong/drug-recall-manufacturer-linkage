-- Final firm -> manufacturer links: exact matches + reviewed matches marked 'y'
DROP TABLE IF EXISTS linkage.firm_manufacturer;
CREATE TABLE linkage.firm_manufacturer AS
SELECT
    c.firm_id, c.firm_norm, c.display_name,
    c.mftr_id, c.mftr_name, c.method, c.sim,
    CASE WHEN c.method = 'exact_key' THEN 'auto_exact' ELSE 'reviewed' END AS link_source
FROM linkage.match_candidates c
LEFT JOIN linkage.match_decisions d
       ON d.firm_norm = c.firm_norm
      AND d.mftr_name = c.mftr_name
WHERE c.candidate_rank = 1
  AND (c.method = 'exact_key' OR d.decision = 'y');

ALTER TABLE linkage.firm_manufacturer ADD PRIMARY KEY (firm_id);

-- 1. Overall coverage
SELECT
    COUNT(*)                                                         AS firms,
    COUNT(fm.firm_id)                                                AS firms_linked,
    ROUND(100.0 * COUNT(fm.firm_id) / COUNT(*), 1)                   AS pct_firms_linked,
    SUM(f.event_count)                                               AS events,
    SUM(f.event_count) FILTER (WHERE fm.firm_id IS NOT NULL)         AS events_linked,
    ROUND(100.0 * SUM(f.event_count) FILTER (WHERE fm.firm_id IS NOT NULL)
          / SUM(f.event_count), 1)                                   AS pct_events_linked
FROM clean.firms f
LEFT JOIN linkage.firm_manufacturer fm USING (firm_id);

-- 2. How firms were linked
SELECT
    COALESCE(fm.link_source, 'unlinked') AS link_source,
    COUNT(*)                             AS firms,
    SUM(f.event_count)                   AS events
FROM clean.firms f
LEFT JOIN linkage.firm_manufacturer fm USING (firm_id)
GROUP BY 1
ORDER BY firms DESC;

-- 3. Sanity check: exact matches on very short keys (most likely to be coincidences)
SELECT display_name, mftr_name, fkey
FROM linkage.match_candidates
WHERE candidate_rank = 1
  AND method = 'exact_key'
  AND LENGTH(fkey) <= 5
ORDER BY fkey;

-- 4. Biggest firms that did NOT link (expect compounders, repackagers, supplement makers)
SELECT f.display_name, f.event_count, f.recall_count
FROM clean.firms f
LEFT JOIN linkage.firm_manufacturer fm USING (firm_id)
WHERE fm.firm_id IS NULL
ORDER BY f.event_count DESC
LIMIT 20;
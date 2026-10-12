-- Your yes/no decisions on uncertain matches. Never dropped, so reviews survive rebuilds.
CREATE TABLE IF NOT EXISTS linkage.match_decisions (
    firm_norm    TEXT NOT NULL,
    display_name TEXT,
    mftr_name    TEXT NOT NULL,
    method       TEXT NOT NULL,
    sim          NUMERIC,
    event_count  INTEGER,
    decision     TEXT CHECK (decision IN ('y', 'n')),
    notes        TEXT,
    PRIMARY KEY (firm_norm, mftr_name)
);

-- Add any new prefix/fuzzy best matches to the queue (existing decisions are kept)
INSERT INTO linkage.match_decisions (firm_norm, display_name, mftr_name, method, sim, event_count)
SELECT firm_norm, display_name, mftr_name, method, sim, event_count
FROM linkage.match_candidates
WHERE candidate_rank = 1
  AND method IN ('prefix', 'fuzzy')
ON CONFLICT DO NOTHING;

-- What's left to review
SELECT method,
       COUNT(*)         AS to_review,
       SUM(event_count) AS recall_events
FROM linkage.match_decisions
WHERE decision IS NULL
GROUP BY method;
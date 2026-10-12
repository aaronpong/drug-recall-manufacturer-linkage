-- Review table: a fixed sample of model labels for hand checking
CREATE TABLE IF NOT EXISTS llm.label_review (
    reason_hash       TEXT PRIMARY KEY REFERENCES llm.reason_categories(reason_hash),
    reason_text       TEXT NOT NULL,
    model_category    TEXT NOT NULL,
    model_confidence  TEXT NOT NULL,
    reviewer_category TEXT,          -- you fill this in
    notes             TEXT,          -- optional
    sampled_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Fixed seed so the same sample is drawn if this is rebuilt
SELECT setseed(0.42);

-- 10 random reasons per category (skips if a sample already exists)
INSERT INTO llm.label_review (reason_hash, reason_text, model_category, model_confidence)
SELECT reason_hash, reason_text, category, confidence
FROM (
    SELECT rc.*,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY random()) AS rn
    FROM llm.reason_categories rc
    WHERE model <> 'manual'
) s
WHERE rn <= 10
  AND NOT EXISTS (SELECT 1 FROM llm.label_review);

SELECT COUNT(*) AS sampled FROM llm.label_review;
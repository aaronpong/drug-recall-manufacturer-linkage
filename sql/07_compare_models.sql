-- How often do Claude and ChatGPT agree, and Cohen's kappa
WITH n AS (
    SELECT COUNT(*)::numeric AS n FROM llm.label_review
),
po AS (   -- observed agreement
    SELECT COUNT(*) FILTER (WHERE model_category = gpt_category)::numeric
           / (SELECT n FROM n) AS po
    FROM llm.label_review
),
cats AS ( -- how often each model used each category
    SELECT c.cat,
           (SELECT COUNT(*) FROM llm.label_review WHERE model_category = c.cat)::numeric
               / (SELECT n FROM n) AS p_claude,
           (SELECT COUNT(*) FROM llm.label_review WHERE gpt_category = c.cat)::numeric
               / (SELECT n FROM n) AS p_gpt
    FROM (SELECT model_category AS cat FROM llm.label_review
          UNION
          SELECT gpt_category FROM llm.label_review) c
),
pe AS (   -- agreement expected by chance
    SELECT SUM(p_claude * p_gpt) AS pe FROM cats
)
SELECT (SELECT n FROM n)                AS n,
       ROUND(po * 100, 1)               AS pct_agree,
       ROUND((po - pe) / (1 - pe), 3)   AS cohens_kappa
FROM po, pe;

-- Flag rows for hand review: every disagreement plus 10 random agreements
ALTER TABLE llm.label_review ADD COLUMN IF NOT EXISTS review_reason TEXT;

UPDATE llm.label_review
SET review_reason = 'disagreement'
WHERE gpt_category <> model_category;

UPDATE llm.label_review
SET review_reason = 'spot_check'
WHERE reason_hash IN (
    SELECT reason_hash
    FROM llm.label_review
    WHERE gpt_category = model_category
    ORDER BY md5(reason_hash || 'spot')   -- fixed random order, same every run
    LIMIT 10
);

SELECT review_reason, COUNT(*) AS n
FROM llm.label_review
GROUP BY review_reason
ORDER BY review_reason;

-- Preview the disagreements
SELECT reason_text, model_category AS claude, gpt_category AS chatgpt
FROM llm.label_review
WHERE review_reason = 'disagreement'
ORDER BY model_category;
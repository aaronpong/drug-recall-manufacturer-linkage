-- 1. Who was right, by review type
SELECT
    review_reason,
    COUNT(*) AS reviewed,
    COUNT(*) FILTER (WHERE reviewer_category = model_category) AS claude_correct,
    COUNT(*) FILTER (WHERE reviewer_category = gpt_category)   AS gpt_correct,
    COUNT(*) FILTER (WHERE reviewer_category <> model_category
                       AND reviewer_category <> gpt_category)  AS both_wrong
FROM llm.label_review
WHERE review_reason IS NOT NULL
GROUP BY review_reason;

-- 2. Disagreements split into clear-cut vs. gray (judgment call) rows
SELECT
    CASE WHEN COALESCE(notes, '') ILIKE '%gray%' THEN 'gray' ELSE 'clear' END AS row_type,
    COUNT(*) AS n,
    COUNT(*) FILTER (WHERE reviewer_category = model_category) AS claude_correct,
    COUNT(*) FILTER (WHERE reviewer_category = gpt_category)   AS gpt_correct
FROM llm.label_review
WHERE review_reason = 'disagreement'
GROUP BY 1;

-- 3. Estimated accuracy on the 110-row sample, with 95% CI
--    Disagreements were all reviewed, so their counts are exact.
--    Agreements were spot-checked, so their accuracy is estimated
--    with a Wilson interval (works even if all spot checks are correct).
WITH counts AS (
    SELECT
        COUNT(*)::numeric AS n_total,
        COUNT(*) FILTER (WHERE model_category = gpt_category)::numeric AS n_agree,
        COUNT(*) FILTER (WHERE review_reason = 'spot_check')::numeric AS n_spot,
        COUNT(*) FILTER (WHERE review_reason = 'spot_check'
                           AND reviewer_category = model_category)::numeric AS spot_correct,
        COUNT(*) FILTER (WHERE review_reason = 'disagreement'
                           AND reviewer_category = model_category)::numeric AS claude_dis_correct,
        COUNT(*) FILTER (WHERE review_reason = 'disagreement'
                           AND reviewer_category = gpt_category)::numeric AS gpt_dis_correct
    FROM llm.label_review
),
w AS (
    SELECT *,
           spot_correct / n_spot AS p,
           ((spot_correct / n_spot) + 3.8416 / (2 * n_spot)) / (1 + 3.8416 / n_spot) AS center,
           1.96 * SQRT((spot_correct / n_spot) * (1 - spot_correct / n_spot) / n_spot
                       + 3.8416 / (4 * n_spot * n_spot)) / (1 + 3.8416 / n_spot) AS half
    FROM counts
)
SELECT
    ROUND(100 * (n_agree * p + claude_dis_correct) / n_total, 1)                         AS claude_accuracy_pct,
    ROUND(100 * (n_agree * GREATEST(center - half, 0) + claude_dis_correct) / n_total, 1) AS claude_ci_low,
    ROUND(100 * (n_agree * LEAST(center + half, 1) + claude_dis_correct) / n_total, 1)    AS claude_ci_high,
    ROUND(100 * (n_agree * p + gpt_dis_correct) / n_total, 1)                            AS gpt_accuracy_pct,
    ROUND(100 * (n_agree * GREATEST(center - half, 0) + gpt_dis_correct) / n_total, 1)    AS gpt_ci_low,
    ROUND(100 * (n_agree * LEAST(center + half, 1) + gpt_dis_correct) / n_total, 1)       AS gpt_ci_high
FROM w;
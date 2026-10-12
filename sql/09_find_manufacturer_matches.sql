-- Trigram similarity for fuzzy matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE SCHEMA IF NOT EXISTS linkage;

-- Match key: normalized name with legal suffixes and generic industry words removed
CREATE OR REPLACE FUNCTION linkage.match_key(name TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    filler TEXT[] := ARRAY[
        'INC','INCORPORATED','LLC','LTD','LIMITED','CORP','CORPORATION','CO','COMPANY',
        'LP','PLC','SA','AG','GMBH','USA','US','THE','OF','AND',
        'PHARMACEUTICALS','PHARMACEUTICAL','PHARMS','PHARM','PHARMA',
        'LABORATORIES','LABORATORY','LABS','LAB','HEALTHCARE','PRODUCTS',
        'INTERNATIONAL','INTL','DIV','DIVISION','INDUSTRIES'];
    cleaned   TEXT;
    words     TEXT[];
    kept      TEXT[] := '{}';
    w         TEXT;
    last_word TEXT;
BEGIN
    cleaned := ' ' || TRIM(REGEXP_REPLACE(
        UPPER(REGEXP_REPLACE(COALESCE(name, ''), '[^A-Za-z0-9 ]', ' ', 'g')),
        '\s+', ' ', 'g')) || ' ';

    -- Dotted abbreviations turn into single letters (U.S.A. -> U S A). Remove the common ones.
    -- Run twice so back-to-back ones (U.S.A. L.P.) are both caught.
    cleaned := REGEXP_REPLACE(cleaned, ' (U S A|U S|L L C|L P|N A) ', ' ', 'g');
    cleaned := REGEXP_REPLACE(cleaned, ' (U S A|U S|L L C|L P|N A) ', ' ', 'g');

    words := regexp_split_to_array(TRIM(cleaned), ' ');

    -- Drop legal suffixes and generic industry words
    FOREACH w IN ARRAY words LOOP
        IF w <> '' AND NOT (w = ANY(filler)) THEN
            kept := kept || w;
        END IF;
    END LOOP;

    -- CMS cuts names at about 15 characters, so the last word may be a
    -- cut-off filler word like 'PHARMACEU' or 'HEALTHCA'. Drop it if so.
    IF array_length(kept, 1) > 1 THEN
        last_word := kept[array_length(kept, 1)];
        IF LENGTH(last_word) >= 3
           AND EXISTS (SELECT 1 FROM unnest(filler) f WHERE f LIKE last_word || '%') THEN
            kept := kept[1:array_length(kept, 1) - 1];
        END IF;
    END IF;

    RETURN NULLIF(array_to_string(kept, ' '), '');
END;
$$;

-- Manufacturer reference table from Part D (excluding 'Overall' rollup rows)
DROP TABLE IF EXISTS linkage.manufacturers CASCADE;
CREATE TABLE linkage.manufacturers (
    mftr_id      SERIAL PRIMARY KEY,
    mftr_name    TEXT NOT NULL UNIQUE,
    match_key    TEXT,
    spend_2024   NUMERIC,
    n_drugs_2024 INTEGER
);

INSERT INTO linkage.manufacturers (mftr_name, match_key, spend_2024, n_drugs_2024)
SELECT
    "Mftr_Name",
    linkage.match_key("Mftr_Name"),
    SUM("Tot_Spndng") FILTER (WHERE "Year" = '2024 (Q1-Q4)'),
    COUNT(DISTINCT "Brnd_Name" || '|' || "Gnrc_Name") FILTER (WHERE "Year" = '2024 (Q1-Q4)')
FROM staging.medicare_partd_raw
WHERE "Mftr_Name" <> 'Overall'
GROUP BY "Mftr_Name";

-- Candidate matches: up to 3 per recall firm, best first
DROP TABLE IF EXISTS linkage.match_candidates;
CREATE TABLE linkage.match_candidates AS
WITH f AS (
    SELECT firm_id, firm_norm, display_name, event_count, recall_count,
           linkage.match_key(firm_norm) AS fkey
    FROM clean.firms
),
m AS (
    SELECT mftr_id, mftr_name, spend_2024, match_key AS mkey
    FROM linkage.manufacturers
    WHERE match_key IS NOT NULL
),
pairs AS (
    SELECT f.*, m.*,
           similarity(f.fkey, m.mkey) AS sim,
           CASE
               WHEN f.fkey = m.mkey THEN 'exact_key'
               -- CMS name cut short: CMS key can end mid-word
               WHEN LENGTH(m.mkey) >= 6 AND f.fkey LIKE m.mkey || '%' THEN 'prefix'
               -- Firm name shorter: must end on a whole word (stops ASCEND -> ASCENDIS)
               WHEN LENGTH(f.fkey) >= 6 AND m.mkey LIKE f.fkey || ' %' THEN 'prefix'
               WHEN similarity(f.fkey, m.mkey) >= 0.5 THEN 'fuzzy'
           END AS method
    FROM f CROSS JOIN m
    WHERE f.fkey IS NOT NULL
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY firm_id
               ORDER BY CASE method WHEN 'exact_key' THEN 1 WHEN 'prefix' THEN 2 ELSE 3 END,
                        sim DESC
           ) AS candidate_rank
    FROM pairs
    WHERE method IS NOT NULL
)
SELECT firm_id, firm_norm, display_name, event_count, recall_count,
       mftr_id, mftr_name, spend_2024, fkey, mkey, method,
       ROUND(sim::numeric, 3) AS sim, candidate_rank
FROM ranked
WHERE candidate_rank <= 3;

-- Summary: how each firm's best candidate was found
SELECT
    COALESCE(c.method, 'no_match') AS best_method,
    COUNT(*)                       AS firms,
    SUM(f.event_count)             AS recall_events
FROM clean.firms f
LEFT JOIN linkage.match_candidates c
       ON c.firm_id = f.firm_id AND c.candidate_rank = 1
GROUP BY 1
ORDER BY firms DESC;

-- Eyeball check: best candidate for the 30 firms with the most recall events
SELECT display_name, event_count, mftr_name, method, sim
FROM linkage.match_candidates
WHERE candidate_rank = 1
ORDER BY event_count DESC
LIMIT 30;
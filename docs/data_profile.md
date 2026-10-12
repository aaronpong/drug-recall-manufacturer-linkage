**Missing values** (query 1)
- No recalls are missing a firm name, recall reason, or product description.
- About 3,200 recalls have no termination date because they are still ongoing or completed but not terminated.

**Dates** (query 2)
- Recall initiation dates range from February 2006 to September 2026.
- All dates are valid YYYYMMDD text, so they can be safely converted to date types.

**Categories** (query 3)
- About 81% of recalls are Class II. Class I (most serious) and Class III are about 10% each.
- `voluntary_mandated` records missing values two ways ("N/A" and blank), which need to be standardized.

**Recall events** (query 4)
- 18,002 recalls belong to 4,698 recall events (about 3.8 products per event), so counts by firm or year should be checked at both the recall and the event level.
- Ranking firms by recall count is misleading. The top firms by recall count (Aidapak, Attix, King Bio) each had 1 or 2 recall events covering hundreds of products, mostly compounders and repackagers. Ranking by event count surfaces manufacturers with repeated recalls (Hospira, Teva, Dr. Reddy's, Akorn, Glenmark).

**Firm names** (queries 5 and 6)
- 1,664 distinct raw firm names drop to 1,541 after removing case and punctuation differences.
- (keep your existing bullets here)

**FDA product info coverage** (query 7)
- 14,828 recalls (82%) have no openFDA product info, and only 3,174 have a manufacturer name.
- Missing values were stored as JSON null rather than SQL NULL, so they needed a different check.

## What this means for cleaning
- Convert date fields from text to dates.
- Standardize missing values in `voluntary_mandated`.
- Build a firm reference table with normalized names, then match firms to manufacturers since openFDA info is mostly missing.
- Report counts at both the recall and the event level.

## Known source data issues
**Terminated recall with no termination date**
- Recall D-0469-2017 (VistaPharm, Inc., started 2017-01-18) is marked "Terminated" but has no termination date.
- The date is missing in the original openFDA JSON, staging, and clean tables, so this is a gap in the source data, not a pipeline error.
- The date was left as NULL rather than filled in. The validation check "terminated recalls have a termination date" will keep reporting it (expected 0, actual 1).

## LLM classification
- 4,463 of 4,464 distinct recall reasons were classified by the model (prompt v2).
- The model declined to classify 1 reason (stop_reason = refusal). It was labeled by hand as microbial_contamination, matching how the model labeled similar "Non-Sterility: contaminated with" reasons, and stored with model = 'manual'.
- sterility_assurance and microbial_contamination overlap for some "Non-Sterility" reasons.

### Label accuracy check
- Sample: 110 recall reasons (10 per category). ChatGPT labeled the same sample independently, without seeing Claude's labels.
- Claude and ChatGPT agreed on 88 of 110 reasons (80%).
- I reviewed all 22 disagreements by hand, plus 10 random agreements. All 10 spot-checked agreements were correct.
- On the disagreements, Claude was right on 8, ChatGPT on 13, and both were wrong on 1.
- Estimated accuracy on the sample: Claude 87.3% (95% CI 65.1–87.3%), ChatGPT 91.8% (95% CI 69.6–91.8%). The interval is wide because only 10 agreements were spot-checked.
- Because the sample has 10 reasons per category, this is accuracy for the average category, not weighted by how common each category is.
- Most disagreements came from gaps in the category list rather than clear mistakes: discoloration, crystallization, and wrong tablets in a bottle don't fit any category cleanly. Claude also tended to pick storage_stability whenever a problem was found during stability testing, even when the specific problem was an impurity or low potency.

## Second source: Medicare Part D Spending by Drug (CMS)
- Copied from my Medicare Part D project database into `staging.medicare_partd_raw`.
- Covers 2024 (Q1-Q4) and 2025 (Q1-Q3), 28,833 rows.
- Rows where Mftr_Name = 'Overall' are drug-level totals across manufacturers and must be excluded from manufacturer-level analysis to avoid double counting.

## Linking recall firms to Medicare Part D manufacturers
- Firm names were reduced to a match key (uppercase, punctuation removed, legal suffixes and generic words like "Pharmaceuticals" and "Inc" dropped, dotted abbreviations like U.S.A. removed, and cut-off filler words at the end of CMS's 15-character names dropped).
- Matching ran in three passes: exact key, prefix (to handle CMS truncation), and fuzzy (pg_trgm similarity ≥ 0.5).
- Exact matches were accepted automatically. Short exact keys were checked by hand, and 2 were rejected (Epic Products and Nova Products, supplement sellers that only shared one word with real manufacturers).
- Prefix and fuzzy matches for firms with 2+ recall events were reviewed with AI-assisted suggestions and confirmed by me (101 reviewed, 15 rejected). Single-event candidates were left unlinked.
- Result: 285 of 1,541 firms (18.5%) linked, covering 2,446 of 4,698 recall events (52.1%). The firms with repeat recalls are mostly manufacturers, which is why a small share of firms covers half the events.
- Most unlinked firms are repackagers (American Health Packaging, RemedyRepack), compounders (PharMEDium, SCA Pharmaceuticals), device makers, and supplement sellers, which don't appear as Part D manufacturers.
- Known limits: string matching can't catch company renames (Watson → Actavis, Valeant → Bausch Health) or "doing business as" names (Harvard Drug Group dba Major Pharmaceuticals).

# Findings: FDA Drug Recalls and Medicare Part D Manufacturers

Data: 18,002 FDA drug recalls (2012–2026, openFDA) grouped into 4,698 recall events,
linked to 2024 Medicare Part D spending by manufacturer (CMS).
Counts are recall events, not individual products, so one large multi-product recall
does not dominate the results.

## 1. The most serious recalls mostly come from outside the Medicare drug supply
- 19.1% of recall events from firms outside Part D (compounders, repackagers,
  supplement sellers) were Class I, compared with 9.3% from Part D manufacturers.
- Unapproved or tainted products (for example, supplements containing hidden sildenafil
  or sibutramine) were 12.0% of other firms' events but only 0.4% of manufacturers' events,
  and 68.3% of these recalls were Class I.
- Microbial contamination showed the same pattern: 7.9% vs. 1.9% of events, with 41.2% Class I.

## 2. Medicare manufacturers mostly recall for quality-specification failures
- Potency or dissolution failures (23.2%) and chemical impurities (20.2%) made up
  43% of Part D manufacturers' recall events.
- These are rarely the most serious kind: about 5% were Class I.

## 3. Larger Medicare manufacturers have more recalls
- 44.1% of manufacturers in the top 2024 spending quartile ($58M+) had at least one
  recall event, compared with 12.7% in the bottom quartile.
- Average recall events rose steadily across quartiles (0.75, 1.53, 2.23, 6.57).
- This likely reflects scale (more products and lots), not necessarily lower quality,
  and larger companies are also easier to match by name.

## 4. Recall volume is stable, but the severity mix has shifted
- Recall events held steady at roughly 280–370 per year from 2013 to 2025.
- Class III recall events fell from 126 (2016) to 41 (2025), while Class II's share
  rose from about half to about 80%. This may reflect classification practices
  rather than a change in drug risk.

## Company highlights
- Teva had the most recall events (160) among Part D manufacturers.
- Hospira/Pfizer had the most Class I recall events (35), none since 2020.
- 71 of Sun Pharma's 95 recall events occurred in 2020 or later.

## Limitations
- 52% of recall events were linked to a Part D manufacturer. Name matching cannot catch
  company renames (Watson → Actavis, Valeant → Bausch Health) or "doing business as" names.
- A company's Medicare spending can be split across several CMS manufacturer names.
- Recall reasons were categorized with an LLM (estimated 87% accuracy on a validation
  sample; see data_profile.md).
- Results show associations, not causes.
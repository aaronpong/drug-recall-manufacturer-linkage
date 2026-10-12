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
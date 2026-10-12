# FDA Drug Recalls vs. Medicare Part D Manufacturers

A data pipeline that links 18,002 FDA drug recalls to 2024 Medicare Part D spending by manufacturer, using PostgreSQL for the data model and validation, the Claude API to categorize free-text recall reasons, and Tableau for the dashboard.

**[View the interactive dashboard on Tableau Public](https://public.tableau.com/app/profile/aaron.pongsugree/viz/FDADrugRecallsvsMedicareManufacturers/Dashboard1)**

## Key findings

- **The most serious recalls mostly come from outside the Medicare drug supply.** 19.1% of recall events from compounders, repackagers, and supplement sellers were Class I (the most serious), compared with 9.3% from Medicare Part D manufacturers.
- **Tainted and unapproved products drive that gap.** They made up 12.0% of other firms' recall events but only 0.4% of Part D manufacturers' events, and 68.3% of them were Class I.
- **Medicare manufacturers mostly recall for quality-specification failures.** Potency/dissolution problems and chemical impurities were 43% of their recall events, and only about 5% of those were Class I.
- **Larger Medicare manufacturers have more recalls.** 44.1% of manufacturers in the top 2024 spending quartile had at least one recall event, compared with 12.7% in the bottom quartile. This likely reflects scale (more products and lots) rather than lower quality.
- **Recall volume has been stable since 2013, but the severity mix has shifted.** Class III recall events fell from 126 in 2016 to 41 in 2025, while Class II grew from about half to about 80% of events.

Full write-up: [docs/findings.md](docs/findings.md)

## Data sources

| Source | What it provides | Size |
|---|---|---|
| [openFDA drug enforcement reports](https://open.fda.gov/apis/drug/enforcement/) | Drug recalls with firm, reason, product, classification, and dates (2006 to 2026) | 18,002 recalls in 4,698 recall events |
| CMS Medicare Part D Spending by Drug | Medicare spending by drug and manufacturer (2024 and 2025 Q1 to Q3) | 28,833 rows, 930 manufacturers |

The Medicare data comes from my earlier project, [medicare-spending-by-drug](https://github.com/aaronpong/medicare-spending-by-drug).

## Pipeline

```
openFDA bulk download ──> staging (raw, untouched) ──> profiling ──> clean data model ──> validation
                                                                          │
                                         Claude API categorizes ──────────┤
                                         recall reasons                   │
                                                                          ▼
CMS Medicare Part D ──> manufacturer reference ──> name matching + review ──> analysis ──> Tableau
```

1. **Load raw data.** A Python script downloads the openFDA bulk file and loads every record into a staging table exactly as received, including the full original JSON.
2. **Profile the source.** SQL checks for missing values, date formats, category values, and name inconsistencies before any cleaning. Findings are in [docs/data_profile.md](docs/data_profile.md).
3. **Build a clean data model.** Three tables: a firm reference table (one row per company), a firm alias table mapping every raw spelling to its firm, and a clean recalls table with proper data types and standardized missing values.
4. **Validate.** Twelve SQL checks covering completeness, uniqueness, referential integrity, standardization, and date logic, logged to an audit table on every run. Eleven pass. One flags a known gap in the FDA source data (a terminated recall with no termination date), which is documented rather than hidden.
5. **Categorize recall reasons with an LLM.** The Claude API sorts each of 4,464 distinct free-text recall reasons into one of 11 categories. Results are stored with the model name and prompt version, in a separate schema so rebuilds never require paying for the API calls again.
6. **Validate the LLM labels.** ChatGPT labeled a stratified sample of 110 reasons independently. I reviewed every disagreement and a random set of agreements by hand.
7. **Link recall firms to Medicare manufacturers.** Names are reduced to a match key, then matched in three passes (exact, prefix, and fuzzy with PostgreSQL `pg_trgm`). Uncertain matches go to a review table that persists across rebuilds.
8. **Analyze and visualize.** SQL analysis at the recall event level, exported to CSV by script and visualized in Tableau.

## Data quality and validation highlights

**Profiling found the problems before cleaning fixed them**
- Firm names varied in case and punctuation: 1,664 raw names reduced to 1,541 firms after normalization.
- 82% of recalls had no FDA-provided manufacturer information, so firm-name matching was required.
- 18,002 recalls belonged to only 4,698 recall events, so all analysis counts events. Otherwise, one recall covering 500 products would look like 500 problems.

**LLM classification was measured, not assumed**
- Claude and ChatGPT agreed on 80% of the 110-reason sample.
- Estimated Claude accuracy on the sample: 87.3% (95% CI 65.1% to 87.3%, Wilson interval on the spot-checked agreements).
- Most disagreements came from gaps in the category list (for example, discoloration and crystallization fit no category cleanly), not careless labeling.
- The model declined to classify 1 reason. It was labeled by hand and stored with `model = 'manual'` to keep it separate from model output.

**Name matching was reviewed by hand where it was uncertain**
- Matching handled CMS's 15-character name truncation ("Accord Healthca"), dotted abbreviations (U.S.A.), and parent/subsidiary names (Hospira/Pfizer).
- Short exact matches were spot-checked. Two were rejected as coincidences (supplement sellers that shared one word with real manufacturers).
- Prefix and fuzzy matches for firms with 2+ recall events were reviewed with AI-assisted suggestions and confirmed by me. 15 were rejected.
- Result: 285 of 1,541 firms (18.5%) linked, covering 2,446 of 4,698 recall events (52.1%). Most unlinked firms are repackagers, compounders, device makers, and supplement sellers that do not appear as Part D manufacturers.

## Tools

- **PostgreSQL** (DBeaver): staging, data model, validation, matching (`pg_trgm`), and analysis
- **Python**: `requests`, `pandas`, `SQLAlchemy`, `psycopg2`
- **Claude API**: recall reason classification
- **Tableau Public**: dashboard
- **Git/GitHub**: version control

## Repository structure

```
├── data/
│   ├── raw/                          # openFDA bulk download (not committed)
│   └── processed/                    # CSVs that feed the dashboard
├── dashboard/                        # Tableau workbook
├── docs/
│   ├── data_profile.md               # profiling results, validation, known issues
│   └── findings.md                   # analysis write-up
├── sql/
│   ├── 01_create_staging.sql         # raw staging table
│   ├── 02_profile_staging.sql        # source profiling queries
│   ├── 03_build_clean_tables.sql     # firms, firm aliases, clean recalls
│   ├── 04_validate_clean_tables.sql  # validation checks with audit log
│   ├── 05_create_llm_tables.sql      # LLM results table
│   ├── 06_label_review.sql           # stratified sample for label review
│   ├── 07_compare_models.sql         # Claude vs. ChatGPT agreement and kappa
│   ├── 08_label_accuracy.sql         # accuracy estimates with confidence intervals
│   ├── 09_find_manufacturer_matches.sql  # match key and candidate matches
│   ├── 10_match_review_queue.sql     # persistent review decisions
│   ├── 11_build_firm_links.sql       # final firm-to-manufacturer links
│   ├── 12_analysis.sql               # analysis view and queries
│   └── 13_dashboard_exports.sql      # queries behind the dashboard CSVs
├── src/
│   ├── db.py                         # database connection
│   ├── 01_load_recalls.py            # download and stage openFDA data
│   ├── 02_classify_reasons.py        # Claude API classification
│   └── 03_export_dashboard_data.py   # write dashboard CSVs
└── requirements.txt
```

## How to run it

1. Create a PostgreSQL database named `drug_recalls`.
2. Create a `.env` file with `PG_USER`, `PG_PASSWORD`, `PG_HOST`, `PG_PORT`, `PG_DB`, and `ANTHROPIC_API_KEY`.
3. Install dependencies: `pip install -r requirements.txt`
4. Load the recall data: `python src/01_load_recalls.py`
5. Run `sql/02` through `sql/05`, then classify reasons: `python src/02_classify_reasons.py`
6. Load the CMS Medicare Part D Spending by Drug data into `staging.medicare_partd_raw`.
7. Run `sql/06` through `sql/13` in order, then export the dashboard data: `python src/03_export_dashboard_data.py`

The label review (step 6 of the pipeline) and match review tables contain manual decisions, so a fresh run starts with those reviews empty.

## Limitations

- About half of recall events could not be linked to a Part D manufacturer. Name matching cannot catch company renames (Watson to Actavis, Valeant to Bausch Health) or "doing business as" names.
- A company's Medicare spending can be split across several CMS manufacturer names.
- Recall reason categories come from an LLM with an estimated 87% accuracy on the validation sample.
- The spending comparison shows association, not cause. Larger manufacturers are also easier to match by name.

## Author

Aaron Pongsugree, M.S. Biostatistics, George Mason University
[GitHub](https://github.com/aaronpong) · [LinkedIn](https://www.linkedin.com/in/aaron-pongsugree)

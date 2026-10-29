# PayScope — End-to-End Project Documentation

**Project:** PayScope — Digital Payments Risk & Merchant Analytics
**Author:** Mahesh Sai Kandula
**Stack:** PostgreSQL · Python (pandas, SQLAlchemy) · SQL · Tableau
**Document version:** 1.0 — verified against the live database on 2026-08-13

---

## Table of contents

1. [What this project is](#1-what-this-project-is)
2. [Architecture](#2-architecture)
3. [Environment and configuration](#3-environment-and-configuration)
4. [Layer 1 — Synthetic data generation (`sql/seed/`)](#4-layer-1--synthetic-data-generation)
5. [Layer 2 — Controlled issue injection (`sql/issues/`)](#5-layer-2--controlled-issue-injection)
6. [Layer 3 — Extraction (`python/extraction/`)](#6-layer-3--extraction)
7. [Layer 4 — Data-quality profiling (`python/dq/`, `sql/qa/`)](#7-layer-4--data-quality-profiling)
8. [Layer 5 — Cleaning and validation (`python/cleaning/`)](#8-layer-5--cleaning-and-validation)
9. [Layer 6 — Loading to the clean schema (`python/loading/`)](#9-layer-6--loading-to-the-clean-schema)
10. [Layer 7 — Business marts (`sql/marts/`)](#10-layer-7--business-marts)
11. [Layer 8 — Risk engine](#11-layer-8--risk-engine)
12. [Layer 9 — Tableau dashboards](#12-layer-9--tableau-dashboards)
13. [Data dictionary](#13-data-dictionary)
14. [Business glossary](#14-business-glossary)
15. [How to run the pipeline](#15-how-to-run-the-pipeline)
16. [Current repository state](#16-current-repository-state)
17. [Known limitations](#17-known-limitations)

---

## 1. What this project is

PayScope simulates the internal data stack of a digital payments processor (the Stripe / Adyen / Square problem space). It is not a dashboard built on a clean CSV — the project deliberately manufactures the messy part of analytics work and then solves it:

1. Generate a realistic operational payments dataset in PostgreSQL.
2. Deliberately inject known, catalogued data-quality defects into it.
3. Profile those defects with independent SQL and Python checks.
4. Clean and validate the data, flagging rather than deleting bad records.
5. Build business-ready aggregate marts on top of the validated data.
6. Score merchant and customer risk with explainable rules.
7. Surface transaction health, merchant risk, and chargeback behaviour in Tableau.

The reason the injection step exists is measurability. Because every defect is introduced on purpose, the detection layer can be graded against a known answer key — which is impossible with an ordinary "found a messy dataset online" project.

**Scale of the dataset:**

| Table | Rows |
|---|---:|
| `customers` | 10,000 |
| `merchants` | 1,200 |
| `devices` | 15,000 |
| `transactions` | 100,000 |
| `chargebacks` | 1,851 |
| `alerts` | 9,956 |
| **Total** | **137,907** |

---

## 2. Architecture

A layered, medallion-style pipeline across three PostgreSQL schemas. Data moves in one direction only; each layer has a single responsibility and its own QA gate.

```
┌──────────────────────────────────────────────────────────────────┐
│  sql/seed/*.sql          Synthetic generation (generate_series)  │
│  sql/issues/*.sql        Controlled DQ-defect injection          │
└───────────────────────────────┬──────────────────────────────────┘
                                ▼
                        ┌───────────────┐
                        │  raw  schema  │  source data, warts and all
                        └───────┬───────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
 extract_raw.py          sql/qa/raw_qa_checks   python/dq/dq_checks.py
 (raw → CSV)             (SQL profiling)        (pandas profiling)
        │                                               │
        ▼                                               ▼
 python/outputs/extracted/*.csv              outputs/dq_reports/
        │                                    raw_dq_summary.csv
        ▼
 ┌──────────────────────────────────────────┐
 │ python/cleaning/clean_*.py               │  standardise → validate →
 │ (dependency-ordered, 6 modules)          │  flag (never delete)
 └───────────────────┬──────────────────────┘
                     ▼
        python/outputs/cleaned/*.csv
                     │
                     ▼  load_clean.py
             ┌───────────────┐
             │ clean schema  │  + is_valid_record, dq_issue_count, cleaned_at
             └───────┬───────┘
                     │            ← sql/qa/clean_qa_checks.sql
                     ▼  sql/marts/*.sql (7 scripts, ordered)
             ┌───────────────┐
             │  mart schema  │  business-ready aggregates
             └───────┬───────┘
                     │            ← sql/qa/mart_qa_checks.sql
                     ▼
              Tableau dashboards
```

### Layer contracts

| Schema | Contract | Consumers |
|---|---|---|
| `raw` | Byte-faithful copy of the source system. Never edited by the pipeline. Mixed casing, broken FKs and impossible dates are *expected* here. | extraction, raw QA |
| `clean` | Every source row is present exactly once. Nothing is deleted. Three audit columns are added: `is_valid_record`, `dq_issue_count`, `cleaned_at`. | marts, ad-hoc analysis |
| `mart` | Pre-aggregated, business-named, filtered to `is_valid_record = TRUE`. | Tableau only |

**Two design rules govern the whole pipeline:**

- **Flag, don't delete.** An invalid record stays in `clean` with `is_valid_record = FALSE` and a defect count. This preserves a full audit trail and makes the cleaning step reversible and measurable — you can always ask "what did we exclude, and why".
- **BI reads marts, never raw or clean.** Business logic lives in SQL under version control, not in Tableau calculated fields. Dashboards stay fast and every metric has one definition.

---

## 3. Environment and configuration

Connection settings live in a `.env` file at the repo root and are read by `python/config/db.py`:

```
DB_USER=...
DB_PASSWORD=...
DB_HOST=localhost
DB_PORT=5432
DB_NAME=...
```

`db.py` builds a single SQLAlchemy engine and exposes `get_engine()`. Every Python module imports from it, so there is exactly one place that knows how to reach the database.

```python
DB_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
engine = create_engine(DB_URL)
```

> **Current state (2026-10-29):** the `raw`, `clean` and `mart` schemas live in the **`payscope`** database, which matches `DB_NAME` in `.env.example`. (On 2026-08-13 they were in a database called `Projects` and every entry point failed; that is fixed.) The `payscope.raw` schema also still holds 10 tables from an unrelated transport project; see [§16](#16-current-repository-state).

---

## 4. Layer 1 — Synthetic data generation

`sql/ddl/01_create_schemas.sql` creates the three schemas; `02_raw_tables.sql` defines the six raw tables; `03_clean_tables.sql` defines their clean counterparts plus the three audit columns.

`sql/seed/01..06_seed_*.sql` populate `raw` using `generate_series` and `RANDOM()`. The generation is designed for realism rather than uniformity:

**Customers (10,000)** — sequential refs (`CUST_n`), emails on a predictable pattern (so corruption is detectable later), phone numbers on the Australian `04…` pattern, country drawn from `{AU, US, GB, IN, SG}`, signup dates spread over the past 730 days, status from `{active, inactive, suspended}`, DOB implying ages 18–70.

**Merchants (1,200)** — six industry categories (`ecommerce`, `food_delivery`, `electronics`, `gaming`, `travel`, `subscription`), five countries, five settlement currencies, onboarding over the past 1,000 days, a **source-system** risk label (`low`/`medium`/`high`), and `is_active` true for ~90%.

The `risk_tier_source` column deserves attention: it is deliberately generated **at random, independent of behaviour**. It represents the untrustworthy label an upstream system hands you. Proving that it does not predict actual behaviour is one of the project's findings — and the reason a behaviour-based segmentation layer exists at all.

**Devices (15,000)** — device type, OS, app version, and a ~5% `is_emulator` rate as a fraud signal. `country_code` and `ip_country_code` are drawn **independently**, so they disagree ~80% of the time — a deliberate geo-mismatch risk signal.

**Transactions (100,000)** — the core fact table. Amounts follow a deliberately skewed distribution (70% under $100, then a mid tier, then a long tail to $2,000) rather than a flat uniform draw. Status is generated with a realistic funnel:

```sql
CASE WHEN RANDOM() < 0.75 THEN 'approved'
     WHEN RANDOM() < 0.90 THEN 'failed'
     WHEN RANDOM() < 0.97 THEN 'pending'
     ELSE 'reversed' END
```

Response codes follow ISO-8583 convention (`'00'` success, `'05'` decline, `'91'` issuer unavailable) and are stored as **text** precisely because the leading zero is significant.

**Chargebacks (1,851)** — derived, not independent: generated only from `approved` transactions at a ~2.5% rate, inheriting the parent transaction's customer, merchant and amount, dated 1–60 days after it. This is what makes the chargeback rate a meaningful ratio.

**Alerts (9,956)** — generated from transactions at a ~10% rate across six named rules, with a risk score in 20–100 and a workflow status (`open`, `under_review`, `resolved`, `false_positive`). Note the seed emits only `low`/`medium`/`high` severity — `critical` appears *only* through the injection script, which has consequences discussed in [§17](#17-known-limitations).

---

## 5. Layer 2 — Controlled issue injection

`sql/issues/01..06_inject_*_issues.sql` are the answer key. Each script applies targeted `UPDATE`s to a random sample of rows, producing a known population of defects. The catalogue:

| # | Defect class | Example | Target |
|---|---|---|---|
| 1 | **Missing values** | `email = NULL`, `legal_name = NULL`, `device_type = NULL`, `app_version = NULL`, `chargeback_amount = NULL` | 250 / 50 / 180 / 150 / 40 |
| 2 | **Duplicates** | copy one customer's email onto another; duplicate merchant names; duplicate `transaction_ref` | 150 / 80 / 300 |
| 3 | **Format inconsistency** | `'au'`, `'usa'`, `'Active'`, `'SUSPENDED'`, `'Ecommerce'`, `'FOOD_DELIVERY'`, `'HIGH'`, `'Med'` | ~1,200 across tables |
| 4 | **Trailing whitespace** | `'travel '`, `'windows '`, `'pending '`, `'wallet '`, `'resolved '`, `'sg '` | ~500 |
| 5 | **Invalid codes** | `settlement_currency = 'AUDD' / 'XXX'`, `currency_code = 'USDX' / 'XXX'` | 82 / 290 |
| 6 | **Invalid numerics** | negative amounts, zero amounts, negative chargeback amounts, `risk_score = 150` and `-10` | 220 / 120 / 35 / 80 |
| 7 | **Impossible dates** | future signup / onboarding / transaction / alert timestamps; `last_seen_at < first_seen_at`; `resolution_date < chargeback_date`; chargeback before its transaction | ~600 |
| 8 | **Broken foreign keys** | `customer_id = 999999 + device_id` etc., pointing at rows that cannot exist | 745 across 4 tables |

Because IDs are offset into an impossible range (`900000 + transaction_id`), broken links are unambiguous — they cannot accidentally hit a real key.

The transaction-level status corruptions are worth noting as a pair: `'Approved'` and `'pending '` are *recoverable* by standardisation (case-fold and trim), whereas `'FAIL'` needs an explicit synonym mapping. This distinction — recoverable formatting vs. genuinely invalid data — is what the cleaning layer is built around.

---

## 6. Layer 3 — Extraction

`python/extraction/extract_raw.py` pulls each of the six raw tables to CSV:

```python
def extract_table(table_name, engine):
    df = pd.read_sql(f"SELECT * FROM raw.{table_name}", engine)
    df.to_csv(f"python/outputs/extracted/raw_{table_name}.csv", index=False)
```

Outputs land in `python/outputs/extracted/`. The CSV hop is a deliberate boundary: it freezes an immutable snapshot so that profiling and cleaning are repeatable against identical input, and it decouples the transformation code from database availability.

---

## 7. Layer 4 — Data-quality profiling

Quality is profiled **twice, independently**, which is a real-world control: two implementations agreeing raises confidence, and disagreement finds bugs in the checks themselves.

**SQL path** — `sql/qa/raw_qa_checks.sql` (262 lines) unions ~35 checks into a single `(table_name, check_name, result)` result set, running directly against `raw`.

**Python path** — `python/dq/dq_checks.py` runs the equivalent checks on the extracted CSVs with pandas and writes `python/outputs/dq_reports/raw_dq_summary.csv`.

Both cover five families: completeness (nulls), uniqueness (duplicates), validity (domain/range), consistency (cross-field timing), and referential integrity (broken FKs).

**Recorded raw profile** (`raw_dq_summary.csv`, 37 checks):

| Table | Rows | Key findings |
|---|---:|---|
| `raw.customers` | 10,000 | 244 null emails · 269 duplicate emails · 39 future signups |
| `raw.merchants` | 1,200 | 50 null legal names · 80 duplicate names · 82 invalid currencies · 29 future onboardings |
| `raw.devices` | 15,000 | 180 null device types · 150 null app versions · 90 broken customer links · 361 impossible timings |
| `raw.transactions` | 100,000 | 300 duplicate refs · 220 negative + 124 zero amounts · 290 invalid currencies · 260 broken links |
| `raw.chargebacks` | 1,851 | 40 null + 35 negative amounts · 110 broken links · 433 invalid resolution timings |
| `raw.alerts` | 9,956 | 80 out-of-range risk scores · 285 broken links |

---

## 8. Layer 5 — Cleaning and validation

Six modules in `python/cleaning/`, each following an identical four-stage contract.

### Stage 1 — Standardise (recover what is recoverable)

```python
df["country_code"] = df["country_code"].astype("string").str.strip().str.upper()
df["status"]       = df["status"].astype("string").str.strip().str.lower()
df["country_code"] = df["country_code"].replace({"USA": "US"})   # explicit synonym
df["status"]       = df["status"].replace({"fail": "failed"})
```

Trim-and-case-fold silently repairs the whitespace and casing defects; explicit `replace` maps handle true synonyms. Dates go through `pd.to_datetime(..., errors="coerce")` and numerics through `pd.to_numeric(..., errors="coerce")`, so unparseable values become `NaT`/`NaN` and are caught as defects downstream instead of crashing the run.

### Stage 2 — Validate against declared domains

Each module declares its allowed vocabularies as module-level constants, e.g. in `clean_transactions.py`:

```python
VALID_STATUSES        = {"approved", "failed", "pending", "reversed"}
VALID_CURRENCIES      = {"AUD", "USD", "GBP", "INR", "SGD"}
VALID_PAYMENT_METHODS = {"card", "wallet", "bank_transfer"}
VALID_COUNTRIES       = {"AU", "US", "GB", "IN", "SG"}
```

### Stage 3 — Accumulate defects as boolean masks

Every rule is a vectorised boolean mask; masks are summed into `dq_issue_count`, so a row carries *how many* things are wrong with it, not just a pass/fail:

```python
issue_masks = [duplicate_transaction_ref, missing_amount, invalid_amount,
               future_transaction, missing_transaction_ts, invalid_status,
               invalid_currency, invalid_payment_method,
               invalid_merchant_country, invalid_customer_country,
               invalid_device_country, broken_customer_link,
               broken_merchant_link, broken_device_link]

for mask in issue_masks:
    df.loc[mask, "dq_issue_count"] += 1

df["is_valid_record"] = df["dq_issue_count"] == 0
df["cleaned_at"] = pd.Timestamp.now()
```

Rule counts per table: customers 6 · merchants 7 · devices 8 · transactions 14 · chargebacks 9 · alerts 11 — **55 validation rules** in total.

### Stage 4 — Emit with audit columns

Output goes to `python/outputs/cleaned/clean_*.csv` with `is_valid_record`, `dq_issue_count` and `cleaned_at` appended.

### Execution order matters

The modules form a dependency graph, because fact tables validate their foreign keys against the **already-cleaned** dimensions:

```
clean_customers  →  clean_devices  →  clean_merchants
                          ↓
                  clean_transactions
                          ↓
              clean_chargebacks , clean_alerts
```

```python
valid_customer_ids = set(customers.loc[customers["is_valid_record"] == True, "customer_id"])
broken_customer_link = ~df["customer_id"].isin(valid_customer_ids)
```

Note carefully what this does: a transaction is flagged not only when its `customer_id` does not exist, but also when the customer exists yet was itself flagged for any reason. This cascade is the single most consequential design decision in the project, and its effect is quantified in [§17](#17-known-limitations).

### Verified cleaning results (live `clean` schema, 2026-08-13)

| Table | Total rows | Valid | Invalid | Valid rate | Avg defects/row |
|---|---:|---:|---:|---:|---:|
| customers | 10,000 | 9,446 | 554 | 94.46% | 0.067 |
| devices | 15,000 | 13,426 | 1,574 | 89.51% | 0.108 |
| merchants | 1,200 | 1,001 | 199 | 83.42% | 0.179 |
| transactions | 100,000 | 69,713 | 30,287 | 69.71% | 0.337 |
| alerts | 9,956 | 6,675 | 3,281 | 67.04% | 0.669 |
| chargebacks | 1,851 | 883 | 968 | 47.70% | 0.866 |

`python/reporting/before_after_summary.py` joins the raw defect counts to these clean-layer outcomes and writes `python/outputs/business_reports/before_after_cleaning_summary.csv`, quantifying the cleaning impact per table.

---

## 9. Layer 6 — Loading to the clean schema

`python/loading/load_clean.py` writes the six cleaned CSVs into the `clean` schema:

```python
df.to_sql(name=table_name, con=engine, schema="clean",
          if_exists="replace", index=False)
```

> **Important:** `if_exists="replace"` makes pandas **drop and recreate** each table, so the carefully typed definitions in `sql/ddl/03_clean_tables.sql` are discarded at load time and replaced with pandas-inferred types. Verified consequences are documented in [§17](#17-known-limitations) — this is the highest-priority defect in the pipeline.

`sql/qa/clean_qa_checks.sql` then reports total / valid / invalid / average-defect counts per clean table as the layer's QA gate.

---

## 10. Layer 7 — Business marts

Seven scripts in `sql/marts/`, orchestrated by `sql/run_marts.sql` (which ends by running the mart QA gate). All of them filter `WHERE is_valid_record = TRUE` — the point where flagged records finally leave the analytical path.

| # | Mart | Grain | Rows (live) | Compression |
|---|---|---|---:|---:|
| 1 | `daily_transaction_monitoring` | date | 404 | 172:1 |
| 2 | `merchant_performance_summary` | merchant | 1,001 | 70:1 |
| 3 | `chargeback_summary` | date × reason × status | 812 | 1.1:1 |
| 4 | `alerts_summary` | date × rule × severity × status | 5,913 | 1.1:1 |
| 5 | `customer_risk_features` | customer | 9,446 | 7:1 |
| 6 | `merchant_risk_segmentation` | merchant | 1,001 | 70:1 |
| 7 | `risk_rule_hits` | rule × entity | 1,256 | — |

### The key SQL technique: aggregate before joining

`merchant_performance_summary` is the pattern worth highlighting. Joining transactions, chargebacks and alerts to merchants in one query would multiply the grains together and inflate every measure. Instead each fact is collapsed to merchant grain in its own CTE first, and only then joined:

```sql
WITH txn AS (SELECT merchant_id, COUNT(*) …  FROM clean.transactions  WHERE is_valid_record GROUP BY merchant_id),
     cb  AS (SELECT merchant_id, COUNT(*) …  FROM clean.chargebacks   WHERE is_valid_record GROUP BY merchant_id),
     al  AS (SELECT merchant_id, COUNT(*) …  FROM clean.alerts        WHERE is_valid_record GROUP BY merchant_id)
SELECT m.*, COALESCE(txn.total_transactions, 0), …
FROM clean.merchants m
LEFT JOIN txn USING (merchant_id)
LEFT JOIN cb  USING (merchant_id)
LEFT JOIN al  USING (merchant_id)
WHERE m.is_valid_record = TRUE;
```

Three supporting habits appear throughout: `LEFT JOIN` + `COALESCE(…, 0)` so a merchant with no chargebacks reads as zero rather than disappearing; `NULLIF(denominator, 0)` on every ratio to make division-by-zero return `NULL` instead of erroring; and `ROUND(…::numeric, 2)` for presentation-ready output.

### Verified mart figures (2026-08-13)

**Transaction monitoring** — 69,713 transactions · $9,250,152 processed · 75.02% approval · 22.57% failure · 30.35% cross-border · 404 days (2025-04-17 → 2026-05-26).

**Chargebacks** — 883 valid · $114,447 total · $129.61 average (the dashboard KPI still shows $130.95, an average of row averages; see roadmap P0-6).

| Reason | Count | Amount | | Outcome | Count |
|---|---:|---:|---|---|---:|
| duplicate_processing | 236 | $32,332 | | closed | 233 |
| service_not_received | 223 | $25,507 | | lost | 226 |
| fraud | 213 | $26,373 | | open | 218 |
| authorization_issue | 211 | $30,235 | | won | 206 |

**Alerts** — 6,675 valid, spread evenly across the six rules (1,047–1,163 each), average risk score 58.7–60.3. Severity mix: medium 2,264 · high 2,211 · low 2,173 · critical 27.

---

## 11. Layer 8 — Risk engine

Risk is scored with **explainable rules, not a model**. In a payments-risk context a merchant whose settlement is held or a customer whose account is frozen is entitled to a reason, and an analyst has to be able to defend the decision. A rule engine trades marginal accuracy for auditability, which is the correct trade here.

### Customer risk — `mart.customer_risk_features`

Builds ~20 behavioural features per customer (volumes, failure rate, cross-border rate, distinct merchants and devices used, chargeback count and value, alert counts by severity, average risk score), then applies a disjunctive flag:

```sql
CASE WHEN COALESCE(cb.chargeback_count, 0)            >= 2
       OR COALESCE(al.critical_severity_alerts, 0)    >= 1
       OR COALESCE(al.high_severity_alerts, 0)        >= 3
       OR COALESCE(txn.failed_transactions, 0)        >= 5
     THEN TRUE ELSE FALSE END AS high_risk_customer_flag
```

`distinct_devices_used` and `distinct_merchants_used` are genuine fraud features — card-testing and account-takeover both show up as one customer spraying across unusually many devices or merchants.

**Verified outcome:** 329 of 9,446 customers flagged (3.5%). Flagged customers average a 44.51% failure rate against 21.76% for the rest — a 2.0× separation, so this flag does discriminate.

### Merchant risk — `mart.merchant_risk_segmentation`

Reads `merchant_performance_summary` and assigns a four-tier segment from three observed behaviours — chargeback rate, failure rate, alert volume — plus a parallel numeric band (1–4) for sorting:

| Segment | Band | Triggers (any one) |
|---|---:|---|
| Critical | 4 | chargeback ≥ 4% **or** failure ≥ 35% **or** alerts ≥ 12 |
| High Risk | 3 | chargeback ≥ 2.5% **or** failure ≥ 28% **or** alerts ≥ 9 |
| Monitor | 2 | chargeback ≥ 1.5% **or** failure ≥ 22% **or** alerts ≥ 6 |
| Low Risk | 1 | none of the above |

`WHERE total_transactions > 0` excludes merchants with no activity, which also protects the `NULL` ratios from being compared.

**Verified distribution:**

| Segment | Merchants | Avg failure | Avg chargeback | Avg alerts | Transactions |
|---|---:|---:|---:|---:|---:|
| Monitor | 440 | 21.77% | 0.78% | 6.1 | 30,499 |
| High Risk | 392 | 24.15% | 1.68% | 7.4 | 27,526 |
| Critical | 81 | 23.71% | 2.87% | 9.1 | 5,697 |
| Low Risk | 88 | 18.64% | 0.53% | 3.9 | 5,991 |

The thresholds are mis-calibrated — 91% of merchants land in Monitor or worse. This is analysed and quantified in [§17](#17-known-limitations).

### Explainability — `mart.risk_rule_hits`

The most portfolio-relevant object in the project. Instead of an opaque score, it emits **one row per triggered rule per entity**, with a human-readable description, so any flag can be traced to its cause:

| Rule | Entity | Condition | Entities hit | Total hits |
|---|---|---|---:|---:|
| `high_activity_device` | device | ≥ 10 valid transactions | 544 | 5,858 |
| `repeated_failed_payments` | customer | ≥ 5 failed transactions | 261 | 1,392 |
| `repeated_risky_alerts` | merchant | ≥ 9 valid alerts | 217 | 2,239 |
| `merchant_chargeback_spike` | merchant | chargeback rate ≥ 2.5% | 202 | 462 |
| `high_chargeback_customer` | customer | ≥ 2 valid chargebacks | 32 | 67 |

The five rules are `UNION ALL`-ed into a common schema — `(rule_name, entity_type, entity_id, rule_hit_count, rule_description)` — which is the right shape: adding a rule means adding a `UNION ALL` block, and no consumer changes.

---

## 12. Layer 9 — Tableau dashboards

Three dashboards read exclusively from the `mart` schema.

**Dashboard 1 — Transaction Monitoring.** KPI tiles (69,713 transactions · $9,250,152 · 75.02% approval · 22.57% failure) above a dual-axis weekly chart: bars for volume, line for approval rate. Answers *are payments healthy, and is that changing?* Source: `daily_transaction_monitoring`.

**Dashboard 2 — Merchant Risk.** KPI tiles (1,001 merchants · 473 high-risk · 1.28% chargeback rate) above a failure-rate × chargeback-rate scatter, coloured by risk segment. Answers *which merchants need intervention?* Source: `merchant_risk_segmentation`. The 473 figure is Critical (81) + High Risk (392).

**Dashboard 3 — Chargeback Analysis.** KPI tiles ($114,447 · 883 disputes · $129.61 average) with chargebacks by reason, dispute outcomes, and a weekly amount trend. Answers *where do disputes come from and how do they resolve?* Source: `chargeback_summary`.

A note on reading Dashboard 2: the scatter shows clear **horizontal colour banding** rather than clusters, and a row of Critical/High-Risk points sitting at exactly 0% chargeback rate. That is the visual signature of hard absolute thresholds — the segments are drawn by the cut-offs, not discovered in the data. It is a useful diagnostic image and directly motivates the re-calibration recommendation.

---

## 13. Data dictionary

### `customers` (10,000)

| Column | Type | Notes |
|---|---|---|
| `customer_id` | BIGSERIAL PK | |
| `customer_ref` | TEXT | Business key, `CUST_n` |
| `full_name`, `phone` | TEXT | |
| `email` | TEXT | Injected: nulls, duplicates, invalid format |
| `country_code` | TEXT | Domain: AU, US, GB, IN, SG |
| `signup_date`, `date_of_birth` | DATE | Injected: future signups |
| `status` | TEXT | Domain: active, inactive, suspended |
| `created_at`, `updated_at` | TIMESTAMP | |

### `merchants` (1,200)

| Column | Type | Notes |
|---|---|---|
| `merchant_id` | BIGSERIAL PK | |
| `merchant_ref`, `merchant_name`, `legal_name` | TEXT | Injected: duplicate names, null legal names |
| `merchant_category` | TEXT | 6 categories |
| `country_code` | TEXT | 5 countries |
| `settlement_currency` | TEXT | AUD, USD, GBP, INR, SGD |
| `onboarding_date` | DATE | Injected: future dates |
| `risk_tier_source` | TEXT | **Random by design** — upstream label, not ground truth |
| `is_active` | BOOLEAN | ~90% true |

### `devices` (15,000)

| Column | Type | Notes |
|---|---|---|
| `device_id` | BIGSERIAL PK | |
| `customer_id` | BIGINT FK | Injected: broken links |
| `device_type` | TEXT | mobile, desktop, tablet |
| `os_name` | TEXT | ios, android, windows, macos |
| `app_version` | TEXT | Injected: nulls |
| `is_emulator` | BOOLEAN | ~5% — fraud signal |
| `first_seen_at`, `last_seen_at` | TIMESTAMP | Injected: `last < first` |
| `country_code`, `ip_country_code` | TEXT | Drawn independently → geo-mismatch signal |

### `transactions` (100,000)

| Column | Type | Notes |
|---|---|---|
| `transaction_id` | BIGSERIAL PK | |
| `transaction_ref` | TEXT | Injected: duplicates |
| `customer_id`, `merchant_id`, `device_id` | BIGINT FK | Injected: broken links |
| `transaction_ts` | TIMESTAMP | Injected: future dates |
| `amount` | NUMERIC(12,2) | Skewed distribution; injected: negative, zero |
| `currency_code` | TEXT | Injected: `USDX`, `XXX`, lowercase |
| `status` | TEXT | approved, failed, pending, reversed |
| `payment_method` | TEXT | card, wallet, bank_transfer |
| `response_code` | TEXT | ISO-8583: `00`, `05`, `91` — **leading zero is significant** |
| `is_cross_border` | BOOLEAN | |
| `merchant_/customer_/device_country_code` | TEXT | Denormalised for geo analysis |

### `chargebacks` (1,851)

| Column | Type | Notes |
|---|---|---|
| `chargeback_id` | BIGSERIAL PK | |
| `transaction_id`, `customer_id`, `merchant_id` | BIGINT FK | Inherited from parent transaction |
| `chargeback_date` | DATE | 1–60 days after transaction |
| `chargeback_amount` | NUMERIC(12,2) | Usually the full transaction amount |
| `chargeback_reason` | TEXT | fraud, service_not_received, duplicate_processing, authorization_issue |
| `dispute_status` | TEXT | open, won, lost, closed |
| `resolution_date` | DATE | NULL for ~25% (unresolved) |

### `alerts` (9,956)

| Column | Type | Notes |
|---|---|---|
| `alert_id` | BIGSERIAL PK | |
| `transaction_id`, `customer_id`, `merchant_id`, `device_id` | BIGINT FK | |
| `alert_ts` | TIMESTAMP | 0–48h after transaction |
| `rule_name` | TEXT | 6 rules |
| `severity` | TEXT | Seed emits low/medium/high; `critical` only from injection |
| `risk_score` | NUMERIC(5,2) | 20–100; injected out-of-range 150 / −10 |
| `alert_status` | TEXT | open, under_review, resolved, false_positive |

### Audit columns (all `clean.*` tables)

| Column | Type | Meaning |
|---|---|---|
| `is_valid_record` | BOOLEAN | `dq_issue_count == 0`; marts filter on this |
| `dq_issue_count` | INTEGER | Number of validation rules the row failed |
| `cleaned_at` | TIMESTAMP | When the cleaning module processed the row |

---

## 14. Business glossary

| Term | Definition as implemented |
|---|---|
| **Approval rate** | `approved / total transactions × 100`, valid records only |
| **Failure rate** | `failed / total transactions × 100` |
| **Chargeback rate** | `chargeback count / total transactions × 100` — the metric card schemes police; sustained breach of ~1% risks penalties or programme termination |
| **Cross-border rate** | `is_cross_border` share; higher rates carry higher fraud and FX exposure |
| **Chargeback** | A customer-initiated forced reversal via their issuer, distinct from a merchant refund |
| **Dispute outcome** | `won` (merchant keeps funds), `lost` (funds reversed), `open`, `closed` |
| **Response code** | ISO-8583 processor result: `00` approved, `05` do-not-honour, `91` issuer unavailable |
| **Source risk tier** | Upstream system's merchant label; random by construction here |
| **Risk segment** | Behaviour-derived tier (Critical / High Risk / Monitor / Low Risk) computed by PayScope |
| **Valid record** | Passed every validation rule for its table |
| **DQ issue count** | Count of failed rules for a row — a severity proxy |
| **Emulator** | Simulated device; a recognised fraud-automation signal |
| **Geo mismatch** | Device country ≠ IP country — VPN / proxy / location-spoofing signal |

---

## 15. How to run the pipeline

Prerequisites: PostgreSQL running locally, Python 3.13, and a `.env` file with valid credentials.

```bash
# 0. Environment
python -m venv .venv && source .venv/bin/activate
pip install pandas sqlalchemy psycopg2-binary python-dotenv
```

```bash
# 1. Schemas, tables, synthetic data, injected defects
psql -d "$DB_NAME" -f sql/ddl/01_create_schemas.sql
psql -d "$DB_NAME" -f sql/ddl/02_raw_tables.sql
psql -d "$DB_NAME" -f sql/ddl/03_clean_tables.sql
for f in sql/seed/0*.sql;   do psql -d "$DB_NAME" -f "$f"; done
for f in sql/issues/0*.sql; do psql -d "$DB_NAME" -f "$f"; done
```

```bash
# 2. Profile the raw layer
psql -d "$DB_NAME" -f sql/qa/raw_qa_checks.sql
python -m python.extraction.extract_raw
python -m python.dq.dq_checks
```

```bash
# 3. Clean — dependency order is mandatory
python -m python.cleaning.clean_customers
python -m python.cleaning.clean_devices
python -m python.cleaning.clean_merchants
python -m python.cleaning.clean_transactions
python -m python.cleaning.clean_chargebacks
python -m python.cleaning.clean_alerts
```

```bash
# 4. Load and verify
python -m python.loading.load_clean
psql -d "$DB_NAME" -f sql/qa/clean_qa_checks.sql
python -m python.reporting.before_after_summary
```

```bash
# 5. Build marts (must run from the repo root — run_marts.sql uses relative \i paths)
psql -d "$DB_NAME" -f sql/run_marts.sql
```

```
# 6. Open the Tableau workbook and point it at the mart schema.
```

All Python modules must be invoked as `python -m python.<package>.<module>` from the repo root, because they use package-qualified imports (`from python.config.db import get_engine`) and repo-root-relative output paths.

---

## 16. Current repository state

Verified against the live database on 2026-10-29 (previous snapshot: 2026-08-13).

**Database location.** The `raw`, `clean` and `mart` schemas live in the `payscope` database (6 + 6 + 7 PayScope tables). `payscope.raw` also contains 10 tables belonging to an unrelated transport-analytics project (`agency`, `calendar`, `routes`, `stops`, `stop_times`, `trips`, `feed_info`, `calendar_dates`, `realtime_trip_stop_time_updates`, `static_load_history`). Because `load_clean.py` uses `if_exists="replace"`, a mistyped table name could drop another project's data, so a separate database per project is still advisable.

**Populated and working:** DDL/seed/issue scripts · 6 extraction+cleaning modules · 3 QA scripts · 7 mart scripts · before/after reporting · `run_pipeline.sh` orchestrator · 3 Tableau dashboards · all clean/mart tables populated. Headline figures re-verified: 100,000 transactions of which 69,713 valid, $9,250,152, 883 chargebacks worth $114,447.09.

**Resolved since 2026-08-13:** empty placeholder files removed; `.gitignore` and `requirements.txt` filled in; `.env` is no longer tracked (`.env.example` documents the variables); generated outputs and build artefacts are no longer tracked; `db.py` hardened.

**Still open:**
- The old `.env` (with the database password) remains in git history until the password is rotated and, optionally, the history is purged (roadmap P0-1).
- The published Tableau Public workbook displays volume and amount KPIs at exactly 2x the database (see roadmap P0-6).
- The type, reproducibility and validity findings in §17 are documented but not yet fixed.

---

## 17. Known limitations

These are verified measurements against the live database, not speculation. They are the honest reading of the pipeline's behaviour, and each has a corresponding recommendation in `UPGRADE_ROADMAP.md`.

### 17.1 The validity cascade dominates the transaction valid rate

Of 30,287 invalid transactions, **29,702 (98.1%)** are invalid *only* because they reference a customer, merchant or device that was itself flagged. Just **585** have a defect of their own.

The observed valid rate is essentially the product of the dimension valid rates:

```
0.9446 (customers) × 0.8342 (merchants) × 0.8951 (devices) = 0.7053
observed transaction valid rate                            = 0.6971
```

So "69.71% of transactions are valid" does not measure transaction quality — it measures the compounded strictness of three upstream tables. Concretely, **6,768 transactions are excluded from every mart because their merchant shares a duplicate name with another merchant** — a cosmetic attribute problem that says nothing about whether the payment happened. The same mechanism drives the chargebacks table down to a 47.70% valid rate.

### 17.2 The pipeline is not reproducible over time

Freshness checks compare against wall-clock time (`NOW()`, `pd.Timestamp.now()`), so injected future-dated defects silently *decay into valid records* as time passes:

| Defect | Injected | Recorded in DQ report | Present today |
|---|---:|---:|---:|
| Future transactions | 180 | 18 | 0 |
| Future alerts | 120 | 0 | 0 |

Consequence in the marts: 105 transactions across 38 days sit **beyond the extraction date**, stretching the fact table to 2026-05-26 and producing the thin tail visible at the right edge of Dashboard 1's volume chart. Re-running the pipeline on a different day yields different results from identical input.

### 17.3 Risk thresholds sit below the population baseline

The Monitor tier triggers at `failure_rate >= 22%`, but the **median merchant failure rate is 22.7%** — the threshold is at the middle of the distribution (5th–95th percentile: 14.5%–30.8%). Trigger coverage:

| Trigger | Merchants caught (of 1,001) |
|---|---:|
| `failure_rate >= 22` (Monitor) | 554 |
| `alert_count >= 6` (Monitor) | 677 |
| `chargeback_rate >= 1.5` (Monitor) | 346 |
| `failure_rate >= 35` (Critical) | 7 |

Only **88 merchants (8.8%)** end up Low Risk; 91% are Monitor or worse. And the segments barely separate on the driver that defines them — Low Risk averages 18.64% failure against Critical's 23.71%. A risk flag that fires on 91% of the population cannot support a decision. The thresholds need to be derived from the observed distribution (percentiles, or peer-group medians within category × country) rather than chosen in absolute terms.

### 17.4 The source risk tier finding holds up statistically

The README's claim that the upstream label is uninformative is correct, and now has a test behind it:

| `risk_tier_source` | Critical | High Risk | Monitor | Low Risk | Critical rate |
|---|---:|---:|---:|---:|---:|
| high | 24 | 132 | 161 | 37 | 6.8% |
| medium | 32 | 119 | 147 | 22 | 10.0% |
| low | 25 | 141 | 132 | 29 | 7.6% |

χ² = 8.10, dof = 6, **p = 0.231** → no statistically significant association. Cramér's V = 0.064 (negligible). The `low` tier even shows a *higher* Critical rate than the `high` tier. This is expected — `risk_tier_source` is generated at random by the seed — but it makes the point cleanly: the behavioural segmentation layer is not decoration, it is the only merchant-risk signal in the system that carries information.

### 17.5 The clean-layer DDL never takes effect, and types degrade

`load_clean.py`'s `if_exists="replace"` drops the tables defined in `sql/ddl/03_clean_tables.sql` and lets pandas re-infer the schema. Verified against `information_schema`:

- **Zero constraints** exist on any `clean` or `mart` table — no primary keys, so `03_clean_tables.sql` is effectively dead code.
- `transaction_ts` and `cleaned_at` are stored as **`text`**, not `timestamp`.
- `amount` is **`double precision`** — binary floating point for monetary values, instead of the declared `NUMERIC(12,2)`.
- `response_code` became **`bigint`**, destroying the ISO-8583 leading zeros: `'00' → 0`, `'05' → 5`. All **96,404** non-null response codes are affected, and the field can no longer round-trip to its source meaning.

### 17.6 Detection coverage does not match the injection catalogue

Two gaps in opposite directions:

**Undetected injection.** `05_inject_chargeback_issues.sql` back-dates chargebacks to before their parent transaction, but no rule anywhere checks `chargeback_date >= transaction_ts`. **41 such rows flow into the marts as valid.**

**Defects credited to injection that the seed created on its own:**

| Check | Actual | Injected | Caused by seed logic |
|---|---:|---:|---:|
| `devices.last_seen_at < first_seen_at` | 361 | 70 | 291 (81%) |
| `chargebacks.resolution_date < chargeback_date` | 433 | 35 | 398 (92%) |

The seed draws `last_seen_at` within the past 30 days but `first_seen_at` across 730 days, and draws `resolution_date` and `chargeback_date` independently — so it generates impossible orderings by construction. The answer key is therefore inaccurate for these two checks.

### 17.7 Duplicate flagging penalises the uncorrupted row

All duplicate checks use `duplicated(keep=False)`, which flags **every** member of a duplicate group. When the injection copies merchant A's name onto merchant B, both A and B are invalidated — A having done nothing wrong. Of 81 merchants flagged for duplicate names, roughly half were never corrupted. `keep="first"` would penalise only the offending copy.

### 17.8 Two "summary" marts are not summaries

`chargeback_summary` is grouped by `(date, reason, dispute_status)` yet also computes `open_disputes`, `won_disputes`, `lost_disputes` and `closed_disputes`. Because `dispute_status` is already a grain key, in **all 812 rows a single counter holds the entire count and the other three are zero** — the columns are degenerate. `alerts_summary` has the same defect with `severity` and `alert_status`.

The compression ratios confirm it: `chargeback_summary` is 812 rows for 883 chargebacks (1.09:1) and `alerts_summary` is 5,913 rows for 6,675 alerts (1.13:1). Both are near-copies of their source tables with a `GROUP BY` attached, unlike `daily_transaction_monitoring` (172:1), which is a genuine aggregate.

### 17.9 A documented risk driver is an artefact of the corruption script

`customer_risk_features` treats `critical_severity_alerts >= 1` as a high-risk trigger. But the seed only ever emits `low`, `medium` and `high` — `critical` exists **solely** because `06_inject_alert_issues.sql` writes it to 40 random rows as a label-inconsistency defect. 27 such alerts survive into the marts, where they function as a genuine risk signal. A data-corruption script is feeding a production risk rule.

### 17.10 Smaller items

- `python/test_connection.py` uses `from config.db import get_engine` while every other module uses `from python.config.db import …`; it fails under the documented `python -m` invocation.
- `run_marts.sql` uses relative `\i sql/marts/…` paths, so it only works when `psql` is launched from the repo root.
- Each mart script is `DROP TABLE` + `CREATE TABLE AS` with a trailing `SELECT … LIMIT 10` inspection query. Outside a transaction, a mid-run failure leaves marts dropped and not rebuilt.
- `load_clean.py` has no `chunksize`, so the 100,000-row transaction load is slower than necessary.
- No indexes exist on the `clean` foreign-key columns that every mart joins on.
- The QA scripts print result sets for a human to read; nothing fails a build, so a regression cannot be caught automatically.

---

*Companion documents: `TECHNICAL_REPORT.md` (findings and analysis) · `UPGRADE_ROADMAP.md` (prioritised improvements).*

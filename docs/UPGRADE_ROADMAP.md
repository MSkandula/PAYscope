# PayScope — Upgrade Roadmap

Prioritised improvements, derived from the audit in `TECHNICAL_REPORT.md`. Each item states the problem, the fix, and why it is worth doing. Effort is rough: **S** ≈ under an hour, **M** ≈ a few hours, **L** ≈ a day or more.

**Suggested order if you only do six things:** P0-1 (rotate the leaked password), P0-3 (fix `DB_NAME`), P0-4 (type enforcement at load), P1-1 (severity-tiered validity), P1-2 (recalibrate thresholds), P2-1 (`requirements.txt` + orchestrator). Those six remove the security exposure, make the repo runnable by a stranger, and fix the two findings a reviewer is most likely to probe.

---

## Status (2026-10-29)

| Item | Status |
|---|---|
| P0-1 Leaked password | **Partly done.** `.env` is untracked and `.env.example` added. **Still required:** rotate the password (it remains in git history). |
| P0-2 `.gitignore` / untrack outputs | **Done.** |
| P0-3 `DB_NAME` | **Done.** The `payscope` database exists and is populated. (Unrelated transport tables still share `payscope.raw`.) |
| P0-4, P0-5, P1-x | Open. |
| P2-1 requirements + orchestrator | **Done:** `requirements.txt` and `run_pipeline.sh`. |
| P2-6 placeholder files | **Done:** empty files removed; `test_connection.py` rewritten. |
| P3-6 dashboard screenshots | Open (and see P0-6). |
| **P0-6** (new) Published dashboards show 2x values | **Open.** See below. |

### P0-6 · Published Tableau Public KPIs are exactly double the database `S` 🔴

**Problem.** Checked on 2026-10-29: the published workbook shows 139,426 transactions (database: 69,713), $18,500,305 total amount ($9,250,152), 1,766 chargebacks (883) and $228,894.18 chargeback amount ($114,447.09). Ratio KPIs (75.02% approval, 22.57% failure) are unaffected because doubling cancels out. The marts in PostgreSQL are correct (404 days, 69,713 transactions, 883 chargebacks, no duplicate rows), so the duplication is in the Tableau extract or data source, not the warehouse.

**Fix.** In Tableau Desktop open the Data Source tab for each mart and compare row counts with the database (`daily_transaction_monitoring` = 404, `chargeback_summary` = 812). Refresh the extract (or switch to a live connection), confirm the KPIs read 69,713 / 883 / $114,447 / $9,250,152, then republish. Also change the "Avg CB" KPI to `SUM(total_chargeback_amount) / SUM(chargeback_count)` so it reads $129.61 instead of the average of row averages.

**Why.** The public link is what a reviewer clicks first. It must agree with the README.

---

## P0 — Correctness and security (do first)

### P0-1 · Remove the leaked database password `S` 🔴

**Problem.** `.env`, containing the live PostgreSQL password, is tracked in git (`git ls-files .env` confirms it) and has been committed since April. Anyone who clones or views the repo has the credential.

**Fix.**
1. **Rotate the password first** — assume it is compromised. This is the only step that actually closes the exposure; the rest is cleanup.
2. Untrack the file and commit a template instead:

```bash
git rm --cached .env
printf 'DB_USER=\nDB_PASSWORD=\nDB_HOST=localhost\nDB_PORT=5432\nDB_NAME=payscope\n' > .env.example
git add .env.example
```

3. Purging it from history needs a force-push and rewrites every commit SHA (`git filter-repo --path .env --invert-paths`). Removing it going forward plus rotating the password is usually enough for a portfolio repo — but do decide deliberately rather than by default.

**Why.** A recruiter or engineer browsing the repo finding a committed credential undoes the impression the rest of the project earns.

---

### P0-2 · Add a real `.gitignore` `S`

**Problem.** `.gitignore` is 0 bytes. Tracked as a result: `.venv/`, six `__pycache__/` directories, eight `.DS_Store` files, and ~32 MB of generated CSVs (`clean_transactions.csv` alone is 13 MB).

**Fix.**

```gitignore
.venv/
__pycache__/
*.pyc
.DS_Store
.env
python/outputs/
```

Then `git rm -r --cached .venv __pycache__ python/outputs` and commit. Keep one small sample CSV per table if you want the repo to be browsable without a database.

**Why.** The pipeline is the deliverable; its output is regenerable. A repo whose diff is dominated by a 100,000-row CSV is hard to review, and committed virtualenvs read as inexperience.

---

### P0-3 · Fix the database name so the project actually runs `S`

**Problem.** `.env` sets `DB_NAME=payscope`, but that database no longer exists — the schemas live in `Projects`. Every Python entry point currently fails with `FATAL: database "payscope" does not exist`.

**Fix.** Point `DB_NAME` at the real database, and preferably give PayScope its own:

```bash
createdb payscope
pg_dump -d Projects -n raw -n clean -n mart | psql -d payscope
```

**Why.** Beyond being broken, `Projects.raw` currently mixes PayScope's 6 tables with 10 tables from an unrelated transport project (`agency`, `routes`, `stops`, `trips`, …). Combined with P0-4's `if_exists="replace"`, a mistyped table name can drop another project's data. One database per project removes the hazard.

---

### P0-4 · Enforce types at the load boundary `M` 🔴

**Problem** (§4.5). `load_clean.py` uses `if_exists="replace"`, so pandas drops each table and re-infers its schema. Consequences verified against `information_schema`: **zero constraints** on any `clean`/`mart` table, `sql/ddl/03_clean_tables.sql` is dead code, `transaction_ts` and `cleaned_at` are stored as `text`, `amount` is `double precision` (float money), and `response_code` became `bigint` — silently destroying ISO-8583 leading zeros (`'00' → 0`) across all 96,404 non-null values.

**Fix.** Create tables from the DDL once, then truncate and append rather than replace:

```python
DTYPES = {"response_code": str, "transaction_ref": str, "currency_code": str}

df = pd.read_csv(path, dtype=DTYPES)          # preserve '00'
with engine.begin() as conn:
    conn.execute(text(f"TRUNCATE clean.{table_name}"))
    df.to_sql(table_name, conn, schema="clean",
              if_exists="append", index=False, chunksize=10_000)
```

Add `NUMERIC(12,2)` for all money columns and `TEXT` for `response_code` in the DDL (both already correct there — they just need to survive the load). `chunksize` also makes the 100k-row load materially faster.

**Why.** The DDL author already made the right call on `response_code`; the loader overrode it. Type contracts that a write path can silently discard are documentation, not contracts. Float money is also a genuine correctness bug — sums of `double precision` don't round-trip to cents.

---

### P0-5 · Introduce an explicit logical run date `M` 🔴

**Problem** (§4.4). Freshness checks compare against wall-clock time (`NOW()`, `pd.Timestamp.now()`), so injected future-dated defects decay into valid records: 180 future transactions injected → 18 recorded → 0 today. 105 future-dated transactions now sit in the marts as real payments, producing the thin tail on Dashboard 1.

**Fix.** Thread one `RUN_DATE` through every layer, defaulting to today but overridable:

```python
# python/config/run_context.py
import os
import pandas as pd

RUN_DATE = pd.Timestamp(os.getenv("PAYSCOPE_RUN_DATE", pd.Timestamp.today().normalize()))
```

Replace every `pd.Timestamp.now()` / `pd.Timestamp.today()` in the cleaning and DQ modules with `RUN_DATE`, and pass it to psql as a variable (`psql -v run_date="'2026-04-17'"`, then `:'run_date'::date` in place of `NOW()`/`CURRENT_DATE`). Set `cleaned_at = RUN_DATE` too, so re-runs are byte-identical.

**Why.** This is the difference between a script and a pipeline. Identical input currently produces different output on different days, which means no result can be reproduced or regression-tested — and it is the first thing an interviewer will find if they re-run the project.

---

## P1 — Analytical credibility

### P1-1 · Split validity by severity and stop cascading `L` 🔴

**Problem** (§4.2). Of 30,287 invalid transactions, **29,702 (98.1%)** are invalid only because they reference a dimension row that was itself flagged; **6,768** because their merchant shares a name with another merchant. Only 585 have a defect of their own. The reported 69.71% valid rate is the product of three dimension valid rates, not a measure of transaction quality.

**Fix.** Two changes, in this order.

**(a) Replace the single boolean with severity tiers.** Classify each rule as `critical` (breaks analysis), `warning` (worth knowing) or `cosmetic` (formatting):

| Rule class | Examples | Effect |
|---|---|---|
| `critical` | broken FK with no resolvable parent, amount ≤ 0, unparseable/missing timestamp | excluded from marts |
| `warning` | future-dated, out-of-range risk score, impossible date ordering | included, flagged |
| `cosmetic` | duplicate display name, invalid country label, missing app version | included, flagged |

```python
df["dq_critical_count"] = sum(m.astype(int) for m in critical_masks)
df["dq_warning_count"]  = sum(m.astype(int) for m in warning_masks)
df["dq_cosmetic_count"] = sum(m.astype(int) for m in cosmetic_masks)
df["is_valid_record"]   = df["dq_critical_count"] == 0
```

Keep `is_valid_record` as the name so no mart query changes.

**(b) Stop propagating dimension invalidity into facts.** Validate fact foreign keys against *existence*, not validity, and route unresolvable references to an unknown member — the standard dimensional pattern:

```python
existing_customer_ids = set(customers["customer_id"])          # not just valid ones
broken_customer_link  = ~df["customer_id"].isin(existing_customer_ids)
df.loc[broken_customer_link, "customer_id"] = -1               # unknown member row
```

Insert a `-1` "Unknown" row in each clean dimension so joins never drop a fact.

**Expected effect.** ~29,700 transactions return to reporting, transaction valid rate rises from 69.7% to roughly 99.4%, and the chargeback rate stops being distorted by which merchants happened to have tidy names. No genuine integrity rule is loosened — a broken key is still a defect; it just no longer deletes the payment.

**Why.** This is the single highest-value change in the roadmap. It converts the DQ framework from "strict" to "correct", and being able to explain the distinction between structural and cosmetic invalidity is exactly the judgement an analytics-engineering interview is probing for.

---

### P1-2 · Derive risk thresholds from the observed distribution `M` 🔴

**Problem** (§4.3). The Monitor tier triggers at `failure_rate >= 22%` while the **median merchant failure rate is 22.7%**. 554 of 1,001 merchants trip that one condition and 677 trip `alert_count >= 6`, so only 88 merchants (8.8%) reach Low Risk — 91% are Monitor or worse. Segment means barely separate (18.64% vs 23.71% failure). The Critical failure trigger at 35% catches 7 merchants and contributes nothing.

**Fix.** Compute thresholds from percentiles instead of hard-coding them:

```sql
WITH pct AS (
    SELECT PERCENTILE_CONT(0.98) WITHIN GROUP (ORDER BY chargeback_rate_pct) AS cb_p98,
           PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY chargeback_rate_pct) AS cb_p90,
           PERCENTILE_CONT(0.98) WITHIN GROUP (ORDER BY failure_rate_pct)    AS fail_p98,
           PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY failure_rate_pct)    AS fail_p90
    FROM mart.merchant_performance_summary WHERE total_transactions >= 30
)
SELECT m.*,
       CASE WHEN m.chargeback_rate_pct >= p.cb_p98 OR m.failure_rate_pct >= p.fail_p98 THEN 'Critical'
            WHEN m.chargeback_rate_pct >= p.cb_p90 OR m.failure_rate_pct >= p.fail_p90 THEN 'High Risk'
            ... END AS merchant_risk_segment
FROM mart.merchant_performance_summary m CROSS JOIN pct p
```

Three refinements worth adding:

- **Minimum volume gate.** A merchant with 3 transactions and 1 chargeback shows a 33% rate. Require `total_transactions >= 30` for segmentation and give smaller merchants an `Insufficient Volume` tier.
- **Peer groups.** Compare within `merchant_category` × `country_code` so a gaming merchant is measured against gaming merchants — travel and gaming have structurally different baseline chargeback rates.
- **Weighted score instead of pure OR.** A disjunction means the weakest trigger defines the tier. A weighted composite (chargeback rate carries most signal here — it separates tiers 5.4×; failure rate separates 1.3×) ranks merchants more sensibly, with the OR retained only for genuine hard breaches like chargeback rate above the scheme's ~1% threshold.

**Target outcome.** Critical ≈ 2% of merchants, High Risk ≈ 8%, so the review queue matches plausible analyst capacity — and Dashboard 2's scatter shows separation instead of horizontal bands.

**Why.** "91% of merchants are at least Monitor" is indefensible in a review conversation, and it is the second thing an interviewer will probe. Percentile thresholds also adapt as the portfolio changes, which absolute cut-offs never do.

---

### P1-3 · Fix duplicate flagging `S`

**Problem** (§4.7). `duplicated(keep=False)` flags every member of a duplicate group, so when the injection copies merchant A's name onto B, both are invalidated — A having done nothing wrong. About half of the 81 merchants flagged for duplicate names were never corrupted.

**Fix.** `keep="first"` (optionally ordered by `created_at` so the genuine original survives):

```python
duplicate_merchant_name = (df.sort_values("created_at")
                             .duplicated(subset="merchant_name", keep="first")
                             .reindex(df.index))
```

**Why.** One-line change that improves correctness and directly shrinks the P1-1 cascade. It also reflects how deduplication actually works in practice — you keep a survivor.

---

### P1-4 · Assert injection ↔ detection correspondence `M`

**Problem** (§4.6). Two gaps: 41 chargebacks dated **before their parent transaction** flow into the marts because no rule checks for it; and the seed itself creates most of the "injected" timing defects (devices 361 actual vs 70 injected; chargeback resolution 433 vs 35), so the answer key overstates injection by 4–12×.

**Fix.**

1. Add the missing rule to `clean_chargebacks.py`:

```python
txn_dates = transactions.set_index("transaction_id")["transaction_ts"]
parent_date = df["transaction_id"].map(pd.to_datetime(txn_dates)).dt.normalize()
chargeback_before_transaction = df["chargeback_date"].notna() & parent_date.notna() & (df["chargeback_date"] < parent_date)
```

2. Fix the generator so it cannot produce unintended violations:

```sql
-- devices: guarantee last_seen_at >= first_seen_at
first_seen_at + ((RANDOM() * 200)::INT * INTERVAL '1 day') AS last_seen_at
-- chargebacks: resolution always at/after the chargeback
chargeback_date + ((RANDOM() * 60)::INT + 1) AS resolution_date
```

3. Add a coverage test — a table of `(injected_class, detecting_rule, expected_count)` that fails when a class has no detecting rule or the observed count diverges materially from the injected count.

**Why.** The answer key is the project's central claim. Grading the detector against a key you can show is accurate is a much stronger story than asserting the detector works — and "I tested my own test framework and found two gaps" is a genuinely senior thing to be able to say.

---

### P1-5 · Fix the two degenerate summary marts `M`

**Problem** (§4.8). `chargeback_summary` groups by `(date, reason, dispute_status)` yet also computes `open_disputes`/`won_disputes`/`lost_disputes`/`closed_disputes` — in all 812 rows one counter holds the whole count and the rest are zero. `alerts_summary` repeats it with `severity` and `alert_status`. Neither aggregates: 812 rows for 883 chargebacks (1.09:1) and 5,913 for 6,675 alerts (1.13:1), against 172:1 for `daily_transaction_monitoring`.

**Fix.** Make one grain decision per mart. Either keep the dimensional grain and drop the pivot counters, or aggregate to date grain and keep them as real pivots:

```sql
CREATE TABLE mart.chargeback_summary AS
SELECT chargeback_date::date AS chargeback_date,
       COUNT(*) AS chargeback_count,
       ROUND(SUM(chargeback_amount)::numeric, 2) AS total_chargeback_amount,
       COUNT(*) FILTER (WHERE dispute_status = 'open')   AS open_disputes,
       COUNT(*) FILTER (WHERE dispute_status = 'won')    AS won_disputes,
       COUNT(*) FILTER (WHERE dispute_status = 'lost')   AS lost_disputes,
       COUNT(*) FILTER (WHERE dispute_status = 'closed') AS closed_disputes,
       COUNT(*) FILTER (WHERE chargeback_reason = 'fraud') AS fraud_disputes
FROM clean.chargebacks WHERE is_valid_record GROUP BY 1;
```

`COUNT(*) FILTER (WHERE …)` also reads better than `SUM(CASE WHEN … THEN 1 ELSE 0 END)` throughout — it is the idiomatic PostgreSQL form.

**Why.** A mart that is a near-copy of its source isn't doing the job marts exist for. Being able to explain grain — and spot when your own model violated it — is a core analytics-engineering competency.

---

### P1-6 · Derive domain allow-lists from the source contract `S`

**Problem** (§4.9). `customer_risk_features` uses `critical_severity_alerts >= 1` as a high-risk trigger, but `critical` exists **only** because `06_inject_alert_issues.sql` writes it to 40 random rows as a defect. `VALID_SEVERITIES` includes it, so it passes validation and is then consumed as signal — 27 of them reach the marts.

**Fix.** Either remove `critical` from `VALID_SEVERITIES` (matching what the source system can actually emit) and have the injection be caught as the defect it is, or add `critical` to the seed properly so the risk rule has legitimate input. Then add a schema-drift check that flags any categorical value present in the data but absent from the declared source vocabulary.

**Why.** This is the subtlest bug in the project and the most interesting to explain: a value can be *syntactically* valid and *semantically* impossible, pass a domain allow-list, and silently become a feature. Drift detection is the general defence.

---

## P2 — Engineering maturity

### P2-1 · Make the repo runnable: `requirements.txt` + orchestrator `M`

**Problem.** `requirements.txt` is 0 bytes, so the README's install instructions cannot work for anyone cloning the repo. There is no single entry point — the documented run is 12 manual commands that must be issued in exactly the right order, and `run_pipeline.md` and `sql/run_all.sql` are both empty.

**Fix.**

```
pandas==2.2.*
SQLAlchemy==2.0.*
psycopg2-binary==2.9.*
python-dotenv==1.0.*
```

Then one orchestrator that encodes the dependency order and fails loudly:

```python
# run_pipeline.py
STAGES = [
    ("extract",     "python.extraction.extract_raw"),
    ("dq_profile",  "python.dq.dq_checks"),
    ("clean_customers",    "python.cleaning.clean_customers"),
    ("clean_devices",      "python.cleaning.clean_devices"),
    ("clean_merchants",    "python.cleaning.clean_merchants"),
    ("clean_transactions", "python.cleaning.clean_transactions"),
    ("clean_chargebacks",  "python.cleaning.clean_chargebacks"),
    ("clean_alerts",       "python.cleaning.clean_alerts"),
    ("load",       "python.loading.load_clean"),
    ("report",     "python.reporting.before_after_summary"),
]
```

A `Makefile` with `make seed`, `make clean`, `make marts`, `make qa`, `make all` works just as well and is less code.

**Why.** The cleaning modules have a **mandatory** execution order that exists only in a README sentence — run them alphabetically and the fact tables validate against dimensions that haven't been written yet. Encoding order in runnable code, and making the project installable by a stranger, is the minimum bar for "this is engineering, not a notebook".

---

### P2-2 · Turn QA scripts into assertions and log DQ over time `M`

**Problem.** All three QA scripts `SELECT` result sets for a human to read. Nothing fails, so a regression cannot be caught. And `raw_dq_summary.csv` is a single point-in-time snapshot that each run overwrites — quality is never trended.

**Fix.** Make checks raise:

```sql
DO $$
DECLARE bad INT;
BEGIN
    SELECT COUNT(*) INTO bad FROM mart.merchant_performance_summary WHERE chargeback_rate_pct > 100;
    IF bad > 0 THEN RAISE EXCEPTION 'QA FAIL: % merchants with chargeback rate > 100%%', bad; END IF;
END $$;
```

Then persist every DQ run instead of overwriting:

```sql
CREATE TABLE mart.dq_run_log (
    run_id      BIGSERIAL PRIMARY KEY,
    run_date    DATE,
    table_name  TEXT,
    check_name  TEXT,
    result      BIGINT,
    created_at  TIMESTAMP DEFAULT NOW()
);
```

Worthwhile assertions: no mart row count of zero; no percentage outside 0–100; `SUM(mart.daily_transaction_monitoring.total_transactions)` equals the valid clean-transaction count; every valid fact FK resolves; no `transaction_date > :run_date`.

**Why.** Trended quality is a far better dashboard than a static valid rate — "our merchant valid rate dropped 4 points on Tuesday" is an actual operational alert. It also gives you a reconciliation story: the marts provably agree with the clean layer.

---

### P2-3 · Consolidate the six cleaning modules into a rule engine `L`

**Problem.** `clean_customers.py`, `clean_devices.py`, `clean_merchants.py`, `clean_transactions.py`, `clean_chargebacks.py` and `clean_alerts.py` are ~550 lines that are structurally identical — read CSV, standardise, build masks, sum, write. Adding a rule means editing a specific file; changing the *pattern* means editing six. `python/dq/dq_rules.py` and `dq_summary.py` are empty files that were clearly meant to be this.

**Fix.** Declare rules as data and execute them generically:

```python
# python/dq/dq_rules.py
RULES = {
    "transactions": [
        Rule("duplicate_transaction_ref", "cosmetic",
             lambda df, ctx: df["transaction_ref"].duplicated(keep="first")),
        Rule("invalid_amount", "critical",
             lambda df, ctx: df["amount"].notna() & (df["amount"] <= 0)),
        Rule("broken_customer_link", "critical",
             lambda df, ctx: ~df["customer_id"].isin(ctx["customer_ids"])),
    ],
}
```

One executor applies them, and — importantly — emits **long-format** results rather than only a count:

```python
# dq_issues: (table_name, entity_id, rule_name, severity, run_date)
```

**Why.** Two payoffs. Adding a rule becomes a one-line data change with no new code path. And long-format issues let a dashboard answer *why* rows failed, not just how many — which is the missing piece for P3-1. This is also the refactor the empty `dq_rules.py` was reaching for, so it finishes an intention already in the repo.

---

### P2-4 · Make mart builds transactional and path-independent `S`

**Problem.** `run_marts.sql` uses relative `\i sql/marts/…` paths, so it only works when psql is launched from the repo root. Each mart script is `DROP TABLE` + `CREATE TABLE AS` with a trailing `SELECT … LIMIT 10` inspection query — outside a transaction, a mid-run failure leaves marts dropped and not rebuilt, and the inspection queries are noise in automation.

**Fix.** Wrap the run in a transaction and remove the trailing SELECTs (move them into the QA scripts, where inspection belongs):

```sql
BEGIN;
\i sql/marts/01_daily_transaction_monitoring.sql
-- …
COMMIT;
```

Better still, build into a staging name and swap on success, so readers never see a dropped table:

```sql
CREATE TABLE mart.merchant_performance_summary_new AS …;
BEGIN;
  DROP TABLE IF EXISTS mart.merchant_performance_summary;
  ALTER TABLE mart.merchant_performance_summary_new RENAME TO merchant_performance_summary;
COMMIT;
```

Use `\ir` (include-relative) instead of `\i` so the path no longer depends on the working directory.

**Why.** A failed refresh currently leaves the warehouse in a broken state that Tableau will happily display as empty. Atomic swaps are how production marts are refreshed.

---

### P2-5 · Add indexes on the join columns `S`

**Problem.** No indexes exist on the `clean` foreign-key columns that every mart joins and groups on.

**Fix.**

```sql
CREATE INDEX idx_clean_txn_merchant  ON clean.transactions (merchant_id) WHERE is_valid_record;
CREATE INDEX idx_clean_txn_customer  ON clean.transactions (customer_id) WHERE is_valid_record;
CREATE INDEX idx_clean_txn_ts        ON clean.transactions (transaction_ts);
CREATE INDEX idx_clean_cb_merchant   ON clean.chargebacks  (merchant_id) WHERE is_valid_record;
CREATE INDEX idx_clean_alerts_merch  ON clean.alerts       (merchant_id) WHERE is_valid_record;
```

Partial indexes on `is_valid_record` are a good fit because every mart filters on it. Requires P0-4 first, since `if_exists="replace"` drops indexes along with the table.

**Why.** Cheap, and it demonstrates awareness that a warehouse has a physical layer. Also lets you talk about `EXPLAIN ANALYZE` before and after.

---

### P2-6 · Clean up the placeholder files `S`

**Problem.** 14 files are empty: 6 docs (now superseded by `docs/`), 3 zero-cell notebooks, `dq_rules.py`, `dq_summary.py`, `build_features.py`, `sql/run_all.sql`, `sql/ddl/04_mart_views.sql`, `run_pipeline.md`, `tableau/payscope_dashboard_plan.md`.

**Fix.** Fill or delete each. `dq_rules.py` gets filled by P2-3, `run_pipeline.md` by P2-1. The rest should probably go — and either populate the three notebooks with real exploratory analysis or remove them, since empty notebooks in a data project are conspicuous.

**Also fix:** `python/test_connection.py` uses `from config.db import get_engine` while every other module uses `from python.config.db import …`, so it fails under the documented `python -m` invocation.

**Why.** Empty files signal abandoned intent. A reviewer opening `docs/risk_rules.md` and finding nothing discounts the documentation that *is* there.

---

## P3 — Portfolio and product polish

### P3-1 · Build the data-quality dashboard `M` ⭐

**Problem.** The project's stated differentiator is its data-quality layer, and **not one of the three dashboards shows data quality.** All the DQ work is visible only in a CSV.

**Fix.** A fourth Tableau tab, reading `mart.dq_run_log` (P2-2) and the long-format `dq_issues` table (P2-3):

- Valid-rate trend by table over time — the headline quality KPI.
- Defect count by rule, ranked — where quality actually breaks.
- Severity split (critical vs warning vs cosmetic) per table, after P1-1.
- Cascade impact: rows excluded due to their own defect vs an upstream one.
- A record-level drill-through: pick a table, see the flagged rows and their failed rules.

**Why.** This is the highest-leverage single addition in the roadmap. The DQ framework is the most sophisticated part of the project and currently the least visible — a dashboard that shows 4,000 injected defects being caught, and quality trending over runs, is a much stronger artefact than a third risk chart. It converts the project's real strength into something a reviewer sees in five seconds.

---

### P3-2 · Measure alert precision `M` ⭐

**Problem.** `alert_status = 'false_positive'` is populated across 6,675 valid alerts and never analysed. Per-rule precision — the single most decision-relevant property of an alerting system — is unknown.

**Fix.**

```sql
SELECT rule_name, severity,
       COUNT(*) AS alerts,
       COUNT(*) FILTER (WHERE alert_status = 'false_positive') AS false_positives,
       ROUND(100.0 * COUNT(*) FILTER (WHERE alert_status = 'false_positive') / COUNT(*), 2) AS fp_rate_pct,
       ROUND(AVG(risk_score), 1) AS avg_risk_score
FROM clean.alerts WHERE is_valid_record GROUP BY 1, 2 ORDER BY fp_rate_pct DESC;
```

Then: does `risk_score` actually separate true positives from false positives? If not, the score is decoration and the rules need reweighting. Also compute per-rule review cost (alerts × handling time) against detected value.

**Why.** This is the question a risk operations team actually asks — "which rules are wasting my analysts' time?" It moves the project from descriptive reporting into decision support, and it needs no new data.

---

### P3-3 · Validate the risk rules against future outcomes `L` ⭐

**Problem.** Rules are evaluated on the same window they were defined against. Nothing tests whether a flag *predicts* anything.

**Fix.** Split the 404-day window: build features on the first 300 days, then measure what flagged entities did over the remaining 104. For merchants flagged Critical at day 300, what was their chargeback rate afterwards versus Low Risk merchants? Report lift, precision and recall.

**Why.** This is the difference between "I built a rule engine" and "I showed the rule engine works". Even a negative result is valuable and honest — on random synthetic data lift *should* be near 1.0, and saying so demonstrates you understand what your data can and cannot support. This one item would most raise the project's analytical ceiling.

---

### P3-4 · Use cohort denominators for chargeback rate `M`

**Problem.** Chargeback rate divides disputes in a period by transactions in the same period, but disputes lag their transactions by 1–60 days. Rates are therefore understated at the trailing edge of the window — exactly where you would want to spot a deteriorating merchant.

**Fix.** Compute rate on the origination cohort: disputes arising from transactions *originated* in period P, divided by transactions originated in P. Add a maturity indicator so incomplete cohorts are visibly incomplete rather than misleadingly low, and consider a 60-day-lag-adjusted rate for the current period.

**Why.** This is a genuine payments-domain subtlety, and demonstrating awareness of it is a strong differentiator — it is the kind of thing only someone who has thought about dispute lifecycles raises.

---

### P3-5 · Add CI `M`

**Fix.** A GitHub Actions workflow with a Postgres service container that seeds the database, runs the pipeline, and executes the P2-2 assertions on every push.

```yaml
services:
  postgres:
    image: postgres:16
    env: { POSTGRES_PASSWORD: postgres }
    options: >-
      --health-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5
```

**Why.** A green CI badge on the README proves the pipeline runs end-to-end from a clean clone — which no reader can currently verify. Depends on P0-3, P2-1 and P2-2.

---

### P3-6 · Fix the dashboard screenshots `S`

**Problem.** All three PNGs in the repo root are **full screenshots of the Tableau authoring interface** — sheet list, Show Me panel, worksheet tabs and toolbar included. Several KPI tiles are too narrow for their titles, which wrap into unreadable fragments: "Tran sacti ons", "Appr oval Rate", "Merc hant s", "Char geBa ck".

**Fix.** Present the dashboards, not the tool: use Dashboard → Export Image (or presentation mode) to capture only the canvas, widen the KPI tiles so titles fit on one line, and move the three PNGs into `docs/img/`. The README already has commented-out `docs/img/*.png` references waiting for them.

**Why.** These images are the first thing anyone sees. Right now they show the IDE rather than the product, and broken KPI titles read as unfinished — an unfair penalty on genuinely good dashboards. Half an hour here changes the first impression of the whole repo.

---

### P3-7 · Consider dbt for the SQL layer `L`

**Fix.** Port `sql/marts/` to dbt models with `ref()` lineage, `schema.yml` tests (`not_null`, `unique`, `accepted_values`, `relationships`), and generated documentation. The mart layer is already written in the shape dbt expects — CTEs, one model per file, dependency-ordered — so the port is mostly mechanical.

**Why.** It replaces the hand-rolled `run_marts.sql` ordering with a real DAG, converts the QA scripts into declarative tests, and gives you lineage docs for free. It is also the most requested tool in analytics-engineering job ads, so it converts existing work into a resume keyword without rewriting logic. Do it after P0 and P1 — dbt on top of uncalibrated thresholds and a broken type contract would just formalise the problems.

---

## Summary table

| ID | Item | Effort | Impact |
|---|---|---|---|
| P0-1 | Rotate + untrack leaked `.env` password | S | 🔴 Security |
| P0-2 | Real `.gitignore`, untrack 32 MB of output | S | Hygiene |
| P0-3 | Fix `DB_NAME`; give PayScope its own database | S | 🔴 Runnability |
| P0-4 | Enforce types at load (`response_code`, money, timestamps, PKs) | M | 🔴 Correctness |
| P0-5 | Explicit logical run date, replacing `NOW()` | M | 🔴 Reproducibility |
| P1-1 | Severity-tiered validity; stop the FK cascade | L | 🔴 Restores ~29,700 rows |
| P1-2 | Percentile-based risk thresholds + peer groups | M | 🔴 Makes segmentation usable |
| P1-3 | `duplicated(keep="first")` | S | Correctness |
| P1-4 | Injection↔detection coverage test; fix seed timing | M | Framework credibility |
| P1-5 | Fix degenerate grain in two summary marts | M | Modelling |
| P1-6 | Domain allow-lists from source contract + drift check | S | Correctness |
| P2-1 | `requirements.txt` + orchestrator | M | Runnability |
| P2-2 | QA as assertions; persistent `dq_run_log` | M | Engineering |
| P2-3 | Declarative rule engine; long-format `dq_issues` | L | Maintainability |
| P2-4 | Transactional, path-independent mart builds | S | Robustness |
| P2-5 | Indexes on clean FK columns | S | Performance |
| P2-6 | Fill or delete 14 empty files; fix `test_connection.py` | S | Polish |
| P3-1 | **Data-quality dashboard** | M | ⭐ Shows the differentiator |
| P3-2 | **Alert precision analysis** | M | ⭐ Decision support |
| P3-3 | **Forward validation of risk rules** | L | ⭐ Analytical rigour |
| P3-4 | Cohort denominators for chargeback rate | M | Domain depth |
| P3-5 | GitHub Actions CI | M | Credibility |
| P3-6 | Clean dashboard screenshots; fix KPI titles | S | First impression |
| P3-7 | Port mart layer to dbt | L | Tooling |

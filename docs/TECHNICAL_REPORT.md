# PayScope — Technical Report

**Digital Payments Risk & Merchant Analytics**
Mahesh Sai Kandula · MSc Data Science, Macquarie University
Report date: 13 August 2026 · All figures verified against the live PostgreSQL warehouse

---

## Executive summary

PayScope is an end-to-end payments analytics platform: 137,907 synthetic records move through a layered PostgreSQL warehouse (`raw` → `clean` → `mart`), are profiled by 37 data-quality checks, validated against 55 cleaning rules, aggregated into 7 business marts, scored by an explainable risk engine, and surfaced in 3 Tableau dashboards.

The distinguishing feature is the **answer key**. Data-quality defects are injected deliberately and catalogued, so the detection layer can be graded against known truth rather than asserted to work. That design made it possible to audit the pipeline's own behaviour — which is what the second half of this report does.

**What the platform reports:** 69,713 valid transactions worth $9.25M over 404 days, at a 75.02% approval rate, 22.57% failure rate and 30.35% cross-border rate; 883 chargebacks worth $114,447; 1,001 merchants segmented into four behavioural risk tiers; 329 high-risk customers flagged; 1,256 explainable rule hits.

**The headline analytical finding:** the merchant risk label inherited from the source system has **no statistically significant relationship** to observed merchant behaviour (χ² = 8.10, dof = 6, p = 0.231; Cramér's V = 0.064). Merchants labelled `low` risk upstream are flagged Critical *more* often (7.6%) than those labelled `high` (6.8%). Behaviour-based segmentation is not a refinement of the upstream label — it is the only merchant-risk signal in the system that carries information.

**The headline engineering finding:** 98.1% of transactions excluded from the marts were excluded for someone else's defect. Of 30,287 invalid transactions, 29,702 are invalid solely because they point at a dimension row that was itself flagged — 6,768 of them because their merchant happens to share a name with another merchant. Only 585 transactions have a defect of their own. The reported "69.71% valid" figure measures the compounded strictness of three dimension tables, not transaction quality.

Both findings are actionable, and both were only visible because the pipeline was audited against its own answer key.

---

## 1. Problem framing

A payments processor's analytics function has to answer three questions continuously:

1. **Are payments healthy?** Volume, approval and failure rates, and how they trend.
2. **Which merchants are dangerous?** Card schemes penalise processors for sustained merchant chargeback rates above roughly 1%; identifying those merchants early is a direct revenue-protection activity.
3. **Where do disputes come from, and can we win them?** Dispute reason and outcome mix drives both operational staffing and merchant-level pricing.

None of these can be answered from raw operational data. Payments data arrives from card networks, acquirers, gateways and internal services, each with its own conventions — so the same country appears as `AU`, `au` and `AUS`, timestamps arrive in the future, and foreign keys point at records that were never created. Answering the business questions requires solving the data-quality problem first.

PayScope was built around that ordering: the data-quality layer is the project, and the dashboards are its output.

---

## 2. Method

### 2.1 Warehouse design

Three schemas with strict, one-directional contracts:

| Schema | Contract |
|---|---|
| `raw` | Byte-faithful source copy. Never modified by the pipeline. |
| `clean` | Every source row present exactly once, standardised, with `is_valid_record`, `dq_issue_count`, `cleaned_at`. Nothing deleted. |
| `mart` | Business-named aggregates filtered to valid records. The only layer Tableau touches. |

**Flag, don't delete.** Invalid records remain in `clean` with a defect count. This preserves the audit trail, keeps exclusions measurable, and means every dashboard number can be traced back to the rows it excluded and why. It is also what made this report's audit possible — a delete-on-clean pipeline destroys the evidence.

**BI reads marts only.** Metric definitions live in version-controlled SQL, not in Tableau calculated fields, so "approval rate" has exactly one definition.

### 2.2 Synthetic generation with realistic structure

Data is generated in SQL with `generate_series`, but shaped deliberately rather than uniformly:

- **Skewed amounts** — 70% under $100, then a mid tier, then a long tail to $2,000, approximating real payment-value distributions.
- **Derived facts** — chargebacks are generated *from* approved transactions at ~2.5%, inheriting the parent's customer, merchant and amount. This is what makes chargeback rate a meaningful ratio rather than two unrelated random series.
- **Planted risk signals** — a ~5% emulator rate, and device country drawn independently of IP country so geo mismatches occur naturally.
- **An untrustworthy upstream label** — `risk_tier_source` is generated at random, on purpose, to represent a source-system label of unknown quality. Testing it became finding §4.1.
- **ISO-8583 response codes** — `00`, `05`, `91`, stored as text because the leading zero is semantically significant.

### 2.3 Deliberate defect injection

Six scripts inject ~4,000 catalogued defects across eight classes: missing values, duplicates, format inconsistency, trailing whitespace, invalid domain codes, invalid numerics, impossible dates, and broken foreign keys. Broken keys are offset into an impossible range (`900000 + transaction_id`) so they cannot accidentally collide with a real key.

The injection distinguishes **recoverable** corruption from **genuine invalidity** — `'Approved'` and `'pending '` are repairable by case-folding and trimming, while `'FAIL'` needs an explicit synonym map and `'XXX'` is simply not a currency. The cleaning layer is built around that distinction.

### 2.4 Dual-path profiling

Quality is profiled twice and independently: ~35 checks in SQL against `raw` (`sql/qa/raw_qa_checks.sql`), and the equivalents in pandas against the extracted CSVs (`python/dq/dq_checks.py`). Two implementations agreeing raises confidence; disagreement finds bugs in the checks themselves. Coverage spans completeness, uniqueness, validity, cross-field consistency and referential integrity.

### 2.5 Cleaning as a four-stage contract

Six modules, one per table, each identical in shape: **standardise** (trim, case-fold, apply synonym maps, coerce types with `errors="coerce"`) → **validate** against declared domain constants → **accumulate** defects as vectorised boolean masks summed into `dq_issue_count` → **emit** with audit columns. 55 rules total.

Modules run in dependency order (customers → devices → merchants → transactions → chargebacks/alerts) because fact tables validate their foreign keys against the already-cleaned dimensions.

### 2.6 Aggregate before joining

The technique that keeps `merchant_performance_summary` correct: joining transactions, chargebacks and alerts to merchants in a single query would multiply their grains and inflate every measure. Each fact is instead collapsed to merchant grain in its own CTE, then joined:

```sql
WITH txn AS (SELECT merchant_id, COUNT(*) … FROM clean.transactions WHERE is_valid_record GROUP BY merchant_id),
     cb  AS (SELECT merchant_id, COUNT(*) … FROM clean.chargebacks  WHERE is_valid_record GROUP BY merchant_id),
     al  AS (SELECT merchant_id, COUNT(*) … FROM clean.alerts       WHERE is_valid_record GROUP BY merchant_id)
SELECT m.*, COALESCE(txn.total_transactions, 0), …
FROM clean.merchants m
LEFT JOIN txn USING (merchant_id) LEFT JOIN cb USING (merchant_id) LEFT JOIN al USING (merchant_id)
WHERE m.is_valid_record = TRUE;
```

`LEFT JOIN` + `COALESCE(…, 0)` keeps zero-activity merchants visible instead of dropping them; `NULLIF(denominator, 0)` makes every ratio return `NULL` rather than erroring.

### 2.7 Explainable rules, not a model

In payments risk, holding a merchant's settlement or freezing a customer's account requires a defensible reason. `mart.risk_rule_hits` therefore emits **one row per triggered rule per entity** with a human-readable description — `(rule_name, entity_type, entity_id, rule_hit_count, rule_description)` — so any flag traces to its cause. Adding a rule means adding a `UNION ALL` block; no consumer changes. Auditability is worth more than marginal accuracy here.

---

## 3. Results

### 3.1 Data-quality outcomes

Raw profiling recorded ~4,000 defects across 37 checks. Cleaning outcomes:

| Table | Rows | Valid | Invalid | Valid rate | Avg defects/row |
|---|---:|---:|---:|---:|---:|
| customers | 10,000 | 9,446 | 554 | 94.46% | 0.067 |
| devices | 15,000 | 13,426 | 1,574 | 89.51% | 0.108 |
| merchants | 1,200 | 1,001 | 199 | 83.42% | 0.179 |
| transactions | 100,000 | 69,713 | 30,287 | 69.71% | 0.337 |
| alerts | 9,956 | 6,675 | 3,281 | 67.04% | 0.669 |
| chargebacks | 1,851 | 883 | 968 | 47.70% | 0.866 |

These rates require careful interpretation — see §4.2.

### 3.2 Transaction health

69,713 valid transactions · **$9,250,152** processed · **75.02%** approval · **22.57%** failure · **30.35%** cross-border · 404 days (2025-04-17 → 2026-05-26).

The 22.57% failure rate is high for a real processor (single digits would be typical) — a property of the generator's status distribution, not a finding about payments.

### 3.3 Chargebacks

883 valid disputes · **$114,447** total · **$129.61** average. (Earlier versions of this report and the dashboard quoted $130.95; that figure is the *average of the per-row averages* in `mart.chargeback_summary`, not the average dispute. $114,447.09 ÷ 883 = $129.61.) Both reason and outcome are close to uniform, as generated:

| Reason | Count | Amount | | Outcome | Count | Share |
|---|---:|---:|---|---|---:|---:|
| duplicate_processing | 236 | $32,332 | | closed | 233 | 26.4% |
| service_not_received | 223 | $25,507 | | lost | 226 | 25.6% |
| fraud | 213 | $26,373 | | open | 218 | 24.7% |
| authorization_issue | 211 | $30,235 | | won | 206 | 23.3% |

Operationally the useful read is that **226 disputes were lost against 206 won** — a 47% win rate on resolved cases, which in a real portfolio would prompt a review of evidence-submission quality.

### 3.4 Merchant risk segmentation

| Segment | Merchants | Share | Avg failure | Avg chargeback | Avg alerts | Transactions |
|---|---:|---:|---:|---:|---:|---:|
| Monitor | 440 | 44.0% | 21.77% | 0.78% | 6.1 | 30,499 |
| High Risk | 392 | 39.2% | 24.15% | 1.68% | 7.4 | 27,526 |
| Critical | 81 | 8.1% | 23.71% | 2.87% | 9.1 | 5,697 |
| Low Risk | 88 | 8.8% | 18.64% | 0.53% | 3.9 | 5,991 |

Chargeback rate separates the tiers cleanly (0.53% → 2.87%, a 5.4× spread). Failure rate barely separates them at all (18.64% → 23.71%). That asymmetry is diagnosed in §4.3.

### 3.5 Customer risk

329 of 9,446 customers flagged high-risk (3.5%). The flag discriminates:

| | Count | Avg failure rate | Avg chargebacks | Avg alerts |
|---|---:|---:|---:|---:|
| Flagged | 329 | **44.51%** | 0.26 | 1.19 |
| Not flagged | 9,117 | 21.76% | 0.09 | 0.69 |

A 2.0× separation on failure rate and 2.9× on chargebacks, at a 3.5% base rate — a workable review queue.

### 3.6 Explainable rule hits

| Rule | Entity | Condition | Entities | Hits |
|---|---|---|---:|---:|
| `high_activity_device` | device | ≥ 10 valid transactions | 544 | 5,858 |
| `repeated_failed_payments` | customer | ≥ 5 failed transactions | 261 | 1,392 |
| `repeated_risky_alerts` | merchant | ≥ 9 valid alerts | 217 | 2,239 |
| `merchant_chargeback_spike` | merchant | chargeback rate ≥ 2.5% | 202 | 462 |
| `high_chargeback_customer` | customer | ≥ 2 valid chargebacks | 32 | 67 |

1,256 rows total. The rules span three entity types, so a single investigation can pivot between customer, device and merchant views of the same behaviour.

### 3.7 Dashboards

| Dashboard | Question answered | Source mart |
|---|---|---|
| Transaction Monitoring | Are payments healthy, and is that changing? | `daily_transaction_monitoring` |
| Merchant Risk | Which merchants need intervention? | `merchant_risk_segmentation` |
| Chargeback Analysis | Where do disputes come from and how do they resolve? | `chargeback_summary` |

---

## 4. Findings

### 4.1 The inherited merchant risk tier carries no information

The source system's `risk_tier_source` label was tested against the behaviour-derived segment:

| `risk_tier_source` | Critical | High Risk | Monitor | Low Risk | Critical rate |
|---|---:|---:|---:|---:|---:|
| high | 24 | 132 | 161 | 37 | 6.8% |
| medium | 32 | 119 | 147 | 22 | 10.0% |
| low | 25 | 141 | 132 | 29 | 7.6% |

**χ² = 8.10, dof = 6, p = 0.231** — no statistically significant association. **Cramér's V = 0.064**, a negligible effect size. Merchants labelled `low` upstream are flagged Critical slightly *more* often than those labelled `high`.

Here this is true by construction — the seed generates the label at random. But the finding is the point of the exercise: an analyst handed a source-system risk label should test it before inheriting it, and the test is cheap. Had this label been trusted, 141 `low`-tier merchants exhibiting High Risk behaviour and 25 exhibiting Critical behaviour would have gone unreviewed, while 37 `high`-tier merchants would have absorbed monitoring effort they did not warrant. The behavioural layer is not a refinement of the upstream label — it replaces it.

### 4.2 The reported valid rate measures dimension strictness, not fact quality

Decomposing the 30,287 invalid transactions:

| Cause | Count | Share |
|---|---:|---:|
| Referenced dimension row was itself flagged | **29,702** | **98.1%** |
| Transaction has a defect of its own | 585 | 1.9% |

The valid rate is almost exactly the product of the dimension valid rates:

```
0.9446 (customers) × 0.8342 (merchants) × 0.8951 (devices) = 0.7053
observed                                                   = 0.6971
```

The mechanism is that fact-table cleaning validates foreign keys against *valid* dimension IDs, so any dimension defect propagates to every fact row that touches it. Most consequential single instance: **6,768 transactions are excluded from every mart because their merchant shares a name with another merchant.** A duplicated display name says nothing about whether the payment occurred, yet it removes 6.8% of the fact table from all reporting. The same cascade drags chargebacks to a 47.70% valid rate.

**Implication.** "69.71% of transactions are valid" is not a statement about transaction quality and should not be read as one. Validity needs to be split by severity — structural integrity (broken keys, impossible amounts, unparseable dates) should exclude a row from analysis; cosmetic attribute problems on a related dimension should not. The standard dimensional-modelling remedy is to keep the fact and route unresolvable references to an "unknown member" surrogate key. Applied here, that restores ~29,700 transactions to reporting without loosening a single genuine integrity rule.

### 4.3 Risk thresholds are set below the population baseline

The Monitor tier triggers at `failure_rate >= 22%`, but the **median merchant failure rate is 22.7%** (5th–95th percentile: 14.5%–30.8%). The threshold sits at the centre of the distribution it is meant to identify outliers in.

| Trigger | Merchants caught (of 1,001) |
|---|---:|
| `alert_count >= 6` (Monitor) | 677 |
| `failure_rate >= 22` (Monitor) | 554 |
| `chargeback_rate >= 1.5` (Monitor) | 346 |
| `failure_rate >= 35` (Critical) | 7 |

Because the tiers are disjunctive (any one trigger promotes a merchant), only **88 merchants (8.8%) reach Low Risk — 91% are Monitor or worse**. And the tiers barely separate on failure rate: 18.64% for Low Risk against 23.71% for Critical. Meanwhile the Critical failure trigger at 35% catches just 7 merchants, so it contributes almost nothing.

Dashboard 2 shows this visually: the scatter has **horizontal colour bands** rather than clusters, and a row of Critical and High Risk points sitting at exactly 0% chargeback rate — merchants promoted purely by failure rate or alert count. The segments are drawn by the cut-offs, not discovered in the data.

**Implication.** A flag that fires on 91% of the population cannot prioritise work. Thresholds should be derived from the observed distribution — percentiles, or peer-group medians within category × country, so a gaming merchant is compared against gaming merchants — and calibrated to a defensible review capacity (for instance, Critical = worst 2%, High Risk = next 8%). The chargeback-rate dimension already behaves correctly and can anchor the recalibration.

### 4.4 The pipeline is not reproducible across days

Freshness checks compare against wall-clock time (`NOW()`, `pd.Timestamp.now()`), so injected future-dated defects **decay into valid records** as time passes:

| Defect | Injected | Recorded in DQ report | Present today |
|---|---:|---:|---:|
| Future transactions | 180 | 18 | 0 |
| Future alerts | 120 | 0 | 0 |

The visible consequence: 105 transactions across 38 days sit **beyond the extraction date**, stretching the fact table to 2026-05-26 and producing the thin tail at the right edge of Dashboard 1's volume chart — future-dated rows that were caught as defects when injected and are now silently reported as real payments.

**Implication.** Time-dependent validation must run against an explicit logical run date passed through the pipeline, not the system clock. Without that, identical input produces different output on different days and no result in this report is exactly reproducible.

### 4.5 The clean-layer schema definition never takes effect

`load_clean.py` writes with `if_exists="replace"`, which drops each table and lets pandas re-infer its schema — so `sql/ddl/03_clean_tables.sql` is dead code. Verified against `information_schema`:

- **Zero constraints** on any `clean` or `mart` table — no primary keys anywhere.
- `transaction_ts` and `cleaned_at` stored as **`text`**, not `timestamp`.
- `amount` stored as **`double precision`** — binary floating point for money, instead of `NUMERIC(12,2)`.
- `response_code` coerced to **`bigint`**, destroying ISO-8583 leading zeros: `'00' → 0`, `'05' → 5`. All **96,404** non-null codes affected; the field can no longer round-trip to its source meaning.

The `response_code` case is the instructive one: the DDL author correctly chose `TEXT` for exactly this reason, and the loader silently overrode the decision. Type contracts have to be enforced at the write boundary, or they are only documentation.

### 4.6 Detection coverage does not match the injection catalogue

Grading the detection layer against its own answer key found gaps in both directions.

**An injected defect that nothing detects.** `05_inject_chargeback_issues.sql` back-dates chargebacks to before their parent transaction. No rule checks `chargeback_date >= transaction_ts`. **41 chronologically impossible chargebacks flow into the marts as valid** — a dispute recorded before the payment it disputes.

**Defects credited to injection that the generator created itself:**

| Check | Actual | Injected | Created by seed logic |
|---|---:|---:|---:|
| `devices.last_seen_at < first_seen_at` | 361 | 70 | 291 (81%) |
| `chargebacks.resolution_date < chargeback_date` | 433 | 35 | 398 (92%) |

The seed draws `last_seen_at` within 30 days but `first_seen_at` across 730 days, and draws `resolution_date` independently of `chargeback_date` — so it produces impossible orderings by construction. For these two checks the answer key overstates injection by 4–12×.

**Implication.** An injection-based DQ framework is only as trustworthy as the correspondence between injection and detection. That correspondence should be asserted, not assumed: a test that fails when any injected defect class lacks a detecting rule, and when observed counts diverge from injected counts by more than the generator's own contribution.

### 4.7 Duplicate flagging penalises the uncorrupted record

All duplicate checks use `duplicated(keep=False)`, which flags every member of a duplicate group. When the injection copies merchant A's name onto merchant B, **both** are invalidated — A having done nothing wrong. Of 81 merchants flagged for duplicate names, roughly half were never touched. `keep="first"` would penalise only the offending copy, and would immediately reduce the §4.2 cascade.

### 4.8 Two "summary" marts do not summarise

`chargeback_summary` groups by `(date, reason, dispute_status)` while also computing `open_disputes`, `won_disputes`, `lost_disputes`, `closed_disputes`. Since `dispute_status` is already a grain key, in **all 812 rows one counter holds the entire count and the other three are zero**. `alerts_summary` repeats the pattern with `severity` and `alert_status`.

Compression ratios confirm these are not aggregates:

| Mart | Source rows | Mart rows | Compression |
|---|---:|---:|---:|
| `daily_transaction_monitoring` | 69,713 | 404 | **172:1** |
| `merchant_performance_summary` | 69,713 | 1,001 | 70:1 |
| `chargeback_summary` | 883 | 812 | **1.09:1** |
| `alerts_summary` | 6,675 | 5,913 | **1.13:1** |

Two marts genuinely aggregate; two are near-copies of their source with a `GROUP BY` attached, carrying degenerate columns. Each needs one grain decision: either keep the dimensional grain and drop the pivot counters, or aggregate to date grain and keep them.

### 4.9 A corruption artefact feeds a live risk rule

`customer_risk_features` treats `critical_severity_alerts >= 1` as a high-risk trigger. The seed emits only `low`, `medium` and `high` — **`critical` exists solely because `06_inject_alert_issues.sql` writes it to 40 random rows as a label-inconsistency defect.** 27 survive into the marts, where they function as a genuine risk signal driving customer flags.

The cleaning layer treats `critical` as a valid severity (it is in `VALID_SEVERITIES`), so the defect passes through undetected and is then consumed as signal. This is a realistic and instructive failure: a value that is *syntactically* valid but *semantically* impossible for the source system will pass domain validation and silently become a feature. Domain allow-lists should be derived from the source contract, and any value appearing in the data but not in the generator's own vocabulary should raise a schema-drift alert.

---

## 5. What the audit says about the platform

The pipeline is architecturally sound. Layer separation is clean and one-directional, the flag-don't-delete decision is correct and made the audit possible, aggregate-before-join avoids the fan-out trap that quietly breaks most merchant-level reporting, and the explainable rule engine is the right call for a risk context. The two genuine aggregate marts are well built, and the customer risk flag demonstrably discriminates.

The defects the audit found cluster into three themes, and none is architectural:

1. **Severity is missing from the quality model.** Validity is binary, so a duplicated display name is treated exactly like a broken foreign key, and the resulting cascade removes 29,702 sound transactions from reporting (§4.2, §4.7).
2. **Thresholds and domains were chosen in the absolute, not derived from the data.** Risk cut-offs sit at the population median (§4.3), and the severity allow-list admits a value the source system cannot produce (§4.9).
3. **Contracts are documented but not enforced.** The clean-layer DDL is silently discarded at load (§4.5), time-dependence makes results non-reproducible (§4.4), and injection–detection correspondence is assumed rather than tested (§4.6).

All three are addressable without redesigning the warehouse. `UPGRADE_ROADMAP.md` sequences the work; the four highest-value items are severity-tiered validity, distribution-derived risk thresholds, an explicit logical run date, and type enforcement at the load boundary.

---

## 6. Limitations

- **Synthetic data.** All records are generated. The 22.57% failure rate and near-uniform chargeback reason mix are properties of the generator, not observations about payments. Correlation structure that exists in real payments data — merchant quality persisting over time, fraud clustering in bursts — is absent.
- **`risk_tier_source` is random by construction.** §4.1 demonstrates a method, not a discovered fact about any real processor's labelling.
- **Results are not exactly reproducible.** Per §4.4, wall-clock-dependent checks mean re-running the pipeline on a different date yields different outputs from identical input. Figures in this report are pinned to 13 August 2026.
- **No temporal validation of the risk rules.** Rules are evaluated on the same window they were defined against; there is no holdout period or forward test, so "does this flag predict future chargebacks" is unanswered.
- **Chargeback rate uses a same-period denominator.** Disputes lag their transactions by 1–60 days, so a merchant's rate is understated at the window's trailing edge. A cohort denominator (disputes per transactions *originated* in a period) would be the sounder measure.
- **Alert precision is unmeasured.** `alert_status = 'false_positive'` is populated but never analysed, so per-rule precision — the most decision-relevant property of an alerting system — is unknown.

---

## 7. Repository map

```
payscope/
├── sql/
│   ├── ddl/      01 schemas · 02 raw tables · 03 clean tables
│   ├── seed/     01–06 synthetic generation
│   ├── issues/   01–06 controlled defect injection
│   ├── marts/    01–07 business marts
│   ├── qa/       raw · clean · mart QA gates
│   └── run_marts.sql
├── python/
│   ├── config/          db.py — single SQLAlchemy engine
│   ├── extraction/      extract_raw.py — raw → CSV
│   ├── dq/              dq_checks.py — 37 profiling checks
│   ├── cleaning/        clean_*.py — 6 modules, 55 rules
│   ├── loading/         load_clean.py — CSV → clean schema
│   ├── reporting/       before_after_summary.py
│   └── outputs/         extracted · cleaned · dq_reports · business_reports
├── tableau/             workbook
└── docs/
    ├── PROJECT_DOCUMENTATION.md   full end-to-end reference
    ├── TECHNICAL_REPORT.md        this document
    └── UPGRADE_ROADMAP.md         prioritised improvements
```

---

## 8. Reproducing this report

Every figure above came from the live warehouse. The load-bearing queries:

```sql
-- §4.1 source tier vs behavioural segment
SELECT risk_tier_source, merchant_risk_segment, COUNT(*)
FROM mart.merchant_risk_segmentation GROUP BY 1, 2;

-- §4.3 threshold calibration against the observed distribution
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY failure_rate_pct) AS median_failure,
       COUNT(*) FILTER (WHERE failure_rate_pct >= 22) AS caught_by_monitor_trigger,
       COUNT(*) AS total
FROM mart.merchant_risk_segmentation;

-- §4.5 constraint and type verification
SELECT table_schema, table_name, constraint_type
FROM information_schema.table_constraints WHERE table_schema IN ('clean','mart');

SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'clean' AND table_name = 'transactions';

-- §4.8 degenerate grain in chargeback_summary
SELECT COUNT(*) AS rows,
       COUNT(*) FILTER (WHERE chargeback_count
             = open_disputes + won_disputes + lost_disputes + closed_disputes) AS single_bucket_rows
FROM mart.chargeback_summary;
```

§4.2's decomposition is reproduced by rebuilding the three broken-link masks from the cleaned CSVs and counting invalid transactions where no other mask fires.

---

**Author:** Mahesh Sai Kandula — MSc Data Science, Macquarie University (Sydney)
[LinkedIn](https://www.linkedin.com/in/mahesh-kandula-b6393622a/) · [GitHub](https://github.com/MSkandula)

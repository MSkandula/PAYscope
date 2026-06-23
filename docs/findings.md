# PayScope — Findings & Methodology

- **Project:** Digital Payments Risk & Merchant Analytics Platform
- **Author:** Mahesh Sai Kandula
- **Stack:** PostgreSQL · SQL · Python (pandas, SQLAlchemy) · Tableau

---

## 1. Purpose of this document

This report summarises what the PayScope pipeline produces and what can be concluded
from it. PayScope simulates the data stack of a payments processor end to end — from
raw operational data, through validation and cleaning, into business-ready marts and
dashboards.

> **Note on the data.** All data in PayScope is **synthetic and randomly generated**,
> and the data-quality issues are **deliberately injected** to test the validation layer.
> This report therefore does **not** claim to have discovered real-world business trends;
> the values themselves are random. What it reports are the genuine, defensible results
> of the *pipeline's design* — how much bad data was caught, how validity behaves across
> related tables, and what business question each mart is built to answer.

---

## 2. Data and scale

| Table | Rows | Valid records | Valid rate |
|---|---|---|---|
| customers | 10,000 | 9,446 | 94.5% |
| merchants | 1,200 | 1,001 | 83.4% |
| devices | 15,000 | ~13,425 | 89.5% |
| transactions | 100,000 | 69,713 | 69.7% |
| chargebacks | 1,851 | 883 | 47.7% |
| alerts | 9,956 | 6,670 | 67.0% |

Validity is tracked per row using two audit columns — `is_valid_record` (a boolean
gate) and `dq_issue_count` (how many distinct checks a row failed) — plus a
`cleaned_at` timestamp. **Invalid records are flagged, never deleted**, so the full
audit trail is preserved and downstream marts can simply filter to `is_valid_record = TRUE`.

---

## 3. Finding 1 — The cost of dirty data is measurable, and it cascades

Across the six tables, the validation layer caught and flagged tens of thousands of
problem rows: duplicate references, nulls in required fields, broken foreign keys,
future-dated events, out-of-range values, and inconsistent category/currency labels.

The most analytically interesting result is **how validity cascades through the
foreign-key chain**:

- Standalone reference tables stay cleanest — customers at **94.5%** valid.
- Transactions, which depend on valid customers, merchants, *and* devices, drop to
  **69.7%**: a transaction is only as trustworthy as the three entities it links to.
- Chargebacks fall furthest, to **47.7%**, because they depend on a valid transaction
  *and* a valid customer *and* a valid merchant. Each broken link compounds.

**Takeaway:** referential integrity isn't a back-office detail — it directly determines
how much of your data is usable for analysis. A naïve pipeline that joined raw tables
would silently inherit every one of these errors. PayScope's flag-don't-delete approach
makes the trustworthy subset explicit (e.g. the 69,713 transactions, ~$9.25M, that
survive validation) while keeping the rejected rows available for root-cause review.

---

## 4. Finding 2 — Source-system risk tiers don't match actual behaviour

Each merchant arrives with a `risk_tier_source` label (low / medium / high) from the
upstream system. PayScope also computes a **behaviour-based** segmentation in
`mart.merchant_risk_segmentation`, scoring each merchant on observed activity —
chargeback rate, failure rate, and alert volume — into four bands:

| Segment | Merchants |
|---|---|
| Critical | 81 |
| High Risk | 392 |
| Monitor | 440 |
| Low Risk | 88 |

Comparing the two, **the source-system tier shows little relationship to the
behaviour-based segment.** Even allowing for the synthetic data, this mirrors a real
and important analytics-engineering lesson: *inherited labels should be validated
against observed behaviour, not trusted by default.* This is precisely why PayScope
computes its own segmentation layer rather than passing the source tier straight
through to the dashboards.

---

## 5. What each mart is built to answer

The seven marts are designed so an analyst can answer a specific business question from
each without touching raw tables:

| Mart | Business question it answers |
|---|---|
| `daily_transaction_monitoring` | How are volume, approval rate, and failure rate trending day to day? |
| `merchant_performance_summary` | Which merchants drive volume, and how do their approval / chargeback rates compare? |
| `chargeback_summary` | What are chargebacks costing, by reason and dispute outcome, over time? |
| `alerts_summary` | What risk rules are firing, at what severity, and how many are unresolved? |
| `customer_risk_features` | Which customers show high-risk patterns (failed payments, chargebacks, alerts)? |
| `merchant_risk_segmentation` | Which merchants need review, ranked by behaviour-based risk? |
| `risk_rule_hits` | Which specific entities tripped which rule, with an explanation per hit? |

All rates (approval, failure, chargeback, cross-border) are computed with an
**aggregate-before-join** pattern and `SUM(...)/SUM(...)` calculations rather than
averaging pre-computed percentages — this avoids both grain-mismatch double-counting
and the "average of averages" error.

---

## 6. Dashboards

Three Tableau dashboards sit on top of the marts:

- **Transaction Monitoring** — KPI tiles (volume, approval, failure, value) and a weekly
  volume-vs-approval trend.
- **Merchant Risk** — KPI tiles and a failure-rate vs chargeback-rate scatter, sized by
  volume and coloured by risk segment.
- **Chargeback Analysis** — totals, chargebacks by reason, dispute outcomes, and a weekly
  amount trend.

🔗 Live: https://public.tableau.com/app/profile/mahesh.sai.kandula7753/viz/Transaction_monitoring/Dashboard3

---

## 7. Limitations & honest caveats

- **Synthetic data.** Values are randomly generated; no real-world trend should be read
  into specific figures. The pipeline, validation logic, and modelling are the substance.
- **Single-run snapshot.** The marts reflect one generated dataset, not a live feed.
- **Rule-based, not predictive.** Risk scoring is explainable and threshold-driven by
  design, prioritising transparency over predictive power. A production version could add
  a model on top, but the rule layer keeps every flag auditable.

---

## 8. What a production version would add

- Orchestration (Airflow / dbt) to schedule and test the pipeline on real, incremental data
- CI checks running the QA suite on every change
- Alerting when validity rates drop below a threshold (a data-quality SLA)
- A trend layer to track the data-quality and risk metrics *over time*, not just at a snapshot

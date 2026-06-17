# PayScope — Digital Payments Risk & Merchant Analytics

An end-to-end digital payments analytics and risk-monitoring platform built with **PostgreSQL, Python, SQL, and Tableau**. PayScope simulates the data stack of a payments processor (think Stripe / Adyen / Square): it generates realistic operational data, deliberately injects data-quality problems, detects and cleans them through a layered pipeline, builds business marts, and surfaces transaction health, merchant risk, and chargeback behaviour through interactive Tableau dashboards.

> Built as a portfolio project to demonstrate analytics engineering, data-quality engineering, SQL, and business intelligence skills. All data is synthetically generated — no real customer data is used.

---

## Dashboards

<img width="1512" height="982" alt="Dashboard 1" src="https://github.com/user-attachments/assets/cf0eea70-308b-4bbc-9623-a216eb1ec92d" />
<img width="1512" height="982" alt="Dashboard 2" src="https://github.com/user-attachments/assets/cb29ad47-55dd-4dfb-9f51-76c21e65c517" />
<img width="1512" height="982" alt="Dashboard 3" src="https://github.com/user-attachments/assets/3da847cd-7ba9-4af1-8dc7-e938d4c5c7e2" />


| Dashboard | What it answers |
|---|---|
| **Transaction Monitoring** | Are payments healthy? Daily volume, approval/failure rates, cross-border activity over time. |
| **Merchant Risk** | Which merchants are risky? Failure vs chargeback scatter, segmented by behaviour-based risk tier. |
| **Chargeback Analysis** | Where do disputes come from and how do they resolve? Breakdown by reason, outcome, and weekly trend. |

<!-- 
![Transaction Monitoring](docs/img/transaction_monitoring.png)
![Merchant Risk](docs/img/merchant_risk.png)
![Chargeback Analysis](docs/img/chargeback_analysis.png)
-->

---

## Why this project

Most portfolio dashboards start from a clean CSV. Real analytics work doesn't — the hard part is the messy data *before* the chart. PayScope is built to show that I can handle the full lifecycle: model a schema, generate realistic data, find and fix quality issues, build trustworthy aggregates, and only then visualise. The data-quality layer is the part most candidates skip, and it's the part this project is built around.

---

## Architecture

A layered (medallion-style) pipeline across three PostgreSQL schemas:

```
Synthetic data generation
        │
        ▼
   raw schema  ─────────►  Python extraction  ─────►  Raw QA checks
        │                                                  │
        ▼                                                  ▼
   Data cleaning & validation (Python)            (profile injected issues)
        │
        ▼
   Clean CSV outputs  ─────►  clean schema  ─────►  Clean QA checks
        │
        ▼
   Business marts (SQL)  ─────►  mart schema  ─────►  Mart QA checks
        │
        ▼
   Tableau dashboards
```

**`raw`** — source-system data, warts and all.
**`clean`** — validated data. Records are **flagged, not deleted** (`is_valid_record`, `dq_issue_count`, `cleaned_at`), preserving a full audit trail.
**`mart`** — business-ready aggregates that the BI layer reads from. Tableau never touches raw tables.

---

## Tech stack

| Layer | Tools |
|---|---|
| Database | PostgreSQL (multi-schema: `raw` / `clean` / `mart`) |
| Languages | SQL, Python |
| Python | pandas, SQLAlchemy, psycopg2 |
| BI | Tableau |
| Tooling | VS Code, Jupyter, Git/GitHub |

---

## Data model

Six core tables generated synthetically:

| Table | Rows | Description |
|---|---:|---|
| `customers` | 10,000 | Customer master data |
| `merchants` | 1,200 | Merchant master data |
| `devices` | 15,000 | Device / fingerprint metadata |
| `transactions` | 100,000 | Core payments fact table |
| `chargebacks` | 1,851 | Disputes and outcomes |
| `alerts` | 9,956 | Fraud / risk alerts |

---

## Data-quality framework

Realistic operational issues are **deliberately injected** into the raw layer, then detected and cleaned. Examples: null and duplicate emails, invalid currency/country codes, future-dated records, negative or zero amounts, broken foreign keys, impossible timestamps, and inconsistent label casing.

The cleaning pipeline flags each record rather than dropping it. Before/after results:

| Table | Total rows | Valid | Invalid | Valid rate |
|---|---:|---:|---:|---:|
| customers | 10,000 | 9,446 | 554 | 94.5% |
| merchants | 1,200 | 1,001 | 199 | 83.4% |
| devices | 15,000 | 13,426 | 1,574 | 89.5% |
| transactions | 100,000 | 69,713 | 30,287 | 69.7% |
| chargebacks | 1,851 | 883 | 968 | 47.7% |
| alerts | 9,956 | 6,675 | 3,281 | 67.0% |

Quality is profiled with SQL and Python checks at **every** layer (`raw` / `clean` / `mart`), and a before/after report quantifies the cleaning impact.

---

## Business marts

Seven marts power the BI layer:

| Mart | Purpose |
|---|---|
| `daily_transaction_monitoring` | Daily volume, approval/failure rates, cross-border rate |
| `merchant_performance_summary` | Per-merchant volume, approval, chargeback rate, alerts |
| `chargeback_summary` | Chargebacks by date, reason, and dispute outcome |
| `alerts_summary` | Alert volume by rule, severity, and status |
| `customer_risk_features` | Customer-level behavioural risk features + flag |
| `merchant_risk_segmentation` | Merchants classified into Critical / High Risk / Monitor / Low Risk |
| `risk_rule_hits` | Explainable rule-engine output (one row per triggered rule) |

---

## Risk engine

Risk is scored with **explainable rules**, not a black-box model — every flag can be explained to a business user. Rules include repeated failed payments, multiple chargebacks per customer, high-activity devices, merchant chargeback spikes, and repeated risky alerts. Merchants are then segmented (Critical / High Risk / Monitor / Low Risk) from observed behaviour — chargeback rate, failure rate, and alert volume — rather than the inherited source-system label.

> A finding worth noting: the source-system risk tier shows little relationship to actual merchant behaviour, which is exactly why a behaviour-based segmentation layer exists.

---

## Key engineering decisions

- **Raw / clean / mart separation** keeps source data, validated data, and business logic cleanly decoupled.
- **Flag, don't delete** — invalid records are marked, not removed, preserving auditability.
- **Aggregate before joining** — the merchant mart aggregates transactions, chargebacks, and alerts *separately* before joining, avoiding fact-table grain duplication and double-counting.
- **Marts feed BI, not raw tables** — Tableau reads pre-aggregated marts, keeping dashboards fast and logic centralised.
- **Explainable rules over ML** — for a risk context, transparency beats marginal accuracy.

---

## Repository structure

```
payscope/
├── sql/
│   ├── ddl/          # schema + table definitions
│   ├── seed/         # synthetic data generation
│   ├── marts/        # business mart definitions
│   ├── qa/           # raw / clean / mart QA checks
│   └── run_marts.sql # build all marts in order
├── python/
│   ├── config/       # db connection
│   ├── extraction/   # raw → CSV
│   ├── dq/           # data-quality checks
│   ├── cleaning/     # validation + cleaning
│   ├── loading/      # clean → PostgreSQL
│   ├── reporting/    # before/after summary
│   └── outputs/      # generated CSVs
├── tableau/          # packaged workbook(s)
├── docs/             # architecture, glossary, data dictionary
└── README.md
```

---

## How to run

```bash
# 1. Create schemas and raw tables, seed synthetic data, inject DQ issues
psql -d payscope -f sql/ddl/01_create_schemas.sql
psql -d payscope -f sql/ddl/02_raw_tables.sql
# ... seed + inject scripts

# 2. Extract → check → clean → load (Python)
python -m python.extraction.extract_raw
python -m python.dq.dq_checks
python -m python.cleaning.clean_transactions   # + other clean_*.py
python -m python.loading.load_clean

# 3. Build marts + QA
psql -d payscope -f sql/run_marts.sql

# 4. Open the Tableau workbook in /tableau and connect to the mart schema
```

*Database connection is configured via a `.env` file (`DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_NAME`).*

---

## Author

**Mahesh Sai Kandula** — MSc Data Science, Macquarie University (Sydney).
- Open to Data Analyst, Analytics Engineer, and Data Engineer roles.

- [LinkedIn](https://www.linkedin.com/in/mahesh-kandula-b6393622a/) 
- [GitHub](https://github.com/MSkandula)

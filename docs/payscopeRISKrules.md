# PayScope — Risk Rules

This document defines the explainable, threshold-based risk logic used in the mart layer.
All rules run only over validated data (`is_valid_record = TRUE`). The design is
deliberately rule-based rather than model-based, so every flag is transparent and
auditable.

## 1. Merchant risk segmentation

Source: `mart.merchant_risk_segmentation` (built on `mart.merchant_performance_summary`).
Each merchant is placed in the **highest** band whose condition it meets.

| Segment | Band | Condition (any one triggers) |
|---|---|---|
| Critical | 4 | chargeback rate ≥ 4% **or** failure rate ≥ 35% **or** alerts ≥ 12 |
| High Risk | 3 | chargeback rate ≥ 2.5% **or** failure rate ≥ 28% **or** alerts ≥ 9 |
| Monitor | 2 | chargeback rate ≥ 1.5% **or** failure rate ≥ 22% **or** alerts ≥ 6 |
| Low Risk | 1 | none of the above |

Rates are computed with an aggregate-before-join pattern (`SUM/SUM`), not by averaging
pre-computed percentages.

## 2. High-risk customer flag

Source: `mart.customer_risk_features`. A customer is flagged `high_risk_customer_flag = TRUE`
if **any** of the following hold:

- chargeback count ≥ 2, **or**
- critical-severity alerts ≥ 1, **or**
- high-severity alerts ≥ 3, **or**
- failed transactions ≥ 5

## 3. Explainable rule-hit register

Source: `mart.risk_rule_hits`. Each rule writes one row per entity that trips it, with a
plain-language `rule_description`, so any flag can be explained on its own.

| Rule | Entity | Condition | Description |
|---|---|---|---|
| repeated_failed_payments | customer | ≥ 5 failed transactions | Customer has 5+ failed transactions |
| high_chargeback_customer | customer | ≥ 2 valid chargebacks | Customer has 2+ valid chargebacks |
| high_activity_device | device | ≥ 10 valid transactions | Device used in 10+ valid transactions |
| merchant_chargeback_spike | merchant | chargeback rate ≥ 2.5% | Merchant has elevated chargeback rate |
| repeated_risky_alerts | merchant | ≥ 9 valid alerts | Merchant has 9+ valid alerts |

## Design notes

- **Explainable by construction.** Every threshold is a published number, and every hit
  carries its own justification — no black-box scoring.
- **Validated input only.** Rules ignore invalid records, so flags can't be driven by
  dirty data.
- **Tunable.** Thresholds are centralised in the mart SQL; tightening or loosening a band
  is a one-line change, which is how a real risk team would iterate.

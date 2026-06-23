# PayScope — Cleaning & Validation Logic

This document describes how raw data is validated and cleaned before it reaches the
`clean` schema. It mirrors the logic in the `clean_*.py` scripts.

## Core principles

1. **Flag, don't delete.** Every cleaned table carries:
   - `is_valid_record` — boolean; `TRUE` only if the row failed **zero** checks.
   - `dq_issue_count` — how many distinct checks the row failed.
   - `cleaned_at` — audit timestamp.
   Invalid rows are kept, so nothing is lost and issues can be traced.

2. **Standardise before checking.** Text fields are trimmed and case-normalised
   (emails lowercased, country/currency codes uppercased, labels lowercased) *before*
   validation, so cosmetic inconsistencies (`"AU "`, `"Approved"`, `"med"`) don't count
   as errors.

3. **Known-value mappings** fix predictable variants:
   `USA → US`, status `fail → failed`, severity `med → medium`.

4. **Referential integrity uses valid parents only.** Foreign-key checks resolve against
   the set of parent rows that are themselves valid (`is_valid_record = TRUE`), so validity
   cascades correctly down the chain (customer → device/transaction → chargeback/alert).

5. **Dates and numbers are coerced** with errors turned into nulls, which are then caught
   as their own issue rather than crashing the pipeline.

## Allowed value sets

| Field | Allowed values |
|---|---|
| country_code | AU, US, GB, IN, SG |
| currency | AUD, USD, GBP, INR, SGD |
| customer status | active, inactive, suspended |
| merchant category | ecommerce, food_delivery, electronics, gaming, travel, subscription |
| merchant risk tier | low, medium, high |
| device type | mobile, desktop, tablet |
| os name | ios, android, windows, macos |
| transaction status | approved, failed, pending, reversed |
| payment method | card, wallet, bank_transfer |
| chargeback reason | fraud, service_not_received, duplicate_processing, authorization_issue |
| dispute status | open, won, lost, closed |
| alert rule | repeated_failed_payments, shared_device_many_customers, high_chargeback_customer, merchant_chargeback_spike, emulator_device_usage, cross_border_high_risk_merchant |
| alert severity | low, medium, high, critical |
| alert status | open, under_review, resolved, false_positive |

## Checks per table

**customers** — missing email; invalid email format (regex); duplicate email;
invalid country; future signup date; invalid status.

**merchants** — null legal name; duplicate merchant name; invalid category;
invalid country; invalid settlement currency; future onboarding date; invalid risk tier.

**devices** — null/invalid device type; null app version; invalid OS;
invalid country; invalid IP country; broken customer link; impossible timing
(`last_seen_at < first_seen_at`).

**transactions** — duplicate transaction_ref; missing or non-positive amount
(`amount <= 0`); missing or future timestamp; invalid status / currency / payment method;
invalid merchant / customer / device country; broken customer / merchant / device link.

**chargebacks** — missing or non-positive amount; missing chargeback date;
resolution date before chargeback date; invalid reason; invalid dispute status;
broken transaction / customer / merchant link.

**alerts** — missing or future alert timestamp; missing risk score; out-of-range
risk score (`< 0` or `> 100`); invalid rule name / severity / status;
broken transaction / customer / merchant / device link.

A row's `dq_issue_count` is the number of the above it fails; `is_valid_record` is
`TRUE` only when that count is `0`.

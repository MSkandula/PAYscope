-- =========================================
-- PayScope Project
-- File: 07_risk_rule_hits.sql
-- Purpose: Create explainable risk rule hit mart
-- =========================================

DROP TABLE IF EXISTS mart.risk_rule_hits;

CREATE TABLE mart.risk_rule_hits AS

-- Rule 1: Customers with repeated failed payments
SELECT
    'repeated_failed_payments' AS rule_name,
    'customer' AS entity_type,
    customer_id AS entity_id,
    COUNT(*) AS rule_hit_count,
    'Customer has 5 or more failed transactions' AS rule_description
FROM clean.transactions
WHERE is_valid_record = TRUE
  AND status = 'failed'
GROUP BY customer_id
HAVING COUNT(*) >= 5

UNION ALL

-- Rule 2: Customers with multiple chargebacks
SELECT
    'high_chargeback_customer' AS rule_name,
    'customer' AS entity_type,
    customer_id AS entity_id,
    COUNT(*) AS rule_hit_count,
    'Customer has 2 or more valid chargebacks' AS rule_description
FROM clean.chargebacks
WHERE is_valid_record = TRUE
GROUP BY customer_id
HAVING COUNT(*) >= 2

UNION ALL

-- Rule 3: Devices linked to many transactions
SELECT
    'high_activity_device' AS rule_name,
    'device' AS entity_type,
    device_id AS entity_id,
    COUNT(*) AS rule_hit_count,
    'Device used in 10 or more valid transactions' AS rule_description
FROM clean.transactions
WHERE is_valid_record = TRUE
GROUP BY device_id
HAVING COUNT(*) >= 10

UNION ALL

-- Rule 4: Merchants with high chargeback rate
SELECT
    'merchant_chargeback_spike' AS rule_name,
    'merchant' AS entity_type,
    merchant_id AS entity_id,
    chargeback_count AS rule_hit_count,
    'Merchant has chargeback rate of 2.5% or higher' AS rule_description
FROM mart.merchant_performance_summary
WHERE chargeback_rate_pct >= 2.5

UNION ALL

-- Rule 5: Merchants with high alert volume
SELECT
    'repeated_risky_alerts' AS rule_name,
    'merchant' AS entity_type,
    merchant_id AS entity_id,
    alert_count AS rule_hit_count,
    'Merchant has 9 or more valid alerts' AS rule_description
FROM mart.merchant_performance_summary
WHERE alert_count >= 9;

SELECT *
FROM mart.risk_rule_hits
ORDER BY rule_name, rule_hit_count DESC
LIMIT 20;
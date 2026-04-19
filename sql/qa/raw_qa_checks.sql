-- =========================================
-- PayScope Project
-- File: raw_qa_checks.sql
-- Purpose: Profile raw-layer data quality issues
-- =========================================

-- =========================================
-- RAW.CUSTOMERS
-- =========================================

SELECT 'raw.customers' AS table_name, 'row_count' AS check_name, COUNT(*)::TEXT AS result
FROM raw.customers

UNION ALL
SELECT 'raw.customers', 'null_email_count', COUNT(*)::TEXT
FROM raw.customers
WHERE email IS NULL

UNION ALL
SELECT 'raw.customers', 'invalid_email_format_count', COUNT(*)::TEXT
FROM raw.customers
WHERE email IS NOT NULL
  AND email NOT LIKE '%@%.%'

UNION ALL
SELECT 'raw.customers', 'duplicate_email_count', COUNT(*)::TEXT
FROM (
    SELECT email
    FROM raw.customers
    WHERE email IS NOT NULL
    GROUP BY email
    HAVING COUNT(*) > 1
) x

UNION ALL
SELECT 'raw.customers', 'future_signup_date_count', COUNT(*)::TEXT
FROM raw.customers
WHERE signup_date > CURRENT_DATE


UNION ALL

-- =========================================
-- RAW.MERCHANTS
-- =========================================

SELECT 'raw.merchants', 'row_count', COUNT(*)::TEXT
FROM raw.merchants

UNION ALL
SELECT 'raw.merchants', 'null_legal_name_count', COUNT(*)::TEXT
FROM raw.merchants
WHERE legal_name IS NULL

UNION ALL
SELECT 'raw.merchants', 'duplicate_merchant_name_count', COUNT(*)::TEXT
FROM (
    SELECT merchant_name
    FROM raw.merchants
    GROUP BY merchant_name
    HAVING COUNT(*) > 1
) x

UNION ALL
SELECT 'raw.merchants', 'invalid_currency_code_count', COUNT(*)::TEXT
FROM raw.merchants
WHERE settlement_currency NOT IN ('AUD','USD','GBP','INR','SGD')

UNION ALL
SELECT 'raw.merchants', 'future_onboarding_date_count', COUNT(*)::TEXT
FROM raw.merchants
WHERE onboarding_date > CURRENT_DATE


UNION ALL

-- =========================================
-- RAW.DEVICES
-- =========================================

SELECT 'raw.devices', 'row_count', COUNT(*)::TEXT
FROM raw.devices

UNION ALL
SELECT 'raw.devices', 'null_device_type_count', COUNT(*)::TEXT
FROM raw.devices
WHERE device_type IS NULL

UNION ALL
SELECT 'raw.devices', 'null_app_version_count', COUNT(*)::TEXT
FROM raw.devices
WHERE app_version IS NULL

UNION ALL
SELECT 'raw.devices', 'broken_customer_link_count', COUNT(*)::TEXT
FROM raw.devices d
LEFT JOIN raw.customers c
    ON d.customer_id = c.customer_id
WHERE c.customer_id IS NULL

UNION ALL
SELECT 'raw.devices', 'invalid_device_timing_count', COUNT(*)::TEXT
FROM raw.devices
WHERE last_seen_at < first_seen_at


UNION ALL

-- =========================================
-- RAW.TRANSACTIONS
-- =========================================

SELECT 'raw.transactions', 'row_count', COUNT(*)::TEXT
FROM raw.transactions

UNION ALL
SELECT 'raw.transactions', 'duplicate_transaction_ref_count', COUNT(*)::TEXT
FROM (
    SELECT transaction_ref
    FROM raw.transactions
    GROUP BY transaction_ref
    HAVING COUNT(*) > 1
) x

UNION ALL
SELECT 'raw.transactions', 'negative_amount_count', COUNT(*)::TEXT
FROM raw.transactions
WHERE amount < 0

UNION ALL
SELECT 'raw.transactions', 'zero_amount_count', COUNT(*)::TEXT
FROM raw.transactions
WHERE amount = 0

UNION ALL
SELECT 'raw.transactions', 'future_transaction_count', COUNT(*)::TEXT
FROM raw.transactions
WHERE transaction_ts > NOW()

UNION ALL
SELECT 'raw.transactions', 'invalid_currency_code_count', COUNT(*)::TEXT
FROM raw.transactions
WHERE currency_code NOT IN ('AUD','USD','GBP','INR','SGD')

UNION ALL
SELECT 'raw.transactions', 'broken_customer_link_count', COUNT(*)::TEXT
FROM raw.transactions t
LEFT JOIN raw.customers c
    ON t.customer_id = c.customer_id
WHERE c.customer_id IS NULL

UNION ALL
SELECT 'raw.transactions', 'broken_merchant_link_count', COUNT(*)::TEXT
FROM raw.transactions t
LEFT JOIN raw.merchants m
    ON t.merchant_id = m.merchant_id
WHERE m.merchant_id IS NULL

UNION ALL
SELECT 'raw.transactions', 'broken_device_link_count', COUNT(*)::TEXT
FROM raw.transactions t
LEFT JOIN raw.devices d
    ON t.device_id = d.device_id
WHERE d.device_id IS NULL


UNION ALL

-- =========================================
-- RAW.CHARGEBACKS
-- =========================================

SELECT 'raw.chargebacks', 'row_count', COUNT(*)::TEXT
FROM raw.chargebacks

UNION ALL
SELECT 'raw.chargebacks', 'null_chargeback_amount_count', COUNT(*)::TEXT
FROM raw.chargebacks
WHERE chargeback_amount IS NULL

UNION ALL
SELECT 'raw.chargebacks', 'negative_chargeback_amount_count', COUNT(*)::TEXT
FROM raw.chargebacks
WHERE chargeback_amount < 0

UNION ALL
SELECT 'raw.chargebacks', 'broken_transaction_link_count', COUNT(*)::TEXT
FROM raw.chargebacks cb
LEFT JOIN raw.transactions t
    ON cb.transaction_id = t.transaction_id
WHERE t.transaction_id IS NULL

UNION ALL
SELECT 'raw.chargebacks', 'broken_customer_link_count', COUNT(*)::TEXT
FROM raw.chargebacks cb
LEFT JOIN raw.customers c
    ON cb.customer_id = c.customer_id
WHERE c.customer_id IS NULL

UNION ALL
SELECT 'raw.chargebacks', 'broken_merchant_link_count', COUNT(*)::TEXT
FROM raw.chargebacks cb
LEFT JOIN raw.merchants m
    ON cb.merchant_id = m.merchant_id
WHERE m.merchant_id IS NULL

UNION ALL
SELECT 'raw.chargebacks', 'invalid_resolution_timing_count', COUNT(*)::TEXT
FROM raw.chargebacks
WHERE resolution_date IS NOT NULL
  AND resolution_date < chargeback_date


UNION ALL

-- =========================================
-- RAW.ALERTS
-- =========================================

SELECT 'raw.alerts', 'row_count', COUNT(*)::TEXT
FROM raw.alerts

UNION ALL
SELECT 'raw.alerts', 'future_alert_count', COUNT(*)::TEXT
FROM raw.alerts
WHERE alert_ts > NOW()

UNION ALL
SELECT 'raw.alerts', 'invalid_risk_score_count', COUNT(*)::TEXT
FROM raw.alerts
WHERE risk_score < 0
   OR risk_score > 100

UNION ALL
SELECT 'raw.alerts', 'broken_transaction_link_count', COUNT(*)::TEXT
FROM raw.alerts a
LEFT JOIN raw.transactions t
    ON a.transaction_id = t.transaction_id
WHERE t.transaction_id IS NULL

UNION ALL
SELECT 'raw.alerts', 'broken_customer_link_count', COUNT(*)::TEXT
FROM raw.alerts a
LEFT JOIN raw.customers c
    ON a.customer_id = c.customer_id
WHERE c.customer_id IS NULL

UNION ALL
SELECT 'raw.alerts', 'broken_merchant_link_count', COUNT(*)::TEXT
FROM raw.alerts a
LEFT JOIN raw.merchants m
    ON a.merchant_id = m.merchant_id
WHERE m.merchant_id IS NULL

UNION ALL
SELECT 'raw.alerts', 'broken_device_link_count', COUNT(*)::TEXT
FROM raw.alerts a
LEFT JOIN raw.devices d
    ON a.device_id = d.device_id
WHERE d.device_id IS NULL

ORDER BY table_name, check_name;
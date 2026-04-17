-- =========================================
-- PayScope Project
-- File: 06_seed_alerts.sql
-- Purpose: Generate synthetic risk alerts
-- =========================================

INSERT INTO raw.alerts (
    alert_ref,
    transaction_id,
    customer_id,
    merchant_id,
    device_id,
    alert_ts,
    rule_name,
    severity,
    risk_score,
    alert_status
)
SELECT
    'ALT_' || t.transaction_id || '_' || gs AS alert_ref,
    t.transaction_id,
    t.customer_id,
    t.merchant_id,
    t.device_id,

    -- alert happens at or after transaction time
    t.transaction_ts + ((RANDOM()*48)::INT * INTERVAL '1 hour') AS alert_ts,

    (ARRAY[
        'repeated_failed_payments',
        'shared_device_many_customers',
        'high_chargeback_customer',
        'merchant_chargeback_spike',
        'emulator_device_usage',
        'cross_border_high_risk_merchant'
    ])[FLOOR(RANDOM()*6 + 1)] AS rule_name,

    (ARRAY[
        'low',
        'medium',
        'high'
    ])[FLOOR(RANDOM()*3 + 1)] AS severity,

    ROUND((20 + RANDOM()*80)::numeric, 2) AS risk_score,

    (ARRAY[
        'open',
        'under_review',
        'resolved',
        'false_positive'
    ])[FLOOR(RANDOM()*4 + 1)] AS alert_status

FROM raw.transactions t
CROSS JOIN generate_series(1, 1) AS gs
WHERE RANDOM() < 0.10;
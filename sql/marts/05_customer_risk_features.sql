-- =========================================
-- PayScope Project
-- File: 05_customer_risk_features.sql
-- Purpose: Create customer-level risk feature mart
-- =========================================

DROP TABLE IF EXISTS mart.customer_risk_features;

CREATE TABLE mart.customer_risk_features AS
WITH txn AS (
    SELECT
        customer_id,

        COUNT(*) AS total_transactions,
        SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) AS approved_transactions,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_transactions,

        ROUND(SUM(amount)::numeric, 2) AS total_transaction_amount,
        ROUND(AVG(amount)::numeric, 2) AS avg_transaction_amount,

        SUM(CASE WHEN is_cross_border = TRUE THEN 1 ELSE 0 END) AS cross_border_transactions,
        COUNT(DISTINCT merchant_id) AS distinct_merchants_used,
        COUNT(DISTINCT device_id) AS distinct_devices_used

    FROM clean.transactions
    WHERE is_valid_record = TRUE
    GROUP BY customer_id
),

cb AS (
    SELECT
        customer_id,
        COUNT(*) AS chargeback_count,
        ROUND(SUM(chargeback_amount)::numeric, 2) AS total_chargeback_amount
    FROM clean.chargebacks
    WHERE is_valid_record = TRUE
    GROUP BY customer_id
),

al AS (
    SELECT
        customer_id,
        COUNT(*) AS alert_count,
        SUM(CASE WHEN severity = 'high' THEN 1 ELSE 0 END) AS high_severity_alerts,
        SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) AS critical_severity_alerts,
        ROUND(AVG(risk_score)::numeric, 2) AS avg_alert_risk_score
    FROM clean.alerts
    WHERE is_valid_record = TRUE
    GROUP BY customer_id
)

SELECT
    c.customer_id,
    c.customer_ref,
    c.country_code,
    c.status,

    COALESCE(txn.total_transactions, 0) AS total_transactions,
    COALESCE(txn.approved_transactions, 0) AS approved_transactions,
    COALESCE(txn.failed_transactions, 0) AS failed_transactions,

    ROUND(
        100.0 * COALESCE(txn.failed_transactions, 0) / NULLIF(txn.total_transactions, 0),
        2
    ) AS failure_rate_pct,

    COALESCE(txn.total_transaction_amount, 0) AS total_transaction_amount,
    txn.avg_transaction_amount,

    COALESCE(txn.cross_border_transactions, 0) AS cross_border_transactions,

    ROUND(
        100.0 * COALESCE(txn.cross_border_transactions, 0) / NULLIF(txn.total_transactions, 0),
        2
    ) AS cross_border_rate_pct,

    COALESCE(txn.distinct_merchants_used, 0) AS distinct_merchants_used,
    COALESCE(txn.distinct_devices_used, 0) AS distinct_devices_used,

    COALESCE(cb.chargeback_count, 0) AS chargeback_count,
    COALESCE(cb.total_chargeback_amount, 0) AS total_chargeback_amount,

    COALESCE(al.alert_count, 0) AS alert_count,
    COALESCE(al.high_severity_alerts, 0) AS high_severity_alerts,
    COALESCE(al.critical_severity_alerts, 0) AS critical_severity_alerts,
    al.avg_alert_risk_score,

    CASE
        WHEN COALESCE(cb.chargeback_count, 0) >= 2
          OR COALESCE(al.critical_severity_alerts, 0) >= 1
          OR COALESCE(al.high_severity_alerts, 0) >= 3
          OR COALESCE(txn.failed_transactions, 0) >= 5
        THEN TRUE
        ELSE FALSE
    END AS high_risk_customer_flag

FROM clean.customers c
LEFT JOIN txn ON c.customer_id = txn.customer_id
LEFT JOIN cb ON c.customer_id = cb.customer_id
LEFT JOIN al ON c.customer_id = al.customer_id
WHERE c.is_valid_record = TRUE
ORDER BY high_risk_customer_flag DESC, alert_count DESC, chargeback_count DESC;

SELECT *
FROM mart.customer_risk_features
ORDER BY high_risk_customer_flag DESC, alert_count DESC
LIMIT 10;
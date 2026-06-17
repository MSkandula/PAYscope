DROP TABLE IF EXISTS mart.merchant_performance_summary;

CREATE TABLE mart.merchant_performance_summary AS
WITH txn AS (
    SELECT
        merchant_id,
        COUNT(*) AS total_transactions,
        SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) AS approved_transactions,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_transactions,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_transactions,
        SUM(CASE WHEN status = 'reversed' THEN 1 ELSE 0 END) AS reversed_transactions,
        ROUND(SUM(amount)::numeric, 2) AS total_processed_amount,
        ROUND(AVG(amount)::numeric, 2) AS avg_transaction_amount,
        SUM(CASE WHEN is_cross_border = TRUE THEN 1 ELSE 0 END) AS cross_border_transactions
    FROM clean.transactions
    WHERE is_valid_record = TRUE
    GROUP BY merchant_id
),

cb AS (
    SELECT
        merchant_id,
        COUNT(*) AS chargeback_count,
        ROUND(SUM(chargeback_amount)::numeric, 2) AS chargeback_amount
    FROM clean.chargebacks
    WHERE is_valid_record = TRUE
    GROUP BY merchant_id
),

al AS (
    SELECT
        merchant_id,
        COUNT(*) AS alert_count
    FROM clean.alerts
    WHERE is_valid_record = TRUE
    GROUP BY merchant_id
)

SELECT
    m.merchant_id,
    m.merchant_ref,
    m.merchant_name,
    m.merchant_category,
    m.country_code,
    m.settlement_currency,
    m.risk_tier_source,
    m.is_active,

    COALESCE(txn.total_transactions, 0) AS total_transactions,
    COALESCE(txn.approved_transactions, 0) AS approved_transactions,
    COALESCE(txn.failed_transactions, 0) AS failed_transactions,
    COALESCE(txn.pending_transactions, 0) AS pending_transactions,
    COALESCE(txn.reversed_transactions, 0) AS reversed_transactions,

    ROUND(100.0 * COALESCE(txn.approved_transactions, 0) / NULLIF(txn.total_transactions, 0), 2) AS approval_rate_pct,
    ROUND(100.0 * COALESCE(txn.failed_transactions, 0) / NULLIF(txn.total_transactions, 0), 2) AS failure_rate_pct,

    COALESCE(txn.total_processed_amount, 0) AS total_processed_amount,
    txn.avg_transaction_amount,

    COALESCE(txn.cross_border_transactions, 0) AS cross_border_transactions,
    ROUND(100.0 * COALESCE(txn.cross_border_transactions, 0) / NULLIF(txn.total_transactions, 0), 2) AS cross_border_rate_pct,

    COALESCE(cb.chargeback_count, 0) AS chargeback_count,
    COALESCE(cb.chargeback_amount, 0) AS chargeback_amount,
    ROUND(100.0 * COALESCE(cb.chargeback_count, 0) / NULLIF(txn.total_transactions, 0), 2) AS chargeback_rate_pct,

    COALESCE(al.alert_count, 0) AS alert_count

FROM clean.merchants m
LEFT JOIN txn ON m.merchant_id = txn.merchant_id
LEFT JOIN cb ON m.merchant_id = cb.merchant_id
LEFT JOIN al ON m.merchant_id = al.merchant_id
WHERE m.is_valid_record = TRUE
ORDER BY total_transactions DESC;

SELECT *
FROM mart.merchant_performance_summary
ORDER BY total_transactions DESC
LIMIT 10;
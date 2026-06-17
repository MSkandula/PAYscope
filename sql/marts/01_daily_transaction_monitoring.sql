

-- =========================================
-- PayScope Project
-- File: 01_daily_transaction_monitoring.sql
-- Purpose: Create daily transaction monitoring mart
-- =========================================

DROP TABLE IF EXISTS mart.daily_transaction_monitoring;

CREATE TABLE mart.daily_transaction_monitoring AS
SELECT
    transaction_ts::date AS transaction_date,

    COUNT(*) AS total_transactions,

    SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) AS approved_transactions,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_transactions,
    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_transactions,
    SUM(CASE WHEN status = 'reversed' THEN 1 ELSE 0 END) AS reversed_transactions,

    ROUND(
        100.0 * SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
        2
    ) AS approval_rate_pct,

    ROUND(
        100.0 * SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
        2
    ) AS failure_rate_pct,

    ROUND(SUM(amount)::numeric, 2) AS total_transaction_amount,
    ROUND(AVG(amount)::numeric, 2) AS avg_transaction_amount,

    SUM(CASE WHEN is_cross_border = TRUE THEN 1 ELSE 0 END) AS cross_border_transactions,

    ROUND(
        100.0 * SUM(CASE WHEN is_cross_border = TRUE THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
        2
    ) AS cross_border_rate_pct

FROM clean.transactions
WHERE is_valid_record = TRUE
GROUP BY transaction_ts::date
ORDER BY transaction_date;

-- Quick validation check
SELECT *
FROM mart.daily_transaction_monitoring
ORDER BY transaction_date
LIMIT 10;
-- =========================================
-- PayScope Project
-- File: 03_chargeback_summary.sql
-- Purpose: Create chargeback monitoring mart
-- =========================================

DROP TABLE IF EXISTS mart.chargeback_summary;

CREATE TABLE mart.chargeback_summary AS
SELECT
    chargeback_date::date AS chargeback_date,
    chargeback_reason,
    dispute_status,

    COUNT(*) AS chargeback_count,
    ROUND(SUM(chargeback_amount)::numeric, 2) AS total_chargeback_amount,
    ROUND(AVG(chargeback_amount)::numeric, 2) AS avg_chargeback_amount,

    COUNT(DISTINCT customer_id) AS affected_customers,
    COUNT(DISTINCT merchant_id) AS affected_merchants,

    SUM(CASE WHEN dispute_status = 'open' THEN 1 ELSE 0 END) AS open_disputes,
    SUM(CASE WHEN dispute_status = 'won' THEN 1 ELSE 0 END) AS won_disputes,
    SUM(CASE WHEN dispute_status = 'lost' THEN 1 ELSE 0 END) AS lost_disputes,
    SUM(CASE WHEN dispute_status = 'closed' THEN 1 ELSE 0 END) AS closed_disputes

FROM clean.chargebacks
WHERE is_valid_record = TRUE
GROUP BY
    chargeback_date::date,
    chargeback_reason,
    dispute_status
ORDER BY chargeback_date;

SELECT *
FROM mart.chargeback_summary
ORDER BY chargeback_date
LIMIT 10;
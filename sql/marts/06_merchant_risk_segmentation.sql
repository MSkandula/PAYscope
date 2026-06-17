-- =========================================
-- PayScope Project
-- File: 06_merchant_risk_segmentation.sql
-- Purpose: Segment merchants by operational and risk indicators
-- =========================================

DROP TABLE IF EXISTS mart.merchant_risk_segmentation;

CREATE TABLE mart.merchant_risk_segmentation AS
SELECT
    merchant_id,
    merchant_ref,
    merchant_name,
    merchant_category,
    country_code,
    settlement_currency,
    risk_tier_source,
    is_active,

    total_transactions,
    approval_rate_pct,
    failure_rate_pct,
    total_processed_amount,
    avg_transaction_amount,
    cross_border_rate_pct,
    chargeback_count,
    chargeback_amount,
    chargeback_rate_pct,
    alert_count,

    CASE
        WHEN chargeback_rate_pct >= 4
          OR failure_rate_pct >= 35
          OR alert_count >= 12
        THEN 'Critical'

        WHEN chargeback_rate_pct >= 2.5
          OR failure_rate_pct >= 28
          OR alert_count >= 9
        THEN 'High Risk'

        WHEN chargeback_rate_pct >= 1.5
          OR failure_rate_pct >= 22
          OR alert_count >= 6
        THEN 'Monitor'

        ELSE 'Low Risk'
    END AS merchant_risk_segment,

    CASE
        WHEN chargeback_rate_pct >= 4
          OR failure_rate_pct >= 35
          OR alert_count >= 12
        THEN 4

        WHEN chargeback_rate_pct >= 2.5
          OR failure_rate_pct >= 28
          OR alert_count >= 9
        THEN 3

        WHEN chargeback_rate_pct >= 1.5
          OR failure_rate_pct >= 22
          OR alert_count >= 6
        THEN 2

        ELSE 1
    END AS merchant_risk_score_band

FROM mart.merchant_performance_summary
WHERE total_transactions > 0
ORDER BY merchant_risk_score_band DESC, chargeback_rate_pct DESC, failure_rate_pct DESC;

SELECT
    merchant_risk_segment,
    COUNT(*) AS merchant_count,
    ROUND(AVG(failure_rate_pct)::numeric, 2) AS avg_failure_rate_pct,
    ROUND(AVG(chargeback_rate_pct)::numeric, 2) AS avg_chargeback_rate_pct,
    ROUND(AVG(alert_count)::numeric, 2) AS avg_alert_count
FROM mart.merchant_risk_segmentation
GROUP BY merchant_risk_segment
ORDER BY
    CASE merchant_risk_segment
        WHEN 'Critical' THEN 1
        WHEN 'High Risk' THEN 2
        WHEN 'Monitor' THEN 3
        WHEN 'Low Risk' THEN 4
    END;
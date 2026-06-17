-- =========================================
-- PayScope Project
-- File: 04_alerts_summary.sql
-- Purpose: Create alert monitoring summary mart
-- =========================================

DROP TABLE IF EXISTS mart.alerts_summary;

CREATE TABLE mart.alerts_summary AS
SELECT
    alert_ts::date AS alert_date,
    rule_name,
    severity,
    alert_status,

    COUNT(*) AS alert_count,
    ROUND(AVG(risk_score)::numeric, 2) AS avg_risk_score,
    MIN(risk_score) AS min_risk_score,
    MAX(risk_score) AS max_risk_score,

    COUNT(DISTINCT customer_id) AS affected_customers,
    COUNT(DISTINCT merchant_id) AS affected_merchants,
    COUNT(DISTINCT device_id) AS affected_devices,

    SUM(CASE WHEN severity = 'high' THEN 1 ELSE 0 END) AS high_severity_alerts,
    SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) AS critical_severity_alerts,

    SUM(CASE WHEN alert_status = 'open' THEN 1 ELSE 0 END) AS open_alerts,
    SUM(CASE WHEN alert_status = 'under_review' THEN 1 ELSE 0 END) AS under_review_alerts,
    SUM(CASE WHEN alert_status = 'resolved' THEN 1 ELSE 0 END) AS resolved_alerts,
    SUM(CASE WHEN alert_status = 'false_positive' THEN 1 ELSE 0 END) AS false_positive_alerts

FROM clean.alerts
WHERE is_valid_record = TRUE
GROUP BY
    alert_ts::date,
    rule_name,
    severity,
    alert_status
ORDER BY alert_date;

SELECT *
FROM mart.alerts_summary
ORDER BY alert_date
LIMIT 10;
-- =========================================
-- PayScope Project
-- File: mart_qa_checks.sql
-- Purpose: Validate mart-layer tables
-- =========================================

SELECT 'mart.daily_transaction_monitoring' AS mart_table,
       COUNT(*) AS row_count
FROM mart.daily_transaction_monitoring

UNION ALL

SELECT 'mart.merchant_performance_summary',
       COUNT(*)
FROM mart.merchant_performance_summary

UNION ALL

SELECT 'mart.chargeback_summary',
       COUNT(*)
FROM mart.chargeback_summary

UNION ALL

SELECT 'mart.alerts_summary',
       COUNT(*)
FROM mart.alerts_summary

UNION ALL

SELECT 'mart.customer_risk_features',
       COUNT(*)
FROM mart.customer_risk_features

UNION ALL

SELECT 'mart.merchant_risk_segmentation',
       COUNT(*)
FROM mart.merchant_risk_segmentation

UNION ALL

SELECT 'mart.risk_rule_hits',
       COUNT(*)
FROM mart.risk_rule_hits

ORDER BY mart_table;
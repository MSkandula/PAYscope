-- =========================================
-- PayScope Project
-- File: run_marts.sql
-- Purpose: Run all mart scripts in correct order
-- =========================================

\i sql/marts/01_daily_transaction_monitoring.sql
\i sql/marts/02_merchant_performance_summary.sql
\i sql/marts/03_chargeback_summary.sql
\i sql/marts/04_alerts_summary.sql
\i sql/marts/05_customer_risk_features.sql
\i sql/marts/06_merchant_risk_segmentation.sql
\i sql/marts/07_risk_rule_hits.sql

\i sql/qa/mart_qa_checks.sql
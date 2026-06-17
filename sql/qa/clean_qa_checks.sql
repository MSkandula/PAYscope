-- =========================================
-- PayScope Project
-- File: clean_qa_checks.sql
-- Purpose: Validate clean-layer loaded tables
-- =========================================

SELECT 'clean.customers' AS table_name,
       COUNT(*) AS total_rows,
       SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END) AS valid_rows,
       SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END) AS invalid_rows,
       ROUND(AVG(dq_issue_count)::numeric, 2) AS avg_dq_issues
FROM clean.customers

UNION ALL

SELECT 'clean.merchants',
       COUNT(*),
       SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
       SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END),
       ROUND(AVG(dq_issue_count)::numeric, 2)
FROM clean.merchants

UNION ALL

SELECT 'clean.devices',
       COUNT(*),
       SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
       SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END),
       ROUND(AVG(dq_issue_count)::numeric, 2)
FROM clean.devices

UNION ALL

SELECT 'clean.transactions',
       COUNT(*),
       SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
       SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END),
       ROUND(AVG(dq_issue_count)::numeric, 2)
FROM clean.transactions

UNION ALL

SELECT 'clean.chargebacks',
       COUNT(*),
       SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
       SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END),
       ROUND(AVG(dq_issue_count)::numeric, 2)
FROM clean.chargebacks

UNION ALL

SELECT 'clean.alerts',
       COUNT(*),
       SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
       SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END),
       ROUND(AVG(dq_issue_count)::numeric, 2)
FROM clean.alerts

ORDER BY table_name;
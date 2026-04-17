-- =========================================
-- PayScope Project
-- File: 06_inject_alert_issues.sql
-- Purpose: Inject controlled data quality issues into raw.alerts
-- =========================================

-- =========================================
-- 1. BROKEN TRANSACTION LINKS
-- =========================================
UPDATE raw.alerts
SET transaction_id = 980000 + alert_id
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    ORDER BY RANDOM()
    LIMIT 80
);

-- =========================================
-- 2. BROKEN CUSTOMER LINKS
-- =========================================
UPDATE raw.alerts
SET customer_id = 981000 + alert_id
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    ORDER BY RANDOM()
    LIMIT 70
);

-- =========================================
-- 3. BROKEN MERCHANT LINKS
-- =========================================
UPDATE raw.alerts
SET merchant_id = 982000 + alert_id
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    ORDER BY RANDOM()
    LIMIT 60
);

-- =========================================
-- 4. BROKEN DEVICE LINKS
-- =========================================
UPDATE raw.alerts
SET device_id = 983000 + alert_id
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    ORDER BY RANDOM()
    LIMIT 75
);

-- =========================================
-- 5. FUTURE ALERT TIMESTAMPS
-- =========================================
UPDATE raw.alerts
SET alert_ts = NOW() + ((RANDOM()*30)::INT + 1) * INTERVAL '1 day'
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    ORDER BY RANDOM()
    LIMIT 120
);

-- =========================================
-- 6. INVALID / INCONSISTENT RULE NAMES
-- =========================================
UPDATE raw.alerts
SET rule_name = 'Repeated_Failed_Payments'
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    WHERE rule_name = 'repeated_failed_payments'
    ORDER BY RANDOM()
    LIMIT 90
);

UPDATE raw.alerts
SET rule_name = 'emulator_device_usage '
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    WHERE rule_name = 'emulator_device_usage'
    ORDER BY RANDOM()
    LIMIT 70
);

-- =========================================
-- 7. INVALID / INCONSISTENT SEVERITIES
-- =========================================
UPDATE raw.alerts
SET severity = 'HIGH'
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    WHERE severity = 'high'
    ORDER BY RANDOM()
    LIMIT 80
);

UPDATE raw.alerts
SET severity = 'Med'
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    WHERE severity = 'medium'
    ORDER BY RANDOM()
    LIMIT 70
);

UPDATE raw.alerts
SET severity = 'critical'
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    ORDER BY RANDOM()
    LIMIT 40
);

-- =========================================
-- 8. OUT-OF-RANGE RISK SCORES
-- =========================================
UPDATE raw.alerts
SET risk_score = 150
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    ORDER BY RANDOM()
    LIMIT 45
);

UPDATE raw.alerts
SET risk_score = -10
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    ORDER BY RANDOM()
    LIMIT 35
);

-- =========================================
-- 9. INCONSISTENT ALERT STATUS LABELS
-- =========================================
UPDATE raw.alerts
SET alert_status = 'Open'
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    WHERE alert_status = 'open'
    ORDER BY RANDOM()
    LIMIT 60
);

UPDATE raw.alerts
SET alert_status = 'UNDER_REVIEW'
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    WHERE alert_status = 'under_review'
    ORDER BY RANDOM()
    LIMIT 50
);

UPDATE raw.alerts
SET alert_status = 'resolved '
WHERE alert_id IN (
    SELECT alert_id
    FROM raw.alerts
    WHERE alert_status = 'resolved'
    ORDER BY RANDOM()
    LIMIT 45
);
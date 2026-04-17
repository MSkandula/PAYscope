-- =========================================
-- PayScope Project
-- File: 03_inject_device_issues.sql
-- Purpose: Inject controlled data quality issues into raw.devices
-- =========================================

-- =========================================
-- 1. NULL DEVICE TYPES
-- =========================================
UPDATE raw.devices
SET device_type = NULL
WHERE device_id IN (
    SELECT device_id
    FROM raw.devices
    ORDER BY RANDOM()
    LIMIT 180
);

-- =========================================
-- 2. INCONSISTENT OS NAMES
-- =========================================
UPDATE raw.devices
SET os_name = 'ios'
WHERE device_id IN (
    SELECT device_id
    FROM raw.devices
    WHERE os_name = 'iOS'
    ORDER BY RANDOM()
    LIMIT 120
);

UPDATE raw.devices
SET os_name = 'ANDROID'
WHERE device_id IN (
    SELECT device_id
    FROM raw.devices
    WHERE os_name = 'Android'
    ORDER BY RANDOM()
    LIMIT 120
);

UPDATE raw.devices
SET os_name = 'windows '
WHERE device_id IN (
    SELECT device_id
    FROM raw.devices
    WHERE os_name = 'Windows'
    ORDER BY RANDOM()
    LIMIT 80
);

-- =========================================
-- 3. NULL APP VERSION
-- =========================================
UPDATE raw.devices
SET app_version = NULL
WHERE device_id IN (
    SELECT device_id
    FROM raw.devices
    ORDER BY RANDOM()
    LIMIT 150
);

-- =========================================
-- 4. BROKEN CUSTOMER LINKS
-- intentionally reference non-existing customer_id
-- =========================================
UPDATE raw.devices
SET customer_id = 999999 + device_id
WHERE device_id IN (
    SELECT device_id
    FROM raw.devices
    ORDER BY RANDOM()
    LIMIT 90
);

-- =========================================
-- 5. IMPOSSIBLE TIMING
-- last_seen_at before first_seen_at
-- =========================================
UPDATE raw.devices
SET last_seen_at = first_seen_at - INTERVAL '5 days'
WHERE device_id IN (
    SELECT device_id
    FROM raw.devices
    ORDER BY RANDOM()
    LIMIT 70
);

-- =========================================
-- 6. BAD COUNTRY CODE FORMATS
-- =========================================
UPDATE raw.devices
SET country_code = 'au'
WHERE device_id IN (
    SELECT device_id
    FROM raw.devices
    WHERE country_code = 'AU'
    ORDER BY RANDOM()
    LIMIT 90
);

UPDATE raw.devices
SET ip_country_code = 'sg '
WHERE device_id IN (
    SELECT device_id
    FROM raw.devices
    WHERE ip_country_code = 'SG'
    ORDER BY RANDOM()
    LIMIT 70
);
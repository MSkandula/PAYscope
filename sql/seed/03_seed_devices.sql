-- =========================================
-- PayScope Project
-- File: 03_seed_devices.sql
-- =========================================

INSERT INTO raw.devices (
    device_ref,
    customer_id,
    device_type,
    os_name,
    app_version,
    is_emulator,
    first_seen_at,
    last_seen_at,
    country_code,
    ip_country_code
)
SELECT
    'DEV_' || gs AS device_ref,

    -- link to customers
    (RANDOM() * 9999 + 1)::INT AS customer_id,

    -- device types
    (ARRAY['mobile','desktop','tablet'])[FLOOR(RANDOM()*3 + 1)] AS device_type,

    -- OS distribution
    (ARRAY['iOS','Android','Windows','MacOS'])[FLOOR(RANDOM()*4 + 1)] AS os_name,

    -- app version
    'v' || (1 + FLOOR(RANDOM()*5)) || '.' || FLOOR(RANDOM()*10) AS app_version,

    -- small % emulators (fraud signal)
    CASE 
        WHEN RANDOM() < 0.05 THEN TRUE
        ELSE FALSE
    END AS is_emulator,

    -- first seen in last 2 years
    NOW() - (RANDOM()*730)::INT * INTERVAL '1 day' AS first_seen_at,

    -- last seen after first_seen
    NOW() - (RANDOM()*30)::INT * INTERVAL '1 day' AS last_seen_at,

    -- device country
    (ARRAY['AU','US','GB','IN','SG'])[FLOOR(RANDOM()*5 + 1)] AS country_code,

    -- IP country (can differ → important for risk later)
    (ARRAY['AU','US','GB','IN','SG'])[FLOOR(RANDOM()*5 + 1)] AS ip_country_code

FROM generate_series(1, 15000) AS gs;
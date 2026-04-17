-- =========================================
-- PayScope Project
-- File: 01_seed_customers.sql
-- Purpose: Generate synthetic customers data
-- =========================================

INSERT INTO raw.customers (
    customer_ref,
    full_name,
    email,
    phone,
    country_code,
    signup_date,
    status,
    date_of_birth,
    created_at,
    updated_at
)
SELECT
    'CUST_' || gs AS customer_ref,

    -- simple name generation
    'Customer_' || gs AS full_name,

    -- emails (we will break some later)
    'customer' || gs || '@example.com' AS email,

    -- simple phone pattern
    '04' || LPAD((RANDOM()*99999999)::INT::TEXT, 8, '0') AS phone,

    -- country distribution (realistic mix)
    (ARRAY['AU','US','GB','IN','SG'])[FLOOR(RANDOM()*5 + 1)] AS country_code,

    -- signup dates in past 2 years
    CURRENT_DATE - (RANDOM()*730)::INT AS signup_date,

    -- status distribution
    (ARRAY['active','inactive','suspended'])[FLOOR(RANDOM()*3 + 1)] AS status,

    -- age between ~18–70
    CURRENT_DATE - ((18 + RANDOM()*52)::INT * 365) AS date_of_birth,

    -- timestamps
    NOW() - (RANDOM()*365)::INT * INTERVAL '1 day' AS created_at,
    NOW() AS updated_at

FROM generate_series(1, 10000) AS gs;
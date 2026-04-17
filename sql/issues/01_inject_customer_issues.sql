-- =========================================
-- PayScope Project
-- File: 01_inject_customer_issues.sql
-- Purpose: Inject controlled data quality issues into raw.customers
-- =========================================

-- =========================================
-- 1. NULL EMAILS
-- =========================================
UPDATE raw.customers
SET email = NULL
WHERE customer_id IN (
    SELECT customer_id
    FROM raw.customers
    ORDER BY RANDOM()
    LIMIT 250
);

-- =========================================
-- 2. DUPLICATE EMAILS
-- Copy email from one customer to another
-- =========================================
UPDATE raw.customers c
SET email = src.email
FROM (
    SELECT customer_id, email
    FROM raw.customers
    WHERE email IS NOT NULL
    ORDER BY RANDOM()
    LIMIT 150
) src
WHERE c.customer_id IN (
    SELECT customer_id
    FROM raw.customers
    WHERE customer_id NOT IN (
        SELECT customer_id
        FROM raw.customers
        ORDER BY RANDOM()
        LIMIT 150
    )
    ORDER BY RANDOM()
    LIMIT 150
);

-- =========================================
-- 3. INVALID EMAIL FORMAT
-- =========================================
UPDATE raw.customers
SET email = 'invalid_email_format'
WHERE customer_id IN (
    SELECT customer_id
    FROM raw.customers
    WHERE email IS NOT NULL
    ORDER BY RANDOM()
    LIMIT 120
);

-- =========================================
-- 4. INCONSISTENT COUNTRY CODES
-- =========================================
UPDATE raw.customers
SET country_code = 'au'
WHERE customer_id IN (
    SELECT customer_id
    FROM raw.customers
    WHERE country_code = 'AU'
    ORDER BY RANDOM()
    LIMIT 100
);

UPDATE raw.customers
SET country_code = 'usa'
WHERE customer_id IN (
    SELECT customer_id
    FROM raw.customers
    WHERE country_code = 'US'
    ORDER BY RANDOM()
    LIMIT 80
);

-- =========================================
-- 5. FUTURE SIGNUP DATES
-- =========================================
UPDATE raw.customers
SET signup_date = CURRENT_DATE + ((RANDOM()*120)::INT + 1)
WHERE customer_id IN (
    SELECT customer_id
    FROM raw.customers
    ORDER BY RANDOM()
    LIMIT 60
);

-- =========================================
-- 6. INCONSISTENT STATUS LABELS
-- =========================================
UPDATE raw.customers
SET status = 'Active'
WHERE customer_id IN (
    SELECT customer_id
    FROM raw.customers
    WHERE status = 'active'
    ORDER BY RANDOM()
    LIMIT 90
);

UPDATE raw.customers
SET status = 'SUSPENDED'
WHERE customer_id IN (
    SELECT customer_id
    FROM raw.customers
    WHERE status = 'suspended'
    ORDER BY RANDOM()
    LIMIT 70
);
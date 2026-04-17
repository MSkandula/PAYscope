-- =========================================
-- PayScope Project
-- File: 02_inject_merchant_issues.sql
-- Purpose: Inject controlled data quality issues into raw.merchants
-- =========================================

-- =========================================
-- 1. DUPLICATE MERCHANT NAMES
-- =========================================
UPDATE raw.merchants m
SET merchant_name = src.merchant_name
FROM (
    SELECT merchant_id, merchant_name
    FROM raw.merchants
    ORDER BY RANDOM()
    LIMIT 80
) src
WHERE m.merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    WHERE merchant_id NOT IN (
        SELECT merchant_id
        FROM raw.merchants
        ORDER BY RANDOM()
        LIMIT 80
    )
    ORDER BY RANDOM()
    LIMIT 80
);

-- =========================================
-- 2. INVALID / NON-STANDARD CURRENCY CODES
-- =========================================
UPDATE raw.merchants
SET settlement_currency = 'AUDD'
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    WHERE settlement_currency = 'AUD'
    ORDER BY RANDOM()
    LIMIT 35
);

UPDATE raw.merchants
SET settlement_currency = 'usd'
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    WHERE settlement_currency = 'USD'
    ORDER BY RANDOM()
    LIMIT 30
);

UPDATE raw.merchants
SET settlement_currency = 'XXX'
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    ORDER BY RANDOM()
    LIMIT 20
);

-- =========================================
-- 3. INCONSISTENT MERCHANT CATEGORY LABELS
-- =========================================
UPDATE raw.merchants
SET merchant_category = 'Ecommerce'
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    WHERE merchant_category = 'ecommerce'
    ORDER BY RANDOM()
    LIMIT 45
);

UPDATE raw.merchants
SET merchant_category = 'FOOD_DELIVERY'
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    WHERE merchant_category = 'food_delivery'
    ORDER BY RANDOM()
    LIMIT 35
);

UPDATE raw.merchants
SET merchant_category = 'travel '
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    WHERE merchant_category = 'travel'
    ORDER BY RANDOM()
    LIMIT 25
);

-- =========================================
-- 4. FUTURE ONBOARDING DATES
-- =========================================
UPDATE raw.merchants
SET onboarding_date = CURRENT_DATE + ((RANDOM()*180)::INT + 1)
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    ORDER BY RANDOM()
    LIMIT 40
);

-- =========================================
-- 5. INCONSISTENT RISK TIER LABELS
-- =========================================
UPDATE raw.merchants
SET risk_tier_source = 'High'
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    WHERE risk_tier_source = 'high'
    ORDER BY RANDOM()
    LIMIT 30
);

UPDATE raw.merchants
SET risk_tier_source = 'MEDIUM'
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    WHERE risk_tier_source = 'medium'
    ORDER BY RANDOM()
    LIMIT 25
);

-- =========================================
-- 6. NULL LEGAL NAMES
-- =========================================
UPDATE raw.merchants
SET legal_name = NULL
WHERE merchant_id IN (
    SELECT merchant_id
    FROM raw.merchants
    ORDER BY RANDOM()
    LIMIT 50
);
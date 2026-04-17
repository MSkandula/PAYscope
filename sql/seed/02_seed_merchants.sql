-- =========================================
-- PayScope Project
-- File: 02_seed_merchants.sql
-- =========================================

INSERT INTO raw.merchants (
    merchant_ref,
    merchant_name,
    legal_name,
    merchant_category,
    country_code,
    settlement_currency,
    onboarding_date,
    risk_tier_source,
    is_active,
    created_at,
    updated_at
)
SELECT
    'MERCH_' || gs AS merchant_ref,

    'Merchant_' || gs AS merchant_name,

    'Merchant_' || gs || '_PTY_LTD' AS legal_name,

    -- industry categories
    (ARRAY[
        'ecommerce',
        'food_delivery',
        'electronics',
        'gaming',
        'travel',
        'subscription'
    ])[FLOOR(RANDOM()*6 + 1)] AS merchant_category,

    -- country
    (ARRAY['AU','US','GB','IN','SG'])[FLOOR(RANDOM()*5 + 1)] AS country_code,

    -- currency based loosely on region
    (ARRAY['AUD','USD','GBP','INR','SGD'])[FLOOR(RANDOM()*5 + 1)] AS settlement_currency,

    -- onboarding in last 3 years
    CURRENT_DATE - (RANDOM()*1000)::INT AS onboarding_date,

    -- initial risk label (not final, just source system)
    (ARRAY['low','medium','high'])[FLOOR(RANDOM()*3 + 1)] AS risk_tier_source,

    -- most merchants active
    CASE 
        WHEN RANDOM() < 0.9 THEN TRUE
        ELSE FALSE
    END AS is_active,

    NOW() - (RANDOM()*365)::INT * INTERVAL '1 day' AS created_at,
    NOW() AS updated_at

FROM generate_series(1, 1200) AS gs;
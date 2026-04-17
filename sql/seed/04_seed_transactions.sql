-- =========================================
-- PayScope Project
-- File: 04_seed_transactions.sql
-- =========================================

INSERT INTO raw.transactions (
    transaction_ref,
    customer_id,
    merchant_id,
    device_id,
    transaction_ts,
    amount,
    currency_code,
    status,
    payment_method,
    response_code,
    is_cross_border,
    merchant_country_code,
    customer_country_code,
    device_country_code
)
SELECT
    'TXN_' || gs AS transaction_ref,

    -- links
    (RANDOM()*9999 + 1)::INT AS customer_id,
    (RANDOM()*1199 + 1)::INT AS merchant_id,
    (RANDOM()*14999 + 1)::INT AS device_id,

    -- timestamp (last 1 year)
    NOW() - (RANDOM()*365)::INT * INTERVAL '1 day' AS transaction_ts,

    -- amount distribution (realistic skew)
    ROUND(
    (
        CASE 
            WHEN RANDOM() < 0.7 THEN RANDOM()*100
            WHEN RANDOM() < 0.9 THEN RANDOM()*500
            ELSE RANDOM()*2000
        END
    )::numeric
, 2) AS amount,

    -- currency
    (ARRAY['AUD','USD','GBP','INR','SGD'])[FLOOR(RANDOM()*5 + 1)] AS currency_code,

    -- status distribution
    CASE 
        WHEN RANDOM() < 0.75 THEN 'approved'
        WHEN RANDOM() < 0.90 THEN 'failed'
        WHEN RANDOM() < 0.97 THEN 'pending'
        ELSE 'reversed'
    END AS status,

    -- payment method
    (ARRAY['card','wallet','bank_transfer'])[FLOOR(RANDOM()*3 + 1)] AS payment_method,

    -- response codes
    CASE 
        WHEN RANDOM() < 0.75 THEN '00'     -- success
        WHEN RANDOM() < 0.85 THEN '05'     -- decline
        ELSE '91'                          -- issuer unavailable
    END AS response_code,

    -- cross-border logic
    CASE 
        WHEN RANDOM() < 0.3 THEN TRUE
        ELSE FALSE
    END AS is_cross_border,

    -- merchant country
    (ARRAY['AU','US','GB','IN','SG'])[FLOOR(RANDOM()*5 + 1)],

    -- customer country
    (ARRAY['AU','US','GB','IN','SG'])[FLOOR(RANDOM()*5 + 1)],

    -- device country
    (ARRAY['AU','US','GB','IN','SG'])[FLOOR(RANDOM()*5 + 1)]

FROM generate_series(1, 100000) AS gs;
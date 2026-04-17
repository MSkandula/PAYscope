-- =========================================
-- PayScope Project
-- File: 05_seed_chargebacks.sql
-- Purpose: Generate synthetic chargebacks
-- =========================================

INSERT INTO raw.chargebacks (
    chargeback_ref,
    transaction_id,
    customer_id,
    merchant_id,
    chargeback_date,
    chargeback_amount,
    chargeback_reason,
    dispute_status,
    resolution_date
)
SELECT
    'CB_' || t.transaction_id AS chargeback_ref,
    t.transaction_id,
    t.customer_id,
    t.merchant_id,

    -- chargeback happens after transaction date
    (t.transaction_ts::date + ((RANDOM()*60)::INT + 1)) AS chargeback_date,

    -- usually full amount disputed
    t.amount AS chargeback_amount,

    (ARRAY[
        'fraud',
        'service_not_received',
        'duplicate_processing',
        'authorization_issue'
    ])[FLOOR(RANDOM()*4 + 1)] AS chargeback_reason,

    (ARRAY[
        'open',
        'won',
        'lost',
        'closed'
    ])[FLOOR(RANDOM()*4 + 1)] AS dispute_status,

    -- some have resolution dates, some remain unresolved
    CASE
        WHEN RANDOM() < 0.75
            THEN (t.transaction_ts::date + ((RANDOM()*90)::INT + 5))
        ELSE NULL
    END AS resolution_date

FROM raw.transactions t
WHERE t.status = 'approved'
  AND RANDOM() < 0.025;
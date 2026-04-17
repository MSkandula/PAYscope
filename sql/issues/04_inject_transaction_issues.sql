-- =========================================
-- PayScope Project
-- File: 04_inject_transaction_issues.sql
-- Purpose: Inject controlled data quality issues into raw.transactions
-- =========================================

-- =========================================
-- 1. DUPLICATE TRANSACTION REFERENCES
-- =========================================
UPDATE raw.transactions t
SET transaction_ref = src.transaction_ref
FROM (
    SELECT transaction_id, transaction_ref
    FROM raw.transactions
    ORDER BY RANDOM()
    LIMIT 300
) src
WHERE t.transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    WHERE transaction_id NOT IN (
        SELECT transaction_id
        FROM raw.transactions
        ORDER BY RANDOM()
        LIMIT 300
    )
    ORDER BY RANDOM()
    LIMIT 300
);

-- =========================================
-- 2. NEGATIVE AMOUNTS
-- =========================================
UPDATE raw.transactions
SET amount = -1 * amount
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    ORDER BY RANDOM()
    LIMIT 220
);

-- =========================================
-- 3. ZERO AMOUNTS
-- =========================================
UPDATE raw.transactions
SET amount = 0
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    WHERE amount > 0
    ORDER BY RANDOM()
    LIMIT 120
);

-- =========================================
-- 4. FUTURE TRANSACTION TIMESTAMPS
-- =========================================
UPDATE raw.transactions
SET transaction_ts = NOW() + ((RANDOM()*45)::INT + 1) * INTERVAL '1 day'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    ORDER BY RANDOM()
    LIMIT 180
);

-- =========================================
-- 5. INVALID / INCONSISTENT STATUS LABELS
-- =========================================
UPDATE raw.transactions
SET status = 'Approved'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    WHERE status = 'approved'
    ORDER BY RANDOM()
    LIMIT 200
);

UPDATE raw.transactions
SET status = 'FAIL'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    WHERE status = 'failed'
    ORDER BY RANDOM()
    LIMIT 150
);

UPDATE raw.transactions
SET status = 'pending '
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    WHERE status = 'pending'
    ORDER BY RANDOM()
    LIMIT 100
);

-- =========================================
-- 6. INVALID CURRENCY CODES
-- =========================================
UPDATE raw.transactions
SET currency_code = 'aud'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    WHERE currency_code = 'AUD'
    ORDER BY RANDOM()
    LIMIT 140
);

UPDATE raw.transactions
SET currency_code = 'USDX'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    WHERE currency_code = 'USD'
    ORDER BY RANDOM()
    LIMIT 90
);

UPDATE raw.transactions
SET currency_code = 'XXX'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    ORDER BY RANDOM()
    LIMIT 60
);

-- =========================================
-- 7. INVALID PAYMENT METHOD LABELS
-- =========================================
UPDATE raw.transactions
SET payment_method = 'Card'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    WHERE payment_method = 'card'
    ORDER BY RANDOM()
    LIMIT 120
);

UPDATE raw.transactions
SET payment_method = 'wallet '
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    WHERE payment_method = 'wallet'
    ORDER BY RANDOM()
    LIMIT 90
);

-- =========================================
-- 8. BROKEN CUSTOMER LINKS
-- =========================================
UPDATE raw.transactions
SET customer_id = 900000 + transaction_id
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    ORDER BY RANDOM()
    LIMIT 100
);

-- =========================================
-- 9. BROKEN MERCHANT LINKS
-- =========================================
UPDATE raw.transactions
SET merchant_id = 800000 + transaction_id
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    ORDER BY RANDOM()
    LIMIT 70
);

-- =========================================
-- 10. BROKEN DEVICE LINKS
-- =========================================
UPDATE raw.transactions
SET device_id = 700000 + transaction_id
WHERE transaction_id IN (
    SELECT transaction_id
    FROM raw.transactions
    ORDER BY RANDOM()
    LIMIT 90
);
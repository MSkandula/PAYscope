-- =========================================
-- PayScope Project
-- File: 05_inject_chargeback_issues.sql
-- Purpose: Inject controlled data quality issues into raw.chargebacks
-- =========================================

-- =========================================
-- 1. BROKEN TRANSACTION LINKS
-- =========================================
UPDATE raw.chargebacks
SET transaction_id = 950000 + chargeback_id
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    ORDER BY RANDOM()
    LIMIT 45
);

-- =========================================
-- 2. BROKEN CUSTOMER LINKS
-- =========================================
UPDATE raw.chargebacks
SET customer_id = 960000 + chargeback_id
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    ORDER BY RANDOM()
    LIMIT 35
);

-- =========================================
-- 3. BROKEN MERCHANT LINKS
-- =========================================
UPDATE raw.chargebacks
SET merchant_id = 970000 + chargeback_id
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    ORDER BY RANDOM()
    LIMIT 30
);

-- =========================================
-- 4. NULL CHARGEBACK AMOUNTS
-- =========================================
UPDATE raw.chargebacks
SET chargeback_amount = NULL
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    ORDER BY RANDOM()
    LIMIT 40
);

-- =========================================
-- 5. NEGATIVE CHARGEBACK AMOUNTS
-- =========================================
UPDATE raw.chargebacks
SET chargeback_amount = -1 * ABS(chargeback_amount)
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    WHERE chargeback_amount IS NOT NULL
    ORDER BY RANDOM()
    LIMIT 35
);

-- =========================================
-- 6. CHARGEBACK DATE BEFORE TRANSACTION DATE
-- =========================================
UPDATE raw.chargebacks
SET chargeback_date = chargeback_date - ((RANDOM()*90)::INT + 10)
WHERE chargeback_id IN (
    SELECT cb.chargeback_id
    FROM raw.chargebacks cb
    ORDER BY RANDOM()
    LIMIT 50
);

-- =========================================
-- 7. INCONSISTENT REASON LABELS
-- =========================================
UPDATE raw.chargebacks
SET chargeback_reason = 'Fraud'
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    WHERE chargeback_reason = 'fraud'
    ORDER BY RANDOM()
    LIMIT 35
);

UPDATE raw.chargebacks
SET chargeback_reason = 'duplicate_processing '
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    WHERE chargeback_reason = 'duplicate_processing'
    ORDER BY RANDOM()
    LIMIT 25
);

-- =========================================
-- 8. INCONSISTENT DISPUTE STATUS LABELS
-- =========================================
UPDATE raw.chargebacks
SET dispute_status = 'OPEN'
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    WHERE dispute_status = 'open'
    ORDER BY RANDOM()
    LIMIT 30
);

UPDATE raw.chargebacks
SET dispute_status = 'Won'
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    WHERE dispute_status = 'won'
    ORDER BY RANDOM()
    LIMIT 20
);

UPDATE raw.chargebacks
SET dispute_status = 'closed '
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    WHERE dispute_status = 'closed'
    ORDER BY RANDOM()
    LIMIT 20
);

-- =========================================
-- 9. RESOLUTION DATE BEFORE CHARGEBACK DATE
-- =========================================
UPDATE raw.chargebacks
SET resolution_date = chargeback_date - ((RANDOM()*20)::INT + 1)
WHERE chargeback_id IN (
    SELECT chargeback_id
    FROM raw.chargebacks
    WHERE resolution_date IS NOT NULL
    ORDER BY RANDOM()
    LIMIT 35
);
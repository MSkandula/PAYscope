-- =========================================
-- PayScope Project
-- File: 03_clean_tables.sql
-- Purpose: Create clean validated tables
-- =========================================

-- =========================================
-- 1. CLEAN CUSTOMERS
-- =========================================
CREATE TABLE IF NOT EXISTS clean.customers (
    customer_id         BIGINT PRIMARY KEY,
    customer_ref        TEXT,
    full_name           TEXT,
    email               TEXT,
    phone               TEXT,
    country_code        TEXT,
    signup_date         DATE,
    status              TEXT,
    date_of_birth       DATE,
    created_at          TIMESTAMP,
    updated_at          TIMESTAMP,
    is_valid_record     BOOLEAN,
    dq_issue_count      INTEGER,
    cleaned_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 2. CLEAN MERCHANTS
-- =========================================
CREATE TABLE IF NOT EXISTS clean.merchants (
    merchant_id             BIGINT PRIMARY KEY,
    merchant_ref            TEXT,
    merchant_name           TEXT,
    legal_name              TEXT,
    merchant_category       TEXT,
    country_code            TEXT,
    settlement_currency     TEXT,
    onboarding_date         DATE,
    risk_tier_source        TEXT,
    is_active               BOOLEAN,
    created_at              TIMESTAMP,
    updated_at              TIMESTAMP,
    is_valid_record         BOOLEAN,
    dq_issue_count          INTEGER,
    cleaned_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 3. CLEAN DEVICES
-- =========================================
CREATE TABLE IF NOT EXISTS clean.devices (
    device_id            BIGINT PRIMARY KEY,
    device_ref           TEXT,
    customer_id          BIGINT,
    device_type          TEXT,
    os_name              TEXT,
    app_version          TEXT,
    is_emulator          BOOLEAN,
    first_seen_at        TIMESTAMP,
    last_seen_at         TIMESTAMP,
    country_code         TEXT,
    ip_country_code      TEXT,
    is_valid_record      BOOLEAN,
    dq_issue_count       INTEGER,
    cleaned_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 4. CLEAN TRANSACTIONS
-- =========================================
CREATE TABLE IF NOT EXISTS clean.transactions (
    transaction_id           BIGINT PRIMARY KEY,
    transaction_ref          TEXT,
    customer_id              BIGINT,
    merchant_id              BIGINT,
    device_id                BIGINT,
    transaction_ts           TIMESTAMP,
    amount                   NUMERIC(12,2),
    currency_code            TEXT,
    status                   TEXT,
    payment_method           TEXT,
    response_code            TEXT,
    is_cross_border          BOOLEAN,
    merchant_country_code    TEXT,
    customer_country_code    TEXT,
    device_country_code      TEXT,
    is_valid_record          BOOLEAN,
    dq_issue_count           INTEGER,
    cleaned_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 5. CLEAN CHARGEBACKS
-- =========================================
CREATE TABLE IF NOT EXISTS clean.chargebacks (
    chargeback_id         BIGINT PRIMARY KEY,
    chargeback_ref        TEXT,
    transaction_id        BIGINT,
    customer_id           BIGINT,
    merchant_id           BIGINT,
    chargeback_date       DATE,
    chargeback_amount     NUMERIC(12,2),
    chargeback_reason     TEXT,
    dispute_status        TEXT,
    resolution_date       DATE,
    is_valid_record       BOOLEAN,
    dq_issue_count        INTEGER,
    cleaned_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 6. CLEAN ALERTS
-- =========================================
CREATE TABLE IF NOT EXISTS clean.alerts (
    alert_id              BIGINT PRIMARY KEY,
    alert_ref             TEXT,
    transaction_id        BIGINT,
    customer_id           BIGINT,
    merchant_id           BIGINT,
    device_id             BIGINT,
    alert_ts              TIMESTAMP,
    rule_name             TEXT,
    severity              TEXT,
    risk_score            NUMERIC(5,2),
    alert_status          TEXT,
    is_valid_record       BOOLEAN,
    dq_issue_count        INTEGER,
    cleaned_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- =========================================
-- PayScope Project
-- File: 02_raw_tables.sql
-- Purpose: Create raw operational tables
-- =========================================

-- =========================================
-- 1. RAW CUSTOMERS
-- =========================================
CREATE TABLE IF NOT EXISTS raw.customers (
    customer_id         BIGSERIAL PRIMARY KEY,
    customer_ref        TEXT,
    full_name           TEXT,
    email               TEXT,
    phone               TEXT,
    country_code        TEXT,
    signup_date         DATE,
    status              TEXT,
    date_of_birth       DATE,
    created_at          TIMESTAMP,
    updated_at          TIMESTAMP
);

-- =========================================
-- 2. RAW MERCHANTS
-- =========================================
CREATE TABLE IF NOT EXISTS raw.merchants (
    merchant_id             BIGSERIAL PRIMARY KEY,
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
    updated_at              TIMESTAMP
);

-- =========================================
-- 3. RAW DEVICES
-- =========================================
CREATE TABLE IF NOT EXISTS raw.devices (
    device_id            BIGSERIAL PRIMARY KEY,
    device_ref           TEXT,
    customer_id          BIGINT,
    device_type          TEXT,
    os_name              TEXT,
    app_version          TEXT,
    is_emulator          BOOLEAN,
    first_seen_at        TIMESTAMP,
    last_seen_at         TIMESTAMP,
    country_code         TEXT,
    ip_country_code      TEXT
);

-- =========================================
-- 4. RAW TRANSACTIONS
-- =========================================
CREATE TABLE IF NOT EXISTS raw.transactions (
    transaction_id           BIGSERIAL PRIMARY KEY,
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
    device_country_code      TEXT
);

-- =========================================
-- 5. RAW CHARGEBACKS
-- =========================================
CREATE TABLE IF NOT EXISTS raw.chargebacks (
    chargeback_id         BIGSERIAL PRIMARY KEY,
    chargeback_ref        TEXT,
    transaction_id        BIGINT,
    customer_id           BIGINT,
    merchant_id           BIGINT,
    chargeback_date       DATE,
    chargeback_amount     NUMERIC(12,2),
    chargeback_reason     TEXT,
    dispute_status        TEXT,
    resolution_date       DATE
);

-- =========================================
-- 6. RAW ALERTS
-- =========================================
CREATE TABLE IF NOT EXISTS raw.alerts (
    alert_id              BIGSERIAL PRIMARY KEY,
    alert_ref             TEXT,
    transaction_id        BIGINT,
    customer_id           BIGINT,
    merchant_id           BIGINT,
    device_id             BIGINT,
    alert_ts              TIMESTAMP,
    rule_name             TEXT,
    severity              TEXT,
    risk_score            NUMERIC(5,2),
    alert_status          TEXT
);

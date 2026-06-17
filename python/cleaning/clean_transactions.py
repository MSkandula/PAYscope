import os
import pandas as pd

INPUT_PATH = "python/outputs/extracted/raw_transactions.csv"
CUSTOMERS_PATH = "python/outputs/cleaned/clean_customers.csv"
MERCHANTS_PATH = "python/outputs/cleaned/clean_merchants.csv"
DEVICES_PATH = "python/outputs/cleaned/clean_devices.csv"

OUTPUT_DIR = "python/outputs/cleaned"
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "clean_transactions.csv")

os.makedirs(OUTPUT_DIR, exist_ok=True)

VALID_STATUSES = {"approved", "failed", "pending", "reversed"}
VALID_CURRENCIES = {"AUD", "USD", "GBP", "INR", "SGD"}
VALID_PAYMENT_METHODS = {"card", "wallet", "bank_transfer"}
VALID_COUNTRIES = {"AU", "US", "GB", "IN", "SG"}


def clean_transactions():
    df = pd.read_csv(INPUT_PATH)
    customers = pd.read_csv(CUSTOMERS_PATH)
    merchants = pd.read_csv(MERCHANTS_PATH)
    devices = pd.read_csv(DEVICES_PATH)

    df["dq_issue_count"] = 0

    valid_customer_ids = set(customers.loc[customers["is_valid_record"] == True, "customer_id"])
    valid_merchant_ids = set(merchants.loc[merchants["is_valid_record"] == True, "merchant_id"])
    valid_device_ids = set(devices.loc[devices["is_valid_record"] == True, "device_id"])

    # Standardize text fields
    df["transaction_ref"] = df["transaction_ref"].astype("string").str.strip()
    df["currency_code"] = df["currency_code"].astype("string").str.strip().str.upper()
    df["status"] = df["status"].astype("string").str.strip().str.lower()
    df["payment_method"] = df["payment_method"].astype("string").str.strip().str.lower()

    df["merchant_country_code"] = df["merchant_country_code"].astype("string").str.strip().str.upper()
    df["customer_country_code"] = df["customer_country_code"].astype("string").str.strip().str.upper()
    df["device_country_code"] = df["device_country_code"].astype("string").str.strip().str.upper()

    # Known status mapping
    df["status"] = df["status"].replace({
        "fail": "failed"
    })

    # Dates
    df["transaction_ts"] = pd.to_datetime(df["transaction_ts"], errors="coerce")

    # Numeric
    df["amount"] = pd.to_numeric(df["amount"], errors="coerce")

    # Issue checks
    duplicate_transaction_ref = df["transaction_ref"].notna() & df["transaction_ref"].duplicated(keep=False)

    missing_amount = df["amount"].isna()
    invalid_amount = df["amount"].notna() & (df["amount"] <= 0)

    future_transaction = df["transaction_ts"] > pd.Timestamp.now()
    missing_transaction_ts = df["transaction_ts"].isna()

    invalid_status = ~df["status"].isin(VALID_STATUSES)
    invalid_currency = ~df["currency_code"].isin(VALID_CURRENCIES)
    invalid_payment_method = ~df["payment_method"].isin(VALID_PAYMENT_METHODS)

    invalid_merchant_country = ~df["merchant_country_code"].isin(VALID_COUNTRIES)
    invalid_customer_country = ~df["customer_country_code"].isin(VALID_COUNTRIES)
    invalid_device_country = ~df["device_country_code"].isin(VALID_COUNTRIES)

    broken_customer_link = ~df["customer_id"].isin(valid_customer_ids)
    broken_merchant_link = ~df["merchant_id"].isin(valid_merchant_ids)
    broken_device_link = ~df["device_id"].isin(valid_device_ids)

    issue_masks = [
        duplicate_transaction_ref,
        missing_amount,
        invalid_amount,
        future_transaction,
        missing_transaction_ts,
        invalid_status,
        invalid_currency,
        invalid_payment_method,
        invalid_merchant_country,
        invalid_customer_country,
        invalid_device_country,
        broken_customer_link,
        broken_merchant_link,
        broken_device_link
    ]

    for mask in issue_masks:
        df.loc[mask, "dq_issue_count"] += 1

    df["is_valid_record"] = df["dq_issue_count"] == 0
    df["cleaned_at"] = pd.Timestamp.now()

    df.to_csv(OUTPUT_PATH, index=False)

    print(f"Cleaned transactions saved to: {OUTPUT_PATH}")
    print(f"Rows: {len(df)}")
    print(f"Valid rows: {df['is_valid_record'].sum()}")
    print(f"Invalid rows: {(~df['is_valid_record']).sum()}")


if __name__ == "__main__":
    clean_transactions()
import os
import pandas as pd

INPUT_PATH = "python/outputs/extracted/raw_chargebacks.csv"
TRANSACTIONS_PATH = "python/outputs/cleaned/clean_transactions.csv"
CUSTOMERS_PATH = "python/outputs/cleaned/clean_customers.csv"
MERCHANTS_PATH = "python/outputs/cleaned/clean_merchants.csv"

OUTPUT_DIR = "python/outputs/cleaned"
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "clean_chargebacks.csv")

os.makedirs(OUTPUT_DIR, exist_ok=True)

VALID_REASONS = {
    "fraud",
    "service_not_received",
    "duplicate_processing",
    "authorization_issue"
}

VALID_DISPUTE_STATUSES = {
    "open",
    "won",
    "lost",
    "closed"
}


def clean_chargebacks():
    df = pd.read_csv(INPUT_PATH)
    transactions = pd.read_csv(TRANSACTIONS_PATH)
    customers = pd.read_csv(CUSTOMERS_PATH)
    merchants = pd.read_csv(MERCHANTS_PATH)

    df["dq_issue_count"] = 0

    valid_transaction_ids = set(transactions.loc[transactions["is_valid_record"] == True, "transaction_id"])
    valid_customer_ids = set(customers.loc[customers["is_valid_record"] == True, "customer_id"])
    valid_merchant_ids = set(merchants.loc[merchants["is_valid_record"] == True, "merchant_id"])

    # Standardize text fields
    df["chargeback_ref"] = df["chargeback_ref"].astype("string").str.strip()
    df["chargeback_reason"] = df["chargeback_reason"].astype("string").str.strip().str.lower()
    df["dispute_status"] = df["dispute_status"].astype("string").str.strip().str.lower()

    # Dates and numeric fields
    df["chargeback_date"] = pd.to_datetime(df["chargeback_date"], errors="coerce")
    df["resolution_date"] = pd.to_datetime(df["resolution_date"], errors="coerce")
    df["chargeback_amount"] = pd.to_numeric(df["chargeback_amount"], errors="coerce")

    # Issue checks
    missing_amount = df["chargeback_amount"].isna()
    invalid_amount = df["chargeback_amount"].notna() & (df["chargeback_amount"] <= 0)

    missing_chargeback_date = df["chargeback_date"].isna()
    invalid_resolution_timing = (
        df["resolution_date"].notna()
        & df["chargeback_date"].notna()
        & (df["resolution_date"] < df["chargeback_date"])
    )

    invalid_reason = ~df["chargeback_reason"].isin(VALID_REASONS)
    invalid_dispute_status = ~df["dispute_status"].isin(VALID_DISPUTE_STATUSES)

    broken_transaction_link = ~df["transaction_id"].isin(valid_transaction_ids)
    broken_customer_link = ~df["customer_id"].isin(valid_customer_ids)
    broken_merchant_link = ~df["merchant_id"].isin(valid_merchant_ids)

    issue_masks = [
        missing_amount,
        invalid_amount,
        missing_chargeback_date,
        invalid_resolution_timing,
        invalid_reason,
        invalid_dispute_status,
        broken_transaction_link,
        broken_customer_link,
        broken_merchant_link
    ]

    for mask in issue_masks:
        df.loc[mask, "dq_issue_count"] += 1

    df["is_valid_record"] = df["dq_issue_count"] == 0
    df["cleaned_at"] = pd.Timestamp.now()

    df.to_csv(OUTPUT_PATH, index=False)

    print(f"Cleaned chargebacks saved to: {OUTPUT_PATH}")
    print(f"Rows: {len(df)}")
    print(f"Valid rows: {df['is_valid_record'].sum()}")
    print(f"Invalid rows: {(~df['is_valid_record']).sum()}")


if __name__ == "__main__":
    clean_chargebacks()
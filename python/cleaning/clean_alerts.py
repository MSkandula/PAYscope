import os
import pandas as pd

INPUT_PATH = "python/outputs/extracted/raw_alerts.csv"
TRANSACTIONS_PATH = "python/outputs/cleaned/clean_transactions.csv"
CUSTOMERS_PATH = "python/outputs/cleaned/clean_customers.csv"
MERCHANTS_PATH = "python/outputs/cleaned/clean_merchants.csv"
DEVICES_PATH = "python/outputs/cleaned/clean_devices.csv"

OUTPUT_DIR = "python/outputs/cleaned"
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "clean_alerts.csv")

os.makedirs(OUTPUT_DIR, exist_ok=True)

VALID_RULES = {
    "repeated_failed_payments",
    "shared_device_many_customers",
    "high_chargeback_customer",
    "merchant_chargeback_spike",
    "emulator_device_usage",
    "cross_border_high_risk_merchant"
}

VALID_SEVERITIES = {"low", "medium", "high", "critical"}

VALID_ALERT_STATUSES = {
    "open",
    "under_review",
    "resolved",
    "false_positive"
}


def clean_alerts():
    df = pd.read_csv(INPUT_PATH)
    transactions = pd.read_csv(TRANSACTIONS_PATH)
    customers = pd.read_csv(CUSTOMERS_PATH)
    merchants = pd.read_csv(MERCHANTS_PATH)
    devices = pd.read_csv(DEVICES_PATH)

    df["dq_issue_count"] = 0

    valid_transaction_ids = set(transactions.loc[transactions["is_valid_record"] == True, "transaction_id"])
    valid_customer_ids = set(customers.loc[customers["is_valid_record"] == True, "customer_id"])
    valid_merchant_ids = set(merchants.loc[merchants["is_valid_record"] == True, "merchant_id"])
    valid_device_ids = set(devices.loc[devices["is_valid_record"] == True, "device_id"])

    # Standardize text fields
    df["alert_ref"] = df["alert_ref"].astype("string").str.strip()
    df["rule_name"] = df["rule_name"].astype("string").str.strip().str.lower()
    df["severity"] = df["severity"].astype("string").str.strip().str.lower()
    df["alert_status"] = df["alert_status"].astype("string").str.strip().str.lower()

    # Known mappings
    df["severity"] = df["severity"].replace({
        "med": "medium"
    })

    # Dates and numeric fields
    df["alert_ts"] = pd.to_datetime(df["alert_ts"], errors="coerce")
    df["risk_score"] = pd.to_numeric(df["risk_score"], errors="coerce")

    # Issue checks
    missing_alert_ts = df["alert_ts"].isna()
    future_alert_ts = df["alert_ts"] > pd.Timestamp.now()

    missing_risk_score = df["risk_score"].isna()
    invalid_risk_score = df["risk_score"].notna() & (
        (df["risk_score"] < 0) | (df["risk_score"] > 100)
    )

    invalid_rule_name = ~df["rule_name"].isin(VALID_RULES)
    invalid_severity = ~df["severity"].isin(VALID_SEVERITIES)
    invalid_alert_status = ~df["alert_status"].isin(VALID_ALERT_STATUSES)

    broken_transaction_link = ~df["transaction_id"].isin(valid_transaction_ids)
    broken_customer_link = ~df["customer_id"].isin(valid_customer_ids)
    broken_merchant_link = ~df["merchant_id"].isin(valid_merchant_ids)
    broken_device_link = ~df["device_id"].isin(valid_device_ids)

    issue_masks = [
        missing_alert_ts,
        future_alert_ts,
        missing_risk_score,
        invalid_risk_score,
        invalid_rule_name,
        invalid_severity,
        invalid_alert_status,
        broken_transaction_link,
        broken_customer_link,
        broken_merchant_link,
        broken_device_link
    ]

    for mask in issue_masks:
        df.loc[mask, "dq_issue_count"] += 1

    df["is_valid_record"] = df["dq_issue_count"] == 0
    df["cleaned_at"] = pd.Timestamp.now()

    df.to_csv(OUTPUT_PATH, index=False)

    print(f"Cleaned alerts saved to: {OUTPUT_PATH}")
    print(f"Rows: {len(df)}")
    print(f"Valid rows: {df['is_valid_record'].sum()}")
    print(f"Invalid rows: {(~df['is_valid_record']).sum()}")


if __name__ == "__main__":
    clean_alerts()
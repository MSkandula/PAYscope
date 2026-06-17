import os
import pandas as pd

INPUT_DIR = "python/outputs/extracted"
OUTPUT_DIR = "python/outputs/dq_reports"
os.makedirs(OUTPUT_DIR, exist_ok=True)


def load_csv(file_name):
    return pd.read_csv(os.path.join(INPUT_DIR, file_name))


def add_result(results, table_name, check_name, result):
    results.append({
        "table_name": table_name,
        "check_name": check_name,
        "result": int(result)
    })


def check_customers(results):
    df = load_csv("raw_customers.csv")
    table = "raw.customers"

    add_result(results, table, "row_count", len(df))
    add_result(results, table, "null_email_count", df["email"].isna().sum())
    add_result(results, table, "duplicate_email_count", df["email"].dropna().duplicated().sum())
    add_result(
        results,
        table,
        "future_signup_date_count",
        (pd.to_datetime(df["signup_date"]) > pd.Timestamp.today().normalize()).sum()
    )


def check_merchants(results):
    df = load_csv("raw_merchants.csv")
    table = "raw.merchants"
    valid_currencies = {"AUD", "USD", "GBP", "INR", "SGD"}

    add_result(results, table, "row_count", len(df))
    add_result(results, table, "null_legal_name_count", df["legal_name"].isna().sum())
    add_result(results, table, "duplicate_merchant_name_count", df["merchant_name"].duplicated().sum())
    add_result(results, table, "invalid_currency_code_count", (~df["settlement_currency"].isin(valid_currencies)).sum())
    add_result(
        results,
        table,
        "future_onboarding_date_count",
        (pd.to_datetime(df["onboarding_date"]) > pd.Timestamp.today().normalize()).sum()
    )


def check_devices(results):
    df = load_csv("raw_devices.csv")
    customers = load_csv("raw_customers.csv")
    table = "raw.devices"

    add_result(results, table, "row_count", len(df))
    add_result(results, table, "null_device_type_count", df["device_type"].isna().sum())
    add_result(results, table, "null_app_version_count", df["app_version"].isna().sum())
    add_result(results, table, "broken_customer_link_count", (~df["customer_id"].isin(set(customers["customer_id"]))).sum())
    add_result(
        results,
        table,
        "invalid_device_timing_count",
        (pd.to_datetime(df["last_seen_at"]) < pd.to_datetime(df["first_seen_at"])).sum()
    )


def check_transactions(results):
    df = load_csv("raw_transactions.csv")
    customers = load_csv("raw_customers.csv")
    merchants = load_csv("raw_merchants.csv")
    devices = load_csv("raw_devices.csv")

    table = "raw.transactions"
    valid_currencies = {"AUD", "USD", "GBP", "INR", "SGD"}

    add_result(results, table, "row_count", len(df))
    add_result(results, table, "duplicate_transaction_ref_count", df["transaction_ref"].duplicated().sum())
    add_result(results, table, "negative_amount_count", (df["amount"] < 0).sum())
    add_result(results, table, "zero_amount_count", (df["amount"] == 0).sum())
    add_result(results, table, "future_transaction_count", (pd.to_datetime(df["transaction_ts"]) > pd.Timestamp.now()).sum())
    add_result(results, table, "invalid_currency_code_count", (~df["currency_code"].isin(valid_currencies)).sum())
    add_result(results, table, "broken_customer_link_count", (~df["customer_id"].isin(set(customers["customer_id"]))).sum())
    add_result(results, table, "broken_merchant_link_count", (~df["merchant_id"].isin(set(merchants["merchant_id"]))).sum())
    add_result(results, table, "broken_device_link_count", (~df["device_id"].isin(set(devices["device_id"]))).sum())


def check_chargebacks(results):
    df = load_csv("raw_chargebacks.csv")
    transactions = load_csv("raw_transactions.csv")
    customers = load_csv("raw_customers.csv")
    merchants = load_csv("raw_merchants.csv")

    table = "raw.chargebacks"

    add_result(results, table, "row_count", len(df))
    add_result(results, table, "null_chargeback_amount_count", df["chargeback_amount"].isna().sum())
    add_result(results, table, "negative_chargeback_amount_count", (df["chargeback_amount"] < 0).sum())
    add_result(results, table, "broken_transaction_link_count", (~df["transaction_id"].isin(set(transactions["transaction_id"]))).sum())
    add_result(results, table, "broken_customer_link_count", (~df["customer_id"].isin(set(customers["customer_id"]))).sum())
    add_result(results, table, "broken_merchant_link_count", (~df["merchant_id"].isin(set(merchants["merchant_id"]))).sum())

    chargeback_date = pd.to_datetime(df["chargeback_date"], errors="coerce")
    resolution_date = pd.to_datetime(df["resolution_date"], errors="coerce")

    add_result(
        results,
        table,
        "invalid_resolution_timing_count",
        ((resolution_date.notna()) & (resolution_date < chargeback_date)).sum()
    )


def check_alerts(results):
    df = load_csv("raw_alerts.csv")
    transactions = load_csv("raw_transactions.csv")
    customers = load_csv("raw_customers.csv")
    merchants = load_csv("raw_merchants.csv")
    devices = load_csv("raw_devices.csv")

    table = "raw.alerts"

    add_result(results, table, "row_count", len(df))
    add_result(results, table, "future_alert_count", (pd.to_datetime(df["alert_ts"]) > pd.Timestamp.now()).sum())
    add_result(results, table, "invalid_risk_score_count", ((df["risk_score"] < 0) | (df["risk_score"] > 100)).sum())
    add_result(results, table, "broken_transaction_link_count", (~df["transaction_id"].isin(set(transactions["transaction_id"]))).sum())
    add_result(results, table, "broken_customer_link_count", (~df["customer_id"].isin(set(customers["customer_id"]))).sum())
    add_result(results, table, "broken_merchant_link_count", (~df["merchant_id"].isin(set(merchants["merchant_id"]))).sum())
    add_result(results, table, "broken_device_link_count", (~df["device_id"].isin(set(devices["device_id"]))).sum())


def main():
    results = []

    check_customers(results)
    check_merchants(results)
    check_devices(results)
    check_transactions(results)
    check_chargebacks(results)
    check_alerts(results)

    dq_summary = pd.DataFrame(results)

    output_path = os.path.join(OUTPUT_DIR, "raw_dq_summary.csv")
    dq_summary.to_csv(output_path, index=False)

    print(dq_summary)
    print(f"\nSaved DQ report to: {output_path}")


if __name__ == "__main__":
    main()
import os
import pandas as pd

INPUT_PATH = "python/outputs/extracted/raw_devices.csv"
CUSTOMERS_PATH = "python/outputs/cleaned/clean_customers.csv"

OUTPUT_DIR = "python/outputs/cleaned"
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "clean_devices.csv")

os.makedirs(OUTPUT_DIR, exist_ok=True)

VALID_DEVICE_TYPES = {"mobile", "desktop", "tablet"}
VALID_OS_NAMES = {"ios", "android", "windows", "macos"}
VALID_COUNTRIES = {"AU", "US", "GB", "IN", "SG"}


def clean_devices():
    df = pd.read_csv(INPUT_PATH)
    customers = pd.read_csv(CUSTOMERS_PATH)

    df["dq_issue_count"] = 0

    valid_customer_ids = set(
        customers.loc[customers["is_valid_record"] == True, "customer_id"]
    )

    # Standardize text fields
    df["device_type"] = df["device_type"].astype("string").str.strip().str.lower()
    df["os_name"] = df["os_name"].astype("string").str.strip().str.lower()
    df["app_version"] = df["app_version"].astype("string").str.strip()
    df["country_code"] = df["country_code"].astype("string").str.strip().str.upper()
    df["ip_country_code"] = df["ip_country_code"].astype("string").str.strip().str.upper()

    # Standardize OS display values
    df["os_name"] = df["os_name"].replace({
        "ios": "ios",
        "android": "android",
        "windows": "windows",
        "macos": "macos"
    })

    # Dates
    df["first_seen_at"] = pd.to_datetime(df["first_seen_at"], errors="coerce")
    df["last_seen_at"] = pd.to_datetime(df["last_seen_at"], errors="coerce")

    # Issue checks
    null_device_type = df["device_type"].isna()
    invalid_device_type = df["device_type"].notna() & ~df["device_type"].isin(VALID_DEVICE_TYPES)

    null_app_version = df["app_version"].isna() | (df["app_version"] == "")
    invalid_os_name = ~df["os_name"].isin(VALID_OS_NAMES)

    invalid_country = ~df["country_code"].isin(VALID_COUNTRIES)
    invalid_ip_country = ~df["ip_country_code"].isin(VALID_COUNTRIES)

    broken_customer_link = ~df["customer_id"].isin(valid_customer_ids)

    invalid_timing = df["last_seen_at"] < df["first_seen_at"]

    issue_masks = [
        null_device_type,
        invalid_device_type,
        null_app_version,
        invalid_os_name,
        invalid_country,
        invalid_ip_country,
        broken_customer_link,
        invalid_timing
    ]

    for mask in issue_masks:
        df.loc[mask, "dq_issue_count"] += 1

    df["is_valid_record"] = df["dq_issue_count"] == 0
    df["cleaned_at"] = pd.Timestamp.now()

    df.to_csv(OUTPUT_PATH, index=False)

    print(f"Cleaned devices saved to: {OUTPUT_PATH}")
    print(f"Rows: {len(df)}")
    print(f"Valid rows: {df['is_valid_record'].sum()}")
    print(f"Invalid rows: {(~df['is_valid_record']).sum()}")


if __name__ == "__main__":
    clean_devices()
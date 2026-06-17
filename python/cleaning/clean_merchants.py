import os
import pandas as pd

INPUT_PATH = "python/outputs/extracted/raw_merchants.csv"
OUTPUT_DIR = "python/outputs/cleaned"
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "clean_merchants.csv")

os.makedirs(OUTPUT_DIR, exist_ok=True)

VALID_COUNTRIES = {"AU", "US", "GB", "IN", "SG"}
VALID_CURRENCIES = {"AUD", "USD", "GBP", "INR", "SGD"}
VALID_RISK_TIERS = {"low", "medium", "high"}

VALID_CATEGORIES = {
    "ecommerce",
    "food_delivery",
    "electronics",
    "gaming",
    "travel",
    "subscription"
}


def clean_merchants():
    df = pd.read_csv(INPUT_PATH)

    df["dq_issue_count"] = 0

    # Standardize text fields
    df["merchant_name"] = df["merchant_name"].astype("string").str.strip()
    df["legal_name"] = df["legal_name"].astype("string").str.strip()
    df["merchant_category"] = df["merchant_category"].astype("string").str.strip().str.lower()
    df["country_code"] = df["country_code"].astype("string").str.strip().str.upper()
    df["settlement_currency"] = df["settlement_currency"].astype("string").str.strip().str.upper()
    df["risk_tier_source"] = df["risk_tier_source"].astype("string").str.strip().str.lower()

    # Dates
    df["onboarding_date"] = pd.to_datetime(df["onboarding_date"], errors="coerce").dt.date
    df["created_at"] = pd.to_datetime(df["created_at"], errors="coerce")
    df["updated_at"] = pd.to_datetime(df["updated_at"], errors="coerce")

    today = pd.Timestamp.today().date()

    # Issue checks
    null_legal_name = df["legal_name"].isna() | (df["legal_name"] == "")
    duplicate_merchant_name = df["merchant_name"].notna() & df["merchant_name"].duplicated(keep=False)
    invalid_category = ~df["merchant_category"].isin(VALID_CATEGORIES)
    invalid_country = ~df["country_code"].isin(VALID_COUNTRIES)
    invalid_currency = ~df["settlement_currency"].isin(VALID_CURRENCIES)
    future_onboarding = df["onboarding_date"] > today
    invalid_risk_tier = ~df["risk_tier_source"].isin(VALID_RISK_TIERS)

    issue_masks = [
        null_legal_name,
        duplicate_merchant_name,
        invalid_category,
        invalid_country,
        invalid_currency,
        future_onboarding,
        invalid_risk_tier
    ]

    for mask in issue_masks:
        df.loc[mask, "dq_issue_count"] += 1

    df["is_valid_record"] = df["dq_issue_count"] == 0
    df["cleaned_at"] = pd.Timestamp.now()

    df.to_csv(OUTPUT_PATH, index=False)

    print(f"Cleaned merchants saved to: {OUTPUT_PATH}")
    print(f"Rows: {len(df)}")
    print(f"Valid rows: {df['is_valid_record'].sum()}")
    print(f"Invalid rows: {(~df['is_valid_record']).sum()}")


if __name__ == "__main__":
    clean_merchants()
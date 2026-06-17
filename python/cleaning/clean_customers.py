import os
import pandas as pd

INPUT_PATH = "python/outputs/extracted/raw_customers.csv"
OUTPUT_DIR = "python/outputs/cleaned"
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "clean_customers.csv")

os.makedirs(OUTPUT_DIR, exist_ok=True)


VALID_COUNTRIES = {"AU", "US", "GB", "IN", "SG"}
VALID_STATUSES = {"active", "inactive", "suspended"}


def clean_customers():
    df = pd.read_csv(INPUT_PATH)

    # Track issue count per row
    df["dq_issue_count"] = 0

    # Clean text fields
    df["email"] = df["email"].astype("string").str.strip().str.lower()
    df["country_code"] = df["country_code"].astype("string").str.strip().str.upper()
    df["status"] = df["status"].astype("string").str.strip().str.lower()

    # Fix known country mapping
    df["country_code"] = df["country_code"].replace({
        "USA": "US"
    })

    # Dates
    df["signup_date"] = pd.to_datetime(df["signup_date"], errors="coerce").dt.date
    df["date_of_birth"] = pd.to_datetime(df["date_of_birth"], errors="coerce").dt.date
    df["created_at"] = pd.to_datetime(df["created_at"], errors="coerce")
    df["updated_at"] = pd.to_datetime(df["updated_at"], errors="coerce")

    today = pd.Timestamp.today().date()

    # Issue checks
    missing_email = df["email"].isna()
    invalid_email = df["email"].notna() & ~df["email"].str.contains(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", regex=True)
    duplicate_email = df["email"].notna() & df["email"].duplicated(keep=False)
    invalid_country = ~df["country_code"].isin(VALID_COUNTRIES)
    future_signup = df["signup_date"] > today
    invalid_status = ~df["status"].isin(VALID_STATUSES)

    issue_masks = [
        missing_email,
        invalid_email,
        duplicate_email,
        invalid_country,
        future_signup,
        invalid_status
    ]

    for mask in issue_masks:
        df.loc[mask, "dq_issue_count"] += 1

    # Record is valid only if no serious issue remains
    df["is_valid_record"] = df["dq_issue_count"] == 0

    # Add audit timestamp
    df["cleaned_at"] = pd.Timestamp.now()

    df.to_csv(OUTPUT_PATH, index=False)

    print(f"Cleaned customers saved to: {OUTPUT_PATH}")
    print(f"Rows: {len(df)}")
    print(f"Valid rows: {df['is_valid_record'].sum()}")
    print(f"Invalid rows: {(~df['is_valid_record']).sum()}")


if __name__ == "__main__":
    clean_customers()
# =========================================
# PayScope Project
# File: extract_raw.py
# Purpose: Extract raw schema tables into CSV files
# =========================================

import os
import pandas as pd
from python.config.db import get_engine

# output folder
OUTPUT_DIR = "python/outputs/extracted"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# tables to extract
TABLES = [
    "customers",
    "merchants",
    "devices",
    "transactions",
    "chargebacks",
    "alerts"
]

def extract_table(table_name: str, engine) -> None:
    query = f"SELECT * FROM raw.{table_name}"
    df = pd.read_sql(query, engine)

    output_path = os.path.join(OUTPUT_DIR, f"raw_{table_name}.csv")
    df.to_csv(output_path, index=False)

    print(f"Extracted raw.{table_name}: {len(df)} rows -> {output_path}")

def main():
    engine = get_engine()

    for table_name in TABLES:
        extract_table(table_name, engine)

    print("Raw extraction completed successfully.")

if __name__ == "__main__":
    main()
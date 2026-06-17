import os
import pandas as pd
from python.config.db import get_engine

INPUT_DIR = "python/outputs/cleaned"

TABLES = {
    "clean_customers.csv": "customers",
    "clean_merchants.csv": "merchants",
    "clean_devices.csv": "devices",
    "clean_transactions.csv": "transactions",
    "clean_chargebacks.csv": "chargebacks",
    "clean_alerts.csv": "alerts"
}


def load_table(csv_file, table_name, engine):
    path = os.path.join(INPUT_DIR, csv_file)

    df = pd.read_csv(path)

    df.to_sql(
        name=table_name,
        con=engine,
        schema="clean",
        if_exists="replace",
        index=False
    )

    print(f"Loaded {csv_file} -> clean.{table_name}: {len(df)} rows")


def main():
    engine = get_engine()

    for csv_file, table_name in TABLES.items():
        load_table(csv_file, table_name, engine)

    print("All cleaned tables loaded into PostgreSQL clean schema.")


if __name__ == "__main__":
    main()

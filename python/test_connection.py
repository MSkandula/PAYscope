# =========================================
# PayScope Project
# File: test_connection.py
# Purpose: Verify the .env credentials reach the right database
# Run:     python -m python.test_connection
# =========================================

import pandas as pd

from python.config.db import get_engine


def main():
    engine = get_engine()

    with engine.connect() as conn:
        info = pd.read_sql(
            "SELECT current_database() AS database, current_user AS db_user, version() AS server",
            conn,
        )
        print(info.to_string(index=False))

        schemas = pd.read_sql(
            """
            SELECT table_schema, COUNT(*) AS tables
            FROM information_schema.tables
            WHERE table_schema IN ('raw', 'clean', 'mart')
            GROUP BY table_schema
            ORDER BY table_schema
            """,
            conn,
        )

        if schemas.empty:
            print("\nConnected, but raw/clean/mart are empty — run the pipeline next.")
        else:
            print()
            print(schemas.to_string(index=False))


if __name__ == "__main__":
    main()

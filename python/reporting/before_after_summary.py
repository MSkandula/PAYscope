import os
import pandas as pd
from python.config.db import get_engine

OUTPUT_DIR = "python/outputs/business_reports"
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "before_after_cleaning_summary.csv")

os.makedirs(OUTPUT_DIR, exist_ok=True)


def main():
    engine = get_engine()

    raw_dq = pd.read_csv("python/outputs/dq_reports/raw_dq_summary.csv")

    clean_summary_query = """
        SELECT 'customers' AS table_name, COUNT(*) AS total_rows,
               SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END) AS valid_rows,
               SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END) AS invalid_rows
        FROM clean.customers

        UNION ALL
        SELECT 'merchants', COUNT(*),
               SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
               SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END)
        FROM clean.merchants

        UNION ALL
        SELECT 'devices', COUNT(*),
               SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
               SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END)
        FROM clean.devices

        UNION ALL
        SELECT 'transactions', COUNT(*),
               SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
               SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END)
        FROM clean.transactions

        UNION ALL
        SELECT 'chargebacks', COUNT(*),
               SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
               SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END)
        FROM clean.chargebacks

        UNION ALL
        SELECT 'alerts', COUNT(*),
               SUM(CASE WHEN is_valid_record = TRUE THEN 1 ELSE 0 END),
               SUM(CASE WHEN is_valid_record = FALSE THEN 1 ELSE 0 END)
        FROM clean.alerts;
    """

    clean_summary = pd.read_sql(clean_summary_query, engine)

    clean_summary["valid_rate_pct"] = (
        clean_summary["valid_rows"] / clean_summary["total_rows"] * 100
    ).round(2)

    clean_summary["invalid_rate_pct"] = (
        clean_summary["invalid_rows"] / clean_summary["total_rows"] * 100
    ).round(2)

    raw_issue_summary = (
        raw_dq[raw_dq["check_name"] != "row_count"]
        .assign(result=lambda x: pd.to_numeric(x["result"], errors="coerce").fillna(0))
        .groupby("table_name", as_index=False)["result"]
        .sum()
        .rename(columns={"result": "raw_issue_count"})
    )

    raw_issue_summary["table_name"] = raw_issue_summary["table_name"].str.replace("raw.", "", regex=False)

    final_summary = clean_summary.merge(
        raw_issue_summary,
        on="table_name",
        how="left"
    )

    final_summary["raw_issue_count"] = final_summary["raw_issue_count"].fillna(0).astype(int)

    final_summary = final_summary[
        [
            "table_name",
            "total_rows",
            "raw_issue_count",
            "valid_rows",
            "invalid_rows",
            "valid_rate_pct",
            "invalid_rate_pct"
        ]
    ].sort_values("table_name")

    final_summary.to_csv(OUTPUT_PATH, index=False)

    print(final_summary)
    print(f"\nSaved before-after summary to: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
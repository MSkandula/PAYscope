#!/usr/bin/env bash
# =========================================
# PayScope Project
# File: run_pipeline.sh
# Purpose: Rebuild the entire warehouse from scratch, in dependency order
# Usage:   ./run_pipeline.sh          (full rebuild: schema + seed + inject + transform)
#          ./run_pipeline.sh --transform-only   (skip seeding; re-clean existing raw data)
# =========================================

set -euo pipefail

cd "$(dirname "$0")"          # always run from the repo root (run_marts.sql needs relative paths)

# --- config ------------------------------------------------------------------
PSQL="${PSQL:-psql}"
PY="${PY:-.venv/bin/python}"

if [[ ! -f .env ]]; then
    echo "ERROR: .env not found. Copy .env.example to .env and fill it in." >&2
    exit 1
fi

# export DB_* from .env, then hand the password to psql via PGPASSWORD
set -a; source .env; set +a
export PGPASSWORD="$DB_PASSWORD"
PSQL_ARGS=(-h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -q)

step() { echo; echo "=== $* ==="; }

# --- 0. connectivity ---------------------------------------------------------
step "Connecting to $DB_NAME as $DB_USER"
"$PSQL" "${PSQL_ARGS[@]}" -c "SELECT current_database(), current_user;"

if [[ "${1:-}" != "--transform-only" ]]; then
    # --- 1. schema -----------------------------------------------------------
    step "1. Creating schemas and tables"
    for f in sql/ddl/01_create_schemas.sql sql/ddl/02_raw_tables.sql sql/ddl/03_clean_tables.sql; do
        echo "  $f"; "$PSQL" "${PSQL_ARGS[@]}" -f "$f"
    done

    # --- 2. synthetic data ---------------------------------------------------
    step "2. Seeding synthetic data (order matters: chargebacks/alerts derive from transactions)"
    for f in sql/seed/0*.sql; do echo "  $f"; "$PSQL" "${PSQL_ARGS[@]}" -f "$f"; done

    # --- 3. inject known defects --------------------------------------------
    step "3. Injecting controlled data-quality defects"
    for f in sql/issues/0*.sql; do echo "  $f"; "$PSQL" "${PSQL_ARGS[@]}" -f "$f"; done
fi

# --- 4. extract + profile ----------------------------------------------------
step "4. Extracting raw -> CSV"
$PY -m python.extraction.extract_raw

step "5. Profiling raw data quality"
$PY -m python.dq.dq_checks

# --- 6. clean (dependency order is MANDATORY) --------------------------------
step "6. Cleaning and validating"
for m in clean_customers clean_devices clean_merchants \
         clean_transactions clean_chargebacks clean_alerts; do
    echo "  --> $m"
    $PY -m "python.cleaning.$m"
done

# --- 7. load + verify --------------------------------------------------------
step "7. Loading cleaned data into the clean schema"
$PY -m python.loading.load_clean

step "8. Clean-layer QA"
"$PSQL" "${PSQL_ARGS[@]}" -f sql/qa/clean_qa_checks.sql

step "9. Before/after cleaning report"
$PY -m python.reporting.before_after_summary

# --- 10. marts ---------------------------------------------------------------
step "10. Building business marts + mart QA"
"$PSQL" "${PSQL_ARGS[@]}" -f sql/run_marts.sql

echo
echo "=== Pipeline complete. Point Tableau at the mart schema in $DB_NAME. ==="

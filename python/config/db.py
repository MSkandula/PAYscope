# =========================================
# PayScope Project
# File: db.py
# Purpose: Database connection setup
# =========================================

import os
from pathlib import Path
from urllib.parse import quote_plus

from sqlalchemy import create_engine
from dotenv import load_dotenv

# load .env from the repo root, so imports work regardless of working directory
REPO_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(REPO_ROOT / ".env")

# read DB credentials
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")

# fail immediately with a useful message rather than a confusing driver error
_missing = [
    name for name, value in {
        "DB_USER": DB_USER,
        "DB_PASSWORD": DB_PASSWORD,
        "DB_HOST": DB_HOST,
        "DB_PORT": DB_PORT,
        "DB_NAME": DB_NAME,
    }.items()
    if not value
]
if _missing:
    raise RuntimeError(
        f"Missing {', '.join(_missing)} in {REPO_ROOT / '.env'}. "
        "Copy .env.example to .env and fill in your credentials."
    )

# quote_plus so passwords containing @ : / ? # etc. don't corrupt the URL
DB_URL = (
    f"postgresql+psycopg2://{quote_plus(DB_USER)}:{quote_plus(DB_PASSWORD)}"
    f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

# create SQLAlchemy engine
engine = create_engine(DB_URL, pool_pre_ping=True)


def get_engine():
    return engine

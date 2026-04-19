# =========================================
# PayScope Project
# File: db.py
# Purpose: Database connection setup
# =========================================

import os
from sqlalchemy import create_engine
from dotenv import load_dotenv

# load environment variables
load_dotenv()

# read DB credentials
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")

# create connection string
DB_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# create SQLAlchemy engine
engine = create_engine(DB_URL)

def get_engine():
    return engine
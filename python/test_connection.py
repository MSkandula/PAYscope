from config.db import get_engine
import pandas as pd

engine = get_engine()

df = pd.read_sql("SELECT COUNT(*) FROM raw.transactions", engine)
print(df)
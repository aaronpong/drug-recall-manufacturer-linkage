"""Run each query in sql/13_dashboard_exports.sql and save it as its own CSV."""
import re
from pathlib import Path

import pandas as pd
from sqlalchemy import text

from db import get_engine

SQL_FILE = Path("sql/13_dashboard_exports.sql")
OUT_DIR = Path("data/processed")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    engine = get_engine()

    # Each query ends with a semicolon; its comment line names the output file (dash_...)
    statements = [s.strip() for s in SQL_FILE.read_text(encoding="utf-8").split(";") if s.strip()]

    with engine.connect() as conn:
        for stmt in statements:
            match = re.search(r"(dash_\w+)", stmt)
            if not match:
                continue
            name = match.group(1)
            df = pd.read_sql(text(stmt), conn)
            path = OUT_DIR / f"{name}.csv"
            df.to_csv(path, index=False)
            print(f"{path}: {len(df)} rows, {len(df.columns)} columns")


if __name__ == "__main__":
    main()
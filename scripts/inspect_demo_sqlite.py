from __future__ import annotations

import sqlite3
from pathlib import Path


DB_PATH = Path(__file__).resolve().parents[1] / "data" / "sentineledge_demo.db"


def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    tables = [
        row[0]
        for row in conn.execute(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table'
              AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """
        )
    ]
    print(f"Database: {DB_PATH}")
    print("Tables:")
    for table in tables:
        count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"- {table}: {count} row(s)")
    conn.close()


if __name__ == "__main__":
    main()

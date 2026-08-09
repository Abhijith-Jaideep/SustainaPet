"""Create the sustainapet schema and every table the app needs.

The original database lived only on a hosted server, with no migrations and no
schema in the repository. When that server was deleted the schema went with it
and the project could not be revived. This script exists so that never happens
again: point it at an empty Postgres and the application's storage is rebuilt.

The eight application tables come from models.py. The two reference tables,
FoodEmissions and CategoryEmissions, are read with raw SQL by app.py and were
never modelled, so they are declared here.

Usage:
    DATABASE_URL=postgresql+psycopg2://user:pass@host/db python create_schema.py
"""

import os
import sys

from sqlalchemy import create_engine, text

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from models import Base  # noqa: E402

SCHEMA = "sustainapet"

# Not in models.py because app.py queries them with raw SQL. Column names are
# quoted and capitalised to match those queries exactly.
REFERENCE_TABLES = f"""
CREATE TABLE IF NOT EXISTS {SCHEMA}."FoodEmissions" (
    "Name"      TEXT PRIMARY KEY,
    "Emissions" DOUBLE PRECISION NOT NULL,
    "Impact"    TEXT
);

CREATE TABLE IF NOT EXISTS {SCHEMA}."CategoryEmissions" (
    "Category"  TEXT PRIMARY KEY,
    "Emissions" DOUBLE PRECISION NOT NULL,
    "Impact"    TEXT
);
"""


def main():
    url = os.environ.get("DATABASE_URL")
    if not url:
        sys.exit("DATABASE_URL is not set")

    engine = create_engine(url)

    with engine.begin() as conn:
        conn.execute(text(f"CREATE SCHEMA IF NOT EXISTS {SCHEMA}"))
        print(f"schema {SCHEMA} ready")

    # models.py carries schema="sustainapet" on its MetaData, so this lands in
    # the right place without any further configuration.
    Base.metadata.create_all(engine)
    print(f"created {len(Base.metadata.tables)} tables from models.py")

    with engine.begin() as conn:
        conn.execute(text(REFERENCE_TABLES))
    print("created FoodEmissions and CategoryEmissions")

    with engine.connect() as conn:
        rows = conn.execute(
            text(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_schema = :s ORDER BY table_name"
            ),
            {"s": SCHEMA},
        )
        names = [r[0] for r in rows]
    print(f"\n{len(names)} tables in {SCHEMA}:")
    for n in names:
        print("  ", n)


if __name__ == "__main__":
    main()

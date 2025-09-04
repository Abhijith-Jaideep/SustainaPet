from . import engine
from sqlalchemy import text

def list_tables(schema_name="pawprint"):
    with engine.connect() as conn:
        result = conn.execute(
            text(f"SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema = :schema ORDER BY table_name;"),
            {"schema": schema_name}
        )
        return [row for row in result]
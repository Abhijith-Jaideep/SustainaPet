# from sqlalchemy import create_engine, text, inspect, MetaData, Table, select, func
# from sqlalchemy.schema import CreateTable

# DB_USER = "pawprint_admin"
# DB_PASS = "ecopet5!"
# DB_HOST = "ecopawprint.postgres.database.azure.com"
# DB_PORT = 5432
# DB_NAME = "postgres"

# DATABASE_URL = (
#     f"postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
#     "?sslmode=require"
# )

# engine = create_engine(DATABASE_URL, future=True)

# SCHEMA = "pawprint"   # your schema name
# MAX_ROWS = 10         # how many data rows to preview per table

# def print_hr():
#     print("-" * 80)

# with engine.connect() as conn:
#     insp = inspect(conn)

#     # Discover tables in the schema
#     tables = insp.get_table_names(schema=SCHEMA)
#     print(f"Found tables in schema '{SCHEMA}': {tables}")
#     print_hr()

#     metadata = MetaData()
#     for tbl in tables:
#         print(f"Table: {SCHEMA}.{tbl}")
#         print_hr()

#         # --- Structure: columns ---
#         cols = insp.get_columns(tbl, schema=SCHEMA)
#         print("Columns:")
#         for c in cols:
#             # c has: name, type, nullable, default, autoincrement, comment, etc.
#             print(f"  - {c['name']:30} {str(c['type']):20} "
#                   f"nullable={c.get('nullable', True)} "
#                   f"default={c.get('default', None)}")
#         print_hr()

#         # --- Primary key ---
#         pk = insp.get_pk_constraint(tbl, schema=SCHEMA)
#         print(f"Primary Key: {pk.get('constrained_columns', [])}")
#         print_hr()

#         # --- Foreign keys ---
#         fks = insp.get_foreign_keys(tbl, schema=SCHEMA)
#         if fks:
#             print("Foreign Keys:")
#             for fk in fks:
#                 print(f"  - columns={fk['constrained_columns']} "
#                       f"-> {fk['referred_schema']}.{fk['referred_table']}({fk['referred_columns']}) "
#                       f"onupdate={fk.get('options', {}).get('onupdate')} "
#                       f"ondelete={fk.get('options', {}).get('ondelete')}")
#         else:
#             print("Foreign Keys: None")
#         print_hr()

#         # --- Indexes ---
#         idxs = insp.get_indexes(tbl, schema=SCHEMA)
#         if idxs:
#             print("Indexes:")
#             for idx in idxs:
#                 print(f"  - name={idx['name']} columns={idx['column_names']} unique={idx.get('unique', False)}")
#         else:
#             print("Indexes: None (or only implicit PK index)")
#         print_hr()

#         # --- Row count (quick) ---
#         table_obj = Table(tbl, metadata, schema=SCHEMA, autoload_with=conn)
#         total = conn.execute(select(func.count()).select_from(table_obj)).scalar_one()
#         print(f"Row count: {total}")
#         print_hr()

#         # --- Sample data ---
#         print(f"Top {MAX_ROWS} rows:")
#         preview = conn.execute(select(table_obj).limit(MAX_ROWS)).mappings().all()
#         if not preview:
#             print("  (no rows)")
#         else:
#             # pretty print as key=value on one line per row
#             for i, row in enumerate(preview, start=1):
#                 kv = ", ".join(f"{k}={row[k]!r}" for k in row.keys())
#                 print(f"  {i:>2}: {kv}")
#         print_hr()

#         # --- Optional: print CREATE TABLE DDL (comment out if not needed) ---
#         try:
#             ddl = str(CreateTable(table_obj).compile(conn))
#             print("CREATE TABLE DDL:")
#             print(ddl)
#         except Exception as e:
#             print(f"(Could not generate DDL: {e})")

#         print("\n" + "=" * 80 + "\n")


















# backend/test.py (your deleter)
from db import SessionLocal
from models import User, UserQuest, Event

session = SessionLocal()

ids_to_delete = [13,14]

for uid in ids_to_delete:
    u = session.get(User, uid)
    if not u:
        continue
    print("Deleting:", u.userid, u.name)

    # 1) Delete child rows explicitly
    session.query(Event).filter(Event.userid == uid).delete(synchronize_session=False)
    session.query(UserQuest).filter(UserQuest.userid == uid).delete(synchronize_session=False)

    # 2) Now delete the user
    session.delete(u)

session.commit()
session.close()

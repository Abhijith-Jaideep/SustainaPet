import os
from sqlalchemy import text
from db import SessionLocal, engine 

# test the connection
def test_connection():
    try:
        with engine.connect() as conn:
            result = conn.execute(text("SELECT 1"))
            value = result.scalar()
            assert value == 1
        print("✅ Database connection successful!")
    except Exception as e:
        print("❌ Database connection failed:", e)

# testSession 
def test_session_crud():
    from sqlalchemy import Table, Column, Integer, String, MetaData

    metadata = MetaData()
    # temporary test table
    test_table = Table(
        "test_table", metadata,
        Column("id", Integer, primary_key=True),
        Column("name", String(50), nullable=False),
    )

    # create the table
    metadata.create_all(engine)

    session = SessionLocal()
    try:
        # CREATE
        insert_stmt = test_table.insert().values(name="Alice")
        session.execute(insert_stmt)
        session.commit()
        print("✅ Inserted data successfully")

        # READ
        select_stmt = test_table.select()
        rows = session.execute(select_stmt).fetchall()
        print("Read rows:", rows)

        # UPDATE
        update_stmt = test_table.update().where(test_table.c.name=="Alice").values(name="Bob")
        session.execute(update_stmt)
        session.commit()
        print("✅ Updated data successfully")

        # DELETE
        delete_stmt = test_table.delete().where(test_table.c.name=="Bob")
        session.execute(delete_stmt)
        session.commit()
        print("✅ Deleted data successfully")

    finally:
        session.close()
        test_table.drop(engine)

if __name__ == "__main__":
    test_connection()
    test_session_crud()

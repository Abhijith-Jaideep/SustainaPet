from backend.db import SessionLocal
from backend.models import User

def insert_test_users():
    db = SessionLocal()
    try:
        users = [
            User(name="Tim", ecopetmood=5, carbonpoints=100),
            User(name="Michael", ecopetmood=3, carbonpoints=80),
            User(name="Abhijith", ecopetmood=7, carbonpoints=120),
        ]
        db.add_all(users)
        db.commit()
        print("✅ Test users inserted successfully!")
    except Exception as e:
        db.rollback()
        print(f"❌ Error inserting users: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    insert_test_users()

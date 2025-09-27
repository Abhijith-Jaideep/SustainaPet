from backend.db import SessionLocal
from backend.models import Friends

def insert_test_friends():
    db = SessionLocal()
    try:
        # User ID 4,5,6
        # Friendship cases:
        friends = [
            Friends(userid=4, friendid=6),
            Friends(userid=6, friendid=4),
            Friends(userid=5, friendid=4),
            Friends(userid=4, friendid=5),
        ]
        db.add_all(friends)
        db.commit()
        print("✅ Friends test data inserted successfully!")
    except Exception as e:
        db.rollback()
        print(f"❌ Error inserting Friends: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    insert_test_friends()

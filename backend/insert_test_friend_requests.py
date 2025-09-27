from proto import ENUM
from sqlalchemy import cast
from backend.db import SessionLocal, engine
from backend.models import Base, FriendRequests, RequestStatusEnum

# def insert_test_friend_requests():
#     db = SessionLocal()
#     try:
#         Base.metadata.create_all(bind=engine)

#         # User ID 4,5,6
#         requests = [
#              FriendRequests(
#                 requesterid=4,
#                 receiverid=5,
#                 status='Pending'
#             ),
#             FriendRequests(
#                 requesterid=5,
#                 receiverid=6,
#                 status='Pending'
#             ),
#             FriendRequests(
#                 requesterid=6,
#                 receiverid=4,
#                 status='Pending'
#             ),
#         ]
#         db.add_all(requests)
#         db.commit()
#         print("✅ FriendRequests test data inserted successfully!")
#     except Exception as e:
#         db.rollback()
#         print(f"❌ Error inserting FriendRequests: {e}")
#     finally:
#         db.close()


# backend/insert_test_friend_requests.py
from backend.db import SessionLocal
from backend.models import FriendRequests

def insert_test_friend_requests():
    db = SessionLocal()
    try:
        # 1. delte the original FriendRequests
        db.query(FriendRequests).delete()
        db.commit()

        # 2. insert new test data
        # Our design：
        # request_id=1 -> Tim(4) request Michael(5) -> accept test cases
        # request_id=2 -> Abhijith(6) request Michael(5) -> reject test cases
        new_requests = [
            FriendRequests(requesterid=4, receiverid=5, status='Pending'),  # accept 
            FriendRequests(requesterid=6, receiverid=5, status='Pending'),  # reject 
        ]
        db.add_all(new_requests)
        db.commit()

        # output request_id corresponding relation
        all_requests = db.query(FriendRequests).all()
        for r in all_requests:
            print(f"request_id={r.requestid}, {r.requesterid} -> {r.receiverid}, status={r.status}")

        print("✅ Test FriendRequests inserted successfully!")

    finally:
        db.close()


if __name__ == "__main__":
    insert_test_friend_requests()

from datetime import datetime
from fastapi import APIRouter, FastAPI, Depends
from pydantic import BaseModel
from sqlalchemy import TIMESTAMP, create_engine, Column
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
import uuid

DATABASE_URL = "postgresql+psycopg2://postgres:123123@localhost:5433/pawprint"

engine = create_engine(DATABASE_URL, echo=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    user_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    created_at = Column(TIMESTAMP, default=datetime.utcnow)

Base.metadata.create_all(bind=engine)

class LoginRequest(BaseModel):
    user_id: uuid.UUID | None = None  

router = APIRouter(prefix="/login", tags=["Login"])

def get_db():
    db = SessionLocal()
    try:
        yield db
        db.commit() 
    finally:
        db.close()

@router.post("/")
def login(request: LoginRequest, db: Session = Depends(get_db)):
    print(">>> POST /login function called <<<")
    user_id = request.user_id or uuid.uuid4()

    existing_user = db.query(User).filter(User.user_id == user_id).first()
    if existing_user:
        return {"message": f"User already exists: {existing_user.user_id}"}

    new_user = User(user_id=user_id)
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    print("Inserted user:", new_user.user_id)

    return {"message": f"Logged in with UserID {new_user.user_id}"}
@router.get("/status")
def login_status():
    return {"message": "Please use POST /login to login"}

# ------------------------
# main app
# ------------------------
app = FastAPI(title="Login API")
app.include_router(router)
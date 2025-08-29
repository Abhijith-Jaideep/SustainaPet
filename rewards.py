from datetime import datetime
from flask import Flusk, APIRouter, Depends
from sqlalchemy import TIMESTAMP, ForeignKey, Integer, create_engine, Column
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session

from login import SessionLocal

router = APIRouter(prefix="/rewards",tags=["Rewards"])

def get_db():
    db = SessionLocal
    try:
        yield db
        db.commit()
    finally:
        db.close()

@router.post("/")

DATABASE_URL = ""

engine = create_engine(DATABASE_URL, echo=True)
SessionalLocal = sessionmaker(autocommit=False, autoflush=False,bind=engine)
Base = declarative_base()

class Reward(Base):
    __tablename__="rewards"
    user_id = Column(Integer, ForeignKey("users.user_id"))
    rewards_pt = Column(Integer,)
    updated_at = Column(TIMESTAMP, default=datetime.utcnow)



# backend/models.py
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime, Float, Text, ForeignKey,
    MetaData
)
from sqlalchemy.sql import quoted_name

# All tables live in the "pawprint" schema
metadata = MetaData(schema="pawprint")
Base = declarative_base(metadata=metadata)

# ---------------------- User ----------------------
class User(Base):
    __tablename__ = quoted_name("User", True)   # table is still "User" (quoted)

    # map to lowercase physical columns
    userid = Column("userid", Integer, primary_key=True)
    name = Column("name", String(16), nullable=False)
    ecopetmood = Column("ecopetmood", Integer, nullable=False, default=0)
    carbonpoints = Column("carbonpoints", Integer, nullable=False, default=0)

    # if you already added these columns with lowercase names, map them here;
    # otherwise comment these two out (or create them in the DB).
    weeklyemissionssaved = Column("weeklyemissionssaved", Float, nullable=False, default=0.0)
    weeklyemissionsproduced = Column("weeklyemissionsproduced", Float, nullable=False, default=0.0)


# ---------------------- Quest ----------------------
class Quest(Base):
    __tablename__ = "quest"
    questid = Column(Integer, primary_key=True)
    description = Column(Text, nullable=False)
    difficulty = Column(String(6), nullable=False)      # enum in DB → String here
    reward = Column(Integer, nullable=False, default=0) # SMALLINT ok as int
    emissions = Column(Float, nullable=False, default=0.0)

# ---------------------- UserQuest ----------------------
class UserQuest(Base):
    __tablename__ = "userquests"
    userquestid = Column(Integer, primary_key=True)

    # IMPORTANT: reference the actual Column object, not a string
    userid = Column(Integer, ForeignKey(User.userid, ondelete="CASCADE"), nullable=False)

    # your DB has no FK to quest in the DDL; leave as plain int
    questid = Column(Integer, nullable=False)

    isactive = Column(Boolean, nullable=False, default=True)
    iscompleted = Column(Boolean, nullable=False, default=False)
    completeddate = Column(DateTime)

    user = relationship("User", backref="userquests")
    quest = relationship(
        "Quest",
        primaryjoin="foreign(UserQuest.questid) == Quest.questid",
        viewonly=True
    )

# ---------------------- GroceryReceipt ----------------------
class GroceryReceipt(Base):
    # Table is quoted/mixed-case in DB
    __tablename__ = quoted_name("GroceryReceipt", True)

    receiptid = Column(Integer, primary_key=True, autoincrement=True)
    userid = Column(Integer, ForeignKey(User.userid, ondelete="CASCADE"), nullable=False)
    totalemissions = Column(Float, nullable=False, default=0.0)
    date = Column(DateTime, nullable=False)

    # Relationships
    user = relationship("User", backref="groceryreceipts")
    events = relationship("Event", back_populates="receipt")

# ---------------------- Event ----------------------
class Event(Base):
    __tablename__ = "event"
    eventid = Column(Integer, primary_key=True)

    userid = Column(Integer, ForeignKey(User.userid, ondelete="CASCADE"), nullable=False)
    userquestid = Column(Integer, ForeignKey('userquests.userquestid', ondelete="CASCADE"), nullable=True)

    # Now we can reference the actual Column on GroceryReceipt (defined above)
    receiptid = Column(Integer, ForeignKey(GroceryReceipt.receiptid, ondelete="CASCADE"), nullable=True)

    tripid = Column(Integer)
    description = Column(Text, nullable=False)
    type = Column(String(20), nullable=False)
    emissions = Column(Float, nullable=False)
    datetime = Column(DateTime, nullable=False)

    user = relationship("User")
    userquest = relationship("UserQuest")
    receipt = relationship("GroceryReceipt", back_populates="events")

# ---------------------- Conversion metrics ----------------------
class EmissionConversionSaving(Base):
    __tablename__ = "emissionconversionssaving"
    metricid = Column(Integer, primary_key=True)
    name = Column(String(64), nullable=False)
    description = Column(Text)
    emissionsperx = Column(Float, nullable=False)

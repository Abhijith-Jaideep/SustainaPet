# backend/models.py
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime, Float, Text, ForeignKey,
    MetaData
)
from sqlalchemy.sql import quoted_name

metadata = MetaData(schema="pawprint")
Base = declarative_base(metadata=metadata)

class User(Base):
    __tablename__ = quoted_name("User", True)   # -> "User" (quoted)
    userid = Column(Integer, primary_key=True)
    name = Column(String(16), nullable=False)
    ecopetmood = Column(Integer, nullable=False, default=0)
    carbonpoints = Column(Integer, nullable=False, default=0)

class Quest(Base):
    __tablename__ = "quest"
    questid = Column(Integer, primary_key=True)
    description = Column(Text, nullable=False)
    difficulty = Column(String(6), nullable=False)      # enum in DB → String here
    reward = Column(Integer, nullable=False, default=0) # SMALLINT ok as int
    emissions = Column(Float, nullable=False, default=0.0)

class UserQuest(Base):
    __tablename__ = "userquests"
    userquestid = Column(Integer, primary_key=True)

    # IMPORTANT: because Base.metadata already has schema="pawprint",
    # using just 'User.userid' is enough and resolves to pawprint."User"
    userid = Column(Integer, ForeignKey('User.userid', ondelete="CASCADE"), nullable=False)

    # your DB has no FK to quest in the DDL; leave as plain int
    questid = Column(Integer, nullable=False)

    isactive = Column(Boolean, nullable=False, default=True)
    iscompleted = Column(Boolean, nullable=False, default=False)
    completeddate = Column(DateTime)

    user = relationship("User", backref="userquests")
    quest = relationship("Quest",
        primaryjoin="foreign(UserQuest.questid) == Quest.questid",
        viewonly=True)

class Event(Base):
    __tablename__ = "event"
    eventid = Column(Integer, primary_key=True)

    userid = Column(Integer, ForeignKey('User.userid', ondelete="CASCADE"), nullable=False)
    userquestid = Column(Integer, ForeignKey('userquests.userquestid', ondelete="CASCADE"), nullable=True)

    receiptid = Column(Integer, ForeignKey('GroceryReceipt.receiptid', ondelete="CASCADE"), nullable=True)
    tripid = Column(Integer)
    description = Column(Text, nullable=False)
    type = Column(String(20), nullable=False)  
    emissions = Column(Float, nullable=False)
    datetime = Column(DateTime, nullable=False)

    user = relationship("User")
    userquest = relationship("UserQuest")
    receipt = relationship("GroceryReceipt", back_populates="events") 

class EmissionConversionSaving(Base):
    __tablename__ = "emissionconversionssaving"
    metricid = Column(Integer, primary_key=True)
    name = Column(String(64), nullable=False)
    description = Column(Text)
    emissionsperx = Column(Float, nullable=False)

class GroceryReceipt(Base):
    __tablename__ = "GroceryReceipt"

    receiptid = Column(Integer, primary_key=True, autoincrement=True)
    userid = Column(Integer, ForeignKey('User.userid', ondelete="CASCADE"), nullable=False)
    totalemissions = Column(Float, nullable=False, default=0.0)
    date = Column(DateTime, nullable=False)

    # Relationships
    user = relationship("User", backref="groceryreceipts")
    events = relationship("Event", back_populates="receipt")

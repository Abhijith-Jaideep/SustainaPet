# backend/models.py
import enum
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy.dialects.postgresql import ENUM as PGEnum
from sqlalchemy import (
    Column, Integer, PrimaryKeyConstraint, String, Boolean, DateTime, Float, Text, ForeignKey,
    MetaData, quoted_name
)


metadata = MetaData(schema="sustainapet")
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

    # IMPORTANT: because Base.metadata already has schema="sustainapet",
    # using just 'User.userid' is enough and resolves to sustainapet."User"
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

# ---------------------- GroceryReceipt ----------------------
class GroceryReceipt(Base):
    __tablename__ = quoted_name("GroceryReceipt", True)

    receiptid = Column(Integer, primary_key=True, autoincrement=True)
    userid = Column(Integer, ForeignKey('User.userid', ondelete="CASCADE"), nullable=False)
    totalemissions = Column(Float, nullable=False, default=0.0)
    date = Column(DateTime, nullable=False)

    user = relationship("User", backref="groceryreceipts")

    # tell SQLAlchemy which FK on Event points here
    events = relationship(
        "Event",
        back_populates="receipt",
        foreign_keys="Event.receiptid",
    )


class Event(Base):
    __tablename__ = "event"
    eventid = Column(Integer, primary_key=True)

    userid = Column(Integer, ForeignKey('User.userid', ondelete="CASCADE"), nullable=False)
    userquestid = Column(Integer, ForeignKey('userquests.userquestid', ondelete="CASCADE"), nullable=True)

    # ADD the FK to GroceryReceipt
    receiptid = Column(
        Integer,
        ForeignKey('GroceryReceipt.receiptid', ondelete="CASCADE"),
        nullable=True,
    )
    tripid = Column(Integer)

    description = Column(Text, nullable=False)
    type = Column(String(7), nullable=False)
    emissions = Column(Float, nullable=False)
    datetime = Column(DateTime, nullable=False)

    user = relationship("User")
    userquest = relationship("UserQuest")

    # back link to GroceryReceipt
    receipt = relationship(
        "GroceryReceipt",
        back_populates="events",
        foreign_keys=[receiptid],
    )


# ---------------------- Conversion metrics ----------------------
class EmissionConversionSaving(Base):
    __tablename__ = "emissionconversionssaving"
    metricid = Column(Integer, primary_key=True)
    name = Column(String(64), nullable=False)
    description = Column(Text)
    emissionsperx = Column(Float, nullable=False)

# FriendRequests status enum
class RequestStatusEnum(enum.Enum):
    Accepted = "Accepted"
    Pending = "Pending"
    Rejected = "Rejected"

# FriendRequests table
class FriendRequests(Base):
    __tablename__ = "FriendRequests"

    requestid = Column(Integer, primary_key=True)
    requesterid = Column(Integer, ForeignKey("User.userid"), nullable=False)
    receiverid = Column(Integer, ForeignKey("User.userid"), nullable=False)
    status = Column(
        PGEnum('Pending', 'Accepted', 'Rejected', name='friend_request_status_enum', create_type=True),
        nullable=False,
        server_default='Pending'
    )

# Friends table
class Friends(Base):
    __tablename__ = "Friends"

    userid = Column(Integer, ForeignKey("User.userid"), nullable=False)
    friendid = Column(Integer, ForeignKey("User.userid"), nullable=False)

    __table_args__ = (
        PrimaryKeyConstraint('userid', 'friendid'),  # composite primary key
    )
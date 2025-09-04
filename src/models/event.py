from . import db, event_type_enum
from datetime import datetime
from sqlalchemy import Enum


class Event(db.Model):
    __tablename__ = "event"
    eventid = db.Column(db.Integer, primary_key=True)
    userquestid = db.Column(db.Integer, db.ForeignKey('user_quests.user_quest_id'), nullable=False)
    receipt_id = db.Column(db.Integer, db.ForeignKey('grocery_receipt.receipt_id'))
    trip_id = db.Column(db.Integer, db.ForeignKey('trip.trip_id'))
    type = db.Column(event_type_enum, nullable=False)
    emissions = db.Column(db.Float, nullable=False)
    date_time = db.Column(db.DateTime, nullable=True, default=datetime.utcnow)

    def __repr__(self):
        return '<Task %r>' % self.event_id
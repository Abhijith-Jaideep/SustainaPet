from . import db
from datetime import datetime

class Event(db.Model):
    event_id = db.Column(db.Integer,primary_key=True)
    user_id = db.Column(db.Integer,db.ForeignKey('user_quests.user_id')) # foreign_key should be correct
    user_quest_id = db.Column(db.Integer,db.ForeignKey('user_quests.user_quest_id'))
    receipt_id = db.Column(db.Integer,db.ForeignKey('grocery_receipt.receipt_id'))
    trip_id = db.Column(db.Integer,db.ForeignKey('trip.trip_id'))
    type = db.Column(db.Enum("Trip","Grocery","Quest"),nullable=False)
    emissions = db.Column(db.Float,nullable=False)
    date_time = db.Column(db.DateTime, nullable=True, default=datetime.utcnow)

    def __repre__(self):
        return '<Task %r>' % self.event_id
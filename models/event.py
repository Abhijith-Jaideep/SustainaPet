from . import db

class Event(db.Model):
    event_id = db.column(db.Integer,primary_key=True)
    user_id = db.column(db.Integer,db.foreign_key('user_id'))
    user_quest_id = db.column(db.Integer,db.foreign_key('user_quest_id'))
    receipt_id = db.column(db.Integer,db.foreign_key('receipt_id'))
    trip_id = db.column(db.Integer,db.foreign_key('trip_id'))
    type = db.column(db.Enum("Trip","Grocery","Quest"),nullable=False)
    emissions = db.column(db.Integer,nullable=False)
    date_time = db.column(db.TimeStamp,nullable=False)

    def __repre__(self):
        return '<Task %r>' % self.event_id
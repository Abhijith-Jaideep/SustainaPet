from datetime import datetime
from . import db,transport_mode_enum

class Trip(db.Model):
    trip_id = db.Column(db.Integer,primary_key=True)
    userid = db.Column(db.Integer,db.ForeignKey('user.user_id'), nullable=False)
    mode = db.Column(transport_mode_enum, nullable=False)
    eventid = db.Column(db.Integer,nullable=False)
    tripdate = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    duration = db.Column(db.Interval,nullable=False)
    emissions =db.Column(db.Float,nullable=False)

    def __repr__(self):
        return '<Task %r>' % self.trip_id
    
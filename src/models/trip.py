from datetime import datetime
from . import db

class Trip(db.Model):
    trip_id = db.Column(db.Integer,primary_key=True)
    user_id = db.Column(db.Integer,db.ForeignKey('user.user_id'), nullable=False)
    mode = db.Column(db.Enum("Train","Bus","Tram","Bicycle","Self-Driving","Automobile","Airplane","Other"))
    event_id = db.Column(db.Integer,nullable=False)
    trip_date = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    duration = db.Column(db.Interval,nullable=False)
    emissions =db.Column(db.Float,nullable=False)

    def __repr__(self):
        return '<Task %r>' % self.trip_id
    
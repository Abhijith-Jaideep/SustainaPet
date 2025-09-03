from . import db

class Trip(db.Model):
    trip_id = db.column(db.Integer,primary_key=True)
    user_id = db.column(db.Integer,db.ForeignKey('user.id'))
    mode = db.column(db.Enum("Train","Bus","Tram","Bicycle","Self-Driving","Automobile","Airplane","Other"),db.ForeignKey('mode'))
    event_id = db.column(db.Integer,nullable=False)
    trip_date =db.column(db.Timestamp,nullable=False)
    duration = db.column(db.Interval,nullable=False)
    emissions =db.column(db.Float,nullable=False)

    def __repr__(self):
        return '<Task %r>' % self.trip_id
    
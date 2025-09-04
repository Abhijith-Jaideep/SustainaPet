from . import db

class TransportEmissions(db.Model):
    mode = db.Column(db.Enum("Train","Bus","Tram","Bicycle","Self-Driving","Automobile","Airplane","Other"),primary_key=True)
    emissions_per_km = db.Column(db.Float,nullable=False)

    def __repr__(self):
        return '<Task %r>' % self.quest_id
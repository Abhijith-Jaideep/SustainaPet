from . import db, transport_mode_enum
from sqlalchemy import Enum

transport_mode_enum = Enum(
    "Train", "Bus", "Tram", "Bicycle", "Self-Driving", "Automobile", "Airplane", "Other",
    name="transport_mode_enum"
)

class TransportEmissions(db.Model):
    __tablename__ = "transport_emissions"

    mode = db.Column(transport_mode_enum, primary_key=True)
    emissions_per_km = db.Column(db.Float,nullable=False)

    def __repr__(self):
        return '<Task %r>' % self.event_id
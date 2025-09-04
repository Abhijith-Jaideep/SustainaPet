from . import db

class AverageAustralianCarbonEmissions(db.Model):
    year = db.Column(db.String(4), primary_key=True)
    weekly_emissions = db.Column(db.Float,nullable=False)

    def __repr__(self):
        return '<Task %r>' % self.year
from . import db

class FoodEmissions(db.Model):
    food_id = db.Column(db.Integer,primary_key=True)
    food_description = db.Column(db.String(500),nullable=False)
    carbon_emissions_per_kg = db.Column(db.Float,nullable=False)

    def __repr__(self):
        return '<Task %r>' % self.food_id
from . import db

class User(db.Model):
    user_id = db.Column(db.Integer,primary_key=True)
    name = db.Column(db.String(16),nullable=False)
    eco_pet_mood = db.Column(db.Integer,nullable=False)
    carbon_points = db.Column(db.Integer,nullable=False)

    def __repre__(self):
        return '<Task %r>' % self.user_id
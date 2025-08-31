from . import db

class User(db.Model):
    user_id = db.column(db.Integer,primary_key=True)
    name = db.column(db.String(16),nullable=False)
    eco_pet_mood = db.column(db.Integer,nullable=False)
    carbon_points = db.column(db.Integer,nullable=False)

    def __repre__(self):
        return '<Task %r>' % self.user_id
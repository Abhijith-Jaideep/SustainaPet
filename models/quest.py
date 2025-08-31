from . import db

class Quest(db.Model):
    quest_id = db.column(db.Integer, primary_key =True)
    description =db.column(db.String(500),nullable = True)
    difficulty = db.column(db.enum("Easy","Medium","Hard"),nullable = False)
    reward = db.column(db.SmallInt,nullable = False)
    emissions = db.column(db.float, nullable = False)

    def __repr__(self):
        return '<Task %r>' % self.quest_id
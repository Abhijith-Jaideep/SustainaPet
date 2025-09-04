from . import db

class Quest(db.Model):
    quest_id = db.Column(db.Integer, primary_key =True)
    description =db.Column(db.String(500),nullable = True)
    difficulty = db.Column(db.Enum("Easy","Medium","Hard"),nullable = False)
    reward = db.Column(db.SmallInteger,nullable = False)
    emissions = db.Column(db.Float, nullable = False)

    def __repr__(self):
        return (f"<Quest(quest_id={self.quest_id}, description={self.description}, "
                f"difficulty={self.difficulty}, reward={self.reward}, "
                f"emissions={self.emissions})>")
from . import db,quest_difficulty_enum
from sqlalchemy import Enum


class Quest(db.Model):
    __tablename__ = "quest"
    quest_id = db.Column(db.Integer, primary_key =True)
    description =db.Column(db.String(500),nullable = True)
    difficulty = db.Column(quest_difficulty_enum, nullable=False)
    reward = db.Column(db.SmallInteger,nullable = False)
    emissions = db.Column(db.Float, nullable = False)

    def __repr__(self):
        return (f"<Quest(quest_id={self.quest_id}, description={self.description}, "
                f"difficulty={self.difficulty}, reward={self.reward}, "
                f"emissions={self.emissions})>")
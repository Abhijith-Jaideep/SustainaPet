from . import db
from datetime import datetime

class UserQuests(db.Model):
    user_quest_id = db.Column(db.Integer,primary_key=True)
    user_id = db.Column(db.Integer,db.ForeignKey("user.user_id"), nullable=False)
    quest_id = db.Column(db.Integer,db.ForeignKey("quest.quest_id"), nullable=False)
    event_id = db.Column(db.Integer,nullable=True)
    is_active = db.Column(db.Boolean,nullable=False)
    is_completed = db.Column(db.Boolean, nullable=False)
    completed_data = db.Column(db.DateTime, nullable=True, default=datetime.utcnow)

    quest = db.relationship("Quest", backref="user_quests")

    def __repr__(self):
        quest_info = (f"description={self.quest.description}, "
                      f"difficulty={self.quest.difficulty}, "
                      f"reward={self.quest.reward}, "
                      f"emissions={self.quest.emissions}") if self.quest else "No quest linked"

        return (f"<UserQuests(user_quest_id={self.user_quest_id}, "
                f"user_id={self.user_id}, quest_id={self.quest_id}, "
                f"event_id={self.event_id}, is_active={self.is_active}, "
                f"is_completed={self.is_completed}, completed_data={self.completed_data}, "
                f"{quest_info})>")
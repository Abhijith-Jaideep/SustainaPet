from . import db
from datetime import datetime

class UserQuests(db.Model):
    __tablename__ = "user_quests"
    user_quest_id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.user_id'), nullable=False)
    events = db.relationship("Event", backref="user_quest")

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
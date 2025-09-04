from . import db
from datetime import datetime

class UserQuests(db.Model):
    __tablename__ = "user_quests"
    __table_args__ = {"schema": "pawprint"}
    userquestid = db.Column(db.Integer, primary_key=True)
    userid = db.Column(db.Integer, db.ForeignKey('user.user_id'), nullable=False)
    events = db.relationship("Event", backref="userquest")

    quest = db.relationship("Quest", backref="userquests")

    def __repr__(self):
        quest_info = (f"description={self.quest.description}, "
                      f"difficulty={self.quest.difficulty}, "
                      f"reward={self.quest.reward}, "
                      f"emissions={self.quest.emissions}") if self.quest else "No quest linked"

        return (f"<UserQuests(userquestid={self.userquestid}, "
                f"user_id={self.userid}, quest_id={self.questid}, "
                f"event_id={self.eventid}, is_active={self.isactive}, "
                f"is_completed={self.iscompleted}, completed_data={self.completeddata}, "
                f"{quest_info})>")
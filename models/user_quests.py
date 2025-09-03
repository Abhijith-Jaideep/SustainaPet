from . import db

class UserQuests(db.Model):
    user_quest_id = db.column(db.Integer,primary_key=True)
    user_id = db.column(db.Integer,foreignkey=True)
    quest_id = db.column(db.Integer,foreignkey=True)
    event_id = db.column(db.Integer,nullable=False)
    is_active = db.column(db.Boolean,nullable=False)
    is_completed = db.column(db.Boolean, nullable=False)
    completed_data = db.column(db.Timestamp,nullable=False)

    def __repre__(self):
        return '<Task %r>' % self.user_quest_id
from src.models import db
from src.models.quest import Quest
from src.models.user_quests import UserQuests
from src.models.user import User

class ReRollQuest:
    def set_excluded_quest(self,user_id,user_quest_id):
        '''
        input: user_quest_id
        output: is_active turned out to be False
        '''
        targeted_user = db.session.query(UserQuests).filter_by(user_id=user_id).all()
        if targeted_user is None:
            return
        for i in targeted_user:
            targeted_quest = db.session.query(UserQuests).filter_by(user_quest_id = user_quest_id).first()
            targeted_quest.is_active = False
            db.session.commit()
        return targeted_quest
    
    def re_allocate_quest(self,user_id,quest_id):
        '''
        When assigning tasks, events do not have to be bound; they can be associated later upon completion.
        '''
        user = db.session.query(User).filter_by(user_id=user_id).first()
        if not user:
            print(f"User {user_id} not found")
            return None

        # check the quest existence
        quest = db.session.query(Quest).filter_by(quest_id=quest_id).first()
        if not quest:
            print(f"Quest {quest_id} not found")
            return None

        # check the quest has been allocated to the user
        existing = db.session.query(UserQuests).filter_by(user_id=user_id, quest_id=quest_id).first()
        if existing:
            print(f"User {user_id} already has quest {quest_id}")
            return existing

        # create an new UserQuest
        new_user_quest = UserQuests(
            user_id=user_id,
            quest_id=quest_id,
            is_active=True,
            is_completed=False,
            completed_data=None
        )

        db.session.add(new_user_quest)
        db.session.commit()
        print(new_user_quest)

        return new_user_quest
    
  

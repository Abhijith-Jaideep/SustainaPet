from src.models import db
from src.models.quest import Quest
from src.models.user_quests import UserQuests
from src.models.event import Event

class PrintCompletion:
    def display_completion(self,user_quest_id):
        """
        input: user_quest_id (int)
        output: isActive (boolean)
        """
        uq = is_completed = db.session.query(UserQuests).filter_by(user_quest_id = user_quest_id).first()
        return uq.is_completed if uq else None

    def set_completion(self,user_quest_id):
        '''
        when the user set the quest completed, the is_completed atttribute will be changed
        '''
        completed_quest = db.session.query(UserQuests).filter_by(user_quest_id=user_quest_id).first()
        if completed_quest:
            completed_quest.is_completed = True
            db.session.commit()
        print(completed_quest)
        return completed_quest


    def display_completion_emissions(self,user_quest_id):
        '''
        input: user_quest_id (int)
        output: emissions (float)
        '''
        uq = db.session.query(Event).filter_by(user_quest_id =user_quest_id).first()
        return uq.emissions if uq else None

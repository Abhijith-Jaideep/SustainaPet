from models import db
from models.quest import Quest
from models.user_quests import UserQuests

def display_completion(user_quest_id):
    """
    input: user_quest_id (int)
    output: isActive (boolean)
    """
    is_completed = db.query(UserQuests).filter_by(user_quest_id = user_quest_id).all()
    return is_completed.is_completed

def set_completion(user_quest_id):
    '''
    when the user set the quest completed, the is_completed atttribute will be changed
    '''
    completed_quest = db.query(UserQuests).filter_by(user_quest_id=user_quest_id).first()
    if completed_quest:
        db.is_completed = True
        db.session.commit()
    return completed_quest


def display_completion_emissions(completed_quest):
    '''
    when the userQuestId input, the corresponding emiss
    '''
    

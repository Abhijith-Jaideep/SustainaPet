from models import db
from models.quest import Quest

def __init__(self):
    '''
    user's quest collection (each user will be applied three different types quest per week)
    '''
    self.quest_collection = []

def create_quest_collection(self,quest_id,difficulty):
    '''
    identify existence of the quest
    append the quest to user's quest collection by difficulty
    return user's quest_collection
    '''
    quest = db.query(Quest).filter_by(quest_id=quest_id,difficulty=difficulty).first()
    if not quest:
        return "The Quest does not exist"
    easy_quests = db.query(Quest).filter_by(difficulty="Easy").all()
    medium_quests = db.query(Quest).filter_by(difficulty="Medium").all()
    hard_quests = db.query(Quest).filter_by(difficulty="Hard").all()
    self.quest_collection = [
            easy_quests.pop() if easy_quests else None,
            medium_quests.pop() if medium_quests else None,
            hard_quests.pop() if hard_quests else None
        ]  
    return self.quest_collection

def remove_quest(quest_id):
    pass

def allocate_quest(self,User):
    pass

def display_quest(self):
    for q in self.quest_collection:
        print(q.description,q.difficulty,q.emissions,q.reward)


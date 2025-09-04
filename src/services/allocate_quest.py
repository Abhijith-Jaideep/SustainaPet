from src.models import db
from src.models.quest import Quest

class QuestAllocation:
    def __init__(self):
        '''
        user's quest collection (each user will be applied three different types quest per week)
        '''
        self.quest_collection = []

    def create_quest_collection(self):
        '''
        identify existence of the quest
        append the quest to user's quest collection by difficulty
        return user's quest_collection
        '''
        quest = Quest.query.all()
        if not quest:
            return "The Quest does not exist"
        easy_quests = Quest.query.filter_by(difficulty="Easy").all()
        medium_quests = Quest.query.filter_by(difficulty="Medium").all()
        hard_quests = Quest.query.filter_by(difficulty="Hard").all()
        self.quest_collection = [
                easy_quests.pop() if easy_quests else None,
                medium_quests.pop() if medium_quests else None,
                hard_quests.pop() if hard_quests else None
            ]  
        return self.quest_collection

    def display_quest(self):
        quest_list = []
        for q in self.quest_collection:
            if q:
                quest_list.append({
                    "quest_id": q.quest_id,
                    "description": q.description,
                    "difficulty": q.difficulty,
                    "reward": q.reward,
                    "emissions": q.emissions
                })
        return quest_list


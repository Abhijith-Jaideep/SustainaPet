import pytest
from src.services.handle_quest_completion import HandleQuestCompletion

from src.models import db
from src.models.user_quests import UserQuests



def test_increase_reward_initial(app,sample_data):
    '''
    input: user_quest_id(where user has completed), user_id
    output: user.carbon_points
    '''
    with app.app_context():
        rd = HandleQuestCompletion()
        result = rd.increase_reward(user_id=1)
        # it will return an objective result 
        # quest_id=101: 15 +120 but the quest has not been completed yet
        assert result.carbon_points == 120

def test_increase_reward_second(app,sample_data):
    '''
    input: user_quest_id(where user has completed), user_id
    output: user.carbon_points
    '''
    with app.app_context():
        rd = HandleQuestCompletion()
        result = rd.increase_reward(user_id=2)
        # it will return an objective result 
        # quest_id=101: 15 +120 but the quest has not been completed yet
        assert result.carbon_points == 115

def test_improve_pet_mood(app,sample_data):
    '''
    input: user_quest_id(where user has completed), user_id
    output: user.eco_pet_mood
    '''
    with app.app_context():
        rd = HandleQuestCompletion()
        result = rd.improve_pet_mood(user_id=2)
        print("eco_pet_mood after improvement:", result.eco_pet_mood)

        completed = db.session.query(UserQuests).filter_by(user_id=2, is_completed=True).all()
        print("Completed quests:", completed)
        assert result.eco_pet_mood == 31

    
import pytest
from src.services.re_roll_quest import ReRollQuest

def test_set_excluded_quest(app,sample_data):
    rq = ReRollQuest()
    result = rq.set_excluded_quest(user_id=1,user_quest_id=301)
    assert result.is_active == False

def test_re_allocate_quest(app,sample_data):
    rq = ReRollQuest()
    result = rq.re_allocate_quest(user_id=1,quest_id=102)
    assert result.quest_id != 101 # result is an object of user_quest



import pytest
from src.services.update_quest import UpdateQuest

def test_set_life_cycle():
    uq = UpdateQuest()
    result = uq.set_life_cycle()

def test_select_archieve_events(app, sample_data):  
    with app.app_context():
        uq = UpdateQuest()
        result = uq.select_archieve_events(life_cycle=7)
        print(result)
        assert any(e.event_id == 201 for e in result)
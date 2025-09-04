import pytest
from src.services.print_completion import PrintCompletion

def test_display_completion(app, sample_data):
    '''
        input: user_quest_id
        uq1 = UserQuests(user_quest_id=301, user_id=1, quest_id=101, event_id=201,
                     is_active=True, is_completed=False, completed_data=None)
        output: is_completed = False
    '''
    with app.app_context():
        uq = PrintCompletion()
        result = uq.display_completion(user_quest_id=301)
        assert result == False

def test_set_completion(app,sample_data):
    with app.app_context():
        uq = PrintCompletion()
        result = uq.set_completion(user_quest_id =301)
        assert result.is_completed == True
        
def test_display_completion_emissions(app,sample_data):
    '''
    input: user_quest_id
    uq1 = UserQuests(user_quest_id=301, user_id=1, quest_id=101, event_id=201,
                     is_active=True, is_completed=False, completed_data=None) 
    output: e1.emissions
    e1 = Event(event_id=201, user_id=1, user_quest_id=301, receipt_id=None, trip_id=401, 
               type="Trip", emissions=12.5, date_time=datetime.now() - timedelta(days=10))
    '''
    with app.app_context():
        uq = PrintCompletion()
        result = uq.display_completion_emissions(user_quest_id=301)
        assert result == 12.5
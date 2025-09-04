import pytest
from src.services.allocate_quest import QuestAllocation

def test_create_quest_collection(app,sample_data):
    qa =QuestAllocation()
    result = qa.create_quest_collection()
    assert result is not None
    
def test_display_quest(app,sample_data):
    qa =QuestAllocation()
    result = qa.display_quest()
from flask import Flask
from src import create_app
from src.models import db
from src.models.quest import Quest
from src.services.allocate_quest import QuestAllocation
from src.config import TestingConfig
from src.models.user import User

app = Flask(__name__)
app.config.from_object(TestingConfig) 

app = create_app("testing")

with app.app_context():
    db.create_all() 

    # test the function:create_quest_collection
    # from src.services.allocate_quest import create_quest_collection

    #insert rows
    r1_quest = Quest(quest_id=101,description="go to Melbourne CBD by bus",difficulty="Easy",reward=15,emissions=33.22)
    r2_quest = Quest(quest_id=102,description="collect all plastic rubbish in Clayton",difficulty="Medium",reward=50,emissions=54.18)
    r3_quest = Quest(quest_id=103,description="invite 25 people to bring food in reusable containers",difficulty="Hard",reward=90,emissions=79.13)
    r4_quest = Quest(quest_id=104,description="donate at least 2 items that no longer need to children in need",difficulty="Medium",reward=55,emissions=39.97)
    db.session.add_all([r1_quest, r2_quest, r3_quest, r4_quest])
    db.session.commit()

    qa = QuestAllocation()
    allocate_quest_test1 = qa.create_quest_collection()
    print(allocate_quest_test1)
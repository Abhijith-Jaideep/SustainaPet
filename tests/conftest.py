from asyncio import Event
from datetime import datetime, timedelta
import pytest
from src.models.trip import Trip
from src.models.average_australia_carbon_emissions import AverageAustralianCarbonEmissions
from src.models.food_emissions import FoodEmissions
from src.models.grocery_receipt import GroceryReceipt
from src.models.receipt_items import ReceiptItems
from src.models.transport_emissions import TransportEmissions
from src.models.user_quests import UserQuests
from src import create_app, db
from src.models.user import User
from src.models.quest import Quest
from src.models.event import Event
from src.services.allocate_quest import QuestAllocation



print("conftest.py is loaded") 

@pytest.fixture
def app():
    app = create_app("testing")
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()

@pytest.fixture
def client(app):
    return app.test_client()

@pytest.fixture
def sample_data(app):
    r1 = Quest(quest_id=101, description="go to Melbourne CBD by bus", difficulty="Easy", reward=15, emissions=33.22)
    r2 = Quest(quest_id=102, description="collect all plastic rubbish in Clayton", difficulty="Medium", reward=50, emissions=54.18)
    r3 = Quest(quest_id=103, description="invite 25 people...", difficulty="Hard", reward=90, emissions=79.13)
    r4 = Quest(quest_id=104, description="donate items...", difficulty="Medium", reward=55, emissions=39.97)

    u1 = User(user_id=1, name="Alice", eco_pet_mood=2, carbon_points=120)
    u2 = User(user_id=2, name="Bob", eco_pet_mood=1, carbon_points=60)

    e1 = Event(event_id=201, user_id=1, user_quest_id=301, receipt_id=None, trip_id=401, 
               type="Trip", emissions=12.5, date_time=datetime.now() - timedelta(days=10))
    e2 = Event(event_id=202, user_id=2, user_quest_id=None, receipt_id=501, trip_id=None, 
               type="Grocery", emissions=8.9, date_time=datetime.now() - timedelta(days=2))
    #new
    e3 = Event(event_id=203, user_id=1,user_quest_id=302,receipt_id=None,trip_id=None,type="Grocery",emissions=8.9,date_time=datetime.now() - timedelta(days=2))

    t1 = Trip(trip_id=401, user_id=1, mode="Bus", event_id=201,
              trip_date=datetime.now() - timedelta(days=10), duration=timedelta(hours=0, minutes=45, seconds=0), emissions=12.5)

    g1 = GroceryReceipt(receipt_id=501, user_id=2, event_id=202, 
                        total_emissions=8.9,  date=datetime.now() - timedelta(days=2))

    f1 = FoodEmissions(food_id=601, food_description="Beef", carbon_emissions_per_kg=27.0)
    f2 = FoodEmissions(food_id=602, food_description="Chicken", carbon_emissions_per_kg=6.9)

    ri1 = ReceiptItems(receipt_item_id=701, receipt_id=501, food_id=601, weight=0.5, item_carbon_emissions=13.5)
    ri2 = ReceiptItems(receipt_item_id=702, receipt_id=501, food_id=602, weight=1.2, item_carbon_emissions=8.28)

    uq1 = UserQuests(user_quest_id=301, user_id=1, quest_id=101, event_id=201,
                     is_active=True, is_completed=False, completed_data=None)
    #new
    uq2 = UserQuests(user_quest_id=302, user_id=2, quest_id=104,event_id=203,is_active=True,is_completed=True,completed_data= None)

    te1 = TransportEmissions(mode="Bus", emissions_per_km=0.08)
    te2 = TransportEmissions(mode="Car", emissions_per_km=0.21)

    avg1 = AverageAustralianCarbonEmissions(year="2023", weekly_emissions=320.5)

    db.session.add_all([r1, r2, r3, r4, u1, u2, e1, e2,e3, t1, g1, f1, f2, ri1, ri2, uq1,uq2, te1, te2, avg1])
    db.session.commit()
    print("fixture executed")
    return [r1, r2, r3, r4]
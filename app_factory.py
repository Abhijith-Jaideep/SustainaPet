from flask import Flask
from src.models import db
from src.models.user import User
from src.models.user_quests import UserQuests
from src.models.grocery_receipt import GroceryReceipt  # <-- 先导入
from src.models.food_emissions import FoodEmissions
from src.models.receipt_items import ReceiptItems
from src.models.event import Event  # <-- 再导入
from src.models.quest import Quest
from src.models.trip import Trip
from src.models.transport_emissions import TransportEmissions

from src.config import DevelopmentConfig, TestingConfig, ProductionConfig

config_dict = {
    "development": DevelopmentConfig,
    "testing": TestingConfig,
    "production": ProductionConfig
}

def create_app(config_name="development"):
    app = Flask(__name__)
    app.config.from_object(config_dict[config_name])
    db.init_app(app)
    with app.app_context():
        db.create_all()
    return app
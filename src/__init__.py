from flask import Flask
from src.models import db
from src.config import DevelopmentConfig, TestingConfig, ProductionConfig
from .models.user_quests import UserQuests
from .models.quest import Quest
from .models.trip import Trip

def create_app(config_name="development"):
    app = Flask(__name__)

    if config_name == "development":
        app.config.from_object(DevelopmentConfig)
    elif config_name == "testing":
         app.config.from_object(TestingConfig)
    elif config_name == "production":
        app.config.from_object(ProductionConfig)
    else:
        raise ValueError("Invalid config name")

    db.init_app(app)

    return app
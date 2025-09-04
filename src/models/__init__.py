from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import Enum, create_engine, text


event_type_enum = Enum("Trip", "Grocery", "Quest", name="event_type_enum")
quest_difficulty_enum = Enum("Easy", "Medium", "Hard", name="quest_difficulty_enum")
transport_mode_enum = Enum(
    "Train", "Bus", "Tram", "Bicycle", "Self-Driving", 
    "Automobile", "Airplane", "Other", name="transport_mode_enum"
)
transport_mode_enum = Enum(
    "Train", "Bus", "Tram", "Bicycle", "Self-Driving",
    "Automobile", "Airplane", "Other",
    name="transport_mode_enum"
)

db = SQLAlchemy()

DB_USER = "pawprint_admin"
DB_PASS = "ecopet5!"
DB_HOST = "ecopawprint.postgres.database.azure.com"
DB_PORT = 5432
DB_NAME = "postgres"  
DATABASE_URL = f"postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}?sslmode=require"

# engine = create_engine(DATABASE_URL, future=True)
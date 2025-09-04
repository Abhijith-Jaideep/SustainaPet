# from src import create_app, db
# from src.models.quest import Quest
# from src.models.transport_emissions import TransportEmissions
# from src.models.food_emissions import FoodEmissions
# from src.models.average_australia_carbon_emissions import AverageAustralianCarbonEmissions
# from src.models.receipt_items import ReceiptItems
# from src.models.grocery_receipt import GroceryReceipt
# from src.models.trip import Trip
# from src.models.user_quests import UserQuests
# from src.models.user import User
# from src.models.event import Event



# app = create_app("development")

# if __name__ == "__main__":
#     with app.app_context():
#         db.create_all()  
#     app.run(debug=True)

from app_factory import create_app

app = create_app("development")

if __name__ == "__main__":
    app.run(debug=True)
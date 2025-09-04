# # test_db.py
# from src.models.quest import Quest
# from main import create_app, db

# app = create_app()  # 根据你想用的配置切换环境
# with app.app_context():
#     quests = Quest.query.all()
#     print("Quests in DB:", quests)
from main import create_app, db
from src.models.quest import Quest

app = create_app()
with app.app_context():
    db.create_all()  
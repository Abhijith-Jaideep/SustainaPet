# from flask import Flask
# from src.models import db
# from src.config import DevelopmentConfig, TestingConfig, ProductionConfig
# from .models.user_quests import UserQuests
# from .models.quest import Quest
# from .models.trip import Trip

# def create_app(config_name="development"):
#     app = Flask(__name__)

#     # 根据传入的 config_name 选择不同的环境配置
#     if config_name == "development":
#         app.config.from_object(DevelopmentConfig)
#     elif config_name == "testing":
#         app.config.from_object(TestingConfig)
#     elif config_name == "production":
#         app.config.from_object(ProductionConfig)
#     else:
#         raise ValueError("Invalid config name")

#     # 初始化数据库
#     db.init_app(app)

#     # 注册蓝图
#     app.register_blueprint(quest_bp, url_prefix="/api/quest")
#     # 如果有其他 Blueprint，也在这里注册
#     # app.register_blueprint(quest_completion_bp, url_prefix="/api/completion")
#     # app.register_blueprint(quest_reward_bp, url_prefix="/api/reward")

#     return app
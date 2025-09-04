from flask import Flask
from src.models import db
from src.controllers.quest_allocation import quest_bp
# 如果你还有其他 Blueprint，比如 quest_completion、quest_reward
# from src.controllers.quest_completion import quest_completion_bp
# from src.controllers.quest_reward import quest_reward_bp

def create_app():
    app = Flask(__name__)

    # 配置数据库
    app.config['SQLALCHEMY_DATABASE_URI'] = (
    "postgresql+psycopg2://pawprint_admin:ecopet5!@ecopawprint.postgres.database.azure.com:5432/postgres?sslmode=require") # 替换为你的数据库
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # 初始化数据库
    db.init_app(app)

    # 注册 Blueprint
    app.register_blueprint(quest_bp, url_prefix='/api')
    # app.register_blueprint(quest_completion_bp, url_prefix='/api')
    # app.register_blueprint(quest_reward_bp, url_prefix='/api')

    return app

if __name__ == "__main__":
    app = create_app()
    with app.app_context():
        db.create_all()  # 如果表不存在就创建
    app.run(debug=True, host='0.0.0.0', port=5000)
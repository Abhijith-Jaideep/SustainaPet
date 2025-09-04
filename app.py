from flask import Flask
from src.models import db
from src.controllers.quest_allocation import quest_bp

from src import create_app

app = create_app(config_name="development")

if __name__ == "__main__":
    # 启动 Flask 服务
    app.run(host="0.0.0.0", port=5000, debug=True)
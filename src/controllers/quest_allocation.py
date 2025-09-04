from flask import Blueprint, jsonify
from src.services.allocate_quest import QuestAllocation

quest_bp = Blueprint("quest", __name__)
qa = QuestAllocation()

@quest_bp.route('/quests/weekly', methods=['GET'])
def get_weekly_quests():
    qa.create_quest_collection()  # 创建本周任务
    quests = qa.display_quest()   # 获取任务信息
    print("Weekly quests:", quests)
    return jsonify({
        "week_start": "Saturday midnight",  # 可以后续动态计算
        "quests": quests
    })
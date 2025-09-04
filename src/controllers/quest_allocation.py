from flask import Blueprint, jsonify
from src.services.allocate_quest import QuestAllocation

quest_bp = Blueprint("quest", __name__)
qa = QuestAllocation()

@quest_bp.route("/quests/weekly", methods=["GET"])
def get_weekly_quests():
    """
    frontend request the weekly quest
    """
    qa.create_quest_collection()  # create new quest of this week
    quests = qa.display_quest()   # return format
    return jsonify({
        "week_start": "Saturday midnight",  # calculate based on real date
        "quests": quests
    })
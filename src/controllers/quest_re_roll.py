from flask import Blueprint, request, jsonify
from src.services.re_roll_quest import ReRollQuest

reroll_bp = Blueprint("reroll", __name__)
rrq = ReRollQuest()


@reroll_bp.route("/quest/<int:user_id>/<int:user_quest_id>/refresh", methods=["POST"])
def refresh_quest(user_id, user_quest_id):
    """
    user click the refresh button：
    1. set the quest to inactive
    2. rellocate a new quest to the user
    """
    # 1️⃣ set original quest as inactive
    old_quest = rrq.set_excluded_quest(user_id, user_quest_id)
    if not old_quest:
        return jsonify({"error": "UserQuest not found"}), 404

    # 2️⃣ rellocate the new quest
    # Assuming the frontend passes the new quest_id through request.json
    data = request.get_json()
    new_quest_id = data.get("quest_id")
    if not new_quest_id:
        return jsonify({"error": "New quest_id is required"}), 400

    new_quest = rrq.re_allocate_quest(user_id, new_quest_id)
    if not new_quest:
        return jsonify({"error": "Failed to assign new quest"}), 400

    # return the information of new quest
    return jsonify({
        "message": "Quest refreshed successfully",
        "old_quest_id": user_quest_id,
        "new_quest_id": new_quest.quest_id,
        "user_id": user_id
    })

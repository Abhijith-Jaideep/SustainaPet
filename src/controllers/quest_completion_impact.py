from flask import Blueprint, request, jsonify
from src.services.print_completion import PrintCompletion  # import the service

completion_bp = Blueprint("completion", __name__)
pc = PrintCompletion()


@completion_bp.route("/quest/<int:user_quest_id>/confirm", methods=["GET"])
def confirm_completion(user_quest_id):
    is_completed = pc.display_completion(user_quest_id)
    return jsonify({
        "user_quest_id": user_quest_id,
        "completed": bool(is_completed)
    })


@completion_bp.route("/quest/<int:user_quest_id>/complete", methods=["POST"])
def complete_quest(user_quest_id):
    completed_quest = pc.set_completion(user_quest_id)
    if not completed_quest:
        return jsonify({"error": "Quest not found"}), 404

    emissions = pc.display_completion_emissions(user_quest_id) or 0

    quest_info = {
        "quest_id": completed_quest.quest_id,
        "description": completed_quest.quest.description if hasattr(completed_quest, "quest") else "",
        "reward": completed_quest.quest.reward if hasattr(completed_quest, "quest") else 0,
        "difficulty": completed_quest.quest.difficulty if hasattr(completed_quest, "quest") else "",
        "emissions": emissions
    }

    return jsonify({
        "message": "Quest completed successfully",
        "user_quest_id": user_quest_id,
        "quest": quest_info
    })
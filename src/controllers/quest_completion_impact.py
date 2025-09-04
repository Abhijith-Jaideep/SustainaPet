from flask import Blueprint, request, jsonify
from src.services.print_completion import PrintCompletion  # import the service

quest_bp = Blueprint("quest", __name__)
pc = PrintCompletion()


@quest_bp.route("/quest/<int:user_quest_id>/confirm", methods=["GET"])
def confirm_completion(user_quest_id):
    """
    When the user clicks the Complete button, return whether it is completed or not.
    """
    is_completed = pc.display_completion(user_quest_id)
    return jsonify({
        "user_quest_id": user_quest_id,
        "already_completed": bool(is_completed)
    })


@quest_bp.route("/quest/<int:user_quest_id>/complete", methods=["POST"])
def complete_quest(user_quest_id):
    """
    after user click Yes, and after Complete :
    1. set quest completion
    2. return CO2 emissions
    """
    completed_quest = pc.set_completion(user_quest_id)
    if not completed_quest:
        return jsonify({"error": "Quest not found"}), 404

    emissions = pc.display_completion_emissions(user_quest_id)

    return jsonify({
        "message": "Quest completed successfully",
        "user_quest_id": user_quest_id,
        "quest_id": completed_quest.quest_id,
        "emissions": emissions
    })
from flask import Blueprint, request, jsonify
from src.services.handle_quest_completion import HandleQuestCompletion
from src.models.user_quests import UserQuests

# create Blueprint
quest_bp = Blueprint("quest", __name__)
hc = HandleQuestCompletion()


@quest_bp.route("/quest/<int:user_quest_id>/complete", methods=["POST"])
def complete_quest(user_quest_id):
    """
    User clicks to complete the task: 
    1. Mark user_quest as completed 
    2. Update carbon_points based on quest rewards 
    3. Update eco_pet_mood based on quest difficulty 
    4. Return the updated user information to the front end.
    """
    # Query the corresponding user for UserQuest
    user_quest = UserQuests.query.filter_by(user_quest_id=user_quest_id).first()
    if not user_quest:
        return jsonify({"error": "UserQuest not found"}), 404

    user_id = user_quest.user_id

    # Mark task as completed
    user_quest.is_completed = True
    # Submit transaction (optional, can also be submitted uniformly in increase_reward and improve_pet_mood)
    from src.models import db
    db.session.commit()

    # Call the service to update carbon_points and eco_pet_mood.
    updated_user = hc.increase_reward(user_id)
    updated_user = hc.improve_pet_mood(user_id)

    return jsonify({
        "message": "Quest completed successfully",
        "user_id": user_id,
        "carbon_points": updated_user.carbon_points,
        "eco_pet_mood": updated_user.eco_pet_mood
    })
from flask import Blueprint, jsonify, request
from src.models.user import User

home_bp = Blueprint("home", __name__)

@home_bp.route("/user/<int:user_id>/carbon_points", methods=["GET"])
def get_carbon_points(user_id):
    """
    return the user's current carbon points
    """
    user = User.query.filter_by(user_id=user_id).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    return jsonify({
        "user_id": user.user_id,
        "carbon_points": user.carbon_points
    })
from flask import Flask, request, jsonify
from src.models import db, User

app = Flask(__name__)
db.init_app(app)

@app.route("/register", methods=["POST"])
def register():
    data = request.get_json()
    name = data.get("name")
    mood = data.get("ecopetmood")       
    carbonpoint = data.get("carbonpoint")  

    if not name:
        return jsonify({"error": "Name is required"}), 400

    new_user = User(
        name=name,
        ecopetmood=mood,
        carbonpoint=carbonpoint or 0
    )
    db.session.add(new_user)
    db.session.commit()

    return jsonify({
        "message": "User registered",
        "user_id": str(new_user.user_id),
        "ecopetmood": new_user.ecopetmood,
        "carbonpoint": new_user.carbonpoint
    }), 201

@app.route("/login", methods=["POST"])
def login():
    data = request.get_json()
    user_id = data.get("user_id")
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400

    user = User.query.filter_by(user_id=user_id).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    return jsonify({
        "message": f"Logged in as {user.name}",
        "user_id": str(user.user_id),
        "ecopetmood": user.ecopetmood,
        "carbonpoint": user.carbonpoint
    }), 200
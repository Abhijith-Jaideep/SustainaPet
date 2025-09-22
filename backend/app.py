# backend/app.py
import base64
from flask import Flask, Blueprint, jsonify, request, abort
from flask_cors import CORS
from datetime import datetime
import requests
from sqlalchemy import select, func, cast, Integer,create_engine
import os
import pandas as pd
from backend.emissions_models.ItemToDataset import map_receipt_with_emissions, items_index, cat_index
from backend.receipt_update.receipt_parser import parse_items_only_from_lines

from backend.emissions_models.ItemToDataset import build_category_index, build_index_from_emissions, map_receipt_with_emissions

from .db import SessionLocal
from .models import User, Quest, UserQuest, Event, EmissionConversionSaving, GroceryReceipt
from flask_sqlalchemy import SQLAlchemy
from backend.emissions_models.item_info import map_receipt 
from backend.receipt_update.receipt_parser import extract_items_from_bytes
import base64, re
from io import BytesIO
from PIL import Image

db = SQLAlchemy()

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})  # relax as needed for dev
api = Blueprint("api", __name__, url_prefix="/api")

with SessionLocal() as session:
    # Use the existing session connection for pandas
    conn = session.connection()

    df_emissions = pd.read_sql('SELECT * FROM pawprint."FoodEmissions";', conn)
    df_category_emissions = pd.read_sql('SELECT * FROM pawprint."CategoryEmissions";', conn)


# ---- configuration ----
# If a quest has NO explicit emissions value, we convert points -> CO2e saved:
# event(type="Points", emissions = -(POINT_KG_PER_POINT * reward))
POINT_KG_PER_POINT = float(os.environ.get("POINT_KG_PER_POINT", "0.05"))  # kg per point


# ---------- helpers ----------
def as_user_dict(u: User):
    return {
        "userid": u.userid,
        "name": u.name,
        "ecopetmood": u.ecopetmood,
        "carbonpoints": u.carbonpoints,
    }

def as_quest_dict(q: Quest):
    return {
        "questid": q.questid,
        "description": q.description,
        "difficulty": q.difficulty,
        "reward": q.reward,
        "emissions": q.emissions,
    }

def as_userquest_dict(uq: UserQuest):
    return {
        "userquestid": uq.userquestid,
        "userid": uq.userid,
        "questid": uq.questid,
        "isactive": uq.isactive,
        "iscompleted": uq.iscompleted,
        "completeddate": uq.completeddate.isoformat() if uq.completeddate else None,
    }

def as_event_dict(ev: Event):
    return {
        "eventid": ev.eventid,
        "userid": ev.userid,
        "userquestid": ev.userquestid,
        "receiptid": ev.receiptid,
        "tripid": ev.tripid,
        "description": ev.description,
        "type": ev.type,
        "emissions": ev.emissions,
        "datetime": ev.datetime.isoformat() if ev.datetime else None,
    }

def as_groceryreceipt_dict(gr: GroceryReceipt):
    return {
        "receiptid": gr.receiptid,
        "userid": gr.userid,
        "totalemissions": gr.totalemissions,
        "date": gr.date.isoformat() if gr.date else None,
    }

def _month_bounds(year: int, month: int):
    """Return [start, end) datetimes for a calendar month."""
    start = datetime(year, month, 1)
    if month == 12:
        end = datetime(year + 1, 1, 1)
    else:
        end = datetime(year, month + 1, 1)
    return start, end


# ---------- misc / health ----------
@api.get("/ping")
def ping():
    return jsonify({"ok": True, "point_kg_per_point": POINT_KG_PER_POINT})


# ---------- Users ----------
@api.get("/users")
def list_users():
    session = SessionLocal()
    try:
        rows = session.execute(select(User).order_by(User.userid)).scalars().all()
        return jsonify([as_user_dict(u) for u in rows])
    finally:
        session.close()

@api.get("/users/<int:userid>")
def get_user(userid):
    session = SessionLocal()
    try:
        u = session.get(User, userid)
        if not u:
            abort(404, description="User not found")
        return jsonify(as_user_dict(u))
    finally:
        session.close()

@api.post("/users")
def create_user():
    data = request.get_json(force=True)
    name = (data.get("name") or "").strip()
    if not name or len(name) > 16:
        abort(400, description="name is required and must be <= 16 chars")

    session = SessionLocal()
    try:
        u = User(name=name, ecopetmood=0, carbonpoints=0)
        session.add(u)
        session.commit()
        session.refresh(u)
        return jsonify(as_user_dict(u)), 201
    finally:
        session.close()

@api.patch("/users/<int:userid>")
def update_user(userid):
    data = request.get_json(force=True)
    session = SessionLocal()
    try:
        u = session.get(User, userid)
        if not u:
            abort(404, description="User not found")

        if "name" in data:
            name = (data["name"] or "").strip()
            if not name or len(name) > 16:
                abort(400, description="name must be non-empty and <= 16 chars")
            u.name = name

        if "ecopetmood" in data:
            mood = int(data["ecopetmood"])
            if mood < 0 or mood > 100:
                abort(400, description="ecopetmood must be 0..100")
            u.ecopetmood = mood

        if "carbonpoints" in data:
            pts = int(data["carbonpoints"])
            if pts < 0:
                abort(400, description="carbonpoints must be >= 0")
            u.carbonpoints = pts

        session.commit()
        return jsonify(as_user_dict(u))
    finally:
        session.close()

@api.get("/users/<int:userid>/userquests")
def list_userquests(userid):
    """
    Query params:
      - status: 'active' (default), 'completed', or 'all'
    Returns userquests joined with quest details.
    """
    status = (request.args.get("status") or "active").lower().strip()
    session = SessionLocal()
    try:
        u = session.get(User, userid)
        if not u:
            abort(404, description="User not found")

        stmt = (
            select(UserQuest, Quest)
            .join(Quest, Quest.questid == UserQuest.questid)
            .where(UserQuest.userid == userid)
            .order_by(UserQuest.userquestid.desc())
        )

        if status == "active":
            stmt = stmt.where(UserQuest.isactive == True, UserQuest.iscompleted == False)
        elif status == "completed":
            stmt = stmt.where(UserQuest.iscompleted == True)
        elif status == "all":
            pass
        else:
            abort(400, description="status must be active|completed|all")

        rows = session.execute(stmt).all()
        data = []
        for uq, q in rows:
            data.append({
                "userquestid": uq.userquestid,
                "userid": uq.userid,
                "questid": uq.questid,
                "isactive": bool(uq.isactive),
                "iscompleted": bool(uq.iscompleted),
                "completeddate": uq.completeddate.isoformat() if uq.completeddate else None,
                "quest": as_quest_dict(q),  # includes description/difficulty/reward/emissions
            })
        return jsonify(data)
    finally:
        session.close()


# ---------- Quests ----------
@api.get("/quests")
def list_quests():
    difficulty = request.args.get("difficulty")  # Easy/Medium/Hard
    limit = int(request.args.get("limit", 50))
    session = SessionLocal()
    try:
        stmt = select(Quest)
        if difficulty:
            stmt = stmt.where(Quest.difficulty == difficulty)
        stmt = stmt.order_by(Quest.questid).limit(limit)
        rows = session.execute(stmt).scalars().all()
        return jsonify([as_quest_dict(q) for q in rows])
    finally:
        session.close()

# Assign specific quests
@api.post("/users/<int:userid>/quests")
def assign_quests(userid):
    """
    Body: {"questids": [1,2,3]}
    Creates userquests (isactive=true, iscompleted=false)
    """
    data = request.get_json(force=True)
    questids = list({int(q) for q in data.get("questids", [])})
    if not questids:
        abort(400, description="questids required")

    session = SessionLocal()
    try:
        if not session.get(User, userid):
            abort(404, description="User not found")

        # Ensure quests exist
        existing_qids = set(q.questid for q in session.execute(
            select(Quest).where(Quest.questid.in_(questids))
        ).scalars().all())
        missing = set(questids) - existing_qids
        if missing:
            abort(400, description=f"Unknown questids: {sorted(missing)}")

        # Insert userquests
        created = []
        for qid in sorted(existing_qids):
            uq = UserQuest(userid=userid, questid=qid, isactive=True, iscompleted=False)
            session.add(uq)
            created.append(uq)

        session.commit()
        return jsonify([as_userquest_dict(uq) for uq in created]), 201
    finally:
        session.close()

# Assign random quests (NEW)
@api.post("/users/<int:userid>/quests/assign_random")
def assign_random_quests(userid):
    """
    Body (JSON):
      {
        "count": 3,                      # optional, default 3
        "difficulty": ["Easy","Medium"]  # optional, filter set
      }

    Picks random quests the user doesn't already have (any status)
    and creates UserQuest rows (isactive=true, iscompleted=false).
    """
    data = request.get_json(silent=True) or {}
    count = int(data.get("count", 3))
    diffs = data.get("difficulty") or []  # list or empty

    if count <= 0:
        abort(400, description="count must be > 0")

    session = SessionLocal()
    try:
        if not session.get(User, userid):
            abort(404, description="User not found")

        # Quest IDs the user already has (active or completed)
        existing_qids = set(
            qid for (qid,) in session.execute(
                select(UserQuest.questid).where(UserQuest.userid == userid)
            ).all()
        )

        # Base query: quests not already in user's set
        q = select(Quest).where(~Quest.questid.in_(existing_qids))
        if diffs:
            q = q.where(Quest.difficulty.in_(diffs))

        # Random order (func.random for SQLite/Postgres; for MySQL use func.rand())
        q = q.order_by(func.random()).limit(count)

        picks = session.execute(q).scalars().all()
        if not picks:
            return jsonify({"created": [], "note": "no quests available to assign"}), 200

        created = []
        for quest in picks:
            uq = UserQuest(
                userid=userid,
                questid=quest.questid,
                isactive=True,
                iscompleted=False,
            )
            session.add(uq)
            created.append(uq)

        session.commit()
        return jsonify([as_userquest_dict(uq) for uq in created]), 201
    finally:
        session.close()


# ---------- Complete a userquest (creates event, updates points/mood) ----------
@api.post("/userquests/<int:userquestid>/complete")
def complete_userquest(userquestid):
    """
    Body (optional): {"completeddate": "2025-09-01T10:00:00", "mood_delta": 5}
    - Sets iscompleted=true, completeddate=now() or provided
    - Creates an Event with type='Quest' if quest.emissions provided (could be pos/neg)
    - If quest has NO emissions, creates Event type='Points' with emissions
      = -(POINT_KG_PER_POINT * reward)  (treated as CO₂ saved)
    - Increments user's carbonpoints by quest.reward
    - Adjusts user's ecopetmood by mood_delta (default +5), clamped to [0,100]
    Transactional.
    """
    data = request.get_json(silent=True) or {}
    when = data.get("completeddate")
    mood_delta = int(data.get("mood_delta", 10))

    session = SessionLocal()
    try:
        uq = session.get(UserQuest, userquestid)
        if not uq:
            abort(404, description="UserQuest not found")

        if uq.iscompleted:
            abort(409, description="UserQuest already completed")

        u = session.get(User, uq.userid)
        q = session.get(Quest, uq.questid)
        if not (u and q):
            abort(400, description="User or Quest missing")

        # Update UserQuest
        uq.iscompleted = True
        uq.completeddate = datetime.fromisoformat(when) if when else datetime.utcnow()

        # Create appropriate event(s)
        if q.emissions is not None and float(q.emissions) != 0.0:
            # Use explicit quest emissions
            ev = Event(
                userid=u.userid,
                userquestid=uq.userquestid,
                description=f"Completed quest: {q.description}",
                type="Quest",
                emissions=float(q.emissions),
                datetime=uq.completeddate,
            )
            session.add(ev)
        else:
            # Convert points -> CO2e saved
            if POINT_KG_PER_POINT > 0 and (q.reward or 0) > 0:
                ev_points = Event(
                    userid=u.userid,
                    userquestid=uq.userquestid,
                    description=f"Points conversion for quest: {q.description}",
                    type="Points",
                    emissions=-(POINT_KG_PER_POINT * float(q.reward or 0)),
                    datetime=uq.completeddate,
                )
                session.add(ev_points)

        # Update User
        u.carbonpoints = max(0, (u.carbonpoints or 0) + (q.reward or 0))
        new_mood = (u.ecopetmood or 0) + mood_delta
        u.ecopetmood = min(100, max(0, new_mood))

        session.commit()
        return jsonify({
            "userquest": as_userquest_dict(uq),
            "user": as_user_dict(u),
            "point_kg_per_point": POINT_KG_PER_POINT,
        })
    finally:
        session.close()


# ---------- Events ----------
@api.get("/users/<int:userid>/events")
def user_events(userid):
    limit = int(request.args.get("limit", 50))
    session = SessionLocal()
    try:
        if not session.get(User, userid):
            abort(404, description="User not found")
        rows = session.execute(
            select(Event).where(Event.userid == userid).order_by(Event.datetime.desc()).limit(limit)
        ).scalars().all()
        return jsonify([as_event_dict(e) for e in rows])
    finally:
        session.close()


# ---------- Conversions ----------
@api.get("/conversions")
def list_conversions():
    session = SessionLocal()
    try:
        rows = session.execute(
            select(EmissionConversionSaving).order_by(EmissionConversionSaving.metricid)
        ).scalars().all()
        return jsonify([
            {
                "metricid": r.metricid,
                "name": r.name,
                "description": r.description,
                "emissionsperx": r.emissionsperx,
            } for r in rows
        ])
    finally:
        session.close()


# ---------- Dashboard ----------
@api.get("/users/<int:userid>/dashboard")
def user_dashboard(userid):
    session = SessionLocal()
    try:
        u = session.get(User, userid)
        if not u:
            abort(404, description="User not found")

        # counts
        active_count = session.execute(
            select(func.count()).select_from(UserQuest).where(
                UserQuest.userid == userid, UserQuest.isactive == True, UserQuest.iscompleted == False
            )
        ).scalar_one()

        completed_count = session.execute(
            select(func.count()).select_from(UserQuest).where(
                UserQuest.userid == userid, UserQuest.iscompleted == True
            )
        ).scalar_one()

        # total emissions saved from quest events (<=0 values) — NB: Points events
        # are also included in monthly endpoints; this keeps dashboard as-is.
        total_emissions = session.execute(
            select(func.coalesce(func.sum(Event.emissions), 0.0)).where(
                Event.userid == userid, Event.type == "Quest"
            )
        ).scalar_one()

        return jsonify({
            "user": as_user_dict(u),
            "active_quests": int(active_count),
            "completed_quests": int(completed_count),
            "total_emissions_saved": float(total_emissions),  # negative number means "saved"
        })
    finally:
        session.close()


# ---------- Monthly Emissions ----------
@api.get("/users/<int:userid>/emissions/monthly")
def user_monthly_emissions(userid):
    """
    Query params:
      - year (default: current UTC year)
      - month 1..12 (default: current UTC month)

    Returns totals (emitted/saved/net), weekly buckets (1–5), and by-type breakdown.
    """
    now = datetime.utcnow()
    year = int(request.args.get("year", now.year))
    month = int(request.args.get("month", now.month))
    if month < 1 or month > 12:
        abort(400, description="month must be 1..12")

    session = SessionLocal()
    try:
        user = session.get(User, userid)
        if not user:
            abort(404, description="User not found")

        start, end = _month_bounds(year, month)

        # Totals
        total_sum = session.execute(
            select(func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid == userid)
            .where(Event.datetime >= start)
            .where(Event.datetime < end)
        ).scalar_one()

        emitted_pos = session.execute(
            select(func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid == userid)
            .where(Event.datetime >= start)
            .where(Event.datetime < end)
            .where(Event.emissions > 0.0)
        ).scalar_one()

        saved_raw = session.execute(
            select(func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid == userid)
            .where(Event.datetime >= start)
            .where(Event.datetime < end)
            .where(Event.emissions < 0.0)
        ).scalar_one()
        saved_mag = abs(float(saved_raw)) if saved_raw else 0.0

        # Weekly buckets (1–5): floor((day-1)/7)+1
        week_of_month = cast(
            (func.floor((func.extract("day", Event.datetime) - 1) / 7) + 1),
            Integer,
        )
        weekly_rows = session.execute(
            select(
                week_of_month.label("week"),
                func.coalesce(func.sum(Event.emissions), 0.0).label("kg"),
            )
            .where(Event.userid == userid)
            .where(Event.datetime >= start)
            .where(Event.datetime < end)
            .group_by(week_of_month)
            .order_by(week_of_month.asc())
        ).all()
        weekly = [{"week": int(w.week), "kg": float(w.kg)} for w in weekly_rows]

        # By type
        type_rows = session.execute(
            select(
                Event.type.label("type"),
                func.coalesce(func.sum(Event.emissions), 0.0).label("kg"),
            )
            .where(Event.userid == userid)
            .where(Event.datetime >= start)
            .where(Event.datetime < end)
            .group_by(Event.type)
            .order_by(Event.type.asc())
        ).all()
        breakdown = [
            {"type": r.type, "kg": float(r.kg)} for r in type_rows if r.type is not None
        ]

        return jsonify({
            "user": {"userid": user.userid, "name": user.name},
            "period": {
                "year": year,
                "month": month,
                "start": start.date().isoformat(),
                "end": end.date().isoformat(),
            },
            "totals": {
                "emitted_kg": float(emitted_pos),
                "saved_kg": float(saved_mag),
                "net_kg": float(total_sum),  # could be negative if net saving
            },
            "weekly": weekly,
            "breakdown_by_type": breakdown,
        })
    finally:
        session.close()

# ---------- Photo Extraction ----------
@api.post("/users/<int:userid>/emissions/monthly")
def user_photo_info():
    pass


@app.route("/map-receipt", methods=["POST"])
def map_receipt_route():
    receipt_json = request.get_json()    
    
    # call map_receipt_with_emissions
    df_filtered = map_receipt_with_emissions(
    receipt_json, 
    items_index, 
    cat_index, 
    df_emissions, 
    df_category_emissions
    )

    # Compute total emissions
    total_emissions = float(df_filtered["TotalEmissions"].sum())

    # Require userid in request
    user_id = receipt_json.get("userid")
    if not user_id:
        return jsonify({"error": "Missing userid in request"}), 400

    session = SessionLocal()

    # Insert into GroceryReceipt (ORM)
    gr = GroceryReceipt(
        userid=user_id,
        totalemissions=total_emissions,
        date=datetime.utcnow(),
    )
    session.add(gr)
    session.flush()  # ensures receiptid is populated without commit

    # Create linked Event
    ev = Event(
        userid=user_id,
        receiptid=gr.receiptid,  
        description=f"Grocery receipt with {len(df_filtered)} items",
        type="Grocery",   # must exist in event_type_enum
        emissions=total_emissions,
        datetime=datetime.utcnow(),
    )
    session.add(ev)

    session.commit()
    session.close()
    
    return jsonify(df_filtered.to_dict(orient="records"))


receipt_json = None
GOOGLE_KEY_PATH = r"backend\receipt_update\savvy-girder-472600-s1-07e7b3e23118.json"

def _normalize_b64(s: str) -> bytes:
    # Strip data URL prefix if present
    s = re.sub(r'^data:image/[^;]+;base64,', '', s, flags=re.I)
    # Fix URL-safe variants
    s = s.replace('-', '+').replace('_', '/')
    # Fix padding
    pad = (-len(s)) % 4
    if pad:
        s += '=' * pad
    return base64.b64decode(s, validate=False)

@app.route("/receipt-parser", methods=["POST"])
def update_receipt():
    data = request.get_json()
    if not data or "image_base64" not in data:
        return jsonify({"error": "No image_base64 field"}), 400

    try:
        img_bytes = _normalize_b64(data["image_base64"])

        # Sanity check: does PIL accept it as an image?
        with Image.open(BytesIO(img_bytes)) as im:
            im.verify()  # raises if not a valid image

        items_parsed = extract_items_from_bytes(img_bytes, key_path=GOOGLE_KEY_PATH)
        return jsonify({"receipt_json": items_parsed})

    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({"error": f"Parsing failed: {str(e)}"}), 500

# Mount the blueprint
app.register_blueprint(api)

if __name__ == "__main__":
    # Run with: python -m backend.app
    app.run(host="0.0.0.0", port=5000, debug=True)
    CORS(app)
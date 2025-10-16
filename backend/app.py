# backend/app.py
from flask import Flask, Blueprint, jsonify, request, abort
from flask_cors import CORS
from datetime import datetime, timedelta
from pytest import Session
from sqlalchemy import select, func, cast, Integer
import os
# --- add these ---
import re
import base64 as _b64
from io import BytesIO
from PIL import Image, UnidentifiedImageError

import pandas as pd
from emissions_models.ItemToDataset import (
    map_receipt_with_emissions,
    build_index_from_emissions,
    build_category_index,
)

from models import GroceryReceipt


MAX_IMAGE_BYTES = int(os.environ.get("MAX_IMAGE_BYTES", "6000000"))  # ~6 MB

from db import SessionLocal
from models import FriendRequests, Friends, RequestStatusEnum, User, Quest, UserQuest, Event, EmissionConversionSaving
from receipt_update.receipt_parser import extract_items_from_bytes

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})  # relax as needed for dev
api = Blueprint("api", __name__, url_prefix="/api")

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

def _month_bounds(year: int, month: int):
    """Return [start, end) datetimes for a calendar month."""
    start = datetime(year, month, 1)
    if month == 12:
        end = datetime(year + 1, 1, 1)
    else:
        end = datetime(year, month + 1, 1)
    return start, end

# ---- mapping cache (globals) ----
items_index = None
cat_index = None
df_emissions = None
df_category_emissions = None

def _bump_weekly(user: User, delta_kg: float) -> None:
    # no-op stub so route doesn't crash; wire to your counters if you have them
    return

def _ensure_emission_refs_loaded():
    """
    Lazy-load FoodEmissions / CategoryEmissions from the SAME database your app already uses,
    then build indices once and cache them in globals.
    """
    global items_index, cat_index, df_emissions, df_category_emissions
    if items_index is not None and cat_index is not None:
        return

    s = SessionLocal()
    try:
        engine = s.get_bind()

        # Pull only the columns we use
        df_em = pd.read_sql('SELECT "Name","Emissions","Impact" FROM pawprint."FoodEmissions";', engine)
        df_cat = pd.read_sql('SELECT "Category","Emissions","Impact" FROM pawprint."CategoryEmissions";', engine)

        # Clean + numeric
        df_em = df_em[df_em["Name"].notna()].copy()
        df_cat = df_cat[df_cat["Category"].notna()].copy()
        df_em["Emissions"] = pd.to_numeric(df_em["Emissions"], errors="coerce").fillna(0.0)
        df_cat["Emissions"] = pd.to_numeric(df_cat["Emissions"], errors="coerce").fillna(0.0)

        # Build indices using your helper functions
        idx = build_index_from_emissions(df_em, name_col="Name")
        cat = build_category_index(df_cat["Category"].tolist())

        # Publish to globals
        df_emissions = df_em
        df_category_emissions = df_cat
        items_index = idx
        cat_index = cat

        # Rebind to module globals (Python scoping)
        globals()["df_emissions"] = df_emissions
        globals()["df_category_emissions"] = df_category_emissions
        globals()["items_index"] = items_index
        globals()["cat_index"] = cat_index
    finally:
        s.close()

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
        u = User(name=name, ecopetmood=50, carbonpoints=0)
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

# ---------- Single UserQuest + Replace Random ----------

@api.get("/userquests/<int:userquestid>")
def get_userquest(userquestid: int):
    """
    Return one userquest joined with quest details.
    Shape matches list_userquests rows (includes nested 'quest').
    """
    session = SessionLocal()
    try:
        row = session.execute(
            select(UserQuest, Quest)
            .join(Quest, Quest.questid == UserQuest.questid)
            .where(UserQuest.userquestid == userquestid)
        ).first()

        if not row:
            abort(404, description="UserQuest not found")

        uq, q = row
        return jsonify({
            "userquestid": uq.userquestid,
            "userid": uq.userid,
            "questid": uq.questid,
            "isactive": bool(uq.isactive),
            "iscompleted": bool(uq.iscompleted),
            "completeddate": uq.completeddate.isoformat() if uq.completeddate else None,
            "quest": as_quest_dict(q),
        })
    finally:
        session.close()


@api.post("/userquests/<int:userquestid>/replace_random")
def replace_userquest_random(userquestid: int):
    """
    Body (optional):
      {
        "difficulty": ["Easy"]   # or ["Easy","Medium"]; defaults to SAME difficulty as current quest
      }

    Replaces the quest *in-place* on the SAME UserQuest row by switching questid
    to a random quest the user doesn't already have (any status) and that differs
    from the current questid. Returns the updated userquest + nested quest.
    """
    data = request.get_json(silent=True) or {}

    session = SessionLocal()
    try:
        # Load current
        uq = session.get(UserQuest, userquestid)
        if not uq:
            abort(404, description="UserQuest not found")

        cur_q = session.get(Quest, uq.questid)
        if not cur_q:
            abort(400, description="Quest missing for this UserQuest")

        # Determine difficulty filter
        diffs = data.get("difficulty")
        if not diffs:
            # default to current quest difficulty
            diffs = [cur_q.difficulty] if cur_q.difficulty else []

        # Quests already assigned to this user (any status) — avoid duplicates
        existing_qids = set(
            qid for (qid,) in session.execute(
                select(UserQuest.questid).where(UserQuest.userid == uq.userid)
            ).all()
        )

        # Candidate pool: not already owned; not the current quest; honor difficulty if provided
        q = select(Quest).where(~Quest.questid.in_(existing_qids))
        if diffs:
            q = q.where(Quest.difficulty.in_(diffs))
        q = q.order_by(func.random()).limit(1)

        pick = session.execute(q).scalars().first()
        if not pick:
            # If we can't find a totally new quest, relax the "not already owned" constraint
            # but still avoid replacing with the same questid.
            q2 = select(Quest).where(Quest.questid != uq.questid)
            if diffs:
                q2 = q2.where(Quest.difficulty.in_(diffs))
            q2 = q2.order_by(func.random()).limit(1)
            pick = session.execute(q2).scalars().first()

        if not pick:
            abort(409, description="No alternative quest available for replacement")

        # Replace IN-PLACE: keep same userquestid, swap questid, keep active & not completed
        uq.questid = pick.questid
        uq.isactive = True
        uq.iscompleted = False
        uq.completeddate = None

        session.commit()
        session.refresh(uq)

        # Join to return nested quest details
        q_pick = session.get(Quest, uq.questid)
        return jsonify({
            "userquestid": uq.userquestid,
            "userid": uq.userid,
            "questid": uq.questid,
            "isactive": bool(uq.isactive),
            "iscompleted": bool(uq.iscompleted),
            "completeddate": uq.completeddate.isoformat() if uq.completeddate else None,
            "quest": as_quest_dict(q_pick),
        })

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
    mood_delta = int(data.get("mood_delta", 5))

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
    now = datetime.utcnow()
    year = int(request.args.get("year", now.year))
    month = int(request.args.get("month", now.month))
    if month < 1 or month > 12: abort(400, description="month must be 1..12")

    session = SessionLocal()
    try:
        user = session.get(User, userid)
        if not user: abort(404, description="User not found")
        start, end = _month_bounds(year, month)

        total_sum = session.execute(select(func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid == userid, Event.datetime >= start, Event.datetime < end)).scalar_one()
        emitted_pos = session.execute(select(func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid == userid, Event.datetime >= start, Event.datetime < end, Event.emissions > 0.0)).scalar_one()
        saved_raw = session.execute(select(func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid == userid, Event.datetime >= start, Event.datetime < end, Event.emissions < 0.0)).scalar_one()
        saved_mag = abs(float(saved_raw)) if saved_raw else 0.0

        week_of_month = cast((func.floor((func.extract("day", Event.datetime) - 1) / 7) + 1), Integer)
        weekly_rows = session.execute(select(
            week_of_month.label("week"),
            func.coalesce(func.sum(Event.emissions), 0.0).label("kg"),
        ).where(Event.userid == userid, Event.datetime >= start, Event.datetime < end)
         .group_by(week_of_month).order_by(week_of_month.asc())).all()
        weekly = [{"week": int(w.week), "kg": float(w.kg)} for w in weekly_rows]

        type_rows = session.execute(select(Event.type.label("type"), func.coalesce(func.sum(Event.emissions), 0.0).label("kg"))
            .where(Event.userid == userid, Event.datetime >= start, Event.datetime < end)
            .group_by(Event.type).order_by(Event.type.asc())).all()
        breakdown = [{"type": r.type, "kg": float(r.kg)} for r in type_rows if r.type is not None]

        return jsonify({
            "user": {"userid": user.userid, "name": user.name},
            "period": {"year": year, "month": month, "start": start.date().isoformat(), "end": end.date().isoformat()},
            "totals": {"emitted_kg": float(emitted_pos), "saved_kg": float(saved_mag), "net_kg": float(total_sum)},
            "weekly": weekly,
            "breakdown_by_type": breakdown,
        })
    finally:
        session.close()

# ---------- Photo Extraction placeholder ----------
@api.post("/users/<int:userid>/emissions/monthly")
def user_photo_info():
    return jsonify({"ok": False, "error": "not implemented"}), 501

# ---------- Receipt Parsing ----------
def _normalize_b64(s: str) -> bytes:
    s = re.sub(r'^data:image/[^;]+;base64,', '', s, flags=re.I)
    s = s.replace('-', '+').replace('_', '/')
    pad = (-len(s)) % 4
    if pad: s += '=' * pad
    return _b64.b64decode(s, validate=False)

@api.post("/receipt-parser")
def update_receipt():
    data = request.get_json(silent=True) or {}
    b64s = data.get("image_base64")
    if not b64s:
        return jsonify({"error": "No image_base64 field"}), 400

    try:
        # quick size gate on the base64 payload (~0.75 factor -> decoded bytes)
        approx_bytes = int(len(b64s) * 0.75)
        if approx_bytes > MAX_IMAGE_BYTES:
            return jsonify({"error": f"image too large; limit {MAX_IMAGE_BYTES} bytes"}), 413

        # decode & sanity check
        img_bytes = _normalize_b64(b64s)
        with Image.open(BytesIO(img_bytes)) as im:
            im.verify()

        # Let receipt_parser decide how to create the Vision client/creds.
        # Just pass through whatever the env provides (path or inline JSON).
        key_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        items_parsed = extract_items_from_bytes(img_bytes, key_path=key_path)

        return jsonify({"receipt_json": items_parsed})

    except UnidentifiedImageError:
        return jsonify({"error": "invalid_image"}), 400
    except Exception as e:
        return jsonify({"error": "Parsing failed", "detail": str(e)}), 500


@api.post("/users/<int:userid>/map-receipt")  # <-- fixed leading slash
def map_receipt_route(userid):
    receipt_json = request.get_json(silent=True)
    if receipt_json is None:
        return jsonify({"error": "invalid_json"}), 400

    _ensure_emission_refs_loaded()
    session = SessionLocal()
    try:
        df_filtered = map_receipt_with_emissions(
            receipt_json,
            items_index,
            cat_index,
            df_emissions,
            df_category_emissions
        )

        total_emissions = float(df_filtered["TotalEmissions"].sum())

        gr = GroceryReceipt(userid=userid, totalemissions=total_emissions, date=datetime.utcnow())
        session.add(gr)
        session.flush()

        ev = Event(
            userid=userid,
            receiptid=gr.receiptid,
            description=f"Grocery receipt with {len(df_filtered)} items",
            type="Grocery",
            emissions=total_emissions,
            datetime=datetime.utcnow(),
        )
        session.add(ev)

        u = session.get(User, userid)
        if not u:
            abort(404, description="User not found")
        _bump_weekly(u, total_emissions)

        session.commit()
        return jsonify(df_filtered.to_dict(orient="records"))
    finally:
        session.close()


@api.get("/users/<int:userid>/search_friend")
def search_friend(userid):
    """
    Input the user_id, and then the user name will appear
    """
    db = SessionLocal()  # creat the database session
    try:
        user = db.query(User).filter(User.userid == userid).first()
        if not user:
            return jsonify({"error": "User not found"}), 404
        return jsonify({
            "userid": user.userid,
            "name": user.name
        })
    finally:
        db.close()  # close session


@api.post("/users/<int:userid>/add_friend")
def add_friend(userid: int):
    db: Session = SessionLocal()
    try:
        data = request.get_json()
        if not data or "friend_userid" not in data:
            return jsonify({"error": "friend_userid is required"}), 400

        friend_userid = data["friend_userid"]

        from_user = db.query(User).filter(User.userid == userid).first()
        to_user = db.query(User).filter(User.userid == friend_userid).first()
        if not from_user or not to_user:
            return jsonify({"error": "User not found"}), 404

        existing = db.query(FriendRequests).filter(
            FriendRequests.requesterid == userid,
            FriendRequests.receiverid == friend_userid
        ).first()
        if existing:
            return jsonify({"error": "Friend request already exists"}), 400

        new_request = FriendRequests(
            requesterid=from_user.userid,
            receiverid=friend_userid,
            status=RequestStatusEnum.Pending.value  
        )
        db.add(new_request)
        db.commit()

        return jsonify({
            "message": "Friend Request Sent",
            "data": {
                "from_user_id": from_user.userid,
                "to_user_id": friend_userid,
                "status": new_request.status  
            }
        })
    finally:
        db.close()

@api.get("/users/<int:userid>/process_request")
def get_pending_requests(userid: int):
    db: Session = SessionLocal()
    try:
        requests = db.query(FriendRequests).filter(
            FriendRequests.receiverid == userid,
            FriendRequests.status == 'Pending'
        ).all()

        result = []
        for req in requests:
            from_user = db.query(User).filter(User.userid == req.requesterid).first()
            result.append({
                "request_id": req.requestid,
                "from_user_id": from_user.userid,
                "from_user_name": from_user.name
            })

        return jsonify({"pending_requests": result})
    finally:
        db.close()

@api.post("/users/<int:userid>/process_request")
def process_request(userid: int):
    """
    Input: JSON {"request_id": int, "action": "accept"/"reject"}
    """
    db: Session = SessionLocal()
    try:
        data = request.get_json()
        if not data or "request_id" not in data or "action" not in data:
            return jsonify({"error": "request_id and action are required"}), 400

        request_id = data["request_id"]
        action = data["action"].lower()

        # query the requerst
        friend_request = db.query(FriendRequests).filter(
            FriendRequests.requestid == request_id,
            FriendRequests.receiverid == userid
        ).first()

        if not friend_request:
            return jsonify({"error": "Friend request not found"}), 404

        # accept
        if action == "accept":
            # insert the relationship of friends, but check whether it exists
            for u1, u2 in [(userid, friend_request.requesterid), (friend_request.requesterid, userid)]:
                exists = db.query(Friends).filter(
                    Friends.userid == u1, Friends.friendid == u2
                ).first()
                if not exists:
                    db.add(Friends(userid=u1, friendid=u2))
            
            friend_request.status = "Accepted"

        # reject
        elif action == "reject":
            friend_request.status = "Rejected"

        else:
            return jsonify({"error": "Invalid action, must be 'accept' or 'reject'"}), 400

        db.commit()

        return jsonify({
            "message": f"Friend request {action}ed successfully",
            "data": {
                "request_id": friend_request.requestid,
                "from_user_id": friend_request.requesterid,
                "to_user_id": friend_request.receiverid,
                "status": friend_request.status
            }
        })

    finally:
        db.close()

@api.get("/users/<int:userid>/leaderboard")
def show_leaderboard(userid: int):
    """
    Return a leaderboard of the user and their friends,
    ranked primarily by carbon saved (monthly), then by lowest emitted (monthly),
    then by carbonpoints.
    """
    db: Session = SessionLocal()
    try:
        # 1) Ensure current user exists
        current_user = db.query(User).filter(User.userid == userid).first()
        if not current_user:
            return jsonify({"error": "User not found"}), 404

        # 2) Friend ids for this user
        friend_ids = db.query(Friends.friendid).filter(Friends.userid == userid).all()
        friend_ids = [fid for (fid,) in friend_ids]

        # 3) Include the user themselves
        user_ids = friend_ids + [userid]

        # 4) Fetch users
        users = db.query(User).filter(User.userid.in_(user_ids)).all()

        # --- Time windows ---
        now = datetime.utcnow()
        month_start, month_end = _month_bounds(now.year, now.month)
        week_start = now - timedelta(days=7)

        # --- Helper: reduce rows -> dict {userid: sum} ---
        def _to_map(rows):
            out = {}
            for uid, total in rows:
                out[int(uid)] = float(total or 0.0)
            return out

        # Monthly emitted (positive only)
        emitted_month_rows = db.execute(
            select(Event.userid, func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid.in_(user_ids))
            .where(Event.datetime >= month_start)
            .where(Event.datetime < month_end)
            .where(Event.emissions > 0.0)
            .group_by(Event.userid)
        ).all()
        emitted_month = _to_map(emitted_month_rows)

        # Monthly saved (negative only) -> store magnitude (positive number)
        saved_month_rows = db.execute(
            select(Event.userid, func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid.in_(user_ids))
            .where(Event.datetime >= month_start)
            .where(Event.datetime < month_end)
            .where(Event.emissions < 0.0)
            .group_by(Event.userid)
        ).all()
        # convert to magnitude
        saved_month = {int(uid): abs(float(total or 0.0)) for uid, total in saved_month_rows}

        # Weekly (last 7 days) emitted (positive)
        emitted_week_rows = db.execute(
            select(Event.userid, func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid.in_(user_ids))
            .where(Event.datetime >= week_start)
            .where(Event.datetime <= now)
            .where(Event.emissions > 0.0)
            .group_by(Event.userid)
        ).all()
        emitted_week = _to_map(emitted_week_rows)

        # Weekly (last 7 days) saved (negative) -> magnitude
        saved_week_rows = db.execute(
            select(Event.userid, func.coalesce(func.sum(Event.emissions), 0.0))
            .where(Event.userid.in_(user_ids))
            .where(Event.datetime >= week_start)
            .where(Event.datetime <= now)
            .where(Event.emissions < 0.0)
            .group_by(Event.userid)
        ).all()
        saved_week_mag = {int(uid): abs(float(total or 0.0)) for uid, total in saved_week_rows}

        # Sort: saved_month DESC, emitted_month ASC, carbonpoints DESC, name ASC
        def _sort_key(u: User):
            s = saved_month.get(u.userid, 0.0)
            e = emitted_month.get(u.userid, 0.0)
            return (-s, e, -int(u.carbonpoints or 0), (u.name or "").lower())

        leaderboard = sorted(users, key=_sort_key)

        # Build response
        result = []
        for u in leaderboard:
            uid = u.userid
            em_month = emitted_month.get(uid, 0.0)
            sv_month = saved_month.get(uid, 0.0)
            em_week = emitted_week.get(uid, 0.0)
            sv_week = saved_week_mag.get(uid, 0.0)

            result.append({
                "userid": uid,
                "name": u.name,
                "carbonpoints": int(u.carbonpoints or 0),
                "ecopetmood": int(u.ecopetmood or 0),

                # Monthly totals for UI/labels
                "emitted_month_kg": em_month,   # >= 0
                "saved_month_kg": sv_month,     # magnitude

                # Weekly (last 7 days) — convenient for top cards if you want
                "emitted_week_kg": em_week,     # >= 0
                "saved_week_kg": sv_week,       # magnitude

                # Frontend-friendly aliases (match your UserDto convention)
                "weekly_emissions_produced": em_week,   # positive
                "weekly_emissions_saved": -sv_week,     # negative by convention
            })

        return jsonify({"leaderboard": result})

    finally:
        db.close()


# Mount the blueprint
app.register_blueprint(api)

if __name__ == "__main__":
    # Run with: python -m backend.app
    app.run(host="0.0.0.0", port=8080, debug=True)
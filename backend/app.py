# backend/app.py
import base64 as _b64
import os
import re
from datetime import datetime
from io import BytesIO

import pandas as pd
from PIL import Image, UnidentifiedImageError
from flask import Flask, Blueprint, jsonify, request, abort
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import select, func, cast, Integer

from db import SessionLocal
from models import User, Quest, UserQuest, Event, EmissionConversionSaving, GroceryReceipt


# Eager imports from your emissions stack (kept)
from emissions_models.ItemToDataset import map_receipt_with_emissions, items_index, cat_index
from emissions_models.item_info import map_receipt
from receipt_update.receipt_parser import extract_items_from_bytes

db = SQLAlchemy()

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})
api = Blueprint("api", __name__, url_prefix="/api")
app.url_map.strict_slashes = False  # small QoL: /users/1 == /users/1/

# ---- configuration ----
POINT_KG_PER_POINT = float(os.environ.get("POINT_KG_PER_POINT", "0.05"))
MAX_IMAGE_BYTES = int(os.environ.get("MAX_IMAGE_BYTES", str(6 * 1024 * 1024)))  # 6MB default

# ---------- Preload emissions reference tables ----------
df_emissions = None
df_category_emissions = None
_df_ready = False

def _ensure_emission_refs_loaded():
    """Load the emissions DataFrames once, on first use (keeps boot lean)."""
    global df_emissions, df_category_emissions, _df_ready
    if _df_ready:
        return
    with SessionLocal() as _session:
        conn = _session.connection()
        df_emissions = pd.read_sql('SELECT * FROM pawprint."FoodEmissions";', conn)
        df_category_emissions = pd.read_sql('SELECT * FROM pawprint."CategoryEmissions";', conn)
    _df_ready = True
# ---------- Weekly counters: name-compat shims ----------
WES_ATTR = (
    "weekly_emissions_saved"
    if hasattr(User, "weekly_emissions_saved")
    else ("weeklyemissionssaved" if hasattr(User, "weeklyemissionssaved") else None)
)
WEP_ATTR = (
    "weekly_emissions_produced"
    if hasattr(User, "weekly_emissions_produced")
    else ("weeklyemissionsproduced" if hasattr(User, "weeklyemissionsproduced") else None)
)

def _get_wes(u: User) -> float:
    return float(getattr(u, WES_ATTR, 0.0)) if WES_ATTR else 0.0

def _get_wep(u: User) -> float:
    return float(getattr(u, WEP_ATTR, 0.0)) if WEP_ATTR else 0.0

def _set_wes(u: User, val: float) -> None:
    if WES_ATTR:
        setattr(u, WES_ATTR, float(val))

def _set_wep(u: User, val: float) -> None:
    if WEP_ATTR:
        setattr(u, WEP_ATTR, float(val))

def _bump_weekly(u: User, delta: float) -> None:
    if delta >= 0:
        _set_wep(u, _get_wep(u) + delta)
    else:
        _set_wes(u, _get_wes(u) + delta)

# ---------- helpers ----------
def as_user_dict(u: User):
    return {
        "userid": u.userid,
        "name": u.name,
        "ecopetmood": u.ecopetmood,
        "carbonpoints": u.carbonpoints,
        "weekly_emissions_saved": _get_wes(u),
        "weekly_emissions_produced": _get_wep(u),
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
    start = datetime(year, month, 1)
    end = datetime(year + 1, 1, 1) if month == 12 else datetime(year, month + 1, 1)
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

        if "weekly_emissions_saved" in data:
            wes = float(data["weekly_emissions_saved"])
            if wes > 0:
                abort(400, description="weekly_emissions_saved must be <= 0")
            _set_wes(u, wes)

        if "weekly_emissions_produced" in data:
            wep = float(data["weekly_emissions_produced"])
            if wep < 0:
                abort(400, description="weekly_emissions_produced must be >= 0")
            _set_wep(u, wep)

        session.commit()
        return jsonify(as_user_dict(u))
    finally:
        session.close()

# ---------- UserQuests ----------
@api.get("/users/<int:userid>/userquests")
def list_userquests(userid):
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
            stmt = stmt.where(UserQuest.isactive == True, UserQuest.iscompleted == False)  # noqa: E712
        elif status == "completed":
            stmt = stmt.where(UserQuest.iscompleted == True)  # noqa: E712
        elif status != "all":
            abort(400, description="status must be active|completed|all")

        rows = session.execute(stmt).all()
        return jsonify([{**as_userquest_dict(uq), "quest": as_quest_dict(q)} for uq, q in rows])
    finally:
        session.close()

@api.get("/userquests/<int:userquestid>")
def get_userquest(userquestid):
    session = SessionLocal()
    try:
        uq = session.get(UserQuest, userquestid)
        if not uq:
            abort(404, description="UserQuest not found")
        q = session.get(Quest, uq.questid)
        return jsonify({**as_userquest_dict(uq), "quest": as_quest_dict(q) if q else None})
    finally:
        session.close()

@api.post("/users/<int:userid>/quests")
def assign_quests(userid):
    data = request.get_json(force=True)
    questids = list({int(q) for q in data.get("questids", [])})
    if not questids:
        abort(400, description="questids required")

    session = SessionLocal()
    try:
        if not session.get(User, userid):
            abort(404, description="User not found")

        existing_qids = set(q.questid for q in session.execute(
            select(Quest).where(Quest.questid.in_(questids))
        ).scalars().all())
        missing = set(questids) - existing_qids
        if missing:
            abort(400, description=f"Unknown questids: {sorted(missing)}")

        created = []
        for qid in sorted(existing_qids):
            uq = UserQuest(userid=userid, questid=qid, isactive=True, iscompleted=False)
            session.add(uq); created.append(uq)

        session.commit()
        return jsonify([as_userquest_dict(uq) for uq in created]), 201
    finally:
        session.close()

@api.post("/users/<int:userid>/quests/assign_random")
def assign_random_quests(userid):
    data = request.get_json(silent=True) or {}
    count = int(data.get("count", 3)); diffs = data.get("difficulty") or []
    if count <= 0:
        abort(400, description="count must be > 0")

    session = SessionLocal()
    try:
        if not session.get(User, userid):
            abort(404, description="User not found")

        existing_qids = set(qid for (qid,) in session.execute(
            select(UserQuest.questid).where(UserQuest.userid == userid)
        ).all())

        q = select(Quest).where(~Quest.questid.in_(existing_qids))
        if diffs: q = q.where(Quest.difficulty.in_(diffs))
        picks = session.execute(q.order_by(func.random()).limit(count)).scalars().all()

        if not picks:
            return jsonify({"created": [], "note": "no quests available to assign"}), 200

        created = []
        for quest in picks:
            uq = UserQuest(userid=userid, questid=quest.questid, isactive=True, iscompleted=False)
            session.add(uq); created.append(uq)

        session.commit()
        return jsonify([as_userquest_dict(uq) for uq in created]), 201
    finally:
        session.close()
        
@api.post("/userquests/<int:userquestid>/replace_random")
def replace_userquest(userquestid):
    data = request.get_json(silent=True) or {}
    diffs = data.get("difficulty") or []  # e.g. ["Easy"] or ["Easy","Medium"]

    session = SessionLocal()
    try:
        # Load current UQ + related user & quest
        uq = session.get(UserQuest, userquestid)
        if not uq:
            abort(404, description="UserQuest not found")

        user = session.get(User, uq.userid)
        if not user:
            abort(404, description="User not found")

        current_q = session.get(Quest, uq.questid)
        if not current_q:
            abort(404, description="Current quest not found")

        # Build a pool of candidate quests:
        #  - not already assigned to this user (active or completed)
        #  - optionally matching difficulty filters
        existing_qids = set(qid for (qid,) in session.execute(
            select(UserQuest.questid).where(UserQuest.userid == uq.userid)
        ).all())

        q = select(Quest).where(~Quest.questid.in_(existing_qids))
        if diffs:
            q = q.where(Quest.difficulty.in_(diffs))

        # If no filter given, bias to the same difficulty as before
        if not diffs and current_q.difficulty:
            q = q.where(Quest.difficulty == current_q.difficulty)

        # Pick one at random
        new_q = session.execute(q.order_by(func.random()).limit(1)).scalars().first()
        if not new_q:
            # Nothing to replace with; keep current
            q_dict = as_quest_dict(current_q)
            return jsonify({**as_userquest_dict(uq), "quest": q_dict}), 200

        # Replace in place
        uq.questid = new_q.questid
        uq.isactive = True
        uq.iscompleted = False
        uq.completeddate = None

        session.commit()
        session.refresh(uq)

        return jsonify({**as_userquest_dict(uq), "quest": as_quest_dict(new_q)}), 200
    finally:
        session.close()


# ---------- Complete a userquest ----------
@api.post("/userquests/<int:userquestid>/complete")
def complete_userquest(userquestid):
    data = request.get_json(silent=True) or {}
    when = data.get("completeddate"); mood_delta = int(data.get("mood_delta", 10))

    session = SessionLocal()
    try:
        uq = session.get(UserQuest, userquestid)
        if not uq: abort(404, description="UserQuest not found")
        if uq.iscompleted: abort(409, description="UserQuest already completed")

        u = session.get(User, uq.userid); q = session.get(Quest, uq.questid)
        if not (u and q): abort(400, description="User or Quest missing")

        uq.iscompleted = True
        uq.completeddate = datetime.fromisoformat(when) if when else datetime.utcnow()

        if q.emissions is not None and float(q.emissions) != 0.0:
            ev = Event(userid=u.userid, userquestid=uq.userquestid,
                       description=f"Completed quest: {q.description}",
                       type="Quest", emissions=float(q.emissions),
                       datetime=uq.completeddate)
            session.add(ev); _bump_weekly(u, ev.emissions)
        else:
            if POINT_KG_PER_POINT > 0 and (q.reward or 0) > 0:
                evp = Event(userid=u.userid, userquestid=uq.userquestid,
                            description=f"Points conversion for quest: {q.description}",
                            type="Points",
                            emissions=-(POINT_KG_PER_POINT * float(q.reward or 0)),
                            datetime=uq.completeddate)
                session.add(evp); _bump_weekly(u, evp.emissions)

        u.carbonpoints = max(0, (u.carbonpoints or 0) + (q.reward or 0))
        u.ecopetmood = min(100, max(0, (u.ecopetmood or 0) + mood_delta))
        session.commit()
        return jsonify({"userquest": as_userquest_dict(uq), "user": as_user_dict(u),
                        "point_kg_per_point": POINT_KG_PER_POINT})
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
            select(Event).where(Event.userid == userid)
            .order_by(Event.datetime.desc()).limit(limit)
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
        return jsonify([{
            "metricid": r.metricid, "name": r.name, "description": r.description, "emissionsperx": r.emissionsperx
        } for r in rows])
    finally:
        session.close()

# ---------- Dashboard ----------
@api.get("/users/<int:userid>/dashboard")
def user_dashboard(userid):
    session = SessionLocal()
    try:
        u = session.get(User, userid)
        if not u: abort(404, description="User not found")
        active_count = session.execute(select(func.count()).select_from(UserQuest).where(
            UserQuest.userid == userid, UserQuest.isactive == True, UserQuest.iscompleted == False  # noqa: E712
        )).scalar_one()
        completed_count = session.execute(select(func.count()).select_from(UserQuest).where(
            UserQuest.userid == userid, UserQuest.iscompleted == True  # noqa: E712
        )).scalar_one()
        total_emissions = session.execute(select(func.coalesce(func.sum(Event.emissions), 0.0)).where(
            Event.userid == userid, Event.type == "Quest"
        )).scalar_one()
        return jsonify({
            "user": as_user_dict(u),
            "active_quests": int(active_count),
            "completed_quests": int(completed_count),
            "total_emissions_saved": float(total_emissions),
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
        approx_bytes = int(len(b64s) * 0.75)
        if approx_bytes > MAX_IMAGE_BYTES:
            return jsonify({"error": f"image too large; limit {MAX_IMAGE_BYTES} bytes"}), 413

        img_bytes = _normalize_b64(b64s)
        with Image.open(BytesIO(img_bytes)) as im:
            im.verify()

        key_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or \
                   r"receipt_update/savvy-girder-472600-s1-07e7b3e23118.json"

        items_parsed = extract_items_from_bytes(img_bytes, key_path=key_path)
        return jsonify({"receipt_json": items_parsed})
    except UnidentifiedImageError:
        return jsonify({"error": "invalid_image"}), 400
    except Exception as e:
        return jsonify({"error": "Parsing failed", "detail": str(e)}), 500

# ---------- Map Receipt & Create Event/Receipt ----------
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

# Mount the blueprint
app.register_blueprint(api)

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
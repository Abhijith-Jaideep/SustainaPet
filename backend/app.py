# backend/app.py
import base64 as _b64
import os
import re
from datetime import datetime
from io import BytesIO

import pandas as pd
from PIL import Image
from flask import Flask, Blueprint, jsonify, request, abort
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import select, func, cast, Integer

from .db import SessionLocal
from .models import User, Quest, UserQuest, Event, EmissionConversionSaving, GroceryReceipt

# Emissions mapping utilities (no globals imported to avoid import-time work)
from backend.emissions_models.ItemToDataset import (
    build_category_index,
    build_index_from_emissions,
    map_receipt_with_emissions,
)
from backend.emissions_models.item_info import map_receipt  # noqa: F401 (kept for clarity)
from backend.receipt_update.receipt_parser import extract_items_from_bytes

db = SQLAlchemy()

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})
api = Blueprint("api", __name__, url_prefix="/api")

# ---------- lazy-loaded globals (avoid crashing at import time) ----------
df_emissions = None
df_category_emissions = None
_items_index = None
_cat_index = None

def _ensure_emissions_loaded():
    """Load emissions tables & build indices exactly once (lazy)."""
    global df_emissions, df_category_emissions, _items_index, _cat_index
    if df_emissions is not None and df_category_emissions is not None:
        return
    with SessionLocal() as s:
        conn = s.connection()
        df_emissions = pd.read_sql('SELECT * FROM pawprint."FoodEmissions";', conn)
        df_category_emissions = pd.read_sql('SELECT * FROM pawprint."CategoryEmissions";', conn)
    _items_index = build_index_from_emissions(df_emissions)
    _cat_index = build_category_index(df_category_emissions)

@app.before_first_request
def _warm():
    # Try to warm caches; if it fails (cold DB, migrations, etc.), we’ll retry on-demand.
    try:
        _ensure_emissions_loaded()
    except Exception:
        app.logger.exception("Startup preload failed; will retry lazily on first request.")

# ---- configuration ----
POINT_KG_PER_POINT = float(os.environ.get("POINT_KG_PER_POINT", "0.05"))  # kg per point

# ---------- Weekly counters shims ----------
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
    """delta >= 0 -> produced; delta < 0 -> saved"""
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

def as_groceryreceipt_dict(gr: GroceryReceipt):
    return {
        "receiptid": gr.receiptid,
        "userid": gr.userid,
        "totalemissions": gr.totalemissions,
        "date": gr.date.isoformat() if gr.date else None,
    }

def _month_bounds(year: int, month: int):
    start = datetime(year, month, 1)
    end = datetime(year + 1, 1, 1) if month == 12 else datetime(year, month + 1, 1)
    return start, end

# ---------- root / health ----------
@app.get("/")
def root():
    return jsonify({"ok": True, "service": "pawprint-backend", "point_kg_per_point": POINT_KG_PER_POINT})

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
            stmt = stmt.where(UserQuest.isactive == True, UserQuest.iscompleted == False)
        elif status == "completed":
            stmt = stmt.where(UserQuest.iscompleted == True)
        elif status == "all":
            pass
        else:
            abort(400, description="status must be active|completed|all")

        rows = session.execute(stmt).all()
        data = [{**as_userquest_dict(uq), "quest": as_quest_dict(q)} for uq, q in rows]
        return jsonify(data)
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

        existing_qids = set(
            q.questid for q in session.execute(
                select(Quest).where(Quest.questid.in_(questids))
            ).scalars().all()
        )
        missing = set(questids) - existing_qids
        if missing:
            abort(400, description=f"Unknown questids: {sorted(missing)}")

        created = []
        for qid in sorted(existing_qids):
            uq = UserQuest(userid=userid, questid=qid, isactive=True, iscompleted=False)
            session.add(uq)
            created.append(uq)

        session.commit()
        return jsonify([as_userquest_dict(uq) for uq in created]), 201
    finally:
        session.close()

@api.post("/users/<int:userid>/quests/assign_random")
def assign_random_quests(userid):
    data = request.get_json(silent=True) or {}
    count = int(data.get("count", 3))
    diffs = data.get("difficulty") or []
    if count <= 0:
        abort(400, description="count must be > 0")

    session = SessionLocal()
    try:
        if not session.get(User, userid):
            abort(404, description="User not found")

        existing_qids = set(
            qid for (qid,) in session.execute(
                select(UserQuest.questid).where(UserQuest.userid == userid)
            ).all()
        )

        q = select(Quest).where(~Quest.questid.in_(existing_qids))
        if diffs:
            q = q.where(Quest.difficulty.in_(diffs))
        q = q.order_by(func.random()).limit(count)

        picks = session.execute(q).scalars().all()
        if not picks:
            return jsonify({"created": [], "note": "no quests available to assign"}), 200

        created = []
        for quest in picks:
            uq = UserQuest(userid=userid, questid=quest.questid, isactive=True, iscompleted=False)
            session.add(uq)
            created.append(uq)

        session.commit()
        return jsonify([as_userquest_dict(uq) for uq in created]), 201
    finally:
        session.close()

# ---------- Complete a userquest ----------
@api.post("/userquests/<int:userquestid>/complete")
def complete_userquest(userquestid):
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

        uq.iscompleted = True
        uq.completeddate = datetime.fromisoformat(when) if when else datetime.utcnow()

        if q.emissions is not None and float(q.emissions) != 0.0:
            ev = Event(
                userid=u.userid,
                userquestid=uq.userquestid,
                description=f"Completed quest: {q.description}",
                type="Quest",
                emissions=float(q.emissions),
                datetime=uq.completeddate,
            )
            session.add(ev)
            _bump_weekly(u, ev.emissions)
        else:
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
                _bump_weekly(u, ev_points.emissions)

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

        active_count = session.execute(
            select(func.count()).select_from(UserQuest).where(
                UserQuest.userid == userid,
                UserQuest.isactive == True,
                UserQuest.iscompleted == False
            )
        ).scalar_one()

        completed_count = session.execute(
            select(func.count()).select_from(UserQuest).where(
                UserQuest.userid == userid,
                UserQuest.iscompleted == True
            )
        ).scalar_one()

        total_emissions = session.execute(
            select(func.coalesce(func.sum(Event.emissions), 0.0)).where(
                Event.userid == userid, Event.type == "Quest"
            )
        ).scalar_one()

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
    if month < 1 or month > 12:
        abort(400, description="month must be 1..12")

    session = SessionLocal()
    try:
        user = session.get(User, userid)
        if not user:
            abort(404, description="User not found")

        start, end = _month_bounds(year, month)

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

        week_of_month = cast((func.floor((func.extract("day", Event.datetime) - 1) / 7) + 1), Integer)
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
        breakdown = [{"type": r.type, "kg": float(r.kg)} for r in type_rows if r.type is not None]

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
                "net_kg": float(total_sum),
            },
            "weekly": weekly,
            "breakdown_by_type": breakdown,
        })
    finally:
        session.close()

# ---------- Photo Extraction ----------
@api.post("/users/<int:userid>/emissions/monthly")
def user_photo_info(userid):
    return jsonify({"ok": False, "error": "not implemented"}), 501

# ---------- Receipt Parsing ----------
def _normalize_b64(s: str) -> bytes:
    s = re.sub(r'^data:image/[^;]+;base64,', '', s, flags=re.I)
    s = s.replace('-', '+').replace('_', '/')
    pad = (-len(s)) % 4
    if pad:
        s += '=' * pad
    return _b64.b64decode(s, validate=False)

@app.route("/receipt-parser", methods=["POST"])
def update_receipt():
    data = request.get_json()
    if not data or "image_base64" not in data:
        return jsonify({"error": "No image_base64 field"}), 400

    try:
        img_bytes = _normalize_b64(data["image_base64"])
        with Image.open(BytesIO(img_bytes)) as im:
            im.verify()

        items_parsed = extract_items_from_bytes(
            img_bytes,
            key_path=r"backend/receipt_update/savvy-girder-472600-s1-07e7b3e23118.json",
        )
        return jsonify({"receipt_json": items_parsed})
    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({"error": f"Parsing failed: {str(e)}"}), 500

# ---------- Map Receipt & Create Event/Receipt ----------
@app.route("/<int:userid>/map-receipt", methods=["POST"])
def map_receipt_route(userid):
    session = SessionLocal()
    try:
        # Ensure reference data/indices are ready
        try:
            _ensure_emissions_loaded()
        except Exception as e:
            app.logger.exception("Failed to load emissions reference data")
            return jsonify({"error": f"server not ready: {e}"}), 500

        receipt_json = request.get_json()
        df_filtered = map_receipt_with_emissions(
            receipt_json,
            _items_index,
            _cat_index,
            df_emissions,
            df_category_emissions,
        )

        total_emissions = float(df_filtered["TotalEmissions"].sum())

        gr = GroceryReceipt(
            userid=userid,
            totalemissions=total_emissions,
            date=datetime.utcnow(),
        )
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
    # Local dev only; Render uses Gunicorn with: gunicorn --bind 0.0.0.0:$PORT backend.app:app
    app.run(host="0.0.0.0", port=5000, debug=True)

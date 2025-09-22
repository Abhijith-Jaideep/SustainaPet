import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend.app import app
from backend.models import User, Quest, UserQuest
from backend.db import SessionLocal   
from datetime import datetime
from backend.app import _month_bounds
import pytest

def test_month_bounds_normal_month():
    start, end = _month_bounds(2025, 5)  
    assert start == datetime(2025, 5, 1)
    assert end == datetime(2025, 6, 1)

@pytest.fixture
def client():
    with app.test_client() as client:
        yield client

def test_ping(client):
    response = client.get("/api/ping")  # send GET request
    assert response.status_code == 200  # check
    data = response.get_json()          # return JSON
    assert "ok" in data
    assert data["ok"] is True
    assert "point_kg_per_point" in data
    assert isinstance(data["point_kg_per_point"], float)  # validation type

# ------------------ Users ------------------

@pytest.fixture
def test_user():
    session = SessionLocal()
    user = User(name="testuser", ecopetmood=5, carbonpoints=100)
    session.add(user)
    session.commit()
    session.refresh(user)
    yield user.userid  
    session.delete(user)
    session.commit()
    session.close()

def test_quests():
    session = SessionLocal()
    quests = [
        Quest(description="Recycle 10 items", difficulty="easy", reward=10, emissions=1.2),
        Quest(description="Walk 5km", difficulty="medium", reward=20, emissions=0.5)
    ]
    session.add_all(quests)
    session.commit()
    quest_ids = [q.questid for q in quests]
    yield quest_ids
    for q in quests:
        session.delete(q)
    session.commit()
    session.close()

def test_list_users(client):
    """test GET /api/users"""
    rv = client.get("/api/users")
    assert rv.status_code == 200
    data = rv.get_json()
    assert isinstance(data, list)

def test_get_user_not_found(client):
    """test GET /api/users/<userid> doesn't exist"""
    rv = client.get("/api/users/99999")  # assume this id is not exist
    assert rv.status_code == 404

def test_create_user_and_update(client):
    """test POST /api/users and PATCH /api/users/<userid>"""
    # create user
    rv = client.post("/api/users", json={"name": "TestUser"})
    assert rv.status_code == 201
    user_data = rv.get_json()
    assert user_data["name"] == "TestUser"
    user_id = user_data["userid"]

    # update user
    rv = client.patch(f"/api/users/{user_id}", json={"name": "UpdatedUser"})
    assert rv.status_code == 200
    updated_data = rv.get_json()
    assert updated_data["name"] == "UpdatedUser"

# ------------------ UserQuests ------------------

def test_list_userquests_invalid_status(client):
    """test GET /api/users/<userid>/userquests status 参数非法"""
    # create an user
    rv = client.post("/api/users", json={"name": "QuestTester"})
    user_id = rv.get_json()["userid"]

    rv = client.get(f"/api/users/{user_id}/userquests?status=invalid")
    assert rv.status_code == 400

def test_list_userquests_default(client):
    """test GET /api/users/<userid>/userquests 默认 status"""
    # create an user
    rv = client.post("/api/users", json={"name": "QuestTester2"})
    user_id = rv.get_json()["userid"]

    rv = client.get(f"/api/users/{user_id}/userquests")
    assert rv.status_code == 200
    data = rv.get_json()
    assert isinstance(data, list)

# ------------------ Quests ------------------

def test_list_quests_default(client):
    """test GET /api/quests 默认参数"""
    rv = client.get("/api/quests")
    assert rv.status_code == 200
    data = rv.get_json()
    assert isinstance(data, list)

def test_list_quests_with_difficulty(client):
    """test GET /api/quests?difficulty=Easy"""
    rv = client.get("/api/quests?difficulty=Easy")
    assert rv.status_code == 200
    data = rv.get_json()
    assert isinstance(data, list)

def test_assign_quests(client, test_user, test_quests):
    rv = client.post(f"/api/users/{test_user}/quests", json={"questids": test_quests})
    assert rv.status_code == 201
    data = rv.get_json()
    assert len(data) == len(test_quests)
    for uq in data:
        assert uq["userid"] == test_user
        assert uq["isactive"] is True
        assert uq["iscompleted"] is False

def test_assign_random_quests(client, test_user):
    rv = client.post(f"/api/users/{test_user}/quests/assign_random", json={"count": 2})
    assert rv.status_code in (200, 201)
    data = rv.get_json()
    if rv.status_code == 201:
        assert isinstance(data, list)
        assert all("userid" in uq and uq["userid"] == test_user for uq in data)
    else:
        assert "created" in data


# ------------------ Complete UserQuest ------------------


def test_complete_userquest(client, test_user, test_quests):
    session = SessionLocal()
    uq = UserQuest(userid=test_user, questid=test_quests[0], isactive=True, iscompleted=False)
    session.add(uq)
    session.commit()
    session.refresh(uq)
    uqid = uq.userquestid
    session.close()

    rv = client.post(f"/api/userquests/{uqid}/complete", json={"mood_delta": 5})
    assert rv.status_code == 200
    data = rv.get_json()
    assert data["userquest"]["iscompleted"] is True
    assert data["user"]["ecopetmood"] >= 0
    assert data["point_kg_per_point"] is not None

# ------------------ User Events ------------------

def test_user_events(client, test_user):
    rv = client.get(f"/api/users/{test_user}/events?limit=5")
    assert rv.status_code == 200
    data = rv.get_json()
    assert isinstance(data, list)

# ------------------ Conversions ------------------

def test_list_conversions(client):
    """GET /conversions"""
    rv = client.get("/api/conversions")
    assert rv.status_code == 200
    data = rv.get_json()
    assert isinstance(data, list)
    if data:
        assert "metricid" in data[0]

# ------------------ Dashboard ------------------

def test_user_dashboard(client, test_user):
    rv = client.get(f"/api/users/{test_user}/dashboard")
    assert rv.status_code == 200
    data = rv.get_json()
    assert "user" in data
    assert "active_quests" in data
    assert "completed_quests" in data
    assert "total_emissions_saved" in data

# ------------------ Monthly Emissions ------------------

def test_user_monthly_emissions(client, test_user):
    rv = client.get(f"/api/users/{test_user}/emissions/monthly?year=2025&month=9")
    assert rv.status_code == 200
    data = rv.get_json()
    assert "totals" in data
    assert "weekly" in data
    assert "breakdown_by_type" in data
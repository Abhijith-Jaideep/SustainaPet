from xmlrpc.client import DateTime
from models import db
from models.event import Event
from models.user_quests import UserQuests
from datetime import date, timedelta


def set_life_cycle():
    life_cycle = timedelta(days=7)
    return life_cycle


def select_archieve_events(set_life_cycle):
    archieve_event_collection = db.query(Event).filter(date.today()-DateTime>set_life_cycle).all()
    for a in archieve_event_collection:
        user_quest= db.query(UserQuests).filter(event_id=a.event_id).first()
        user_quest.is_active = False
        db.commit()


    
from xmlrpc.client import DateTime
from src.models import db
from src.models.event import Event
from src.models.user_quests import UserQuests
from datetime import date, datetime, timedelta

class UpdateQuest:
    def set_life_cycle(self):
        life_cycle = timedelta(days=7)
        return life_cycle


    def select_archieve_events(self,life_cycle):
        '''
        when the user open the dashboard each time,
        select_archieve_events would be call to mark the overdue event
        [The alternative method is to use 'join' to improve the performance]
        '''
        # find all overdue event in the event table
        archieve_event_collection = db.session.query(Event)\
            .filter(Event.date_time < datetime.now() - timedelta(days=life_cycle))\
            .all()
        
        print(archieve_event_collection)
        
        # match that against the rows in userquests table
        print("now:", datetime.now())
        for a in archieve_event_collection:
            user_quest= db.session.query(UserQuests).filter(UserQuests.event_id == a.event_id).first()
            user_quest.is_active = False
            db.session.commit()
            print(a.event_id, a.date_time)
        
        return archieve_event_collection



    
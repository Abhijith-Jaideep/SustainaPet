from src.models import db
from src.models.quest import Quest
from src.models.user_quests import UserQuests
from src.models.user import User
from src.models import db
from src.models.quest import Quest
from src.models.user_quests import UserQuests
from src.models.user import User

class HandleQuestCompletion:
    def increase_reward(self,user_id):
        '''
        Distribute the corresponding points in quest table to the user who have completed related quest
        in their user_quest table
        '''
        # find the user
        reward_user = db.session.query(User).filter_by(user_id=user_id).first()
        if not reward_user:
            return 
        # find the quest points
        completed_quest = db.session.query(UserQuests).filter_by(user_id=user_id,is_completed=True,is_active=True).all()
        if completed_quest:
            for a in completed_quest:
                reward_points = db.session.query(Quest).filter_by(quest_id = a.quest_id).first()
                if reward_points:
                    reward_user.carbon_points += reward_points.reward
        db.session.commit()
        return reward_user

    def improve_pet_mood(self,user_id):
        '''
        The user's pet mood would be improved when the quest completed
        easy quest: 20, medium quest: 30, hard quest:40
        attention: this function will be call for each user_quest only once
        '''
        # find the user
        reward_user = db.session.query(User).filter_by(user_id=user_id).first()
        if not reward_user:
            return
        # find the mood point
        completed_quest = db.session.query(UserQuests).filter_by(user_id=user_id,is_completed=True,is_active=True).all()
        if completed_quest:
            for a in completed_quest:
                level = db.session.query(Quest).filter_by(quest_id=a.quest_id).first()
                print("Processing quest_id:", a.quest_id, "level:", level)
                if not level:
                    continue
                if level.difficulty == "Easy":
                    reward_user.eco_pet_mood += 20
                elif level.difficulty == "Medium":
                    reward_user.eco_pet_mood += 30
                elif level.difficulty == "Hard":
                    reward_user.eco_pet_mood += 40
                else:
                    continue
        db.session.commit()
        return reward_user
    


    
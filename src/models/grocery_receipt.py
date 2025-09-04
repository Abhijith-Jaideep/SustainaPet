from datetime import datetime
from . import db

class GroceryReceipt(db.Model):
    receipt_id = db.Column(db.Integer,primary_key=True)
    user_id = db.Column(db.Integer,db.ForeignKey('user.user_id'),nullable=False)
    event_id = db.Column(db.Integer,nullable=False)
    total_emissions = db.Column(db.Float,nullable=False)
    date = db.Column(db.DateTime,nullable=False,default=datetime.utcnow)

    def __repr__(self):
        return '<Task %r>' % self.receipt_id
    


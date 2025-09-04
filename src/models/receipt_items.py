from . import db

class ReceiptItems(db.Model):
    receipt_item_id = db.Column(db.Integer,primary_key=True)
    receipt_id = db.Column(db.Integer,db.ForeignKey('grocery_receipt.receipt_id'),nullable=False)
    food_id =db.Column(db.Integer,db.ForeignKey('food_emissions.food_id'),nullable=False)
    weight = db.Column(db.Float,nullable=False)
    item_carbon_emissions=db.Column(db.Float,nullable=False)

    def __repr__(self):
        return '<Task %r>' % self.receipt_item_id
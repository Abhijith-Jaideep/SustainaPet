
class BaseConfig:
    SQLALCHEMY_TRACK_MODIFICATIONS = False

class DevelopmentConfig(BaseConfig):
    SQLALCHEMY_DATABASE_URI = ""

class TestingConfig(BaseConfig):
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:" 
    TESTING = True

class ProductionConfig(BaseConfig):
    SQLALCHEMY_DATABASE_URI=""



class BaseConfig:
    SQLALCHEMY_TRACK_MODIFICATIONS = False

class DevelopmentConfig(BaseConfig):
    SQLALCHEMY_DATABASE_URI = (
        "postgresql+psycopg2://pawprint_admin:ecopet5!"
        "@ecopawprint.postgres.database.azure.com:5432/postgres?sslmode=require"
    )

class TestingConfig(BaseConfig):
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    TESTING = True

class ProductionConfig(BaseConfig):
    SQLALCHEMY_DATABASE_URI = (
        "postgresql+psycopg2://pawprint_admin:ecopet5!"
        "@ecopawprint.postgres.database.azure.com:5432/postgres?sslmode=require"
    )



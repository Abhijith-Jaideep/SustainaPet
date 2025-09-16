# backend/db.py
import os
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

# ---- Robust .env loading (works even without python-dotenv) ----
def _fallback_load_env(paths):
    def parse_line(line: str):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            return None, None
        k, v = line.split("=", 1)
        return k.strip(), v.strip().strip('"').strip("'")

    for p in paths:
        try:
            if os.path.exists(p):
                with open(p, "r", encoding="utf-8") as f:
                    for raw in f:
                        k, v = parse_line(raw)
                        if k and (k not in os.environ):  # don't overwrite existing env
                            os.environ[k] = v
                break  # loaded successfully
        except Exception:
            # ignore parse errors and try next path
            pass

def _load_env():
    # Try python-dotenv first
    try:
        from dotenv import load_dotenv  # type: ignore
        # Try common locations: CWD, project root, alongside this file
        here = os.path.dirname(__file__)
        project_root = os.path.dirname(here)
        candidates = [
            os.path.join(os.getcwd(), ".env"),
            os.path.join(project_root, ".env"),
            os.path.join(here, ".env"),
        ]
        # load first existing; load_dotenv returns True/False
        loaded = False
        for p in candidates:
            if os.path.exists(p):
                loaded = load_dotenv(p)
                if loaded:
                    break
        if not loaded:
            # fallback to default search if none of the candidates matched
            load_dotenv()
        return
    except Exception:
        # Fallback minimal loader (no dependency)
        here = os.path.dirname(__file__)
        project_root = os.path.dirname(here)
        candidates = [
            os.path.join(os.getcwd(), ".env"),
            os.path.join(project_root, ".env"),
            os.path.join(here, ".env"),
        ]
        _fallback_load_env(candidates)

_load_env()
# ----------------------------------------------------------------

# Read individual values
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME")

if not all([DB_USER, DB_PASS, DB_HOST, DB_PORT, DB_NAME]):
    raise RuntimeError(
        "Missing one or more required DB_* env vars in .env "
        "(expected DB_USER, DB_PASS, DB_HOST, DB_PORT, DB_NAME)."
    )

# Build DATABASE_URL for SQLAlchemy
DATABASE_URL = (
    f"postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}?sslmode=require"
)

# Engine with health-checks so stale connections are refreshed automatically
engine = create_engine(
    DATABASE_URL,
    future=True,
    pool_pre_ping=True,   # validate connections before using them
    pool_recycle=1800,    # recycle connections every 30 minutes
)

# Session factory (use SessionLocal() per request / route)
SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    future=True,
)

# Optional: quick connectivity check
def ping():
    """Return True if DB responds to a simple SELECT 1."""
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return True

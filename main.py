# from fastapi import FastAPI
# # from login import router as login_router

# app = FastAPI()
# # app.include_router(login_router)

# from fastapi import FastAPI
# from pydantic import BaseModel
# import uuid
# from login import router as login_router
# from db import engine, test_connection
# print("Starting FastAPI main.py...")

# app = FastAPI(title="Login API")

# class LoginRequest(BaseModel):
#     user_id: uuid.UUID | None = None

# @app.post("/login")
# def login(request: LoginRequest):
#     user_id = request.user_id or uuid.uuid4()
#     return {"message": f"Logged in with UserID {user_id}"}
# print(app.routes) 

# app.include_router(login_router)

from src.models.db_utils import list_tables

tables = list_tables()
print(tables)
import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, URL

load_dotenv()

def get_engine():
    url = URL.create(
        "postgresql+psycopg2",
        username=os.getenv("PG_USER"),
        password=os.getenv("PG_PASSWORD"),
        host=os.getenv("PG_HOST"),
        port=int(os.getenv("PG_PORT")),
        database=os.getenv("PG_DB"),
    )
    return create_engine(url)
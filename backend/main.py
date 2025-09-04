# main.py

from fastapi import FastAPI
from pydantic import BaseModel
from utils import get_sql_query, run_query

app = FastAPI()

class QueryRequest(BaseModel):
    question: str

@app.post("/ask")
def ask_database(request: QueryRequest):
    """Convert question to SQL and execute it."""
    sql = get_sql_query(request.question)
    if sql:
        results = run_query(sql)
        return {"sql": sql, "results": results}
    else:
        return {"error": "Could not generate SQL"}

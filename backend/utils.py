# utils.py

import psycopg2
import warnings
from vertexai.preview import initializer
from vertexai.preview.generative_models import GenerativeModel
from vertexai.generative_models import GenerationConfig

# --- Step 1: Initialize Vertex AI with your project ---
initializer.init(
    project="YOUR_PROJECT_ID",  # <-- replace with your GCP project ID
    location="us-central1"
)

# Ignore pandas warnings (kept in case you import pandas later)
warnings.filterwarnings('ignore', category=UserWarning)

# Database connection parameters
db_params = {
    "dbname": "postgres",
    "user": "postgres",
    "password": "Hexen2002_23",
    "host": "db.xjcsrfbdtkizmpvvvoot.supabase.co",
    "port": "5432"
}

# AI model setup
generation_config = GenerationConfig(temperature=0.2)
model = GenerativeModel("gemini-pro")

PROMPT = """You are a helpful database assistant. Your goal is to convert natural language questions into SQL queries.
... (keep your schema description here) ...
"""

# --- Helpers ---

def get_sql_query(question: str) -> str | None:
    """Ask Gemini to turn a question into SQL."""
    try:
        prompt_with_question = f"{PROMPT}\"{question}\"\nAnswer: "
        response = model.generate_content(
            prompt_with_question,
            generation_config=generation_config
        )
        sql_query = str(response.text).strip()
        if sql_query.startswith("```sql"):
            sql_query = sql_query.replace("```sql", "").replace("```", "").strip()
        return sql_query
    except Exception as e:
        print(f"Error calling AI API: {e}")
        return None


def run_query(sql_query: str):
    """Run a SQL query on the database and return results."""
    try:
        conn = psycopg2.connect(**db_params)
        with conn.cursor() as cur:
            cur.execute(sql_query)
            result = cur.fetchall()
        conn.close()
        return result
    except Exception as e:
        print(f"Error executing SQL query: {e}")
        return None

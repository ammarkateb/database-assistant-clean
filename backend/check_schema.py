#!/usr/bin/env python3
"""
Check your actual Supabase schema
"""

import psycopg2
from contextlib import contextmanager

# Your Supabase connection
DB_CONFIG = {
    "dbname": "postgres",
    "user": "postgres.chdjmbylbqdsavazecll",
    "password": "Hexen2002_23",
    "host": "aws-1-eu-west-2.pooler.supabase.com",
    "port": "6543",
    "sslmode": "require"
}

@contextmanager
def get_db_connection():
    """Get database connection"""
    conn = None
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        yield conn
    except Exception as e:
        print(f"Database error: {e}")
        if conn:
            conn.rollback()
        raise
    finally:
        if conn:
            conn.close()

def check_schema():
    """Check what tables and columns exist"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()

            # Get all tables
            cursor.execute("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                ORDER BY table_name
            """)
            tables = [row[0] for row in cursor.fetchall()]
            print(f"📊 Available tables: {tables}")

            # Check each table's columns
            for table in tables:
                if table in ['customers', 'invoices', 'users', 'products']:
                    try:
                        cursor.execute(f"""
                            SELECT column_name, data_type
                            FROM information_schema.columns
                            WHERE table_name = '{table}'
                            ORDER BY ordinal_position
                        """)
                        columns = cursor.fetchall()
                        print(f"\n🔍 Table '{table}' columns:")
                        for col_name, col_type in columns:
                            print(f"   - {col_name}: {col_type}")
                    except Exception as e:
                        print(f"❌ Error checking table {table}: {e}")

            # Try to get some sample data
            print(f"\n📈 Sample data:")
            for table in ['customers', 'invoices', 'users'][:1]:  # Just check first table
                if table in tables:
                    try:
                        cursor.execute(f"SELECT * FROM {table} LIMIT 3")
                        rows = cursor.fetchall()
                        if rows:
                            print(f"\n   {table} sample:")
                            for row in rows:
                                print(f"     {row}")
                        else:
                            print(f"   {table}: No data")
                    except Exception as e:
                        print(f"❌ Error getting sample from {table}: {e}")

    except Exception as e:
        print(f"❌ Schema check failed: {e}")

if __name__ == '__main__':
    print("🔍 Checking your Supabase schema...")
    check_schema()
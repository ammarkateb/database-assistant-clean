#!/usr/bin/env python3
"""
Quick test server to integrate Ollama with your existing Supabase data
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import requests
import json
import psycopg2
from contextlib import contextmanager

app = Flask(__name__)
CORS(app, supports_credentials=True)

# Your Supabase connection (from your existing config)
DB_CONFIG = {
    "dbname": "postgres",
    "user": "postgres.chdjmbylbqdsavazecll",
    "password": "Hexen2002_23",
    "host": "aws-1-eu-west-2.pooler.supabase.com",
    "port": "6543",
    "sslmode": "require"
}

OLLAMA_URL = "http://localhost:11434"

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

def get_business_context():
    """Get real business data from your Supabase"""
    context = {}

    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()

            # Get customers
            cursor.execute("SELECT name FROM customers LIMIT 5")
            customers = [row[0] for row in cursor.fetchall()]
            context['customers'] = customers

            # Get total revenue
            cursor.execute("SELECT SUM(total_amount) FROM invoices")
            total_revenue = cursor.fetchone()[0] or 0
            context['total_revenue'] = float(total_revenue)

            # Get top customer
            cursor.execute("""
                SELECT c.name, SUM(i.total_amount) as total
                FROM customers c
                JOIN invoices i ON c.customer_id = i.customer_id
                GROUP BY c.name
                ORDER BY total DESC
                LIMIT 1
            """)
            top_customer = cursor.fetchone()
            if top_customer:
                context['top_customer'] = {
                    'name': top_customer[0],
                    'total': float(top_customer[1])
                }

            # Get invoice count
            cursor.execute("SELECT COUNT(*) FROM invoices")
            invoice_count = cursor.fetchone()[0] or 0
            context['total_invoices'] = invoice_count

            print(f"✅ Retrieved business context: {context}")

    except Exception as e:
        print(f"❌ Error getting business context: {e}")
        context = {'error': 'Could not connect to database'}

    return context

def call_ollama(prompt):
    """Call Ollama API"""
    try:
        response = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": "phi3:mini",
                "prompt": prompt,
                "stream": False,
                "options": {
                    "temperature": 0.7,
                    "top_p": 0.9,
                    "max_tokens": 1024
                }
            },
            timeout=30
        )

        if response.status_code == 200:
            return response.json().get('response', '').strip()
        else:
            return f"Error: {response.status_code} - {response.text}"

    except Exception as e:
        return f"Ollama connection error: {str(e)}"

@app.route('/query', methods=['POST'])
def enhanced_query():
    """Enhanced query with real business data"""
    try:
        data = request.json
        user_query = data.get('query', '').strip()

        if not user_query:
            return jsonify({'success': False, 'message': 'Query cannot be empty'})

        # Get real business context
        business_context = get_business_context()

        # Build enhanced prompt with real data
        prompt = f"""You are a bilingual business analyst for Neural Pulse. You have access to real business data.

Business Context:
- Customers: {business_context.get('customers', [])}
- Total Revenue: ${business_context.get('total_revenue', 0):,.2f}
- Top Customer: {business_context.get('top_customer', {}).get('name', 'N/A')} (${business_context.get('top_customer', {}).get('total', 0):,.2f})

User Query: {user_query}

Instructions:
1. Use the REAL data provided above in your response
2. If the query is in Arabic, respond in Arabic
3. If the query is in English, respond in English
4. Be specific and use actual customer names and numbers
5. Keep responses concise and helpful

Response:"""

        # Call Ollama
        ollama_response = call_ollama(prompt)

        return jsonify({
            'success': True,
            'message': ollama_response,
            'model': 'phi3:mini',
            'business_context': business_context,
            'offline': False
        })

    except Exception as e:
        print(f"❌ Error: {e}")
        return jsonify({
            'success': False,
            'message': f'Error processing query: {str(e)}'
        }), 500

@app.route('/test', methods=['GET'])
def test_connection():
    """Test both Ollama and database connections"""
    results = {}

    # Test Ollama
    try:
        ollama_response = call_ollama("Hello, just say 'Ollama is working!'")
        results['ollama'] = {'status': 'connected', 'response': ollama_response}
    except Exception as e:
        results['ollama'] = {'status': 'failed', 'error': str(e)}

    # Test Database
    try:
        context = get_business_context()
        results['database'] = {'status': 'connected', 'data': context}
    except Exception as e:
        results['database'] = {'status': 'failed', 'error': str(e)}

    return jsonify(results)

if __name__ == '__main__':
    print("🚀 Starting Neural Pulse Local Test Server with Ollama...")
    print("📊 Testing connections...")

    # Test connections on startup
    with app.app_context():
        test_results = test_connection()
        print(f"🔍 Connection Test Results: {json.dumps(test_results.get_json(), indent=2)}")

    print("🌐 Server running on http://localhost:5000")
    print("📝 Test queries:")
    print("   POST /query - Send business queries")
    print("   GET /test - Test connections")

    app.run(host='0.0.0.0', port=5000, debug=True)
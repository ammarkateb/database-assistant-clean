#!/usr/bin/env python3
"""
Neural Pulse AI Backend with Ollama Integration
Enhanced Flask app with Phi-3 Mini LLM for intelligent business analytics
"""

from flask import Flask, request, jsonify, session
from flask_cors import CORS
import logging
import os
import sys
import traceback
import hashlib
import json
import asyncio
from datetime import datetime, timedelta
from functools import wraps

# Import your existing modules
from db_assistant import DatabaseAssistant
from facial_auth import FacialAuthentication
from ollama_service import ollama_service, initialize_ollama

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['SESSION_COOKIE_SAMESITE'] = 'None'
app.config['SESSION_COOKIE_SECURE'] = False
app.config['SESSION_COOKIE_HTTPONLY'] = False
CORS(app, supports_credentials=True)
app.secret_key = os.getenv('SECRET_KEY', 'your-secret-key-change-this-in-production')

# Initialize components
DB_AVAILABLE = False
AI_AVAILABLE = False
FACIAL_AUTH_AVAILABLE = False
OLLAMA_AVAILABLE = False
db_assistant = None
facial_auth = None

# Conversation history storage for chat memory
conversation_histories = {}

def init_components():
    """Initialize all components with enhanced error handling"""
    global db_assistant, facial_auth, DB_AVAILABLE, AI_AVAILABLE, FACIAL_AUTH_AVAILABLE, OLLAMA_AVAILABLE

    # Initialize Database Assistant
    try:
        db_assistant = DatabaseAssistant()
        DB_AVAILABLE = True
        logger.info("✅ Database Assistant initialized successfully")
    except Exception as e:
        logger.error(f"❌ Failed to initialize Database Assistant: {e}")
        DB_AVAILABLE = False

    # Initialize Facial Authentication
    try:
        facial_auth = FacialAuthentication()
        FACIAL_AUTH_AVAILABLE = True
        logger.info("✅ Facial Authentication initialized successfully")
    except Exception as e:
        logger.error(f"❌ Failed to initialize Facial Authentication: {e}")
        FACIAL_AUTH_AVAILABLE = False

    # Initialize Ollama
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        OLLAMA_AVAILABLE = loop.run_until_complete(initialize_ollama())
        if OLLAMA_AVAILABLE:
            logger.info("✅ Ollama with Phi-3 Mini initialized successfully")
        else:
            logger.error("❌ Failed to initialize Ollama")
        loop.close()
    except Exception as e:
        logger.error(f"❌ Failed to initialize Ollama: {e}")
        OLLAMA_AVAILABLE = False

# Enhanced query endpoint with Ollama integration
@app.route('/query', methods=['POST'])
def enhanced_query():
    """Enhanced query processing with Ollama LLM"""
    try:
        data = request.json
        query = data.get('query', '').strip()
        conversation_history = data.get('conversation_history', [])

        if not query:
            return jsonify({
                'success': False,
                'message': 'Query cannot be empty'
            }), 400

        logger.info(f"📝 Processing query: {query}")

        # Get business context from database
        business_context = {}
        if DB_AVAILABLE and db_assistant:
            try:
                # Fetch real business data for context
                business_context = get_business_context()
            except Exception as e:
                logger.warning(f"⚠️ Could not fetch business context: {e}")

        # Use Ollama if available, fallback to original system
        if OLLAMA_AVAILABLE:
            try:
                # Generate business-focused prompt
                business_prompt = ollama_service.generate_business_prompt(query, business_context)

                # Get response from Phi-3 Mini
                response = ollama_service.generate_response_sync(business_prompt)

                if response.get('success'):
                    return jsonify({
                        'success': True,
                        'message': response['message'],
                        'model': 'phi3:mini',
                        'tokens': response.get('tokens', 0),
                        'business_context': len(business_context) > 0
                    })
                else:
                    raise Exception(response.get('message', 'Unknown error'))

            except Exception as e:
                logger.error(f"❌ Ollama processing failed: {e}")
                # Fall through to backup system

        # Fallback to existing system
        if DB_AVAILABLE and db_assistant:
            try:
                result = db_assistant.process_query(query, conversation_history)
                return jsonify(result)
            except Exception as e:
                logger.error(f"❌ Database assistant failed: {e}")

        # Final fallback
        return jsonify({
            'success': False,
            'message': 'AI services are currently unavailable. Please try again later.',
            'fallback': True
        }), 503

    except Exception as e:
        logger.error(f"❌ Query processing error: {e}")
        logger.error(traceback.format_exc())
        return jsonify({
            'success': False,
            'message': 'An error occurred while processing your query.'
        }), 500

def get_business_context():
    """Get business context for LLM prompts"""
    context = {}

    try:
        if db_assistant and hasattr(db_assistant, 'get_connection'):
            with db_assistant.get_connection() as conn:
                cursor = conn.cursor()

                # Get customer count
                cursor.execute("SELECT COUNT(*) FROM customers")
                context['total_customers'] = cursor.fetchone()[0]

                # Get invoice count
                cursor.execute("SELECT COUNT(*) FROM invoices")
                context['total_invoices'] = cursor.fetchone()[0]

                # Get top customers
                cursor.execute("""
                    SELECT c.customer_name, SUM(i.total_amount) as total_spent
                    FROM customers c
                    JOIN invoices i ON c.id = i.customer_id
                    GROUP BY c.id, c.customer_name
                    ORDER BY total_spent DESC
                    LIMIT 5
                """)
                context['top_customers'] = [
                    {'name': row[0], 'total_spent': float(row[1])}
                    for row in cursor.fetchall()
                ]

                # Get monthly revenue
                cursor.execute("""
                    SELECT
                        DATE_TRUNC('month', invoice_date) as month,
                        SUM(total_amount) as revenue
                    FROM invoices
                    WHERE invoice_date >= CURRENT_DATE - INTERVAL '12 months'
                    GROUP BY DATE_TRUNC('month', invoice_date)
                    ORDER BY month DESC
                    LIMIT 6
                """)
                context['monthly_revenue'] = [
                    {'month': row[0].strftime('%Y-%m'), 'revenue': float(row[1])}
                    for row in cursor.fetchall()
                ]

    except Exception as e:
        logger.warning(f"⚠️ Error getting business context: {e}")

    return context

# Health check for Ollama
@app.route('/ollama/health', methods=['GET'])
def ollama_health():
    """Check Ollama service health"""
    return jsonify({
        'ollama_available': OLLAMA_AVAILABLE,
        'model': 'phi3:mini' if OLLAMA_AVAILABLE else None,
        'status': 'ready' if OLLAMA_AVAILABLE else 'unavailable'
    })

# Test Ollama endpoint
@app.route('/ollama/test', methods=['POST'])
def test_ollama():
    """Test Ollama with a simple query"""
    if not OLLAMA_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Ollama is not available'
        }), 503

    try:
        data = request.json
        test_query = data.get('query', 'Hello, how are you?')

        response = ollama_service.generate_response_sync(test_query)
        return jsonify(response)

    except Exception as e:
        logger.error(f"❌ Ollama test failed: {e}")
        return jsonify({
            'success': False,
            'message': f'Test failed: {str(e)}'
        }), 500

# Import all existing routes from your original app.py
# (You would copy the rest of your routes here)

if __name__ == '__main__':
    logger.info("🚀 Starting Neural Pulse AI Backend with Ollama...")

    # Initialize all components
    init_components()

    # Print status
    print("\n" + "="*50)
    print("🧠 NEURAL PULSE AI BACKEND STATUS")
    print("="*50)
    print(f"🗄️  Database Assistant: {'✅ Ready' if DB_AVAILABLE else '❌ Failed'}")
    print(f"👁️  Facial Authentication: {'✅ Ready' if FACIAL_AUTH_AVAILABLE else '❌ Failed'}")
    print(f"🤖 Ollama + Phi-3 Mini: {'✅ Ready' if OLLAMA_AVAILABLE else '❌ Failed'}")
    print("="*50)

    # Start the Flask app
    port = int(os.environ.get('PORT', 8000))
    app.run(host='0.0.0.0', port=port, debug=False)
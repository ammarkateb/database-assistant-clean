from flask import Flask, request, jsonify
from flask_cors import CORS
import logging
import os
import sys
import traceback

# Setup logging first
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Try to import database assistant with detailed error logging
print("=== IMPORTING DATABASE ASSISTANT ===")
try:
    from db_assistant import DatabaseAssistant
    print("DatabaseAssistant imported successfully")
    DB_AVAILABLE = True
except ImportError as e:
    print(f"ImportError: Could not import DatabaseAssistant: {e}")
    print(f"Full traceback: {traceback.format_exc()}")
    DB_AVAILABLE = False
except Exception as e:
    print(f"Unexpected error importing DatabaseAssistant: {e}")
    print(f"Full traceback: {traceback.format_exc()}")
    DB_AVAILABLE = False

# Try to initialize database assistant
db_assistant = None
if DB_AVAILABLE:
    print("=== INITIALIZING DATABASE ASSISTANT ===")
    try:
        db_assistant = DatabaseAssistant()
        print("DatabaseAssistant initialized successfully")
        logger.info("DatabaseAssistant initialized successfully")
    except Exception as e:
        print(f"Failed to initialize DatabaseAssistant: {e}")
        print(f"Full traceback: {traceback.format_exc()}")
        logger.error(f"Failed to initialize DatabaseAssistant: {e}")
        DB_AVAILABLE = False

# Try to initialize Gemini AI with detailed error logging
print("=== INITIALIZING GEMINI AI ===")
try:
    import google.generativeai as genai
    print("google.generativeai imported successfully")
    
    gemini_api_key = os.getenv("GOOGLE_API_KEY")
    if gemini_api_key:
        print(f"GOOGLE_API_KEY found (length: {len(gemini_api_key)})")
        genai.configure(api_key=gemini_api_key)
        gemini_model = genai.GenerativeModel('gemini-1.5-flash')
        
        # Test the connection
        test_response = gemini_model.generate_content("Test")
        print("Gemini AI test successful")
        AI_AVAILABLE = True
        logger.info("Gemini AI initialized successfully")
    else:
        print("GOOGLE_API_KEY not found in environment variables")
        AI_AVAILABLE = False
        logger.warning("GOOGLE_API_KEY not found - AI features disabled")
except Exception as e:
    print(f"Failed to initialize Gemini AI: {e}")
    print(f"Full traceback: {traceback.format_exc()}")
    AI_AVAILABLE = False
    logger.error(f"Failed to initialize Gemini AI: {e}")

print(f"=== INITIALIZATION COMPLETE ===")
print(f"DB_AVAILABLE: {DB_AVAILABLE}")
print(f"AI_AVAILABLE: {AI_AVAILABLE}")

def is_database_question(query):
    """Determine if question is database-related"""
    database_keywords = [
        'customer', 'product', 'invoice', 'order', 'sale', 'revenue', 
        'profit', 'data', 'record', 'count', 'total', 'average', 
        'chart', 'graph', 'report', 'analysis', 'database', 'table'
    ]
    
    query_lower = query.lower()
    return any(keyword in query_lower for keyword in database_keywords)

def get_ai_response(query):
    """Get response from Gemini AI for general questions"""
    if not AI_AVAILABLE:
        return "AI service is not available. Please ask database-related questions instead."
    
    try:
        response = gemini_model.generate_content(query)
        return response.text
    except Exception as e:
        logger.error(f"Gemini AI error: {e}")
        return f"Sorry, I couldn't process your question. Error: {str(e)}"

@app.route('/')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'message': 'Smart AI Database Assistant is running!',
        'version': '2.0',
        'database_available': DB_AVAILABLE,
        'ai_available': AI_AVAILABLE,
        'capabilities': [
            'Database queries with charts',
            'General AI questions', 
            'Intelligent question routing'
        ]
    })

@app.route('/query', methods=['POST'])
def handle_query():
    """Handle both database and general queries intelligently"""
    try:
        data = request.get_json()
        
        if not data or 'query' not in data:
            return jsonify({
                'error': 'No query provided',
                'response': 'Please provide a query in the request body.',
                'success': False,
                'data': [],
                'chart': None
            }), 400

        user_query = data['query'].strip()
        
        if not user_query:
            return jsonify({
                'error': 'Empty query',
                'response': 'Please provide a non-empty query.',
                'success': False,
                'data': [],
                'chart': None
            }), 400

        logger.info(f"Processing query: {user_query}")
        
        # Determine if this is a database question
        if is_database_question(user_query) and DB_AVAILABLE:
            try:
                # Use the comprehensive database assistant method that returns structured data
                logger.info("Processing as database query with structured response")
                
                # Use the more comprehensive method that returns structured data
                response_data = db_assistant.execute_query_and_get_results(user_query)
                
                # The method returns a dict with success, message, data, chart, etc.
                return jsonify(response_data)
                
            except Exception as db_error:
                logger.error(f"Database query failed: {db_error}")
                
                # Fallback to AI if database fails
                if AI_AVAILABLE:
                    logger.info("Database failed, falling back to AI")
                    ai_response = get_ai_response(user_query)
                    return jsonify({
                        'response': f"Database temporarily unavailable. Here's what I can tell you: {ai_response}",
                        'query': user_query,
                        'source': 'ai_fallback',
                        'success': True,
                        'data': [],
                        'chart': None,
                        'note': 'Database connection failed, used AI instead'
                    })
                else:
                    return jsonify({
                        'error': 'Database unavailable',
                        'response': 'Sorry, the database is temporarily unavailable and AI fallback is also disabled.',
                        'query': user_query,
                        'source': 'error',
                        'success': False,
                        'data': [],
                        'chart': None
                    })
        
        else:
            # Handle general questions with AI
            if AI_AVAILABLE:
                logger.info("Processing as general AI query")
                ai_response = get_ai_response(user_query)
                return jsonify({
                    'response': ai_response,
                    'query': user_query,
                    'source': 'ai',
                    'success': True,
                    'data': [],
                    'chart': None
                })
            else:
                return jsonify({
                    'error': 'AI unavailable',
                    'response': 'Sorry, AI features are currently unavailable. Please try database-related questions instead.',
                    'query': user_query,
                    'source': 'error',
                    'success': False,
                    'data': [],
                    'chart': None
                })

    except Exception as e:
        logger.error(f"Error processing query: {e}")
        return jsonify({
            'error': 'Internal server error',
            'response': f'Sorry, there was an error processing your request: {str(e)}',
            'source': 'error',
            'success': False,
            'data': [],
            'chart': None
        }), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)

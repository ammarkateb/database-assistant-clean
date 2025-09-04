from flask import Flask, request, jsonify
from flask_cors import CORS
import logging
import os
import sys
import traceback
import google.generativeai as genai

# Import your database assistant
try:
    from db_assistant import DatabaseAssistant
    DB_AVAILABLE = True
except ImportError as e:
    print(f"Warning: Could not import DatabaseAssistant: {e}")
    DB_AVAILABLE = False

app = Flask(__name__)
CORS(app)

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize AI
GEMINI_API_KEY = os.getenv('GEMINI_API_KEY')
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)
    ai_model = genai.GenerativeModel('gemini-1.5-flash')
    AI_AVAILABLE = True
else:
    AI_AVAILABLE = False
    logger.warning("No Gemini API key found")

# Initialize database assistant
db_assistant = None
if DB_AVAILABLE:
    try:
        db_assistant = DatabaseAssistant()
        logger.info("Database Assistant initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize Database Assistant: {e}")
        DB_AVAILABLE = False

def is_database_question(query: str) -> bool:
    """Determine if question is about the database"""
    database_keywords = [
        'customer', 'customers', 'product', 'products', 'invoice', 'invoices',
        'sales', 'revenue', 'purchase', 'order', 'orders', 'how many', 'count',
        'total', 'sum', 'average', 'chart', 'graph', 'report', 'data',
        'database', 'table', 'record', 'show me', 'list', 'find'
    ]
    
    query_lower = query.lower()
    return any(keyword in query_lower for keyword in database_keywords)

def get_ai_response(query: str) -> str:
    """Get response from AI for general questions"""
    try:
        if AI_AVAILABLE:
            response = ai_model.generate_content(f"""
            You are a helpful AI assistant. Answer this question clearly and concisely:
            
            Question: {query}
            
            Provide a helpful, accurate response.
            """)
            return response.text
        else:
            return "AI service is currently unavailable. This appears to be a general question rather than a database query."
    except Exception as e:
        logger.error(f"AI response error: {e}")
        return f"I encountered an error while processing your general question: {str(e)}"

@app.route('/', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'message': 'Smart AI Database Assistant is running!',
        'database_available': DB_AVAILABLE,
        'ai_available': AI_AVAILABLE,
        'capabilities': [
            'Database queries with charts',
            'General AI questions',
            'Intelligent question routing'
        ],
        'version': '2.0'
    })

@app.route('/query', methods=['POST'])
def process_query():
    try:
        data = request.get_json()
        query = data.get('query', '')
        
        if not query:
            return jsonify({'error': 'No query provided'}), 400
        
        logger.info(f"Processing query: {query}")
        
        # Determine if this is a database or general question
        if is_database_question(query):
            # Database question - use your database assistant
            if DB_AVAILABLE and db_assistant:
                try:
                    response = db_assistant.get_response_from_db_assistant(query)
                    return jsonify({
                        'response': response,
                        'type': 'database',
                        'source': 'postgresql_database',
                        'status': 'success'
                    })
                except Exception as e:
                    logger.error(f"Database query failed: {e}")
                    # Fall back to AI for database questions if DB fails
                    fallback_response = get_ai_response(f"This is a database question but I cannot access the database right now. Please provide a general answer about: {query}")
                    return jsonify({
                        'response': f"Database temporarily unavailable. General answer: {fallback_response}",
                        'type': 'database_fallback',
                        'source': 'ai_fallback',
                        'status': 'fallback'
                    })
            else:
                # Database not available, use AI
                ai_response = get_ai_response(query)
                return jsonify({
                    'response': f"Database not connected. AI response: {ai_response}",
                    'type': 'database_unavailable',
                    'source': 'ai_only',
                    'status': 'ai_fallback'
                })
        
        else:
            # General question - use AI
            ai_response = get_ai_response(query)
            return jsonify({
                'response': ai_response,
                'type': 'general',
                'source': 'gemini_ai',
                'status': 'success'
            })
            
    except Exception as e:
        logger.error(f"Error processing query: {e}")
        return jsonify({
            'error': f'Processing error: {str(e)}',
            'status': 'error'
        }), 500

@app.route('/debug', methods=['GET'])
def debug_info():
    return jsonify({
        'files_in_directory': os.listdir('.'),
        'database_available': DB_AVAILABLE,
        'ai_available': AI_AVAILABLE,
        'environment_vars': {k: ('SET' if v else 'NOT_SET') for k, v in {
            'GEMINI_API_KEY': GEMINI_API_KEY,
            'DATABASE_URL': os.getenv('DATABASE_URL'),
            'DATABASE_HOST': os.getenv('DATABASE_HOST')
        }.items()},
        'capabilities': {
            'database_queries': DB_AVAILABLE,
            'ai_responses': AI_AVAILABLE,
            'intelligent_routing': True
        }
    })

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)

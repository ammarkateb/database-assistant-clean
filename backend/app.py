from flask import Flask, request, jsonify
from flask_cors import CORS
import logging
import os
import sys
import traceback
import time

# Setup detailed logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

print("="*50)
print("STARTING APPLICATION...")
print("="*50)

app = Flask(__name__)
CORS(app)

print("Flask app created successfully")

# Check environment variables first
print("="*50)
print("CHECKING ENVIRONMENT VARIABLES...")
print("="*50)

required_vars = ["GOOGLE_API_KEY", "DB_NAME", "DB_USER", "DB_PASSWORD", "DB_HOST", "DB_PORT"]
for var in required_vars:
    value = os.getenv(var)
    if value:
        print(f"{var}: {'*' * len(value[:10])}... (length: {len(value)})")
    else:
        print(f"{var}: NOT SET")

# Initialize facial auth with error handling
print("="*50)
print("INITIALIZING FACIAL AUTHENTICATION...")
print("="*50)

FACIAL_AUTH_AVAILABLE = False
facial_auth = None

try:
    print("Attempting to import facial_auth...")
    from facial_auth import FacialAuthSystem
    print("facial_auth imported successfully")
    
    print("Attempting to initialize FacialAuthSystem...")
    facial_auth = FacialAuthSystem()
    print("FacialAuthSystem initialized successfully")
    
    FACIAL_AUTH_AVAILABLE = True
    print("Facial Authentication: ENABLED")
except ImportError as e:
    print(f"ImportError in facial_auth: {e}")
    print(f"Full traceback: {traceback.format_exc()}")
    FACIAL_AUTH_AVAILABLE = False
except Exception as e:
    print(f"Unexpected error in facial_auth: {e}")
    print(f"Full traceback: {traceback.format_exc()}")
    FACIAL_AUTH_AVAILABLE = False

# Initialize database assistant with error handling
print("="*50)
print("INITIALIZING DATABASE ASSISTANT...")
print("="*50)

DB_AVAILABLE = False
db_assistant = None

try:
    print("Attempting to import DatabaseAssistant...")
    from db_assistant import DatabaseAssistant
    print("DatabaseAssistant imported successfully")
    
    print("Attempting to initialize DatabaseAssistant...")
    db_assistant = DatabaseAssistant()
    print("DatabaseAssistant initialized successfully")
    
    DB_AVAILABLE = True
    print("Database Assistant: ENABLED")
except ImportError as e:
    print(f"ImportError in db_assistant: {e}")
    print(f"Full traceback: {traceback.format_exc()}")
    DB_AVAILABLE = False
except Exception as e:
    print(f"Unexpected error in db_assistant: {e}")
    print(f"Full traceback: {traceback.format_exc()}")
    DB_AVAILABLE = False

# Initialize Gemini AI with error handling
print("="*50)
print("INITIALIZING GEMINI AI...")
print("="*50)

AI_AVAILABLE = False
gemini_model = None

try:
    print("Attempting to import google.generativeai...")
    import google.generativeai as genai
    print("google.generativeai imported successfully")
    
    gemini_api_key = os.getenv("GOOGLE_API_KEY")
    if gemini_api_key:
        print(f"GOOGLE_API_KEY found (length: {len(gemini_api_key)})")
        
        print("Configuring genai with API key...")
        genai.configure(api_key=gemini_api_key)
        
        print("Creating GenerativeModel...")
        gemini_model = genai.GenerativeModel('gemini-1.5-flash')
        
        print("Testing Gemini connection...")
        test_response = gemini_model.generate_content("Test", 
            generation_config=genai.types.GenerationConfig(
                temperature=0.1,
                max_output_tokens=10
            ))
        print(f"Gemini test response: {test_response.text[:50]}...")
        
        AI_AVAILABLE = True
        print("Gemini AI: ENABLED")
    else:
        print("GOOGLE_API_KEY not found in environment")
        AI_AVAILABLE = False
        print("Gemini AI: DISABLED (no API key)")
        
except Exception as e:
    print(f"Error in Gemini AI initialization: {e}")
    print(f"Full traceback: {traceback.format_exc()}")
    AI_AVAILABLE = False

print("="*50)
print("INITIALIZATION COMPLETE")
print("="*50)
print(f"DB_AVAILABLE: {DB_AVAILABLE}")
print(f"AI_AVAILABLE: {AI_AVAILABLE}")
print(f"FACIAL_AUTH_AVAILABLE: {FACIAL_AUTH_AVAILABLE}")
print("="*50)

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

def requires_admin_permission(query):
    """Check if query requires admin permissions"""
    admin_keywords = [
        'insert', 'update', 'delete', 'drop', 'create', 'alter', 
        'truncate', 'grant', 'revoke', 'add customer', 'add product',
        'delete customer', 'delete product', 'update customer', 'update product'
    ]
    query_lower = query.lower()
    return any(keyword in query_lower for keyword in admin_keywords)

@app.route('/')
def health_check():
    """Health check endpoint with detailed status"""
    print("Health check endpoint called")
    return jsonify({
        'status': 'healthy',
        'message': 'Smart AI Database Assistant is running!',
        'version': '2.1-debug',
        'timestamp': time.time(),
        'database_available': DB_AVAILABLE,
        'ai_available': AI_AVAILABLE,
        'facial_auth_available': FACIAL_AUTH_AVAILABLE,
        'environment': {
            'python_version': sys.version,
            'port': os.environ.get('PORT', 'Not set'),
            'railway_env': os.environ.get('RAILWAY_ENVIRONMENT', 'Not Railway')
        },
        'capabilities': [
            'Database queries with charts' if DB_AVAILABLE else 'Database: OFFLINE',
            'General AI questions' if AI_AVAILABLE else 'AI: OFFLINE', 
            'Facial recognition authentication' if FACIAL_AUTH_AVAILABLE else 'Facial Auth: OFFLINE'
        ]
    })

@app.route('/debug', methods=['GET'])
def debug_info():
    """Debug endpoint to show detailed system information"""
    return jsonify({
        'system_info': {
            'python_version': sys.version,
            'working_directory': os.getcwd(),
            'environment_variables': {k: ('SET' if v else 'NOT SET') for k, v in {
                'GOOGLE_API_KEY': os.getenv('GOOGLE_API_KEY'),
                'DB_NAME': os.getenv('DB_NAME'),
                'DB_USER': os.getenv('DB_USER'),
                'DB_PASSWORD': os.getenv('DB_PASSWORD'),
                'DB_HOST': os.getenv('DB_HOST'),
                'DB_PORT': os.getenv('DB_PORT'),
                'PORT': os.getenv('PORT'),
                'RAILWAY_ENVIRONMENT': os.getenv('RAILWAY_ENVIRONMENT')
            }.items()},
        },
        'component_status': {
            'database': DB_AVAILABLE,
            'ai': AI_AVAILABLE,
            'facial_auth': FACIAL_AUTH_AVAILABLE
        },
        'file_check': {
            'facial_auth_py': os.path.exists('facial_auth.py'),
            'db_assistant_py': os.path.exists('db_assistant.py'),
            'requirements_txt': os.path.exists('requirements.txt')
        }
    })

@app.route('/query', methods=['POST'])
def handle_query():
    """Handle both database and general queries intelligently"""
    try:
        print(f"Query endpoint called at {time.time()}")
        
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
        print(f"Processing query: {user_query}")
        
        if not user_query:
            return jsonify({
                'error': 'Empty query',
                'response': 'Please provide a non-empty query.',
                'success': False,
                'data': [],
                'chart': None
            }), 400

        # Check if this requires admin permissions
        if requires_admin_permission(user_query):
            return jsonify({
                'error': 'Admin permission required',
                'response': 'This operation requires admin authentication. Please use the secure query endpoint.',
                'success': False,
                'data': [],
                'chart': None,
                'requires_auth': True
            }), 403
        
        # Determine if this is a database question
        if is_database_question(user_query) and DB_AVAILABLE:
            try:
                print("Processing as database query")
                response_data = db_assistant.execute_query_and_get_results(user_query)
                return jsonify(response_data)
                
            except Exception as db_error:
                print(f"Database query failed: {db_error}")
                
                # Fallback to AI if database fails
                if AI_AVAILABLE:
                    print("Database failed, falling back to AI")
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
                print("Processing as general AI query")
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
        print(f"Error processing query: {e}")
        print(f"Full traceback: {traceback.format_exc()}")
        return jsonify({
            'error': 'Internal server error',
            'response': f'Sorry, there was an error processing your request: {str(e)}',
            'source': 'error',
            'success': False,
            'data': [],
            'chart': None
        }), 500

# Minimal auth endpoints to prevent startup failures
@app.route('/authenticate', methods=['POST'])
def authenticate():
    """Authenticate user with facial recognition"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            "success": False, 
            "message": "Facial authentication is not available"
        })
    
    try:
        data = request.get_json()
        if not data or 'image' not in data:
            return jsonify({"success": False, "message": "Image data required"})
        
        result = facial_auth.authenticate_user(data['image'])
        return jsonify(result)
        
    except Exception as e:
        print(f"Authentication error: {e}")
        return jsonify({"success": False, "message": f"Authentication failed: {str(e)}"})

@app.route('/setup-admin', methods=['POST'])
def setup_admin():
    """Setup admin user"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({"success": False, "message": "Facial authentication is not available"})
    
    try:
        data = request.get_json()
        if not data or 'name' not in data or 'image' not in data:
            return jsonify({"success": False, "message": "Name and image data required"})
        
        result = facial_auth.create_admin_user(data['name'], data['image'])
        return jsonify(result)
        
    except Exception as e:
        print(f"Admin setup error: {e}")
        return jsonify({"success": False, "message": f"Admin setup failed: {str(e)}"})

print("="*50)
print("FLASK APP SETUP COMPLETE")
print("="*50)

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    print(f"Starting Flask app on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)

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

# RE-ENABLE FACIAL AUTH FOR PRODUCTION
try:
    from facial_auth import FacialAuthSystem
    facial_auth = FacialAuthSystem()
    FACIAL_AUTH_AVAILABLE = True
    print("Facial Authentication enabled successfully")
except Exception as e:
    print(f"Failed to initialize Facial Authentication: {e}")
    FACIAL_AUTH_AVAILABLE = False

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
print(f"FACIAL_AUTH_AVAILABLE: {FACIAL_AUTH_AVAILABLE}")

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
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'message': 'Smart AI Database Assistant is running!',
        'version': '2.1',
        'database_available': DB_AVAILABLE,
        'ai_available': AI_AVAILABLE,
        'facial_auth_available': FACIAL_AUTH_AVAILABLE,
        'capabilities': [
            'Database queries with charts',
            'General AI questions', 
            'Intelligent question routing',
            'Facial recognition authentication'
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
        
        # Check if this requires admin permissions and user is authenticated
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
                # Use the comprehensive database assistant method that returns structured data
                logger.info("Processing as database query with structured response")
                
                response_data = db_assistant.execute_query_and_get_results(user_query)
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

# FACIAL AUTH ENDPOINTS - RE-ENABLED
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
            return jsonify({
                "success": False,
                "message": "Image data required"
            })
        
        image_data = data['image']
        result = facial_auth.authenticate_user(image_data)
        
        # Log authentication attempt
        if 'user' in result:
            facial_auth.log_access(
                result['user']['id'],
                result['user']['name'],
                'authentication',
                None,
                request.remote_addr,
                result['success']
            )
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Authentication error: {e}")
        return jsonify({
            "success": False,
            "message": f"Authentication failed: {str(e)}"
        })

@app.route('/setup-admin', methods=['POST'])
def setup_admin():
    """Setup admin user with facial recognition"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            "success": False, 
            "message": "Facial authentication is not available"
        })
    
    try:
        data = request.get_json()
        if not data or 'name' not in data or 'image' not in data:
            return jsonify({
                "success": False,
                "message": "Name and image data required"
            })
        
        name = data['name']
        image_data = data['image']
        
        result = facial_auth.create_admin_user(name, image_data)
        
        # Log admin creation attempt
        facial_auth.log_access(
            result.get('user_id', 'unknown'),
            name,
            'admin_setup',
            None,
            request.remote_addr,
            result['success']
        )
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Admin setup error: {e}")
        return jsonify({
            "success": False,
            "message": f"Admin setup failed: {str(e)}"
        })

@app.route('/facial-auth', methods=['POST'])
def authenticate_face():
    """Authenticate user via facial recognition"""
    return authenticate()  # Use the same logic as /authenticate

@app.route('/add-user', methods=['POST'])
def add_user():
    """Add new authorized user"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            "success": False, 
            "message": "Facial authentication is not available"
        })
    
    try:
        data = request.get_json()
        if not data or 'name' not in data or 'image' not in data:
            return jsonify({
                "success": False,
                "message": "Name and image data required"
            })
        
        name = data['name']
        image_data = data['image']
        role = data.get('role', 'read_only')
        
        result = facial_auth.add_authorized_user(name, role, image_data)
        
        # Log user addition attempt
        facial_auth.log_access(
            result.get('user_id', 'unknown'),
            name,
            'user_creation',
            None,
            request.remote_addr,
            result['success']
        )
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Add user error: {e}")
        return jsonify({
            "success": False,
            "message": f"Failed to add user: {str(e)}"
        })

@app.route('/users', methods=['GET'])
def get_users():
    """Get list of authorized users"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            "success": False, 
            "message": "Facial authentication is not available"
        })
    
    try:
        users = facial_auth.get_authorized_users()
        return jsonify({
            "success": True,
            "users": users
        })
        
    except Exception as e:
        logger.error(f"Get users error: {e}")
        return jsonify({
            "success": False,
            "message": f"Failed to get users: {str(e)}"
        })

@app.route('/secure-query', methods=['POST'])
def secure_database_query():
    """Execute database query with facial authentication"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            "success": False, 
            "message": "Facial authentication is not available"
        })
    
    try:
        data = request.get_json()
        
        if not data or 'query' not in data or 'image' not in data:
            return jsonify({
                "success": False,
                "message": "Query and image data required"
            })
        
        query = data['query']
        image_data = data['image']
        
        # Authenticate user first
        auth_result = facial_auth.authenticate_user(image_data)
        
        if not auth_result['success']:
            return jsonify({
                "success": False,
                "message": "Authentication failed: " + auth_result['message']
            })
        
        user = auth_result['user']
        permission_level = auth_result['permission_level']
        
        # Check query permissions
        permission_check = facial_auth.check_query_permission(query, permission_level)
        
        if not permission_check['allowed']:
            # Log unauthorized attempt
            facial_auth.log_access(
                user['id'],
                user['name'],
                'unauthorized_query',
                query,
                request.remote_addr,
                False
            )
            
            return jsonify({
                "success": False,
                "message": permission_check['message']
            })
        
        # Execute query if authorized
        if DB_AVAILABLE:
            response_data = db_assistant.execute_query_and_get_results(query)
            
            # Log successful query
            facial_auth.log_access(
                user['id'],
                user['name'],
                'secure_query',
                query,
                request.remote_addr,
                response_data['success']
            )
            
            # Add user info to response
            response_data['authenticated_user'] = user['name']
            response_data['permission_level'] = permission_level
            
            return jsonify(response_data)
        else:
            return jsonify({
                "success": False,
                "message": "Database not available"
            })
        
    except Exception as e:
        logger.error(f"Secure query error: {e}")
        return jsonify({
            "success": False,
            "message": f"Server error: {str(e)}"
        })

@app.route('/system-status', methods=['GET'])
def get_system_status():
    """Get system status"""
    try:
        status = {
            'database_available': DB_AVAILABLE,
            'ai_available': AI_AVAILABLE,
            'facial_auth_available': FACIAL_AUTH_AVAILABLE
        }
        
        if FACIAL_AUTH_AVAILABLE:
            auth_status = facial_auth.get_system_status()
            status.update(auth_status)
        
        return jsonify({
            'success': True,
            'status': status
        })
        
    except Exception as e:
        logger.error(f"System status error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to get system status: {str(e)}'
        })

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)

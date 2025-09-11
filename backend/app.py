from flask import Flask, request, jsonify, session
from flask_cors import CORS
import logging
import os
import sys
import traceback
import hashlib
import json
from datetime import datetime, timedelta

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
db_assistant = None
facial_auth = None

# Import database assistant
print("=== IMPORTING DATABASE ASSISTANT ===")
try:
    from db_assistant import DatabaseAssistant
    print("DatabaseAssistant imported successfully")
    DB_AVAILABLE = True
except Exception as e:
    print(f"Failed to import DatabaseAssistant: {e}")
    DB_AVAILABLE = False

# Import facial authentication
print("=== IMPORTING FACIAL AUTH SYSTEM ===")
try:
    from facial_auth import FacialAuthSystem
    print("FacialAuthSystem imported successfully")
    FACIAL_AUTH_AVAILABLE = True
except Exception as e:
    print(f"Failed to import FacialAuthSystem: {e}")
    FACIAL_AUTH_AVAILABLE = False

# Initialize database assistant
if DB_AVAILABLE:
    print("=== INITIALIZING DATABASE ASSISTANT ===")
    try:
        db_assistant = DatabaseAssistant()
        print("DatabaseAssistant initialized successfully")
        logger.info("DatabaseAssistant initialized successfully")
    except Exception as e:
        print(f"Failed to initialize DatabaseAssistant: {e}")
        logger.error(f"Failed to initialize DatabaseAssistant: {e}")
        DB_AVAILABLE = False

# Initialize facial auth
if FACIAL_AUTH_AVAILABLE:
    print("=== INITIALIZING FACIAL AUTH SYSTEM ===")
    try:
        facial_auth = FacialAuthSystem()
        print("Facial authentication system initialized successfully")
        logger.info("Facial authentication system initialized successfully")
    except Exception as e:
        print(f"Failed to initialize facial auth system: {e}")
        logger.error(f"Failed to initialize facial auth system: {e}")
        FACIAL_AUTH_AVAILABLE = False

# Initialize Gemini AI
print("=== INITIALIZING GEMINI AI ===")
try:
    import google.generativeai as genai
    gemini_api_key = os.getenv("GOOGLE_API_KEY")
    if gemini_api_key:
        genai.configure(api_key=gemini_api_key)
        gemini_model = genai.GenerativeModel('gemini-1.5-flash')
        test_response = gemini_model.generate_content("Test")
        AI_AVAILABLE = True
        logger.info("Gemini AI initialized successfully")
    else:
        AI_AVAILABLE = False
        logger.warning("GOOGLE_API_KEY not found")
except Exception as e:
    AI_AVAILABLE = False
    logger.error(f"Failed to initialize Gemini AI: {e}")

print(f"=== INITIALIZATION COMPLETE ===")
print(f"DB_AVAILABLE: {DB_AVAILABLE}")
print(f"AI_AVAILABLE: {AI_AVAILABLE}")
print(f"FACIAL_AUTH_AVAILABLE: {FACIAL_AUTH_AVAILABLE}")

# Helper functions
def get_current_user():
    """Get current authenticated user from session"""
    if 'user_id' in session and 'username' in session:
        return {
            'user_id': session['user_id'],
            'username': session['username'],
            'role': session['role'],
            'full_name': session['full_name']
        }
    return None

def require_auth(func):
    """Decorator to require authentication"""
    def wrapper(*args, **kwargs):
        user = get_current_user()
        if not user:
            return jsonify({
                'success': False,
                'message': 'Authentication required',
                'requires_login': True
            }), 401
        return func(user, *args, **kwargs)
    wrapper.__name__ = func.__name__
    return wrapper

def require_role(required_roles):
    """Decorator to require specific roles"""
    def decorator(func):
        def wrapper(*args, **kwargs):
            user = get_current_user()
            if not user:
                return jsonify({
                    'success': False,
                    'message': 'Authentication required',
                    'requires_login': True
                }), 401
            
            if user['role'] not in required_roles:
                return jsonify({
                    'success': False,
                    'message': f'Access denied. Required roles: {", ".join(required_roles)}',
                    'user_role': user['role']
                }), 403
            
            return func(user, *args, **kwargs)
        wrapper.__name__ = func.__name__
        return wrapper
    return decorator

# MAIN ENDPOINTS
@app.route('/')
def health_check():
    """Health check endpoint"""
    user = get_current_user()
    return jsonify({
        'status': 'healthy',
        'message': 'Smart AI Database Assistant is running!',
        'version': '3.1',
        'database_available': DB_AVAILABLE,
        'ai_available': AI_AVAILABLE,
        'facial_auth_available': FACIAL_AUTH_AVAILABLE,
        'authenticated_user': user['username'] if user else None,
        'features': [
            'Role-based authentication',
            'Permission-controlled database queries',
            'Receipt image processing',
            'Chart generation with access controls',
            'Audit logging',
            'Facial recognition authentication'
        ]
    })

# AUTHENTICATION ENDPOINTS
@app.route('/login', methods=['POST'])
def login():
    """User login with username and password"""
    if not DB_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Database not available'
        }), 500
    
    try:
        data = request.get_json()
        if not data or 'username' not in data or 'password' not in data:
            return jsonify({
                'success': False,
                'message': 'Username and password required'
            }), 400
        
        username = data['username'].strip()
        password = data['password']
        
        if not username or not password:
            return jsonify({
                'success': False,
                'message': 'Username and password cannot be empty'
            }), 400
        
        # Authenticate user
        auth_result = db_assistant.authenticate_user(username, password)
        
        if auth_result['success']:
            user = auth_result['user']
            
            # Set session
            session['user_id'] = user['user_id']
            session['username'] = user['username']
            session['role'] = user['role']
            session['full_name'] = user['full_name']
            session.permanent = True
            
            logger.info(f"User {username} logged in successfully")
            
            return jsonify({
                'success': True,
                'message': auth_result['message'],
                'user': {
                    'username': user['username'],
                    'role': user['role'],
                    'full_name': user['full_name']
                }
            })
        else:
            logger.warning(f"Failed login attempt for username: {username}")
            return jsonify(auth_result), 401
            
    except Exception as e:
        logger.error(f"Login error: {e}")
        return jsonify({
            'success': False,
            'message': 'Login failed due to server error'
        }), 500

@app.route('/setup-admin', methods=['POST'])
def setup_initial_admin():
    """One-time setup to create initial admin user"""
    if not DB_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Database not available'
        }), 500
    
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Check if any admin already exists
            cursor.execute("SELECT COUNT(*) FROM users WHERE role = 'admin'")
            admin_count = cursor.fetchone()[0]
            
            if admin_count > 0:
                return jsonify({
                    'success': False,
                    'message': 'Admin user already exists. Setup not allowed.'
                }), 400
            
            # Create the admin user
            username = 'AmmarKateb'
            password = 'Hexen2002_23'
            full_name = 'Ammar Kateb'
            email = 'ammar.kateb@company.com'
            role = 'admin'
            
            # Create password hash
            salt = hashlib.sha256(username.encode()).hexdigest()[:16]
            password_hash = hashlib.sha256((password + salt).encode()).hexdigest()
            
            cursor.execute("""
                INSERT INTO users (username, email, password_hash, salt, full_name, role, is_active)
                VALUES (%s, %s, %s, %s, %s, %s, true)
                RETURNING user_id
            """, (username, email, password_hash, salt, full_name, role))
            
            admin_user_id = cursor.fetchone()[0]
            conn.commit()
            
            logger.info(f"Initial admin user created: {username}")
            
            return jsonify({
                'success': True,
                'message': f'Admin user {username} created successfully',
                'user_id': admin_user_id
            })
            
    except Exception as e:
        logger.error(f"Error creating admin user: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to create admin user'
        }), 500

@app.route('/logout', methods=['POST'])
def logout():
    """User logout"""
    username = session.get('username', 'Unknown')
    session.clear()
    logger.info(f"User {username} logged out")
    
    return jsonify({
        'success': True,
        'message': 'Logged out successfully'
    })

@app.route('/me', methods=['GET'])
@require_auth
def get_current_user_info(user):
    """Get current user information"""
    try:
        # Get user's accessible charts
        charts = db_assistant.get_user_accessible_charts(user['user_id'])
        
        return jsonify({
            'success': True,
            'user': user,
            'accessible_charts': len(charts),
            'charts': charts
        })
        
    except Exception as e:
        logger.error(f"Error getting user info: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get user information'
        }), 500

# QUERY ENDPOINTS
@app.route('/query', methods=['POST'])
@require_auth
def handle_authenticated_query(user):
    """Handle database queries with authentication and permissions"""
    try:
        data = request.get_json()
        
        if not data or 'query' not in data:
            return jsonify({
                'success': False,
                'message': 'No query provided'
            }), 400

        user_query = data['query'].strip()
        
        if not user_query:
            return jsonify({
                'success': False,
                'message': 'Query cannot be empty'
            }), 400

        logger.info(f"Processing query from {user['username']} ({user['role']}): {user_query}")
        
        # Execute query with user permissions
        response_data = db_assistant.execute_query_with_permissions(user_query, user)
        
        # Add user context to response
        response_data['authenticated_user'] = user['username']
        response_data['user_role'] = user['role']
        
        return jsonify(response_data)
        
    except Exception as e:
        logger.error(f"Error processing query: {e}")
        return jsonify({
            'success': False,
            'message': f'Query processing failed: {str(e)}'
        }), 500

# FACIAL AUTHENTICATION ENDPOINTS
@app.route('/facial-auth/authenticate', methods=['POST'])
def facial_authenticate():
    """Authenticate user using facial recognition"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available'
        }), 500
    
    try:
        data = request.get_json()
        
        if not data or 'image' not in data:
            return jsonify({
                'success': False,
                'message': 'Image data required'
            }), 400
        
        image_base64 = data['image']
        
        # Clean base64 string if it has data URL prefix
        if image_base64.startswith('data:'):
            image_base64 = image_base64.split(',')[1]
        
        # Authenticate using facial recognition
        result = facial_auth.authenticate_user(image_base64)
        
        if result['success']:
            # Log successful facial auth
            user_ip = request.environ.get('HTTP_X_FORWARDED_FOR', request.remote_addr)
            facial_auth.log_access(
                result['user']['id'],
                result['user']['name'],
                'facial_login',
                'Face authentication successful',
                user_ip,
                True
            )
            
            logger.info(f"Facial authentication successful for user: {result['user']['name']}")
        else:
            # Log failed facial auth
            user_ip = request.environ.get('HTTP_X_FORWARDED_FOR', request.remote_addr)
            facial_auth.log_access(
                None,
                'Unknown',
                'facial_login_failed',
                'Face authentication failed',
                user_ip,
                False
            )
            
            logger.warning("Facial authentication failed")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Facial authentication error: {e}")
        return jsonify({
            'success': False,
            'message': f'Authentication failed: {str(e)}'
        }), 500

@app.route('/facial-auth/create-admin', methods=['POST'])
def create_facial_admin():
    """Create admin user for facial authentication"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available'
        }), 500
    
    try:
        data = request.get_json()
        
        if not data or 'name' not in data or 'image' not in data:
            return jsonify({
                'success': False,
                'message': 'Name and image data required'
            }), 400
        
        name = data['name'].strip()
        image_base64 = data['image']
        
        if not name:
            return jsonify({
                'success': False,
                'message': 'Name cannot be empty'
            }), 400
        
        # Clean base64 string if it has data URL prefix
        if image_base64.startswith('data:'):
            image_base64 = image_base64.split(',')[1]
        
        # Create admin user
        result = facial_auth.create_admin_user(name, image_base64)
        
        if result['success']:
            logger.info(f"Facial auth admin user created: {name}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Create facial admin error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to create admin user: {str(e)}'
        }), 500

@app.route('/facial-auth/create-user', methods=['POST'])
def create_facial_user():
    """Create regular user for facial authentication"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available'
        }), 500
    
    try:
        data = request.get_json()
        
        if not data or 'name' not in data or 'image' not in data:
            return jsonify({
                'success': False,
                'message': 'Name and image data required'
            }), 400
        
        name = data['name'].strip()
        image_base64 = data['image']
        permission_level = data.get('permission_level', 'read_only')
        
        if not name:
            return jsonify({
                'success': False,
                'message': 'Name cannot be empty'
            }), 400
        
        # Validate permission level
        valid_permissions = ['read_only', 'admin']
        if permission_level not in valid_permissions:
            return jsonify({
                'success': False,
                'message': f'Invalid permission level. Must be one of: {", ".join(valid_permissions)}'
            }), 400
        
        # Clean base64 string if it has data URL prefix
        if image_base64.startswith('data:'):
            image_base64 = image_base64.split(',')[1]
        
        # Create regular user
        result = facial_auth.create_regular_user(name, image_base64, permission_level)
        
        if result['success']:
            logger.info(f"Facial auth user created: {name} with permission: {permission_level}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Create facial user error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to create user: {str(e)}'
        }), 500

@app.route('/facial-auth/users', methods=['GET'])
def get_facial_users():
    """Get all facial authentication users"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available'
        }), 500
    
    try:
        users = facial_auth.get_authorized_users()
        
        return jsonify({
            'success': True,
            'users': users,
            'count': len(users)
        })
        
    except Exception as e:
        logger.error(f"Get facial users error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to get users: {str(e)}'
        }), 500

@app.route('/facial-auth/delete-user/<user_id>', methods=['DELETE'])
def delete_facial_user(user_id):
    """Delete facial authentication user"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available'
        }), 500
    
    try:
        result = facial_auth.delete_user(user_id)
        
        if result['success']:
            logger.info(f"Facial auth user deleted: {user_id}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Delete facial user error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to delete user: {str(e)}'
        }), 500

@app.route('/facial-auth/status', methods=['GET'])
def get_facial_auth_status():
    """Get facial authentication system status"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available',
            'status': {
                'available': False,
                'total_users': 0,
                'admin_users': 0,
                'regular_users': 0
            }
        })
    
    try:
        status = facial_auth.get_system_status()
        
        return jsonify({
            'success': True,
            'status': status
        })
        
    except Exception as e:
        logger.error(f"Facial auth status error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to get status: {str(e)}'
        }), 500

# ADMIN ENDPOINTS
@app.route('/admin/users', methods=['GET'])
@require_role(['admin'])
def get_all_users(user):
    """Get all users (admin only)"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT user_id, username, full_name, role, created_at, last_login, is_active, email
                FROM users
                ORDER BY created_at DESC
            """)
            
            users = []
            for row in cursor.fetchall():
                users.append({
                    'user_id': row[0],
                    'username': row[1],
                    'full_name': row[2],
                    'role': row[3],
                    'created_at': row[4].isoformat() if row[4] else None,
                    'last_login': row[5].isoformat() if row[5] else None,
                    'is_active': row[6],
                    'email': row[7] if len(row) > 7 else ''
                })
            
            return jsonify({
                'success': True,
                'users': users
            })
            
    except Exception as e:
        logger.error(f"Error getting users: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get users'
        }), 500

@app.route('/admin/create-user', methods=['POST'])
@require_role(['admin'])
def create_user(user):
    """Create new user (admin only)"""
    try:
        data = request.get_json()
        
        required_fields = ['username', 'password', 'full_name', 'role', 'email']
        for field in required_fields:
            if not data or field not in data:
                return jsonify({
                    'success': False,
                    'message': f'Field {field} is required'
                }), 400
        
        username = data['username'].strip()
        password = data['password']
        full_name = data['full_name'].strip()
        role = data['role'].strip().lower()
        email = data['email'].strip()
        
        # Validate role
        valid_roles = ['visitor', 'viewer', 'manager', 'admin']
        if role not in valid_roles:
            return jsonify({
                'success': False,
                'message': f'Invalid role. Must be one of: {", ".join(valid_roles)}'
            }), 400
        
        # Create password hash
        salt = hashlib.sha256(username.encode()).hexdigest()[:16]
        password_hash = hashlib.sha256((password + salt).encode()).hexdigest()
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Check if username already exists
            cursor.execute("SELECT username FROM users WHERE username = %s", (username,))
            if cursor.fetchone():
                return jsonify({
                    'success': False,
                    'message': 'Username already exists'
                }), 400
            
            # Create user
            cursor.execute("""
                INSERT INTO users (username, email, password_hash, salt, full_name, role, is_active)
                VALUES (%s, %s, %s, %s, %s, %s, true)
                RETURNING user_id
            """, (username, email, password_hash, salt, full_name, role))
            
            new_user_id = cursor.fetchone()[0]
            conn.commit()
            
            # Log admin action
            db_assistant.log_user_activity(
                user['user_id'], 
                'create_user', 
                f'Created user {username} with role {role}'
            )
            
            logger.info(f"Admin {user['username']} created user {username} with role {role}")
            
            return jsonify({
                'success': True,
                'message': f'User {username} created successfully',
                'user_id': new_user_id
            }), 201
            
    except Exception as e:
        logger.error(f"Error creating user: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to create user'
        }), 500

@app.route('/admin/audit-log', methods=['GET'])
@require_role(['admin'])
def get_audit_log(user):
    """Get audit log (admin only)"""
    try:
        limit = request.args.get('limit', 100, type=int)
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT al.timestamp, u.username, al.action, al.details
                FROM audit_log al
                LEFT JOIN users u ON al.user_id = u.user_id
                ORDER BY al.timestamp DESC
                LIMIT %s
            """, (limit,))
            
            logs = []
            for row in cursor.fetchall():
                logs.append({
                    'timestamp': row[0].isoformat() if row[0] else None,
                    'username': row[1] or 'System',
                    'action': row[2],
                    'details': row[3]
                })
            
            return jsonify({
                'success': True,
                'logs': logs
            })
            
    except Exception as e:
        logger.error(f"Error getting audit log: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get audit log'
        }), 500

# SYSTEM STATUS
@app.route('/system-status', methods=['GET'])
@require_auth
def get_system_status(user):
    """Get system status for authenticated user"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Get basic stats
            cursor.execute("SELECT COUNT(*) FROM customers")
            customers_count = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM products")
            products_count = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM invoices")
            invoices_count = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM receipt_captures WHERE status = 'pending_review'")
            pending_receipts = cursor.fetchone()[0]
            
            # Get facial auth stats if available
            facial_auth_stats = {}
            if FACIAL_AUTH_AVAILABLE:
                try:
                    facial_status = facial_auth.get_system_status()
                    facial_auth_stats = {
                        'total_facial_users': facial_status.get('total_users', 0),
                        'facial_admin_users': facial_status.get('admin_users', 0),
                        'facial_regular_users': facial_status.get('regular_users', 0),
                        'facial_auth_status': facial_status.get('status', 'unknown')
                    }
                except Exception as e:
                    logger.error(f"Error getting facial auth stats: {e}")
                    facial_auth_stats = {
                        'total_facial_users': 0,
                        'facial_admin_users': 0,
                        'facial_regular_users': 0,
                        'facial_auth_status': 'error'
                    }
            
            status = {
                'database_available': DB_AVAILABLE,
                'ai_available': AI_AVAILABLE,
                'facial_auth_available': FACIAL_AUTH_AVAILABLE,
                'user_role': user['role'],
                'statistics': {
                    'customers': customers_count,
                    'products': products_count,
                    'invoices': invoices_count,
                    'pending_receipts': pending_receipts,
                    **facial_auth_stats
                }
            }
            
            return jsonify({
                'success': True,
                'status': status
            })
            
    except Exception as e:
        logger.error(f"System status error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to get system status: {str(e)}'
        }), 500

# ERROR HANDLERS
@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'success': False,
        'message': 'Endpoint not found'
    }), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({
        'success': False,
        'message': 'Internal server error'
    }), 500

if __name__ == '__main__':
    # Set session lifetime
    app.permanent_session_lifetime = timedelta(hours=24)
    
    # Handle PORT environment variable properly for Railway
    port_env = os.environ.get('PORT', '5000')
    print(f"PORT environment variable: {port_env}")
    
    try:
        port = int(port_env)
        print(f"Successfully parsed port: {port}")
    except (ValueError, TypeError):
        print(f"Failed to parse port '{port_env}', using default 5000")
        port = 5000
    
    print(f"Starting Flask app on 0.0.0.0:{port}")
    app.run(host='0.0.0.0', port=port, debug=False)

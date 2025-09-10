from flask import Flask, request, jsonify, session
from flask_cors import CORS
import logging
import os
import sys
import traceback
import hashlib
import json
from datetime import datetime, timedelta

# Setup logging first
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['SESSION_COOKIE_SAMESITE'] = 'None'
app.config['SESSION_COOKIE_SECURE'] = False
app.config['SESSION_COOKIE_HTTPONLY'] = False
CORS(app, supports_credentials=True)
app.secret_key = os.getenv('SECRET_KEY', 'your-secret-key-change-this-in-production')

# Import updated database assistant
print("=== IMPORTING DATABASE ASSISTANT ===")
try:
    from db_assistant import DatabaseAssistant, get_authenticated_db_response
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

# Initialize database assistant
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

# Initialize Gemini AI
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
        'version': '3.0',
        'database_available': DB_AVAILABLE,
        'ai_available': AI_AVAILABLE,
        'authenticated_user': user['username'] if user else None,
        'features': [
            'Role-based authentication',
            'Permission-controlled database queries',
            'Receipt image processing',
            'Chart generation with access controls',
            'Audit logging'
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

@app.route('/chart/<int:chart_id>', methods=['GET'])
@require_auth
def get_chart_data(user, chart_id):
    """Get specific chart data for authenticated user"""
    try:
        # Check if user can access this chart
        accessible_charts = db_assistant.get_user_accessible_charts(user['user_id'])
        chart = next((c for c in accessible_charts if c['chart_id'] == chart_id), None)
        
        if not chart:
            return jsonify({
                'success': False,
                'message': 'Chart not found or access denied'
            }), 403
        
        # Execute chart query with user permissions
        response_data = db_assistant.execute_query_with_permissions(chart['chart_name'], user)
        
        if response_data['success']:
            response_data['chart_info'] = {
                'chart_id': chart['chart_id'],
                'chart_name': chart['chart_name'],
                'chart_type': chart['chart_type'],
                'category': chart['category'],
                'can_export': chart['can_export']
            }
        
        return jsonify(response_data)
        
    except Exception as e:
        logger.error(f"Error getting chart data: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get chart data'
        }), 500

# RECEIPT PROCESSING ENDPOINTS
@app.route('/receipt/upload', methods=['POST'])
@require_role(['manager', 'admin'])
def upload_receipt(user):
    """Upload receipt image for processing"""
    try:
        data = request.get_json()
        
        if not data or 'image' not in data:
            return jsonify({
                'success': False,
                'message': 'Receipt image data required'
            }), 400
        
        image_base64 = data['image']
        
        # Process receipt image
        result = db_assistant.process_receipt_image(user['user_id'], image_base64)
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Receipt upload error: {e}")
        return jsonify({
            'success': False,
            'message': f'Receipt upload failed: {str(e)}'
        }), 500

@app.route('/receipt/<int:capture_id>/approve', methods=['POST'])
@require_role(['manager', 'admin'])
def approve_receipt(user, capture_id):
    """Approve receipt and create invoice"""
    try:
        data = request.get_json()
        
        if not data or 'customer_id' not in data:
            return jsonify({
                'success': False,
                'message': 'Customer ID required'
            }), 400
        
        customer_id = data['customer_id']
        corrections = data.get('corrections', {})
        
        # Approve receipt and create invoice
        result = db_assistant.approve_receipt_and_create_invoice(
            capture_id, user['user_id'], customer_id, corrections
        )
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Receipt approval error: {e}")
        return jsonify({
            'success': False,
            'message': f'Receipt approval failed: {str(e)}'
        }), 500

@app.route('/receipts/pending', methods=['GET'])
@require_role(['manager', 'admin'])
def get_pending_receipts(user):
    """Get receipts pending approval"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT rc.capture_id, rc.captured_at, rc.extracted_vendor,
                       rc.extracted_total, rc.confidence_score, u.username
                FROM receipt_captures rc
                JOIN users u ON rc.user_id = u.user_id
                WHERE rc.status = 'pending_review'
                ORDER BY rc.captured_at DESC
            """)
            
            receipts = []
            for row in cursor.fetchall():
                receipts.append({
                    'capture_id': row[0],
                    'captured_at': row[1].isoformat() if row[1] else None,
                    'vendor': row[2],
                    'total': float(row[3]) if row[3] else 0,
                    'confidence': float(row[4]) if row[4] else 0,
                    'uploaded_by': row[5]
                })
            
            return jsonify({
                'success': True,
                'receipts': receipts,
                'count': len(receipts)
            })
            
    except Exception as e:
        logger.error(f"Error getting pending receipts: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get pending receipts'
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
                SELECT user_id, username, full_name, role, created_at, last_login, is_active
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
                    'is_active': row[6]
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
            })
            
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
            
            status = {
                'database_available': DB_AVAILABLE,
                'ai_available': AI_AVAILABLE,
                'user_role': user['role'],
                'statistics': {
                    'customers': customers_count,
                    'products': products_count,
                    'invoices': invoices_count,
                    'pending_receipts': pending_receipts
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

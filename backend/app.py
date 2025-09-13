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

# Conversation history storage for chat memory
conversation_histories = {}

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
        print(f"Full traceback: {traceback.format_exc()}")
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

def get_user_conversation_history(user_id):
    """Get conversation history for a user"""
    return conversation_histories.get(str(user_id), [])

def add_to_conversation_history(user_id, sender, content):
    """Add message to user's conversation history"""
    user_id_str = str(user_id)
    if user_id_str not in conversation_histories:
        conversation_histories[user_id_str] = []
    
    conversation_histories[user_id_str].append({
        'sender': sender,
        'content': content,
        'timestamp': datetime.now().isoformat()
    })
    
    # Keep only last 20 messages for memory efficiency
    if len(conversation_histories[user_id_str]) > 20:
        conversation_histories[user_id_str] = conversation_histories[user_id_str][-20:]

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

# Add these endpoints to your app.py Flask application

# Face enrollment endpoints
@app.route('/face-auth/enroll-sample', methods=['POST'])
@require_auth
def enroll_face_sample(user):
    """Enroll a single face sample (1-5) for current user"""
    try:
        data = request.get_json()
        
        if not data or 'face_features' not in data or 'sample_number' not in data:
            return jsonify({
                'success': False,
                'message': 'Face features and sample number required'
            }), 400
        
        face_features = data['face_features']
        sample_number = data['sample_number']
        
        result = db_assistant.enroll_face_sample(user['user_id'], face_features, sample_number)
        
        if result['success']:
            logger.info(f"Face sample {sample_number} enrolled for user: {user['username']}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Face sample enrollment error: {e}")
        return jsonify({
            'success': False,
            'message': f'Face sample enrollment failed: {str(e)}'
        }), 500

@app.route('/face-auth/complete-enrollment', methods=['POST'])
@require_auth
def complete_face_enrollment(user):
    """Complete face enrollment and enable face auth"""
    try:
        result = db_assistant.complete_face_enrollment(user['user_id'])
        
        if result['success']:
            logger.info(f"Face enrollment completed for user: {user['username']}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Face enrollment completion error: {e}")
        return jsonify({
            'success': False,
            'message': f'Face enrollment completion failed: {str(e)}'
        }), 500

@app.route('/face-auth/samples-count', methods=['GET'])
@require_auth
def get_face_samples_count(user):
    """Get number of face samples enrolled for current user"""
    try:
        count = db_assistant.get_user_face_samples_count(user['user_id'])
        
        return jsonify({
            'success': True,
            'samples_enrolled': count,
            'samples_needed': max(0, 5 - count),
            'enrollment_complete': count >= 3
        })
        
    except Exception as e:
        logger.error(f"Error getting face samples count: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get face samples count'
        }), 500

# Face verification endpoint
@app.route('/face-auth/verify', methods=['POST'])
def verify_face_login():
    """Verify face for login (with 3-attempt limit and 0.75 confidence)"""
    if not DB_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Database not available'
        }), 500
    
    try:
        data = request.get_json()
        
        if not data or 'face_features' not in data:
            return jsonify({
                'success': False,
                'message': 'Face features required'
            }), 400
        
        face_features = data['face_features']
        
        # Track failed attempts in session
        if 'face_auth_attempts' not in session:
            session['face_auth_attempts'] = 0
        
        # Check if too many attempts
        if session['face_auth_attempts'] >= 3:
            return jsonify({
                'success': False,
                'message': 'Too many failed face authentication attempts. Please use username/password login.',
                'redirect_to_login': True,
                'attempts_exceeded': True
            }), 429
        
        result = db_assistant.verify_face_with_samples(face_features)
        
        if result['success']:
            user = result['user']
            
            # Clear failed attempts on success
            session['face_auth_attempts'] = 0
            
            # Set user session
            session['user_id'] = user['user_id']
            session['username'] = user['username']
            session['role'] = user['role']
            session['full_name'] = user['full_name']
            session.permanent = True
            
            # Initialize conversation history
            if str(user['user_id']) not in conversation_histories:
                conversation_histories[str(user['user_id'])] = []
            
            logger.info(f"Face authentication successful for user: {user['username']} (confidence: {result['confidence']:.3f})")
            
            return jsonify({
                'success': True,
                'user': user,
                'confidence': result['confidence'],
                'matched_sample': result['matched_sample'],
                'message': result['message']
            })
        else:
            # Increment failed attempts
            session['face_auth_attempts'] += 1
            attempts_remaining = 3 - session['face_auth_attempts']
            
            logger.warning(f"Face authentication failed (attempt {session['face_auth_attempts']}/3)")
            
            if attempts_remaining > 0:
                return jsonify({
                    'success': False,
                    'message': f"{result['message']} ({attempts_remaining} attempts remaining)",
                    'attempts_remaining': attempts_remaining,
                    'confidence': result.get('confidence', 0.0)
                })
            else:
                return jsonify({
                    'success': False,
                    'message': 'Face authentication failed. Redirecting to username/password login.',
                    'redirect_to_login': True,
                    'attempts_exceeded': True
                })
                
    except Exception as e:
        logger.error(f"Face verification error: {e}")
        return jsonify({
            'success': False,
            'message': f'Face verification failed: {str(e)}'
        }), 500

# Face auth management endpoints
@app.route('/face-auth/reset', methods=['POST'])
@require_auth
def reset_face_auth(user):
    """Reset face authentication for re-registration"""
    try:
        result = db_assistant.reset_user_face_auth(user['user_id'])
        
        if result['success']:
            logger.info(f"Face auth reset for user: {user['username']}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Face auth reset error: {e}")
        return jsonify({
            'success': False,
            'message': f'Face auth reset failed: {str(e)}'
        }), 500

@app.route('/face-auth/status', methods=['GET'])
@require_auth
def get_face_auth_status(user):
    """Get face authentication status for current user"""
    try:
        samples_count = db_assistant.get_user_face_samples_count(user['user_id'])
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT face_auth_enabled FROM users WHERE user_id = %s
            """, (user['user_id'],))
            
            result = cursor.fetchone()
            face_auth_enabled = result[0] if result else False
        
        return jsonify({
            'success': True,
            'face_auth_enabled': face_auth_enabled,
            'samples_enrolled': samples_count,
            'samples_needed': max(0, 5 - samples_count),
            'enrollment_complete': samples_count >= 3,
            'can_re_register': True,
            'confidence_threshold': 0.75,
            'max_samples': 5,
            'min_samples_required': 3
        })
        
    except Exception as e:
        logger.error(f"Error getting face auth status: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get face auth status'
        }), 500

# Clear face auth attempts (for testing/admin)
@app.route('/face-auth/clear-attempts', methods=['POST'])
def clear_face_auth_attempts():
    """Clear face authentication attempts for current session"""
    try:
        session['face_auth_attempts'] = 0
        
        return jsonify({
            'success': True,
            'message': 'Face authentication attempts cleared'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Failed to clear attempts: {str(e)}'
        }), 500

# MAIN ENDPOINTS
@app.route('/')
def health_check():
    """Health check endpoint"""
    user = get_current_user()
    return jsonify({
        'status': 'healthy',
        'message': 'Neural Pulse AI Database Assistant is running!',
        'version': '4.0',
        'database_available': DB_AVAILABLE,
        'ai_available': AI_AVAILABLE,
        'facial_auth_available': FACIAL_AUTH_AVAILABLE,
        'authenticated_user': user['username'] if user else None,
        'features': [
            'Role-based authentication',
            'Permission-controlled database queries',
            'Conversation memory system',
            'Enhanced facial recognition with tolerance',
            'Purple-teal themed UI',
            'Admin user management',
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
            
            # Initialize conversation history for user
            if str(user['user_id']) not in conversation_histories:
                conversation_histories[str(user['user_id'])] = []
            
            logger.info(f"User {username} logged in successfully")
            
            return jsonify({
                'success': True,
                'message': auth_result['message'],
                'user': {
                    'user_id': user['user_id'],
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


# Add this near the other endpoint definitions (around line 600)

@app.route('/face-auth/enroll', methods=['POST'])
def face_auth_enroll():
    """Alias for /facial-auth/register to match Flutter frontend calls"""
    return register_face()

@app.route('/invoices', methods=['GET'])
@require_auth
def get_invoices(user):
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT invoice_id, customer_id, invoice_date, total_amount, status
                FROM invoices 
                ORDER BY invoice_date DESC 
                LIMIT 100
            """)
            
            invoices = []
            for row in cursor.fetchall():
                invoices.append({
                    'invoice_id': row[0] or 0,
                    'customer_id': row[1] or 0,
                    'invoice_date': row[2].isoformat() if row[2] else None,
                    'total_amount': float(row[3] or 0),  # Handle null values
                    'status': row[4] or 'pending'
                })
            
            return jsonify({
                'success': True,
                'invoices': invoices,
                'count': len(invoices)
            })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

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
    user = get_current_user()
    username = user['username'] if user else 'Unknown'
    user_id = user['user_id'] if user else None
    
    # Clear conversation history for this user session
    if user_id and str(user_id) in conversation_histories:
        del conversation_histories[str(user_id)]
    
    session.clear()
    logger.info(f"User {username} logged out")
    
    return jsonify({
        'success': True,
        'message': 'Logged out successfully'
    })

@app.route('/query', methods=['POST'])
@require_auth
def handle_authenticated_query(user):
    """Handle database queries with authentication, permissions, and conversation memory"""
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
        
        # Get conversation history for this user
        conversation_history = get_user_conversation_history(user['user_id'])
        
        # Add user's query to conversation history
        add_to_conversation_history(user['user_id'], 'user', user_query)
        
        # Execute query with user permissions and conversation context
        response_data = db_assistant.execute_query_with_permissions(
            user_query, 
            user, 
            conversation_history=conversation_history
        )
        
        # Add AI response to conversation history
        if response_data.get('success') and response_data.get('message'):
            add_to_conversation_history(user['user_id'], 'assistant', response_data['message'])
        
        # Add user context to response
        response_data['authenticated_user'] = user['username']
        response_data['user_role'] = user['role']
        response_data['conversation_context'] = len(conversation_history) > 0
        
        # Debug log for chart issues
        if response_data.get('chart'):
            logger.info(f"Chart generated successfully for query: {user_query}")
        elif 'chart' in user_query.lower():
            logger.warning(f"Chart requested but not generated for: {user_query}")
        
        return jsonify(response_data)
        
    except Exception as e:
        logger.error(f"Error processing query: {e}")
        logger.error(f"Full traceback: {traceback.format_exc()}")
        return jsonify({
            'success': False,
            'message': f'Query processing failed: {str(e)}'
        }), 500
    
    # FACIAL AUTHENTICATION ENDPOINTS
@app.route('/facial-auth/authenticate', methods=['POST'])
def facial_authenticate():
    """Authenticate user using face recognition with improved tolerance"""
    if not DB_AVAILABLE:
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
        
        # Create hash from input image
        import hashlib
        input_encoding = hashlib.sha256(image_base64.encode()).hexdigest()
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # First try exact match
            cursor.execute("""
                SELECT u.user_id, u.username, u.full_name, u.role, frd.face_encoding
                FROM face_recognition_data frd
                JOIN users u ON frd.user_id = u.user_id
                WHERE frd.is_active = true AND u.is_active = true
                AND frd.face_encoding = %s
            """, (input_encoding,))
            
            result = cursor.fetchone()
            
            if not result:
                # Try similarity matching using image size comparison
                cursor.execute("""
                    SELECT u.user_id, u.username, u.full_name, u.role, 
                           frd.face_encoding, frd.face_image_original
                    FROM face_recognition_data frd
                    JOIN users u ON frd.user_id = u.user_id
                    WHERE frd.is_active = true AND u.is_active = true
                """)
                
                all_users = cursor.fetchall()
                
                # Simple similarity check based on image size
                input_size = len(image_base64)
                best_match = None
                best_similarity = 0
                
                for user_data in all_users:
                    stored_image = user_data[5]  # face_image_original
                    if stored_image:
                        stored_size = len(stored_image)
                        # Calculate size similarity (simple approach)
                        size_diff = abs(input_size - stored_size)
                        max_size = max(input_size, stored_size)
                        similarity = 1 - (size_diff / max_size)
                        
                        # If similarity is above 85%, consider it a match
                        if similarity > 0.85 and similarity > best_similarity:
                            best_similarity = similarity
                            best_match = user_data
                
                if best_match:
                    result = best_match[:5]  # Take first 5 elements (exclude image)
            
            if result:
                user_id, username, full_name, role, _ = result
                
                # Update last used timestamp
                cursor.execute("""
                    UPDATE face_recognition_data 
                    SET last_used = NOW() 
                    WHERE user_id = %s
                """, (user_id,))
                conn.commit()
                
                logger.info(f"Face authentication successful for user: {username}")
                
                return jsonify({
                    'success': True,
                    'user': {'id': user_id, 'name': full_name or username},
                    'permission_level': role,
                    'message': f'Welcome back, {full_name or username}!',
                    'confidence': 1.0
                })
            else:
                logger.warning("Face authentication failed - no matching face found")
                return jsonify({
                    'success': False,
                    'message': 'Face not recognized. Please try again with better lighting or register your face again.'
                })
                
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
        
        # Create admin user with enhanced facial recognition
        result = facial_auth.create_admin_user(name, image_base64)
        
        if result['success']:
            logger.info(f"Enhanced facial auth admin user created: {name}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Create facial admin error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to create admin user: {str(e)}'
        }), 500

@app.route('/facial-auth/users', methods=['GET'])
def get_facial_users():
    """Get all facial authentication users with enhanced info"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available'
        }), 500
    
    try:
        users = facial_auth.get_all_users()
        
        return jsonify({
            'success': True,
            'users': users,
            'count': len(users),
            'enhanced_system': True,
            'features': [
                'Multiple face samples per user',
                'Tolerance-based matching',
                'Confidence scoring',
                'Enhanced recognition accuracy'
            ]
        })
        
    except Exception as e:
        logger.error(f"Get facial users error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to get users: {str(e)}'
        }), 500

@app.route('/facial-auth/register', methods=['POST'])
def register_face():
    """Register user face for authentication"""
    if not DB_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Database not available'
        }), 500
    
    try:
        data = request.get_json()
        
        if not data or 'image' not in data or 'user_id' not in data:
            return jsonify({
                'success': False,
                'message': 'Image data and user_id required'
            }), 400
        
        image_base64 = data['image']
        user_id = data['user_id']
        
        # Clean base64 string if it has data URL prefix
        if image_base64.startswith('data:'):
            image_base64 = image_base64.split(',')[1]
        
        # Create hash from input image
        import hashlib
        face_encoding = hashlib.sha256(image_base64.encode()).hexdigest()
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Check if user already has face registered
            cursor.execute("""
                SELECT face_id FROM face_recognition_data 
                WHERE user_id = %s AND is_active = true
            """, (user_id,))
            
            existing_face = cursor.fetchone()
            
            if existing_face:
                # Update existing registration  
                cursor.execute("""
                    UPDATE face_recognition_data
                    SET face_features = %s, registered_at = NOW()
                    WHERE user_id = %s AND is_active = true
                """, (image_base64, user_id))
                message = "Face registration updated successfully"
            else:
                # Create new registration
                cursor.execute("""
                    INSERT INTO face_recognition_data (user_id, face_features, sample_number, registered_at, is_active)
                    VALUES (%s, %s, %s, NOW(), true)
                """, (user_id, image_base64, 1))  # Add sample_number = 1
                message = "Face registered successfully"
            
            # Update user to enable face recognition
            cursor.execute("""
                UPDATE users SET face_recognition_enabled = true WHERE user_id = %s
            """, (user_id,))
            
            conn.commit()
            
            logger.info(f"Face registration successful for user_id: {user_id}")
            
            return jsonify({
                'success': True,
                'message': message
            })
            
    except Exception as e:
        logger.error(f"Face registration error: {e}")
        return jsonify({
            'success': False,
            'message': f'Registration failed: {str(e)}'
        }), 500

@app.route('/facial-auth/delete-user/<user_id>', methods=['DELETE'])
@require_role(['admin'])
def delete_facial_user(current_user, user_id):
    """Delete facial authentication user (admin only)"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available'
        }), 500
    
    try:
        result = facial_auth.delete_user(user_id)
        
        if result['success']:
            # Log admin action
            try:
                facial_auth.log_access(
                    current_user['user_id'],
                    current_user['username'],
                    'delete_facial_user',
                    f'Deleted facial auth user: {user_id}',
                    request.environ.get('HTTP_X_FORWARDED_FOR', request.remote_addr),
                    True
                )
            except Exception as e:
                logger.warning(f"Failed to log user deletion: {e}")
            
            logger.info(f"Admin {current_user['username']} deleted facial auth user: {user_id}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Delete facial user error: {e}")
        return jsonify({
            'success': False,
            'message': f'Failed to delete user: {str(e)}'
        }), 500

@app.route('/facial-auth/status', methods=['GET'])
def get_facial_auth_status():
    """Get enhanced facial authentication system status"""
    if not FACIAL_AUTH_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available',
            'status': {
                'available': False,
                'total_users': 0,
                'admin_users': 0,
                'regular_users': 0,
                'enhanced_features': False
            }
        })
    
    try:
        status = facial_auth.get_system_status()
        
        # Add enhanced system info
        status['enhanced_features'] = True
        status['tolerance_matching'] = True
        status['multiple_samples'] = True
        status['confidence_scoring'] = True
        
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
                SELECT user_id, username, full_name, role, created_at, last_login, is_active, email,
                       COALESCE(face_recognition_enabled, false) as face_recognition_enabled
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
                    'email': row[7] if len(row) > 7 else '',
                    'face_recognition_enabled': row[8] if len(row) > 8 else False
                })
            
            return jsonify({
                'success': True,
                'users': users,
                'total_count': len(users)
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
        
        # Validate inputs
        if not username or not password or not full_name or not email:
            return jsonify({
                'success': False,
                'message': 'All fields must be non-empty'
            }), 400
        
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
            
            # Check if email already exists
            cursor.execute("SELECT email FROM users WHERE email = %s", (email,))
            if cursor.fetchone():
                return jsonify({
                    'success': False,
                    'message': 'Email already exists'
                }), 400
            
            # Create user
            cursor.execute("""
                INSERT INTO users (username, email, password_hash, salt, full_name, role, is_active, face_recognition_enabled)
                VALUES (%s, %s, %s, %s, %s, %s, true, false)
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
                'user': {
                    'user_id': new_user_id,
                    'username': username,
                    'full_name': full_name,
                    'role': role,
                    'email': email,
                    'is_active': True,
                    'face_recognition_enabled': False
                }
            }), 201
            
    except Exception as e:
        logger.error(f"Error creating user: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to create user'
        }), 500

@app.route('/admin/delete-user/<int:user_id>', methods=['DELETE'])
@require_role(['admin'])
def delete_user(current_user, user_id):
    """Delete user (admin only)"""
    try:
        if user_id == current_user['user_id']:
            return jsonify({
                'success': False,
                'message': 'Cannot delete your own account'
            }), 400
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Get user info before deletion
            cursor.execute("SELECT username, role FROM users WHERE user_id = %s", (user_id,))
            user_info = cursor.fetchone()
            
            if not user_info:
                return jsonify({
                    'success': False,
                    'message': 'User not found'
                }), 404
            
            username, role = user_info
            
            # Prevent deletion of last admin
            if role == 'admin':
                cursor.execute("SELECT COUNT(*) FROM users WHERE role = 'admin' AND is_active = true")
                admin_count = cursor.fetchone()[0]
                if admin_count <= 1:
                    return jsonify({
                        'success': False,
                        'message': 'Cannot delete the last admin user'
                    }), 400
            
            # Delete user
            cursor.execute("DELETE FROM users WHERE user_id = %s", (user_id,))
            
            if cursor.rowcount == 0:
                return jsonify({
                    'success': False,
                    'message': 'User not found'
                }), 404
            
            conn.commit()
            
            # Clear conversation history for deleted user
            if str(user_id) in conversation_histories:
                del conversation_histories[str(user_id)]
            
            # Log admin action
            db_assistant.log_user_activity(
                current_user['user_id'], 
                'delete_user', 
                f'Deleted user {username} (ID: {user_id})'
            )
            
            logger.info(f"Admin {current_user['username']} deleted user {username} (ID: {user_id})")
            
            return jsonify({
                'success': True,
                'message': f'User {username} deleted successfully'
            })
            
    except Exception as e:
        logger.error(f"Error deleting user: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to delete user'
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
                'logs': logs,
                'total_shown': len(logs)
            })
            
    except Exception as e:
        logger.error(f"Error getting audit log: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get audit log'
        }), 500

@app.route('/admin/system-stats', methods=['GET'])
@require_role(['admin'])
def get_system_stats(user):
    """Get detailed system statistics (admin only)"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Get user statistics
            cursor.execute("""
                SELECT role, COUNT(*) as count, 
                       COUNT(CASE WHEN is_active THEN 1 END) as active_count
                FROM users 
                GROUP BY role
                ORDER BY role
            """)
            user_stats = []
            for row in cursor.fetchall():
                user_stats.append({
                    'role': row[0],
                    'total': row[1],
                    'active': row[2]
                })
            
            # Get conversation statistics
            total_conversations = len(conversation_histories)
            active_conversations = sum(1 for history in conversation_histories.values() if len(history) > 0)
            total_messages = sum(len(history) for history in conversation_histories.values())
            
            # Get recent activity
            cursor.execute("""
                SELECT COUNT(*) as login_count
                FROM audit_log 
                WHERE action = 'login' AND timestamp > NOW() - INTERVAL '24 hours'
            """)
            recent_logins = cursor.fetchone()[0]
            
            cursor.execute("""
                SELECT COUNT(*) as query_count
                FROM audit_log 
                WHERE action = 'query_execution' AND timestamp > NOW() - INTERVAL '24 hours'
            """)
            recent_queries = cursor.fetchone()[0]
            
            # Get facial auth statistics if available
            facial_stats = {}
            if FACIAL_AUTH_AVAILABLE:
                try:
                    facial_status = facial_auth.get_system_status()
                    facial_stats = {
                        'total_facial_users': facial_status.get('total_users', 0),
                        'facial_admin_users': facial_status.get('admin_users', 0),
                        'facial_regular_users': facial_status.get('regular_users', 0),
                        'total_face_samples': facial_status.get('total_face_samples', 0),
                        'average_samples_per_user': facial_status.get('average_samples_per_user', 0)
                    }
                except Exception as e:
                    logger.error(f"Error getting facial stats: {e}")
                    facial_stats = {'error': 'Failed to get facial auth statistics'}
            
            return jsonify({
                'success': True,
                'statistics': {
                    'users': user_stats,
                    'conversations': {
                        'total_conversation_sessions': total_conversations,
                        'active_conversations': active_conversations,
                        'total_messages': total_messages
                    },
                    'recent_activity': {
                        'logins_24h': recent_logins,
                        'queries_24h': recent_queries
                    },
                    'facial_authentication': facial_stats,
                    'system_status': {
                        'database_available': DB_AVAILABLE,
                        'ai_available': AI_AVAILABLE,
                        'facial_auth_available': FACIAL_AUTH_AVAILABLE
                    }
                }
            })
            
    except Exception as e:
        logger.error(f"Error getting system stats: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get system statistics'
        }), 500

# CONVERSATION MEMORY ENDPOINTS
@app.route('/conversation/history', methods=['GET'])
@require_auth
def get_conversation_history(user):
    """Get conversation history for current user"""
    try:
        history = get_user_conversation_history(user['user_id'])
        
        return jsonify({
            'success': True,
            'conversation_history': history,
            'message_count': len(history)
        })
        
    except Exception as e:
        logger.error(f"Error getting conversation history: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get conversation history'
        }), 500

@app.route('/conversation/clear', methods=['POST'])
@require_auth
def clear_conversation_history(user):
    """Clear conversation history for current user"""
    try:
        user_id_str = str(user['user_id'])
        if user_id_str in conversation_histories:
            conversation_histories[user_id_str] = []
        
        return jsonify({
            'success': True,
            'message': 'Conversation history cleared successfully'
        })
        
    except Exception as e:
        logger.error(f"Error clearing conversation history: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to clear conversation history'
        }), 500

# SYSTEM STATUS
@app.route('/system-status', methods=['GET'])
@require_auth
def get_system_status(user):
    """Get system status for authenticated user"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Get basic stats based on user role
            stats = {}
            
            if user['role'] in ['viewer', 'manager', 'admin']:
                cursor.execute("SELECT COUNT(*) FROM customers")
                stats['customers_count'] = cursor.fetchone()[0]
                
                cursor.execute("SELECT COUNT(*) FROM products")
                stats['products_count'] = cursor.fetchone()[0]
            
            if user['role'] in ['visitor', 'viewer', 'manager', 'admin']:
                cursor.execute("SELECT COUNT(*) FROM invoices")
                stats['invoices_count'] = cursor.fetchone()[0]
            
            if user['role'] in ['manager', 'admin']:
                cursor.execute("SELECT COUNT(*) FROM receipt_captures WHERE status = 'pending_review'")
                stats['pending_receipts'] = cursor.fetchone()[0]
            
            # Get user's conversation info
            user_history = get_user_conversation_history(user['user_id'])
            stats['conversation_messages'] = len(user_history)
            
            # Get facial auth stats if available and user is admin
            facial_auth_stats = {}
            if FACIAL_AUTH_AVAILABLE and user['role'] == 'admin':
                try:
                    facial_status = facial_auth.get_system_status()
                    facial_auth_stats = {
                        'total_facial_users': facial_status.get('total_users', 0),
                        'facial_admin_users': facial_status.get('admin_users', 0),
                        'facial_regular_users': facial_status.get('regular_users', 0),
                        'facial_auth_status': facial_status.get('status', 'unknown'),
                        'enhanced_features': facial_status.get('enhanced_tolerance', False)
                    }
                except Exception as e:
                    logger.error(f"Error getting facial auth stats: {e}")
                    facial_auth_stats = {
                        'facial_auth_status': 'error'
                    }
            
            status = {
                'database_available': DB_AVAILABLE,
                'ai_available': AI_AVAILABLE,
                'facial_auth_available': FACIAL_AUTH_AVAILABLE,
                'user_role': user['role'],
                'user_permissions': {
                    'can_view_customers': user['role'] in ['viewer', 'manager', 'admin'],
                    'can_view_products': user['role'] in ['viewer', 'manager', 'admin'],
                    'can_view_invoices': user['role'] in ['visitor', 'viewer', 'manager', 'admin'],
                    'can_process_receipts': user['role'] in ['manager', 'admin'],
                    'can_manage_users': user['role'] == 'admin'
                },
                'statistics': stats,
                'features': {
                    'conversation_memory': True,
                    'enhanced_facial_recognition': FACIAL_AUTH_AVAILABLE,
                    'role_based_permissions': True,
                    'chart_generation': True,
                    'audit_logging': True
                }
            }
            
            if facial_auth_stats:
                status['facial_authentication'] = facial_auth_stats
            
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

# ENHANCED QUERY ENDPOINT WITH BETTER ERROR HANDLING
@app.route('/query/enhanced', methods=['POST'])
@require_auth
def handle_enhanced_query(user):
    """Enhanced query handler with better conversation memory and error handling"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'message': 'No data provided'
            }), 400
        
        if 'query' not in data:
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

        # Check query length
        if len(user_query) > 1000:
            return jsonify({
                'success': False,
                'message': 'Query too long. Please limit to 1000 characters.'
            }), 400

        logger.info(f"Processing enhanced query from {user['username']} ({user['role']}): {user_query}")
        
        # Get conversation history for this user
        conversation_history = get_user_conversation_history(user['user_id'])
        
        # Add user's query to conversation history
        add_to_conversation_history(user['user_id'], 'user', user_query)
        
        # Execute query with enhanced error handling
        try:
            response_data = db_assistant.execute_query_with_permissions(
                user_query, 
                user, 
                conversation_history=conversation_history
            )
            
            # Add AI response to conversation history
            if response_data.get('success') and response_data.get('message'):
                add_to_conversation_history(user['user_id'], 'assistant', response_data['message'])
            
        except Exception as db_error:
            logger.error(f"Database query error: {db_error}")
            
            # Add error to conversation history
            error_message = f"I encountered an error processing your query: {str(db_error)}"
            add_to_conversation_history(user['user_id'], 'assistant', error_message)
            
            return jsonify({
                'success': False,
                'message': error_message,
                'error_type': 'database_error',
                'authenticated_user': user['username'],
                'user_role': user['role']
            }), 500
        
        # Add enhanced context to response
        response_data['authenticated_user'] = user['username']
        response_data['user_role'] = user['role']
        response_data['conversation_context'] = len(conversation_history) > 0
        response_data['conversation_length'] = len(conversation_history)
        response_data['enhanced_query_processing'] = True
        
        # Debug log for chart issues
        if response_data.get('chart'):
            logger.info(f"Chart generated successfully for enhanced query: {user_query}")
        elif 'chart' in user_query.lower():
            logger.warning(f"Chart requested but not generated for enhanced query: {user_query}")
        
        return jsonify(response_data)
        
    except Exception as e:
        logger.error(f"Error processing enhanced query: {e}")
        logger.error(f"Full traceback: {traceback.format_exc()}")
        
        # Add error to conversation history
        if 'user' in locals():
            error_message = f"System error occurred while processing your query"
            add_to_conversation_history(user['user_id'], 'assistant', error_message)
        
        return jsonify({
            'success': False,
            'message': f'Enhanced query processing failed: {str(e)}',
            'error_type': 'system_error'
        }), 500

# RECEIPT PROCESSING ENDPOINTS (Enhanced for managers/admins)
@app.route('/receipt/upload', methods=['POST'])
@require_role(['manager', 'admin'])
def upload_receipt(user):
    """Upload and process receipt image (manager/admin only)"""
    if not DB_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Database not available for receipt processing'
        }), 500
    
    try:
        data = request.get_json()
        
        if not data or 'image' not in data:
            return jsonify({
                'success': False,
                'message': 'Receipt image data required'
            }), 400
        
        image_base64 = data['image']
        
        # Clean base64 string if it has data URL prefix
        if image_base64.startswith('data:'):
            image_base64 = image_base64.split(',')[1]
        
        # Process receipt with database assistant
        result = db_assistant.process_receipt_image(user['user_id'], image_base64)
        
        if result['success']:
            logger.info(f"Receipt uploaded successfully by {user['username']}")
        else:
            logger.warning(f"Receipt upload failed for {user['username']}: {result.get('message')}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Receipt upload error: {e}")
        return jsonify({
            'success': False,
            'message': f'Receipt upload failed: {str(e)}'
        }), 500

@app.route('/receipt/pending', methods=['GET'])
@require_role(['manager', 'admin'])
def get_pending_receipts(user):
    """Get pending receipts for review (manager/admin only)"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT capture_id, extracted_vendor, extracted_date, extracted_total, 
                       confidence_score, captured_at, u.username as uploaded_by
                FROM receipt_captures rc
                LEFT JOIN users u ON rc.user_id = u.user_id
                WHERE status = 'pending_review'
                ORDER BY captured_at DESC
                LIMIT 50
            """)
            
            receipts = []
            for row in cursor.fetchall():
                receipts.append({
                    'capture_id': row[0],
                    'vendor': row[1],
                    'date': row[2].isoformat() if row[2] else None,
                    'total': float(row[3]) if row[3] else 0.0,
                    'confidence': float(row[4]) if row[4] else 0.0,
                    'uploaded_at': row[5].isoformat() if row[5] else None,
                    'uploaded_by': row[6] or 'Unknown'
                })
            
            return jsonify({
                'success': True,
                'pending_receipts': receipts,
                'count': len(receipts)
            })
            
    except Exception as e:
        logger.error(f"Error getting pending receipts: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get pending receipts'
        }), 500

# ERROR HANDLERS
@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'success': False,
        'message': 'Endpoint not found',
        'available_endpoints': [
            '/login', '/logout', '/query', '/query/enhanced',
            '/facial-auth/authenticate', '/facial-auth/register',
            '/admin/users', '/admin/create-user', '/system-status'
        ]
    }), 404

@app.errorhandler(405)
def method_not_allowed(error):
    return jsonify({
        'success': False,
        'message': 'Method not allowed for this endpoint'
    }), 405

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Internal server error: {error}")
    return jsonify({
        'success': False,
        'message': 'Internal server error occurred'
    }), 500

# HEALTH AND MONITORING
@app.route('/health/detailed', methods=['GET'])
def detailed_health_check():
    """Detailed health check with component status"""
    health_status = {
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'version': '4.0',
        'components': {
            'database': {
                'available': DB_AVAILABLE,
                'status': 'operational' if DB_AVAILABLE else 'unavailable'
            },
            'ai_service': {
                'available': AI_AVAILABLE,
                'status': 'operational' if AI_AVAILABLE else 'unavailable'
            },
            'facial_auth': {
                'available': FACIAL_AUTH_AVAILABLE,
                'status': 'operational' if FACIAL_AUTH_AVAILABLE else 'unavailable'
            },
            'conversation_memory': {
                'available': True,
                'active_sessions': len(conversation_histories),
                'total_messages': sum(len(history) for history in conversation_histories.values())
            }
        },
        'features': {
            'enhanced_facial_recognition': FACIAL_AUTH_AVAILABLE,
            'conversation_memory_system': True,
            'role_based_authentication': True,
            'admin_user_management': True,
            'purple_teal_theme_support': True,
            'chart_generation': AI_AVAILABLE and DB_AVAILABLE,
            'receipt_processing': DB_AVAILABLE
        }
    }
    
    # Determine overall health
    critical_components = [DB_AVAILABLE, AI_AVAILABLE]
    if not all(critical_components):
        health_status['status'] = 'degraded'
    
    return jsonify(health_status)

@app.route('/health/quick', methods=['GET'])
def quick_health_check():
    """Quick health check for load balancers"""
    return jsonify({
        'status': 'ok',
        'timestamp': datetime.now().isoformat()
    })

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
    
    print(f"=== STARTING NEURAL PULSE SERVER ===")
    print(f"Host: 0.0.0.0")
    print(f"Port: {port}")
    print(f"Database Available: {DB_AVAILABLE}")
    print(f"AI Available: {AI_AVAILABLE}")
    print(f"Facial Auth Available: {FACIAL_AUTH_AVAILABLE}")
    print(f"Features: Enhanced conversation memory, Purple-teal theme, Role-based auth")
    print(f"=====================================")
    
    app.run(host='0.0.0.0', port=port, debug=False)
from flask import Flask, request, jsonify, session
from flask_cors import CORS
import logging
import os
import sys
import traceback
import hashlib
import json
from datetime import datetime, timedelta
from functools import wraps

# Setup logging - Force redeploy for endpoint registration
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

# Initialize Ollama
print("=== INITIALIZING OLLAMA ===")
try:
    import requests

    # First check if Ollama is running
    response = requests.get("http://localhost:11434/api/tags", timeout=5)
    if response.status_code == 200:
        logger.info("Ollama server is running")

        # Check if phi3:mini model is available
        models = response.json().get('models', [])
        phi3_available = any('phi3:mini' in model.get('name', '') for model in models)

        if phi3_available:
            AI_AVAILABLE = True
            logger.info("Ollama initialized successfully with phi3:mini model")
            print("✓ Ollama and phi3:mini model available")
        else:
            AI_AVAILABLE = False
            logger.warning("phi3:mini model not found in Ollama. Run: ollama pull phi3:mini")
            print("⚠ Ollama running but phi3:mini model not found")
    else:
        AI_AVAILABLE = False
        logger.warning(f"Ollama not responding: HTTP {response.status_code}")
        print("⚠ Ollama server not responding")
except requests.exceptions.ConnectionError:
    AI_AVAILABLE = False
    logger.error("Cannot connect to Ollama - is it running on localhost:11434?")
    print("✗ Ollama connection failed - make sure Ollama is running")
except Exception as e:
    AI_AVAILABLE = False
    logger.error(f"Failed to connect to Ollama: {e}")
    print(f"✗ Ollama initialization error: {e}")

def call_ollama(prompt):
    """Call Ollama API with phi3:mini model"""
    if not AI_AVAILABLE:
        logger.warning("Ollama not available - returning fallback response")
        return "Ollama not available"

    try:
        logger.info(f"Calling Ollama with prompt length: {len(prompt)} characters")

        response = requests.post(
            "http://localhost:11434/api/generate",
            json={
                "model": "phi3:mini",
                "prompt": prompt,
                "stream": False,
                "options": {
                    "temperature": 0.1,
                    "num_predict": 1000
                }
            },
            timeout=60  # Increased timeout for complex queries
        )

        if response.status_code == 200:
            result = response.json()
            ollama_response = result.get("response", "No response from Ollama")
            logger.info(f"Ollama response received successfully, length: {len(ollama_response)} characters")
            return ollama_response
        else:
            error_msg = f"Ollama error: HTTP {response.status_code}"
            logger.error(error_msg)
            return error_msg

    except requests.exceptions.Timeout:
        error_msg = "Ollama connection timeout (60s exceeded)"
        logger.error(error_msg)
        return f"Ollama connection error: {error_msg}"
    except requests.exceptions.ConnectionError:
        error_msg = "Cannot connect to Ollama - is it running on localhost:11434?"
        logger.error(error_msg)
        return f"Ollama connection error: {error_msg}"
    except Exception as e:
        error_msg = f"Unexpected Ollama error: {str(e)}"
        logger.error(error_msg)
        return f"Ollama connection error: {error_msg}"

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
    @wraps(func)
    def wrapper(*args, **kwargs):
        user = get_current_user()
        if not user:
            return jsonify({
                'success': False,
                'message': 'Authentication required',
                'requires_login': True
            }), 401
        return func(user, *args, **kwargs)
    return wrapper

def require_role(required_roles):
    """Decorator to require specific roles"""
    def decorator(func):
        @wraps(func)
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
        return wrapper
    return decorator

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

@app.route('/register', methods=['POST'])
def register():
    """User registration"""
    if not DB_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Database not available'
        }), 500

    try:
        data = request.get_json()

        required_fields = ['username', 'password', 'email']
        for field in required_fields:
            if not data or field not in data:
                return jsonify({
                    'success': False,
                    'message': f'Field {field} is required'
                }), 400

        username = data['username'].strip()
        password = data['password']
        email = data['email'].strip()

        # Validate inputs
        if not username or not password or not email:
            return jsonify({
                'success': False,
                'message': 'All fields must be non-empty'
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

            # Insert new user (default role as viewer)
            cursor.execute("""
                INSERT INTO users (username, password_hash, salt, full_name, role, email, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING user_id, username, full_name, role, email
            """, (username, password_hash, salt, username, 'viewer', email, datetime.now()))

            user_data = cursor.fetchone()
            conn.commit()

            if user_data:
                user = {
                    'user_id': user_data[0],
                    'username': user_data[1],
                    'full_name': user_data[2],
                    'role': user_data[3],
                    'email': user_data[4]
                }

                logger.info(f"New user registered: {username}")

                return jsonify({
                    'success': True,
                    'message': 'User registered successfully',
                    'user': user
                })
            else:
                return jsonify({
                    'success': False,
                    'message': 'Failed to create user'
                }), 500

    except Exception as e:
        logger.error(f"Registration error: {e}")
        return jsonify({
            'success': False,
            'message': 'Registration failed due to server error'
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

@app.route('/validate-session', methods=['GET'])
@require_auth
def validate_user_session(user):
    """Validate current user session"""
    try:
        return jsonify({
            'valid': True,
            'user_id': user['user_id'],
            'username': user['username'],
            'role': user['role']
        })
    except Exception as e:
        return jsonify({'valid': False}), 401
    

# FACE AUTHENTICATION ENDPOINTS
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
            'confidence_threshold': 0.85,
            'max_samples': 5,
            'min_samples_required': 3
        })
        
    except Exception as e:
        logger.error(f"Error getting face auth status: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get face auth status'
        }), 500

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

# LEGACY FACIAL AUTHENTICATION ENDPOINTS
@app.route('/facial-auth/authenticate', methods=['POST'])
def facial_authenticate():
    """Authenticate user using geometric face recognition"""
    if not DB_AVAILABLE:
        return jsonify({
            'success': False,
            'message': 'Facial authentication not available'
        }), 500

    try:
        data = request.get_json()

        if not data or 'face_features' not in data:
            return jsonify({
                'success': False,
                'message': 'Face features data required'
            }), 400

        face_features = data['face_features']

        # Use geometric face verification from db_assistant
        result = db_assistant.verify_face_with_samples(face_features)

        if result['success']:
            user_data = result['user']

            # Update last used timestamp
            with db_assistant.get_db_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    UPDATE face_recognition_data
                    SET last_used = NOW()
                    WHERE user_id = %s
                """, (user_data['id'],))
                conn.commit()

            logger.info(f"Geometric face authentication successful for user: {user_data['username']}")

            return jsonify({
                'success': True,
                'user': {'id': user_data['id'], 'name': user_data['full_name'] or user_data['username']},
                'permission_level': user_data['role'],
                'message': f'Welcome back, {user_data["full_name"] or user_data["username"]}!',
                'confidence': result['confidence']
            })
        else:
            logger.warning("Geometric face authentication failed - no matching face found")
            return jsonify({
                'success': False,
                'message': result['message']
            })

    except Exception as e:
        logger.error(f"Facial authentication error: {e}")
        return jsonify({
            'success': False,
            'message': f'Authentication failed: {str(e)}'
        }), 500

@app.route('/facial-auth/register', methods=['POST'])
@app.route('/face-auth/enroll', methods=['POST'])  # Alias for Flutter frontend
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
    

# INVOICE MANAGEMENT ENDPOINTS
@app.route('/invoices', methods=['GET'])
@require_auth
def get_invoices(user):
    """Get invoices for current user or all (based on role)"""
    try:
        user_filter = None if user['role'] in ['admin', 'manager'] else user['user_id']
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            if user_filter:
                cursor.execute("""
                    SELECT invoice_id, customer_id, invoice_date, total_amount, status
                    FROM invoices 
                    WHERE customer_id = %s
                    ORDER BY invoice_date DESC 
                    LIMIT 100
                """, (user_filter,))
            else:
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
                    'total_amount': float(row[3] or 0),
                    'status': row[4] or 'pending'
                })
            
            return jsonify({
                'success': True,
                'invoices': invoices,
                'count': len(invoices)
            })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/invoices', methods=['POST'])
@require_role(['manager', 'admin'])
def create_invoice(user):
    """Create new invoice"""
    try:
        data = request.get_json()
        
        required_fields = ['customer_name', 'amount', 'date']
        for field in required_fields:
            if field not in data:
                return jsonify({
                    'success': False,
                    'message': f'Field {field} is required'
                }), 400
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Create invoice
            cursor.execute("""
                INSERT INTO invoices (customer_id, invoice_date, total_amount, status)
                VALUES (%s, %s, %s, %s)
                RETURNING invoice_id
            """, (
                data.get('customer_id', 1),
                data['date'],
                data['amount'],
                data.get('status', 'pending')
            ))
            
            invoice_id = cursor.fetchone()[0]
            conn.commit()
            
            db_assistant.log_user_activity(user['user_id'], 'invoice_creation', f'Invoice {invoice_id} created')
            
            return jsonify({
                'success': True,
                'message': 'Invoice created successfully',
                'invoice_id': invoice_id
            }), 201
            
    except Exception as e:
        logger.error(f"Invoice creation error: {e}")
        return jsonify({
            'success': False,
            'message': f'Invoice creation failed: {str(e)}'
        }), 500

@app.route('/invoices/<int:invoice_id>', methods=['PUT'])
@require_role(['manager', 'admin'])
def update_invoice(user, invoice_id):
    """Update existing invoice"""
    try:
        data = request.get_json()
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Build update query dynamically
            update_fields = []
            values = []
            
            if 'customer_name' in data:
                update_fields.append('customer_id = %s')
                values.append(data['customer_id'])
            if 'amount' in data:
                update_fields.append('total_amount = %s')
                values.append(data['amount'])
            if 'date' in data:
                update_fields.append('invoice_date = %s')
                values.append(data['date'])
            if 'status' in data:
                update_fields.append('status = %s')
                values.append(data['status'])
            
            if not update_fields:
                return jsonify({
                    'success': False,
                    'message': 'No fields to update'
                }), 400
            
            values.append(invoice_id)
            
            cursor.execute(f"""
                UPDATE invoices 
                SET {', '.join(update_fields)}, updated_at = NOW()
                WHERE invoice_id = %s
            """, values)
            
            if cursor.rowcount == 0:
                return jsonify({
                    'success': False,
                    'message': 'Invoice not found'
                }), 404
            
            conn.commit()
            
            db_assistant.log_user_activity(user['user_id'], 'invoice_update', f'Invoice {invoice_id} updated')
            
            return jsonify({
                'success': True,
                'message': 'Invoice updated successfully'
            })
            
    except Exception as e:
        logger.error(f"Invoice update error: {e}")
        return jsonify({
            'success': False,
            'message': f'Invoice update failed: {str(e)}'
        }), 500

@app.route('/invoices/<int:invoice_id>', methods=['DELETE'])
@require_role(['manager', 'admin'])
def delete_invoice(user, invoice_id):
    """Delete invoice"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # First delete related records to avoid foreign key constraint
            cursor.execute("DELETE FROM inventory_movements WHERE invoice_id = %s", (invoice_id,))
            cursor.execute("DELETE FROM invoice_items WHERE invoice_id = %s", (invoice_id,))
            cursor.execute("DELETE FROM invoices WHERE invoice_id = %s", (invoice_id,))
            
            conn.commit()
            
            db_assistant.log_user_activity(user['user_id'], 'invoice_deletion', f'Invoice {invoice_id} deleted')
            
            return jsonify({
                'success': True,
                'message': 'Invoice deleted successfully'
            })
            
    except Exception as e:
        logger.error(f"Invoice deletion error: {e}")
        return jsonify({
            'success': False,
            'message': f'Invoice deletion failed: {str(e)}'
        }), 500

# QUERY ENDPOINTS
# Sync endpoints for Flutter app compatibility
@app.route('/api/sync/users', methods=['GET'])
@require_auth
def sync_users(user):
    """Sync users - Flutter app compatibility"""
    return jsonify({'success': True, 'users': [], 'has_more': False})

@app.route('/api/sync/chat_sessions', methods=['GET'])
@require_auth
def sync_chat_sessions(user):
    """Sync chat sessions - Flutter app compatibility"""
    return jsonify({'success': True, 'sessions': [], 'has_more': False})

@app.route('/api/sync/chat_messages', methods=['GET'])
@require_auth
def sync_chat_messages(user):
    """Sync chat messages - Flutter app compatibility"""
    return jsonify({'success': True, 'messages': [], 'has_more': False})

@app.route('/api/sync/messages', methods=['GET'])
@require_auth
def sync_messages(user):
    """Sync messages - Flutter app compatibility"""
    return jsonify({'success': True, 'messages': [], 'has_more': False})

@app.route('/api/sync/invoices', methods=['GET'])
@require_auth
def sync_invoices(user):
    """Sync invoices - Flutter app compatibility"""
    return jsonify({'success': True, 'invoices': [], 'has_more': False})

@app.route('/api/sync/database_queries', methods=['GET'])
@require_auth
def sync_database_queries(user):
    """Sync database queries - Flutter app compatibility"""
    return jsonify({'success': True, 'queries': [], 'has_more': False})

# Chat session endpoints for Flutter app compatibility
@app.route('/chat/sessions', methods=['POST'])
@require_auth
def create_chat_session(user):
    """Create a new chat session - Flutter app compatibility"""
    return jsonify({
        'success': True,
        'session_id': f"session_{user['user_id']}_{int(datetime.now().timestamp())}",
        'message': 'Chat session created'
    })

@app.route('/chat/message', methods=['POST'])
@require_auth
def send_chat_message(user):
    """Send a chat message - Flutter app compatibility"""
    try:
        data = request.get_json()
        message = data.get('message', '')

        if not message:
            return jsonify({'success': False, 'message': 'Message is required'}), 400

        # Use the existing query logic by calling handle_authenticated_query
        request._cached_json = {'query': message}
        return handle_authenticated_query(user)

    except Exception as e:
        logger.error(f"Chat message error: {e}")
        return jsonify({'success': False, 'message': 'Failed to send message'}), 500

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
    

# RECEIPT PROCESSING ENDPOINTS
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

@app.route('/receipt/approve', methods=['POST'])
@require_role(['manager', 'admin'])
def approve_receipt(user):
    """Approve receipt and create invoice"""
    try:
        data = request.get_json()
        
        if not data or 'capture_id' not in data or 'customer_id' not in data:
            return jsonify({
                'success': False,
                'message': 'Capture ID and customer ID required'
            }), 400
        
        capture_id = data['capture_id']
        customer_id = data['customer_id']
        corrections = data.get('corrections', {})
        
        result = db_assistant.approve_receipt_and_create_invoice(
            capture_id, user['user_id'], customer_id, corrections
        )
        
        if result['success']:
            logger.info(f"Receipt {capture_id} approved by {user['username']}")
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Receipt approval error: {e}")
        return jsonify({
            'success': False,
            'message': f'Receipt approval failed: {str(e)}'
        }), 500

@app.route('/receipt/reject', methods=['POST'])
@require_role(['manager', 'admin'])
def reject_receipt(user):
    """Reject receipt capture"""
    try:
        data = request.get_json()
        
        if not data or 'capture_id' not in data:
            return jsonify({
                'success': False,
                'message': 'Capture ID required'
            }), 400
        
        capture_id = data['capture_id']
        reason = data.get('reason', 'Rejected by user')
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                UPDATE receipt_captures 
                SET status = 'rejected', processed_at = NOW(), rejection_reason = %s
                WHERE capture_id = %s AND status = 'pending_review'
            """, (reason, capture_id))
            
            if cursor.rowcount == 0:
                return jsonify({
                    'success': False,
                    'message': 'Receipt not found or already processed'
                }), 404
            
            conn.commit()
            
            db_assistant.log_user_activity(user['user_id'], 'receipt_rejection', f'Receipt {capture_id} rejected: {reason}')
            
            return jsonify({
                'success': True,
                'message': 'Receipt rejected successfully'
            })
            
    except Exception as e:
        logger.error(f"Receipt rejection error: {e}")
        return jsonify({
            'success': False,
            'message': f'Receipt rejection failed: {str(e)}'
        }), 500

@app.route('/receipt/statistics', methods=['GET'])
@require_role(['manager', 'admin'])
def get_receipt_statistics(user):
    """Get receipt processing statistics"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Get counts by status
            cursor.execute("""
                SELECT status, COUNT(*) as count
                FROM receipt_captures
                GROUP BY status
            """)
            
            status_counts = {}
            for row in cursor.fetchall():
                status_counts[row[0]] = row[1]
            
            # Get recent activity
            cursor.execute("""
                SELECT COUNT(*) FROM receipt_captures 
                WHERE captured_at > NOW() - INTERVAL '7 days'
            """)
            recent_uploads = cursor.fetchone()[0]
            
            cursor.execute("""
                SELECT COUNT(*) FROM receipt_captures 
                WHERE processed_at > NOW() - INTERVAL '7 days' AND status != 'pending_review'
            """)
            recent_processed = cursor.fetchone()[0]
            
            # Get average confidence score
            cursor.execute("""
                SELECT AVG(confidence_score) FROM receipt_captures 
                WHERE confidence_score IS NOT NULL
            """)
            avg_confidence = cursor.fetchone()[0] or 0.0
            
            return jsonify({
                'success': True,
                'statistics': {
                    'status_counts': status_counts,
                    'recent_uploads_7d': recent_uploads,
                    'recent_processed_7d': recent_processed,
                    'average_confidence': round(float(avg_confidence), 2),
                    'total_receipts': sum(status_counts.values())
                }
            })
            
    except Exception as e:
        logger.error(f"Error getting receipt statistics: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get receipt statistics'
        }), 500

# ADMIN USER MANAGEMENT ENDPOINTS
@app.route('/admin/users', methods=['GET'])
@require_role(['admin'])
def get_all_users(user):
    """Get all users (admin only)"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT user_id, username, full_name, role, created_at, last_login, is_active, email,
                       COALESCE(face_auth_enabled, false) as face_auth_enabled,
                       (SELECT COUNT(*) FROM face_recognition_data frd 
                        WHERE frd.user_id = users.user_id AND frd.is_active = true) as face_samples
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
                    'face_auth_enabled': row[8] if len(row) > 8 else False,
                    'face_samples_count': row[9] if len(row) > 9 else 0
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

@app.route('/admin/users/<int:user_id>', methods=['PUT'])
@require_role(['admin'])
def update_user(current_user, user_id):
    """Update user details (admin only)"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'message': 'No update data provided'
            }), 400
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Build update query dynamically
            update_fields = []
            values = []
            
            if 'username' in data:
                # Check if username already exists
                cursor.execute("""
                    SELECT user_id FROM users WHERE username = %s AND user_id != %s
                """, (data['username'], user_id))
                if cursor.fetchone():
                    return jsonify({
                        'success': False,
                        'message': 'Username already exists'
                    }), 400
                update_fields.append('username = %s')
                values.append(data['username'])
            
            if 'full_name' in data:
                update_fields.append('full_name = %s')
                values.append(data['full_name'])
            
            if 'email' in data:
                # Check if email already exists
                cursor.execute("""
                    SELECT user_id FROM users WHERE email = %s AND user_id != %s
                """, (data['email'], user_id))
                if cursor.fetchone():
                    return jsonify({
                        'success': False,
                        'message': 'Email already exists'
                    }), 400
                update_fields.append('email = %s')
                values.append(data['email'])
            
            if 'role' in data:
                valid_roles = ['visitor', 'viewer', 'manager', 'admin']
                if data['role'] not in valid_roles:
                    return jsonify({
                        'success': False,
                        'message': f'Invalid role. Must be one of: {", ".join(valid_roles)}'
                    }), 400
                update_fields.append('role = %s')
                values.append(data['role'])
            
            if 'is_active' in data:
                # Prevent deactivating the last admin
                if not data['is_active']:
                    cursor.execute("""
                        SELECT u1.role, COUNT(u2.user_id) as admin_count
                        FROM users u1,
                             (SELECT user_id FROM users WHERE role = 'admin' AND is_active = true) u2
                        WHERE u1.user_id = %s
                        GROUP BY u1.role
                    """, (user_id,))
                    result = cursor.fetchone()
                    if result and result[0] == 'admin' and result[1] <= 1:
                        return jsonify({
                            'success': False,
                            'message': 'Cannot deactivate the last active admin user'
                        }), 400
                
                update_fields.append('is_active = %s')
                values.append(data['is_active'])
            
            if not update_fields:
                return jsonify({
                    'success': False,
                    'message': 'No valid fields to update'
                }), 400
            
            # Add user_id and updated timestamp
            values.append(user_id)
            
            cursor.execute(f"""
                UPDATE users 
                SET {', '.join(update_fields)}, updated_at = NOW()
                WHERE user_id = %s
            """, values)
            
            if cursor.rowcount == 0:
                return jsonify({
                    'success': False,
                    'message': 'User not found'
                }), 404
            
            conn.commit()
            
            # Get updated user data
            cursor.execute("""
                SELECT user_id, username, full_name, role, email, is_active,
                       COALESCE(face_auth_enabled, false) as face_auth_enabled
                FROM users WHERE user_id = %s
            """, (user_id,))
            
            updated_user = cursor.fetchone()
            user_data = {
                'user_id': updated_user[0],
                'username': updated_user[1],
                'full_name': updated_user[2],
                'role': updated_user[3],
                'email': updated_user[4],
                'is_active': updated_user[5],
                'face_auth_enabled': updated_user[6]
            }
            
            db_assistant.log_user_activity(
                current_user['user_id'], 
                'user_update', 
                f'Updated user {updated_user[1]} (ID: {user_id})'
            )
            
            logger.info(f"Admin {current_user['username']} updated user {updated_user[1]} (ID: {user_id})")
            
            return jsonify({
                'success': True,
                'message': 'User updated successfully',
                'user': user_data
            })
            
    except Exception as e:
        import traceback
        logger.error(f"Error updating user: {e}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        logger.error(f"Request data: {request.get_json()}")
        return jsonify({
            'success': False,
            'message': f'Failed to update user: {str(e)}'
        }), 500
    

@app.route('/admin/users/<int:user_id>/password', methods=['PUT'])
@require_role(['admin'])
def change_user_password(current_user, user_id):
    """Change user password (admin only)"""
    try:
        data = request.get_json()
        
        if not data or 'new_password' not in data:
            return jsonify({
                'success': False,
                'message': 'New password is required'
            }), 400
        
        new_password = data['new_password'].strip()
        
        if len(new_password) < 6:
            return jsonify({
                'success': False,
                'message': 'Password must be at least 6 characters long'
            }), 400
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Get user info
            cursor.execute("""
                SELECT username FROM users WHERE user_id = %s AND is_active = true
            """, (user_id,))
            
            user_info = cursor.fetchone()
            if not user_info:
                return jsonify({
                    'success': False,
                    'message': 'User not found or inactive'
                }), 404
            
            username = user_info[0]
            
            # Create new password hash
            salt = hashlib.sha256(username.encode()).hexdigest()[:16]
            password_hash = hashlib.sha256((new_password + salt).encode()).hexdigest()
            
            # Update password
            cursor.execute("""
                UPDATE users 
                SET password_hash = %s, salt = %s, updated_at = NOW()
                WHERE user_id = %s
            """, (password_hash, salt, user_id))
            
            conn.commit()
            
            db_assistant.log_user_activity(
                current_user['user_id'], 
                'password_change', 
                f'Password changed for user {username} (ID: {user_id})'
            )
            
            logger.info(f"Admin {current_user['username']} changed password for user {username} (ID: {user_id})")
            
            return jsonify({
                'success': True,
                'message': f'Password changed successfully for user {username}'
            })
            
    except Exception as e:
        logger.error(f"Error changing user password: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to change password'
        }), 500

@app.route('/admin/users/<int:user_id>/face-auth', methods=['DELETE'])
@require_role(['admin'])
def admin_reset_user_face_auth(current_user, user_id):
    """Reset face authentication for any user (admin only)"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Get user info
            cursor.execute("""
                SELECT username FROM users WHERE user_id = %s
            """, (user_id,))
            
            user_info = cursor.fetchone()
            if not user_info:
                return jsonify({
                    'success': False,
                    'message': 'User not found'
                }), 404
            
            username = user_info[0]
            
            # Disable face auth
            cursor.execute("""
                UPDATE users SET face_auth_enabled = false WHERE user_id = %s
            """, (user_id,))
            
            # Delete all face samples
            cursor.execute("""
                DELETE FROM face_recognition_data WHERE user_id = %s
            """, (user_id,))
            
            conn.commit()
            
            db_assistant.log_user_activity(
                current_user['user_id'], 
                'admin_face_reset', 
                f'Reset face auth for user {username} (ID: {user_id})'
            )
            
            logger.info(f"Admin {current_user['username']} reset face auth for user {username} (ID: {user_id})")
            
            return jsonify({
                'success': True,
                'message': f'Face authentication reset for user {username}'
            })
            
    except Exception as e:
        logger.error(f"Error resetting user face auth: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to reset face authentication'
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
            
            # Delete all user-related data (to avoid foreign key constraints)
            cursor.execute("DELETE FROM face_recognition_data WHERE user_id = %s", (user_id,))
            cursor.execute("DELETE FROM user_chart_permissions WHERE user_id = %s", (user_id,))
            cursor.execute("DELETE FROM user_table_permissions WHERE user_id = %s", (user_id,))
            cursor.execute("DELETE FROM user_sessions WHERE user_id = %s", (user_id,))
            cursor.execute("DELETE FROM permission_audit WHERE user_id = %s", (user_id,))
            cursor.execute("DELETE FROM receipt_captures WHERE user_id = %s", (user_id,))
            cursor.execute("DELETE FROM audit_log WHERE user_id = %s", (user_id,))

            # Finally delete user
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

# USER PROFILE ENDPOINTS
@app.route('/user/profile', methods=['GET'])
@require_auth
def get_user_profile(user):
    """Get current user profile"""
    try:
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT user_id, username, full_name, role, email, is_active, created_at, last_login,
                       COALESCE(face_auth_enabled, false) as face_auth_enabled,
                       (SELECT COUNT(*) FROM face_recognition_data frd 
                        WHERE frd.user_id = users.user_id AND frd.is_active = true) as face_samples
                FROM users 
                WHERE user_id = %s
            """, (user['user_id'],))
            
            result = cursor.fetchone()
            if not result:
                return jsonify({
                    'success': False,
                    'message': 'User not found'
                }), 404
            
            user_data = {
                'user_id': result[0],
                'username': result[1],
                'full_name': result[2],
                'role': result[3],
                'email': result[4],
                'is_active': result[5],
                'created_at': result[6].isoformat() if result[6] else None,
                'last_login': result[7].isoformat() if result[7] else None,
                'face_auth_enabled': result[8],
                'face_samples_count': result[9]
            }
            
            return jsonify({
                'success': True,
                'user': user_data
            })
            
    except Exception as e:
        logger.error(f"Error getting user profile: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get user profile'
        }), 500

@app.route('/user/profile', methods=['PUT'])
@require_auth
def update_user_profile(user):
    """Update current user profile (limited fields)"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'message': 'No update data provided'
            }), 400
        
        with db_assistant.get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Users can only update their own full_name and email
            update_fields = []
            values = []
            
            if 'full_name' in data:
                update_fields.append('full_name = %s')
                values.append(data['full_name'])
            
            if 'email' in data:
                # Check if email already exists
                cursor.execute("""
                    SELECT user_id FROM users WHERE email = %s AND user_id != %s
                """, (data['email'], user['user_id']))
                if cursor.fetchone():
                    return jsonify({
                        'success': False,
                        'message': 'Email already exists'
                    }), 400
                update_fields.append('email = %s')
                values.append(data['email'])
            
            if not update_fields:
                return jsonify({
                    'success': False,
                    'message': 'No valid fields to update'
                }), 400
            
            values.append(user['user_id'])
            
            cursor.execute(f"""
                UPDATE users 
                SET {', '.join(update_fields)}, updated_at = NOW()
                WHERE user_id = %s
            """, values)
            
            conn.commit()
            
            db_assistant.log_user_activity(
                user['user_id'], 
                'profile_update', 
                'Updated own profile'
            )
            
            # Get updated user data
            cursor.execute("""
                SELECT user_id, username, full_name, role, email, is_active,
                       COALESCE(face_auth_enabled, false) as face_auth_enabled
                FROM users WHERE user_id = %s
            """, (user['user_id'],))
            
            updated_user = cursor.fetchone()
            user_data = {
                'user_id': updated_user[0],
                'username': updated_user[1],
                'full_name': updated_user[2],
                'role': updated_user[3],
                'email': updated_user[4],
                'is_active': updated_user[5],
                'face_auth_enabled': updated_user[6]
            }
            
            return jsonify({
                'success': True,
                'message': 'Profile updated successfully',
                'user': user_data
            })
            
    except Exception as e:
        logger.error(f"Error updating user profile: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to update profile'
        }), 500

# SYSTEM STATUS AND MONITORING
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

# ERROR HANDLERS
@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'success': False,
        'message': 'Endpoint not found',
        'available_endpoints': [
            '/login', '/logout', '/query', '/query/enhanced',
            '/face-auth/verify', '/face-auth/enroll-sample',
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
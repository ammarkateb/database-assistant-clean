import sqlite3
import numpy as np
import uuid
from datetime import datetime
import logging
import base64
from PIL import Image
import io
import cv2
import hashlib

logger = logging.getLogger(__name__)

class FacialAuthSystem:
    def __init__(self):
        self.db_path = 'facial_auth.db'
        self.init_database()
        
        # Try to load OpenCV face detector
        try:
            # Use Haar cascade for face detection (more reliable on Railway)
            self.face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
            self.face_recognition_available = True
            logger.info("OpenCV face detection initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize face detection: {e}")
            self.face_recognition_available = False
    
    def init_database(self):
        """Initialize the facial authentication database"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Create users table - using face_hash instead of encoding for simplicity
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS users (
                        id TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        face_hash TEXT NOT NULL,
                        face_data BLOB,
                        permission_level TEXT NOT NULL,
                        created_at TEXT NOT NULL
                    )
                ''')
                
                # Create access logs table
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS access_logs (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        user_id TEXT,
                        user_name TEXT,
                        access_type TEXT,
                        query TEXT,
                        ip_address TEXT,
                        timestamp TEXT,
                        success BOOLEAN
                    )
                ''')
                
                conn.commit()
                logger.info("Facial auth database initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize database: {e}")
            raise
    
    def _decode_image(self, image_base64):
        """Decode base64 image and convert to OpenCV format"""
        try:
            # Handle different base64 formats
            if isinstance(image_base64, str):
                # Remove data URL prefix if present (data:image/jpeg;base64,)
                if image_base64.startswith('data:'):
                    image_base64 = image_base64.split(',')[1]
                
                # Clean up any whitespace
                image_base64 = image_base64.strip()
            
            # Decode base64
            image_data = base64.b64decode(image_base64)
            
            # Open with PIL first
            image_pil = Image.open(io.BytesIO(image_data))
            if image_pil.mode != 'RGB':
                image_pil = image_pil.convert('RGB')
            
            # Convert to OpenCV format (BGR)
            image_array = np.array(image_pil)
            image_cv = cv2.cvtColor(image_array, cv2.COLOR_RGB2BGR)
            
            logger.info(f"Successfully decoded image with shape: {image_cv.shape}")
            return image_cv
            
        except Exception as e:
            logger.error(f"Failed to decode image: {e}")
            return None
    
    def _extract_face_features(self, image_cv):
        """Extract face features using OpenCV"""
        try:
            if not self.face_recognition_available:
                return None, "Face recognition not available"
            
            # Convert to grayscale for face detection
            gray = cv2.cvtColor(image_cv, cv2.COLOR_BGR2GRAY)
            
            # Detect faces
            faces = self.face_cascade.detectMultiScale(gray, 1.1, 4)
            
            if len(faces) == 0:
                return None, "No face detected in the image"
            
            if len(faces) > 1:
                return None, "Multiple faces detected. Please ensure only one face is visible"
            
            # Extract the face region
            (x, y, w, h) = faces[0]
            face_roi = gray[y:y+h, x:x+w]
            
            # Resize to standard size for consistency
            face_roi = cv2.resize(face_roi, (100, 100))
            
            # Create a simple face hash for comparison
            # This is a simplified approach - in production you'd use proper face embeddings
            face_hash = hashlib.md5(face_roi.tobytes()).hexdigest()
            
            return {
                'face_hash': face_hash,
                'face_data': face_roi.tobytes(),
                'bbox': (x, y, w, h)
            }, None
            
        except Exception as e:
            logger.error(f"Failed to extract face features: {e}")
            return None, f"Face processing error: {str(e)}"
    
    def create_admin_user(self, name, image_base64):
        """Create an admin user with face recognition"""
        try:
            # Check if admin already exists
            users = self.get_all_users()
            admin_exists = any(user['permission_level'] == 'admin' for user in users)
            
            if admin_exists:
                return {
                    "success": False,
                    "message": "Admin user already exists. Only one admin is allowed."
                }
            
            # Decode and process the image
            image_cv = self._decode_image(image_base64)
            if image_cv is None:
                return {"success": False, "message": "Invalid image data"}
            
            # Extract face features
            face_features, error = self._extract_face_features(image_cv)
            if face_features is None:
                return {"success": False, "message": error or "Could not process face"}
            
            # Create user record
            user_id = str(uuid.uuid4())
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """INSERT INTO users (id, name, face_hash, face_data, permission_level, created_at) 
                       VALUES (?, ?, ?, ?, ?, ?)""",
                    (user_id, name, face_features['face_hash'], face_features['face_data'], 
                     'admin', datetime.now().isoformat())
                )
                conn.commit()
            
            logger.info(f"Admin user '{name}' created successfully with ID: {user_id}")
            return {
                "success": True,
                "message": f"Admin user '{name}' created successfully!",
                "user_id": user_id
            }
            
        except Exception as e:
            logger.error(f"Failed to create admin user: {e}")
            return {"success": False, "message": f"Failed to create admin user: {str(e)}"}
    
    def create_regular_user(self, name, image_base64, permission_level='read_only'):
        """Create a regular user with face recognition"""
        try:
            # Decode and process the image
            image_cv = self._decode_image(image_base64)
            if image_cv is None:
                return {"success": False, "message": "Invalid image data"}
            
            # Extract face features
            face_features, error = self._extract_face_features(image_cv)
            if face_features is None:
                return {"success": False, "message": error or "Could not process face"}
            
            # Check for duplicate faces (simplified check)
            users = self.get_all_users()
            for user in users:
                if user['face_hash'] == face_features['face_hash']:
                    return {
                        "success": False,
                        "message": f"This face is already registered for user: {user['name']}"
                    }
            
            # Create user record
            user_id = str(uuid.uuid4())
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """INSERT INTO users (id, name, face_hash, face_data, permission_level, created_at) 
                       VALUES (?, ?, ?, ?, ?, ?)""",
                    (user_id, name, face_features['face_hash'], face_features['face_data'], 
                     permission_level, datetime.now().isoformat())
                )
                conn.commit()
            
            logger.info(f"User '{name}' created successfully with ID: {user_id}")
            return {
                "success": True,
                "message": f"User '{name}' created successfully!",
                "user_id": user_id
            }
            
        except Exception as e:
            logger.error(f"Failed to create user: {e}")
            return {"success": False, "message": f"Failed to create user: {str(e)}"}
    
    def authenticate_user(self, image_base64):
        """Authenticate user using face recognition"""
        try:
            # Decode and process the image
            image_cv = self._decode_image(image_base64)
            if image_cv is None:
                return {"success": False, "message": "Invalid image data"}
            
            # Extract face features from input image
            face_features, error = self._extract_face_features(image_cv)
            if face_features is None:
                return {"success": False, "message": error or "Could not process face"}
            
            # Get all registered users
            users = self.get_all_users()
            if not users:
                return {
                    "success": False,
                    "message": "No users registered. Please setup admin user first."
                }
            
            # Simple hash matching (in production, use proper face recognition)
            for user in users:
                if user['face_hash'] == face_features['face_hash']:
                    logger.info(f"User authenticated: {user['name']}")
                    return {
                        "success": True,
                        "user": {
                            "id": user['id'],
                            "name": user['name']
                        },
                        "permission_level": user['permission_level'],
                        "message": f"Welcome back, {user['name']}!",
                        "confidence": 0.95  # Simulated confidence
                    }
            
            return {
                "success": False,
                "message": "Face not recognized. Please ensure you are registered."
            }
                
        except Exception as e:
            logger.error(f"Authentication failed: {e}")
            return {"success": False, "message": f"Authentication error: {str(e)}"}
    
    def get_all_users(self):
        """Get all registered users"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT id, name, face_hash, permission_level, created_at 
                    FROM users ORDER BY created_at
                """)
                rows = cursor.fetchall()
                
                users = []
                for row in rows:
                    users.append({
                        'id': row[0],
                        'name': row[1],
                        'face_hash': row[2],
                        'permission_level': row[3],
                        'created_at': row[4]
                    })
                
                return users
                
        except Exception as e:
            logger.error(f"Failed to get users: {e}")
            return []
    
    def delete_user(self, user_id):
        """Delete a user by ID"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("DELETE FROM users WHERE id = ?", (user_id,))
                
                if cursor.rowcount > 0:
                    conn.commit()
                    return {"success": True, "message": "User deleted successfully"}
                else:
                    return {"success": False, "message": "User not found"}
                    
        except Exception as e:
            logger.error(f"Failed to delete user: {e}")
            return {"success": False, "message": f"Failed to delete user: {str(e)}"}
    
    def check_query_permission(self, query, permission_level):
        """Check if user has permission to execute the query"""
        if permission_level == 'admin':
            return {"allowed": True, "message": "Admin access granted"}
        
        # Define dangerous operations for read-only users
        dangerous_keywords = [
            'drop', 'delete', 'truncate', 'alter', 'create', 'insert', 
            'update', 'grant', 'revoke', 'commit', 'rollback'
        ]
        
        query_lower = query.lower().strip()
        
        # Check for dangerous keywords
        for keyword in dangerous_keywords:
            if keyword in query_lower:
                return {
                    "allowed": False,
                    "message": f"Permission denied: Read-only users cannot perform '{keyword}' operations"
                }
        
        return {"allowed": True, "message": "Query permission granted"}
    
    def should_generate_chart(self, query):
        """Determine if query should generate a chart based on keywords"""
        chart_keywords = [
            'chart', 'graph', 'plot', 'visual', 'visualize', 'show', 'display',
            'histogram', 'bar chart', 'line chart', 'pie chart', 'scatter plot',
            'trend', 'distribution', 'comparison', 'over time'
        ]
        
        query_lower = query.lower()
        return any(keyword in query_lower for keyword in chart_keywords)
    
    def log_access(self, user_id, user_name, access_type, query, ip_address, success):
        """Log user access and activities"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT INTO access_logs 
                    (user_id, user_name, access_type, query, ip_address, timestamp, success)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (
                    user_id,
                    user_name,
                    access_type,
                    query[:1000] if query else "",  # Limit query length for storage
                    ip_address,
                    datetime.now().isoformat(),
                    success
                ))
                conn.commit()
                
        except Exception as e:
            logger.error(f"Failed to log access: {e}")
    
    def get_access_logs(self, limit=100):
        """Get recent access logs"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT user_name, access_type, query, ip_address, timestamp, success
                    FROM access_logs 
                    ORDER BY timestamp DESC 
                    LIMIT ?
                """, (limit,))
                
                rows = cursor.fetchall()
                return [{
                    'user_name': row[0],
                    'access_type': row[1],
                    'query': row[2],
                    'ip_address': row[3],
                    'timestamp': row[4],
                    'success': row[5]
                } for row in rows]
                
        except Exception as e:
            logger.error(f"Failed to get access logs: {e}")
            return []
    
    def get_system_status(self):
        """Get facial authentication system status"""
        try:
            users = self.get_all_users()
            admin_count = sum(1 for user in users if user['permission_level'] == 'admin')
            regular_count = len(users) - admin_count
            
            return {
                "status": "operational",
                "total_users": len(users),
                "admin_users": admin_count,
                "regular_users": regular_count,
                "database_path": self.db_path,
                "face_recognition_available": self.face_recognition_available
            }
            
        except Exception as e:
            logger.error(f"Failed to get system status: {e}")
            return {
                "status": "error",
                "error": str(e),
                "face_recognition_available": False
            }
    
    # COMPATIBILITY METHODS FOR APP.PY
    def authenticate_face(self, image_base64):
        """Compatibility method - calls authenticate_user"""
        return self.authenticate_user(image_base64)
    
    def add_authorized_user(self, name, role, image_base64):
        """Add authorized user with role mapping"""
        # Map roles to permission levels
        role_mapping = {
            'admin': 'admin',
            'read-only': 'read_only',
            'readonly': 'read_only',
            'user': 'read_only'
        }
        
        permission_level = role_mapping.get(role.lower(), 'read_only')
        
        if permission_level == 'admin':
            return self.create_admin_user(name, image_base64)
        else:
            return self.create_regular_user(name, image_base64, permission_level)
    
    def get_authorized_users(self):
        """Get authorized users without sensitive data"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT id, name, permission_level, created_at 
                    FROM users ORDER BY created_at
                """)
                rows = cursor.fetchall()
                
                users = []
                for row in rows:
                    users.append({
                        'id': row[0],
                        'name': row[1],
                        'permission_level': row[2],
                        'created_at': row[3]
                    })
                
                return users
                
        except Exception as e:
            logger.error(f"Failed to get authorized users: {e}")
            return []

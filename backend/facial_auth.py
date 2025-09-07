import sqlite3
import face_recognition
import numpy as np
import base64
from PIL import Image
import io
import uuid
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

class FacialAuthSystem:
    def __init__(self):
        self.db_path = 'facial_auth.db'
        self.init_database()
    
    def init_database(self):
        """Initialize the facial authentication database"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Create users table
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS users (
                        id TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        face_encoding BLOB NOT NULL,
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
    
    def execute_query(self, query, params=None):
        """Execute a database query"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                if params:
                    cursor.execute(query, params)
                else:
                    cursor.execute(query)
                
                if query.strip().upper().startswith('SELECT'):
                    return cursor.fetchall()
                else:
                    conn.commit()
                    return cursor.rowcount
        except Exception as e:
            logger.error(f"Database query failed: {e}")
            raise e
    
    def authenticate_user(self, image_base64):
        """Authenticate user using facial recognition"""
        try:
            # Decode base64 image
            image_data = base64.b64decode(image_base64)
            image = Image.open(io.BytesIO(image_data))
            image_np = np.array(image)
            
            # Get face encoding
            face_encodings = face_recognition.face_encodings(image_np)
            if not face_encodings:
                return {"success": False, "message": "No face found in image"}
            
            user_encoding = face_encodings[0]
            
            # Check against known faces
            users = self.get_all_users()
            for user in users:
                known_encoding = np.frombuffer(user['face_encoding'], dtype=np.float64)
                match = face_recognition.compare_faces([known_encoding], user_encoding, tolerance=0.6)
                
                if match[0]:
                    return {
                        "success": True,
                        "user": {"id": user['id'], "name": user['name']},
                        "permission_level": user['permission_level'],
                        "message": f"Welcome back, {user['name']}!"
                    }
            
            return {"success": False, "message": "Face not recognized"}
            
        except Exception as e:
            logger.error(f"Authentication failed: {e}")
            return {"success": False, "message": f"Authentication failed: {str(e)}"}
    
    def create_admin_user(self, name, image_base64):
        """Create admin user with facial recognition"""
        try:
            # Check if admin already exists
            users = self.get_all_users()
            if any(user['permission_level'] == 'admin' for user in users):
                return {"success": False, "message": "Admin user already exists"}
            
            # Decode and process image
            image_data = base64.b64decode(image_base64)
            image = Image.open(io.BytesIO(image_data))
            image_np = np.array(image)
            
            # Get face encoding
            face_encodings = face_recognition.face_encodings(image_np)
            if not face_encodings:
                return {"success": False, "message": "No face found in image"}
            
            face_encoding = face_encodings[0]
            
            # Save to database
            user_id = str(uuid.uuid4())
            query = """
            INSERT INTO users (id, name, face_encoding, permission_level, created_at)
            VALUES (?, ?, ?, ?, ?)
            """
            
            self.execute_query(query, (
                user_id,
                name,
                face_encoding.tobytes(),
                'admin',
                datetime.now().isoformat()
            ))
            
            return {
                "success": True,
                "message": f"Admin user '{name}' created successfully",
                "user_id": user_id
            }
            
        except Exception as e:
            logger.error(f"Failed to create admin: {e}")
            return {"success": False, "message": f"Failed to create admin: {str(e)}"}
    
    def get_all_users(self):
        """Get all users from database"""
        try:
            query = "SELECT id, name, face_encoding, permission_level, created_at FROM users"
            rows = self.execute_query(query)
            
            users = []
            for row in rows:
                users.append({
                    'id': row[0],
                    'name': row[1],
                    'face_encoding': row[2],
                    'permission_level': row[3],
                    'created_at': row[4]
                })
            return users
        except Exception as e:
            logger.error(f"Failed to get users: {e}")
            return []
    
    def check_query_permission(self, query, permission_level):
        """Check if user has permission for the query"""
        # Admin users can do anything
        if permission_level == 'admin':
            return {"allowed": True, "message": "Admin access granted"}
        
        # Check for dangerous operations for read-only users
        dangerous_keywords = ['drop', 'delete', 'truncate', 'alter', 'create', 'insert', 'update']
        query_lower = query.lower()
        
        for keyword in dangerous_keywords:
            if keyword in query_lower:
                return {
                    "allowed": False, 
                    "message": f"Read-only users cannot perform '{keyword}' operations"
                }
        
        return {"allowed": True, "message": "Query allowed"}
    
    def should_generate_chart(self, query):
        """Check if query should generate a chart"""
        chart_keywords = ['chart', 'graph', 'plot', 'visual', 'show', 'display']
        return any(keyword in query.lower() for keyword in chart_keywords)
    
    def log_access(self, user_id, user_name, access_type, query, ip_address, success):
        """Log access attempt"""
        try:
            log_query = """
            INSERT INTO access_logs (user_id, user_name, access_type, query, ip_address, timestamp, success)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            
            self.execute_query(log_query, (
                user_id,
                user_name,
                access_type,
                query,
                ip_address,
                datetime.now().isoformat(),
                success
            ))
        except Exception as e:
            logger.error(f"Failed to log access: {e}")
    
    def authenticate_face(self, image_base64):
        """Legacy method for compatibility"""
        return self.authenticate_user(image_base64)
    
    def add_authorized_user(self, name, role, image_base64):
        """Add a new authorized user"""
        try:
            # Decode and process image
            image_data = base64.b64decode(image_base64)
            image = Image.open(io.BytesIO(image_data))
            image_np = np.array(image)
            
            # Get face encoding
            face_encodings = face_recognition.face_encodings(image_np)
            if not face_encodings:
                return {"success": False, "message": "No face found in image"}
            
            face_encoding = face_encodings[0]
            
            # Save to database
            user_id = str(uuid.uuid4())
            query = """
            INSERT INTO users (id, name, face_encoding, permission_level, created_at)
            VALUES (?, ?, ?, ?, ?)
            """
            
            self.execute_query(query, (
                user_id,
                name,
                face_encoding.tobytes(),
                role,
                datetime.now().isoformat()
            ))
            
            return {
                "success": True,
                "message": f"User '{name}' added successfully",
                "user_id": user_id
            }
            
        except Exception as e:
            logger.error(f"Failed to add user: {e}")
            return {"success": False, "message": f"Failed to add user: {str(e)}"}
    
    def get_authorized_users(self):
        """Get list of authorized users (without face encodings)"""
        try:
            query = "SELECT id, name, permission_level, created_at FROM users"
            rows = self.execute_query(query)
            
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

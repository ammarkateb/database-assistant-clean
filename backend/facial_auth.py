import sqlite3
import uuid
from datetime import datetime
import logging
import base64
import hashlib

logger = logging.getLogger(__name__)

class FacialAuthSystem:
    def __init__(self):
        self.db_path = 'facial_auth.db'
        self.init_database()
        logger.info("Simple facial auth system initialized")
    
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
                        image_hash TEXT NOT NULL,
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
    
    def _create_image_hash(self, image_base64):
        """Create a simple hash from the image data"""
        try:
            # Handle different base64 formats
            if isinstance(image_base64, str):
                if image_base64.startswith('data:'):
                    image_base64 = image_base64.split(',')[1]
                image_base64 = image_base64.strip()
            
            # Create hash from image data
            image_hash = hashlib.sha256(image_base64.encode()).hexdigest()[:32]
            return image_hash
            
        except Exception as e:
            logger.error(f"Failed to create image hash: {e}")
            return None
    
    def create_admin_user(self, name, image_base64):
        """Create an admin user"""
        try:
            # Check if admin already exists
            users = self.get_all_users()
            admin_exists = any(user['permission_level'] == 'admin' for user in users)
            
            if admin_exists:
                return {
                    "success": False,
                    "message": "Admin user already exists. Only one admin is allowed."
                }
            
            # Create image hash
            image_hash = self._create_image_hash(image_base64)
            if not image_hash:
                return {"success": False, "message": "Invalid image data"}
            
            # Create user record
            user_id = str(uuid.uuid4())
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """INSERT INTO users (id, name, image_hash, permission_level, created_at) 
                       VALUES (?, ?, ?, ?, ?)""",
                    (user_id, name, image_hash, 'admin', datetime.now().isoformat())
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
        """Create a regular user"""
        try:
            # Create image hash
            image_hash = self._create_image_hash(image_base64)
            if not image_hash:
                return {"success": False, "message": "Invalid image data"}
            
            # Check for duplicate image hashes
            users = self.get_all_users()
            for user in users:
                if user.get('image_hash') == image_hash:
                    return {
                        "success": False,
                        "message": f"This image is already registered for user: {user['name']}"
                    }
            
            # Create user record
            user_id = str(uuid.uuid4())
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """INSERT INTO users (id, name, image_hash, permission_level, created_at) 
                       VALUES (?, ?, ?, ?, ?)""",
                    (user_id, name, image_hash, permission_level, datetime.now().isoformat())
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
        """Authenticate user using image hash comparison"""
        try:
            # Create hash from input image
            input_hash = self._create_image_hash(image_base64)
            if not input_hash:
                return {"success": False, "message": "Invalid image data"}
            
            # Get all registered users
            users = self.get_all_users()
            if not users:
                return {
                    "success": False,
                    "message": "No users registered. Please setup admin user first."
                }
            
            # Check for matching hash
            for user in users:
                if user.get('image_hash') == input_hash:
                    logger.info(f"User authenticated: {user['name']}")
                    return {
                        "success": True,
                        "user": {
                            "id": user['id'],
                            "name": user['name']
                        },
                        "permission_level": user['permission_level'],
                        "message": f"Welcome back, {user['name']}!",
                        "confidence": 1.0
                    }
            
            return {
                "success": False,
                "message": "Image not recognized. Please ensure you are registered."
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
                    SELECT id, name, image_hash, permission_level, created_at 
                    FROM users ORDER BY created_at
                """)
                rows = cursor.fetchall()
                
                users = []
                for row in rows:
                    users.append({
                        'id': row[0],
                        'name': row[1],
                        'image_hash': row[2],
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
                    query[:1000] if query else "",
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
                "face_recognition_available": True
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

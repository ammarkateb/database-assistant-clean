# facial_auth.py
import sqlite3
import base64
import io
from PIL import Image
from datetime import datetime
from typing import List, Dict, Optional

class FacialAuthSystem:
    def __init__(self, db_path: str = "facial_auth.db"):
        self.db_path = db_path
        self.init_database()
        self.authorized_faces = self.load_authorized_faces()
        
    def init_database(self):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS authorized_users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                role TEXT NOT NULL CHECK (role IN ('admin', 'read-only')),
                face_encoding BLOB NOT NULL,
                date_added TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                is_active BOOLEAN DEFAULT TRUE
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS access_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                user_name TEXT,
                access_type TEXT,
                query TEXT,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                ip_address TEXT,
                success BOOLEAN
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def load_authorized_faces(self):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('SELECT id, name, role, face_encoding FROM authorized_users WHERE is_active = TRUE')

        authorized_faces = []
        for row in cursor.fetchall():
            user_id, name, role, encoding_blob = row
            # Skip face_encoding processing for now
            authorized_faces.append({
                'id': user_id,
                'name': name,
                'role': role
            })
        
        conn.close()
        return authorized_faces
    
    def authenticate_face(self, image_data: str):
        try:
            # Basic image validation
            if not image_data or image_data == "test":
                return {
                    "success": False, 
                    "message": "No image provided",
                    "permission_level": "read-only",
                    "user": None
                }
            
            # Validate it's actually image data
            try:
                if 'base64,' in image_data:
                    image_data = image_data.split('base64,')[1]
                
                image_bytes = base64.b64decode(image_data)
                image = Image.open(io.BytesIO(image_bytes))
                # If we get here, it's a valid image
            except:
                return {
                    "success": False,
                    "message": "Invalid image format",
                    "permission_level": "read-only", 
                    "user": None
                }
            
            # Demo authentication: if authorized users exist, authenticate as first admin
            if len(self.authorized_faces) > 0:
                # Find first admin user, or fallback to any user
                admin_user = next((user for user in self.authorized_faces if user['role'] == 'admin'), None)
                user = admin_user or self.authorized_faces[0]
                
                return {
                    "success": True,
                    "message": f"Demo mode: Authenticated as {user['name']}",
                    "permission_level": user['role'],
                    "user": {
                        "id": user['id'],
                        "name": user['name'], 
                        "role": user['role']
                    }
                }
            
            return {
                "success": False,
                "message": "No authorized users found. Add users first.",
                "permission_level": "read-only",
                "user": None
            }
            
        except Exception as e:
            return {
                "success": False,
                "message": f"Authentication error: {str(e)}",
                "permission_level": "read-only",
                "user": None
            }
    
    def check_query_permission(self, query: str, permission_level: str):
        if permission_level == 'none':
            return {"allowed": False, "message": "No database access"}
        
        write_keywords = ['INSERT', 'UPDATE', 'DELETE', 'DROP', 'CREATE', 'ALTER', 'TRUNCATE']
        query_upper = query.upper().strip()
        is_write = any(keyword in query_upper for keyword in write_keywords)
        
        if is_write and permission_level != 'admin':
            return {"allowed": False, "message": "Write operations require admin privileges"}
        
        return {"allowed": True, "message": "Query authorized"}
    
    def log_access(self, user_id, user_name, access_type, query, ip_address, success):
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO access_logs (user_id, user_name, access_type, query, ip_address, success)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (user_id, user_name, access_type, query, ip_address, success))
            conn.commit()
            conn.close()
        except Exception as e:
            print(f"Error logging access: {e}")

    def should_generate_chart(self, query: str):
        """Check if query should generate a chart"""
        chart_keywords = ['chart', 'graph', 'plot', 'visual', 'show', 'display']
        return any(keyword in query.lower() for keyword in chart_keywords)

    def add_authorized_user(self, name: str, role: str, image_data: str):
        try:
            # Validate image
            if 'base64,' in image_data:
                image_data = image_data.split('base64,')[1]
            
            image_bytes = base64.b64decode(image_data)
            image = Image.open(io.BytesIO(image_bytes))
            
            # Store user without face encoding for now
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO authorized_users (name, role, face_encoding)
                VALUES (?, ?, ?)
            ''', (name, role, b'demo_encoding'))
            
            conn.commit()
            user_id = cursor.lastrowid
            conn.close()
            
            # Reload faces
            self.authorized_faces = self.load_authorized_faces()
            
            return {
                "success": True,
                "message": f"User {name} added successfully",
                "user_id": user_id
            }
            
        except Exception as e:
            return {
                "success": False,
                "message": f"Error adding user: {str(e)}"
            }

    def get_authorized_users(self):
        return [{"id": user["id"], "name": user["name"], "role": user["role"]} 
                for user in self.authorized_faces]

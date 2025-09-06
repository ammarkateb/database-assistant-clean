# facial_auth.py
import cv2
import face_recognition
import numpy as np
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
            face_encoding = np.frombuffer(encoding_blob, dtype=np.float64)
            authorized_faces.append({
                'id': user_id,
                'name': name,
                'role': role,
                'encoding': face_encoding
            })
        
        conn.close()
        return authorized_faces
    
    def authenticate_face(self, image_data: str):
        try:
            if 'base64,' in image_data:
                image_data = image_data.split('base64,')[1]
            
            image_bytes = base64.b64decode(image_data)
            image = Image.open(io.BytesIO(image_bytes))
            image_np = np.array(image)
            
            if len(image_np.shape) == 3 and image_np.shape[2] == 3:
                image_np = cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR)
            
            face_locations = face_recognition.face_locations(image_np)
            if len(face_locations) == 0:
                return {
                    "success": False, 
                    "message": "No face detected",
                    "permission_level": "read-only",
                    "user": None
                }
            
            face_encodings = face_recognition.face_encodings(image_np, face_locations)
            if len(face_encodings) == 0:
                return {
                    "success": False, 
                    "message": "Could not encode face",
                    "permission_level": "read-only",
                    "user": None
                }
            
            unknown_encoding = face_encodings[0]
            
            if len(self.authorized_faces) == 0:
                return {
                    "success": False, 
                    "message": "No authorized users found",
                    "permission_level": "read-only",
                    "user": None
                }
            
            authorized_encodings = [user['encoding'] for user in self.authorized_faces]
            face_distances = face_recognition.face_distance(authorized_encodings, unknown_encoding)
            
            best_match_index = np.argmin(face_distances)
            best_distance = face_distances[best_match_index]
            
            if best_distance < 0.5:
                matched_user = self.authorized_faces[best_match_index]
                return {
                    "success": True,
                    "message": f"Welcome, {matched_user['name']}!",
                    "permission_level": matched_user['role'],
                    "user": {
                        "id": matched_user['id'],
                        "name": matched_user['name'],
                        "role": matched_user['role']
                    }
                }
            else:
                return {
                    "success": False,
                    "message": "Face not recognized. Read-only access granted.",
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

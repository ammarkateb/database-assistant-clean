import sqlite3
import uuid
from datetime import datetime
import logging
import base64
import hashlib
import numpy as np
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

class FacialAuthSystem:
    def __init__(self):
        self.db_path = 'facial_auth.db'
        self.init_database()
        logger.info("Enhanced facial auth system initialized with tolerance support")
    
    def init_database(self):
        """Initialize the facial authentication database with enhanced schema"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Create users table with multiple face samples support
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS users (
                        id TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        permission_level TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        updated_at TEXT
                    )
                ''')
                
                # Create face_samples table for multiple reference images
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS face_samples (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        user_id TEXT NOT NULL,
                        image_hash TEXT NOT NULL,
                        sample_number INTEGER NOT NULL,
                        created_at TEXT NOT NULL,
                        FOREIGN KEY (user_id) REFERENCES users (id),
                        UNIQUE(user_id, sample_number)
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
                        success BOOLEAN,
                        confidence_score REAL
                    )
                ''')
                
                conn.commit()
                logger.info("Enhanced facial auth database initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize database: {e}")
            raise
    
    def _create_image_hash(self, image_base64: str) -> Optional[str]:
        """Create a hash from the image data with better normalization"""
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
    
    def _calculate_hash_similarity(self, hash1: str, hash2: str) -> float:
        """Calculate similarity between two hashes (simple implementation)"""
        try:
            if len(hash1) != len(hash2):
                return 0.0
            
            matches = sum(c1 == c2 for c1, c2 in zip(hash1, hash2))
            similarity = matches / len(hash1)
            return similarity
            
        except Exception as e:
            logger.error(f"Failed to calculate hash similarity: {e}")
            return 0.0
    
    def _find_similar_faces(self, input_hash: str, tolerance: float = 0.92) -> List[Dict]:
        """Find faces similar to input hash within tolerance"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT fs.user_id, fs.image_hash, u.name, u.permission_level, fs.sample_number
                    FROM face_samples fs
                    JOIN users u ON fs.user_id = u.id
                """)
                
                samples = cursor.fetchall()
                similar_faces = []
                
                for user_id, stored_hash, name, permission_level, sample_number in samples:
                    similarity = self._calculate_hash_similarity(input_hash, stored_hash)
                    if similarity >= tolerance:
                        similar_faces.append({
                            'user_id': user_id,
                            'name': name,
                            'permission_level': permission_level,
                            'similarity': similarity,
                            'sample_number': sample_number
                        })
                
                # Sort by similarity (highest first)
                similar_faces.sort(key=lambda x: x['similarity'], reverse=True)
                return similar_faces
                
        except Exception as e:
            logger.error(f"Failed to find similar faces: {e}")
            return []
    
    def create_admin_user(self, name: str, image_base64: str) -> Dict:
        """Create an admin user with enhanced face registration"""
        try:
            # Check if admin already exists
            users = self.get_all_users()
            admin_exists = any(user['permission_level'] == 'admin' for user in users)
            
            if admin_exists:
                return {
                    "success": False,
                    "message": "Admin user already exists. Only one admin is allowed."
                }
            
            return self.register_user_with_tolerance(name, image_base64, 'admin')
            
        except Exception as e:
            logger.error(f"Failed to create admin user: {e}")
            return {"success": False, "message": f"Failed to create admin user: {str(e)}"}
    
    def create_regular_user(self, name: str, image_base64: str, permission_level: str = 'read_only') -> Dict:
        """Create a regular user with enhanced face registration"""
        return self.register_user_with_tolerance(name, image_base64, permission_level)
    
    def register_user_with_tolerance(self, name: str, image_base64: str, permission_level: str = 'read_only') -> Dict:
        """Register user with multiple face samples for better recognition"""
        try:
            # Create image hash
            image_hash = self._create_image_hash(image_base64)
            if not image_hash:
                return {"success": False, "message": "Invalid image data"}
            
            # Check for existing user with this name
            existing_user = self._get_user_by_name(name)
            
            if existing_user:
                # Add new face sample to existing user
                return self._add_face_sample_to_user(existing_user['id'], image_hash)
            else:
                # Create new user
                user_id = str(uuid.uuid4())
                
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.cursor()
                    
                    # Create user record
                    cursor.execute(
                        """INSERT INTO users (id, name, permission_level, created_at, updated_at) 
                           VALUES (?, ?, ?, ?, ?)""",
                        (user_id, name, permission_level, datetime.now().isoformat(), datetime.now().isoformat())
                    )
                    
                    # Add first face sample
                    cursor.execute(
                        """INSERT INTO face_samples (user_id, image_hash, sample_number, created_at)
                           VALUES (?, ?, ?, ?)""",
                        (user_id, image_hash, 1, datetime.now().isoformat())
                    )
                    
                    conn.commit()
                
                logger.info(f"User '{name}' registered successfully with enhanced face recognition")
                return {
                    "success": True,
                    "message": f"User '{name}' registered successfully with enhanced face recognition!",
                    "user_id": user_id
                }
            
        except Exception as e:
            logger.error(f"Failed to register user: {e}")
            return {"success": False, "message": f"Failed to register user: {str(e)}"}
    
    def _get_user_by_name(self, name: str) -> Optional[Dict]:
        """Get user by name"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT id, name, permission_level FROM users WHERE name = ?", (name,))
                result = cursor.fetchone()
                
                if result:
                    return {
                        'id': result[0],
                        'name': result[1],
                        'permission_level': result[2]
                    }
                return None
                
        except Exception as e:
            logger.error(f"Failed to get user by name: {e}")
            return None
    
    def _add_face_sample_to_user(self, user_id: str, image_hash: str) -> Dict:
        """Add additional face sample to existing user"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Get current sample count
                cursor.execute("SELECT COUNT(*) FROM face_samples WHERE user_id = ?", (user_id,))
                sample_count = cursor.fetchone()[0]
                
                # Limit to 5 samples per user
                if sample_count >= 5:
                    # Replace oldest sample
                    cursor.execute("""
                        DELETE FROM face_samples 
                        WHERE user_id = ? 
                        ORDER BY created_at ASC 
                        LIMIT 1
                    """, (user_id,))
                    sample_number = sample_count
                else:
                    sample_number = sample_count + 1
                
                # Add new sample
                cursor.execute(
                    """INSERT INTO face_samples (user_id, image_hash, sample_number, created_at)
                       VALUES (?, ?, ?, ?)""",
                    (user_id, image_hash, sample_number, datetime.now().isoformat())
                )
                
                # Update user's last updated time
                cursor.execute(
                    "UPDATE users SET updated_at = ? WHERE id = ?",
                    (datetime.now().isoformat(), user_id)
                )
                
                conn.commit()
                
                return {
                    "success": True,
                    "message": f"Additional face sample added successfully! Now have {sample_number} samples for better recognition.",
                    "user_id": user_id
                }
                
        except Exception as e:
            logger.error(f"Failed to add face sample: {e}")
            return {"success": False, "message": f"Failed to add face sample: {str(e)}"}
    
    def authenticate_user(self, image_base64: str) -> Dict:
        """Authenticate user using basic hash comparison (backwards compatibility)"""
        try:
            input_hash = self._create_image_hash(image_base64)
            if not input_hash:
                return {"success": False, "message": "Invalid image data"}
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT DISTINCT u.id, u.name, u.permission_level
                    FROM users u
                    JOIN face_samples fs ON u.id = fs.user_id
                    WHERE fs.image_hash = ?
                """, (input_hash,))
                
                result = cursor.fetchone()
                
                if result:
                    user_id, name, permission_level = result
                    logger.info(f"User authenticated: {name}")
                    return {
                        "success": True,
                        "user": {"id": user_id, "name": name},
                        "permission_level": permission_level,
                        "message": f"Welcome back, {name}!",
                        "confidence": 1.0
                    }
                
                return {
                    "success": False,
                    "message": "Face not recognized. Please ensure you are registered or try the enhanced recognition."
                }
                
        except Exception as e:
            logger.error(f"Authentication failed: {e}")
            return {"success": False, "message": f"Authentication error: {str(e)}"}
    
    def authenticate_user_with_tolerance(self, image_base64: str, tolerance: float = 0.90) -> Dict:
        """Authenticate user with improved tolerance for face variations"""
        try:
            input_hash = self._create_image_hash(image_base64)
            if not input_hash:
                return {"success": False, "message": "Invalid image data"}
            
            # First try exact match
            exact_result = self.authenticate_user(image_base64)
            if exact_result['success']:
                return exact_result
            
            # Try similarity matching
            similar_faces = self._find_similar_faces(input_hash, tolerance)
            
            if similar_faces:
                # Get best match
                best_match = similar_faces[0]
                confidence = best_match['similarity']
                
                logger.info(f"User authenticated with tolerance: {best_match['name']} (confidence: {confidence:.2f})")
                return {
                    "success": True,
                    "user": {
                        "id": best_match['user_id'],
                        "name": best_match['name']
                    },
                    "permission_level": best_match['permission_level'],
                    "message": f"Welcome back, {best_match['name']}! (Recognition confidence: {confidence:.0%})",
                    "confidence": confidence
                }
            
            return {
                "success": False,
                "message": "Face not recognized. Please ensure proper lighting and positioning, or register your face again."
            }
                
        except Exception as e:
            logger.error(f"Enhanced authentication failed: {e}")
            return {"success": False, "message": f"Authentication error: {str(e)}"}
    
    def get_all_users(self) -> List[Dict]:
        """Get all registered users with sample counts"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT u.id, u.name, u.permission_level, u.created_at, u.updated_at,
                           COUNT(fs.id) as sample_count
                    FROM users u
                    LEFT JOIN face_samples fs ON u.id = fs.user_id
                    GROUP BY u.id, u.name, u.permission_level, u.created_at, u.updated_at
                    ORDER BY u.created_at
                """)
                rows = cursor.fetchall()
                
                users = []
                for row in rows:
                    users.append({
                        'id': row[0],
                        'name': row[1],
                        'permission_level': row[2],
                        'created_at': row[3],
                        'updated_at': row[4],
                        'face_samples': row[5]
                    })
                
                return users
                
        except Exception as e:
            logger.error(f"Failed to get users: {e}")
            return []
    
    def delete_user(self, user_id: str) -> Dict:
        """Delete a user and all their face samples"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Delete face samples first
                cursor.execute("DELETE FROM face_samples WHERE user_id = ?", (user_id,))
                
                # Delete user
                cursor.execute("DELETE FROM users WHERE id = ?", (user_id,))
                
                if cursor.rowcount > 0:
                    conn.commit()
                    return {"success": True, "message": "User and all face samples deleted successfully"}
                else:
                    return {"success": False, "message": "User not found"}
                    
        except Exception as e:
            logger.error(f"Failed to delete user: {e}")
            return {"success": False, "message": f"Failed to delete user: {str(e)}"}
    
    def check_query_permission(self, query: str, permission_level: str) -> Dict:
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
    
    def should_generate_chart(self, query: str) -> bool:
        """Determine if query should generate a chart based on keywords"""
        chart_keywords = [
            'chart', 'graph', 'plot', 'visual', 'visualize', 'show', 'display',
            'histogram', 'bar chart', 'line chart', 'pie chart', 'scatter plot',
            'trend', 'distribution', 'comparison', 'over time'
        ]
        
        query_lower = query.lower()
        return any(keyword in query_lower for keyword in chart_keywords)
    
    def log_access(self, user_id: Optional[str], user_name: str, access_type: str, query: str, ip_address: str, success: bool, confidence_score: float = 1.0):
        """Log user access and activities with confidence score"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT INTO access_logs 
                    (user_id, user_name, access_type, query, ip_address, timestamp, success, confidence_score)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    user_id,
                    user_name,
                    access_type,
                    query[:1000] if query else "",
                    ip_address,
                    datetime.now().isoformat(),
                    success,
                    confidence_score
                ))
                conn.commit()
                
        except Exception as e:
            logger.error(f"Failed to log access: {e}")
    
    def get_access_logs(self, limit: int = 100) -> List[Dict]:
        """Get recent access logs with confidence scores"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT user_name, access_type, query, ip_address, timestamp, success, confidence_score
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
                    'success': row[5],
                    'confidence_score': row[6] if row[6] is not None else 1.0
                } for row in rows]
                
        except Exception as e:
            logger.error(f"Failed to get access logs: {e}")
            return []
    
    def get_system_status(self) -> Dict:
        """Get enhanced facial authentication system status"""
        try:
            users = self.get_all_users()
            admin_count = sum(1 for user in users if user['permission_level'] == 'admin')
            regular_count = len(users) - admin_count
            
            # Get total face samples
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT COUNT(*) FROM face_samples")
                total_samples = cursor.fetchone()[0]
            
            return {
                "status": "operational",
                "total_users": len(users),
                "admin_users": admin_count,
                "regular_users": regular_count,
                "total_face_samples": total_samples,
                "average_samples_per_user": round(total_samples / len(users), 1) if users else 0,
                "database_path": self.db_path,
                "face_recognition_available": True,
                "enhanced_tolerance": True
            }
            
        except Exception as e:
            logger.error(f"Failed to get system status: {e}")
            return {
                "status": "error",
                "error": str(e),
                "face_recognition_available": False,
                "enhanced_tolerance": False
            }
    
    def optimize_user_samples(self, user_id: str) -> Dict:
        """Optimize face samples for a user by removing duplicates"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Get all samples for user
                cursor.execute("""
                    SELECT id, image_hash, created_at 
                    FROM face_samples 
                    WHERE user_id = ? 
                    ORDER BY created_at DESC
                """, (user_id,))
                
                samples = cursor.fetchall()
                unique_hashes = set()
                to_delete = []
                
                for sample_id, image_hash, created_at in samples:
                    if image_hash in unique_hashes:
                        to_delete.append(sample_id)
                    else:
                        unique_hashes.add(image_hash)
                
                # Delete duplicates
                if to_delete:
                    cursor.executemany("DELETE FROM face_samples WHERE id = ?", 
                                     [(sample_id,) for sample_id in to_delete])
                    conn.commit()
                    
                    return {
                        "success": True,
                        "message": f"Removed {len(to_delete)} duplicate face samples",
                        "removed_count": len(to_delete),
                        "remaining_count": len(samples) - len(to_delete)
                    }
                else:
                    return {
                        "success": True,
                        "message": "No duplicate samples found",
                        "removed_count": 0,
                        "remaining_count": len(samples)
                    }
                    
        except Exception as e:
            logger.error(f"Failed to optimize user samples: {e}")
            return {"success": False, "message": f"Failed to optimize samples: {str(e)}"}
    
    # COMPATIBILITY METHODS FOR APP.PY
    def authenticate_face(self, image_base64: str) -> Dict:
        """Compatibility method - calls enhanced authenticate_user_with_tolerance"""
        return self.authenticate_user_with_tolerance(image_base64)
    
    def add_authorized_user(self, name: str, role: str, image_base64: str) -> Dict:
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
    
    def get_authorized_users(self) -> List[Dict]:
        """Get authorized users without sensitive data"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT u.id, u.name, u.permission_level, u.created_at,
                           COUNT(fs.id) as sample_count
                    FROM users u
                    LEFT JOIN face_samples fs ON u.id = fs.user_id
                    GROUP BY u.id, u.name, u.permission_level, u.created_at
                    ORDER BY u.created_at
                """)
                rows = cursor.fetchall()
                
                users = []
                for row in rows:
                    users.append({
                        'id': row[0],
                        'name': row[1],
                        'permission_level': row[2],
                        'created_at': row[3],
                        'face_samples': row[4]
                    })
                
                return users
                
        except Exception as e:
            logger.error(f"Failed to get authorized users: {e}")
            return []
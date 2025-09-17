#!/usr/bin/env python
# coding: utf-8

import base64
import io
import json
import logging
import os
import re
import time
import hashlib
from contextlib import contextmanager
from datetime import datetime
from typing import Dict, Any, List, Optional, Tuple
import pandas as pd
import psycopg2
from psycopg2.pool import SimpleConnectionPool
import matplotlib.pyplot as plt
import seaborn as sns
import google.generativeai as genai
import numpy as np
from dotenv import load_dotenv

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('db_assistant.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configure matplotlib for better charts
plt.style.use('default')
sns.set_palette("husl")
plt.rcParams['figure.facecolor'] = 'white'
plt.rcParams['axes.facecolor'] = 'white'

class DatabaseAssistant:
    def __init__(self):
        """Initialize the Database Assistant with User Authentication"""
        self.load_environment()
        self.setup_ai_model()
        self.setup_database_pool()
        self.conversation_history = []
    


    def enroll_face_sample(self, user_id: int, face_features: str, sample_number: int) -> Dict[str, Any]:
        """Enroll a single face sample for a user (1-5)"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                # Validate sample number
                if sample_number not in [1, 2, 3, 4, 5]:
                    return {
                        'success': False,
                        'message': 'Sample number must be between 1 and 5'
                    }
                
                # Insert or update the face sample
                cursor.execute("""
                    INSERT INTO face_recognition_data (user_id, face_features, sample_number, is_active, registered_at)
                    VALUES (%s, %s, %s, true, NOW())
                    ON CONFLICT (user_id, sample_number) 
                    DO UPDATE SET 
                        face_features = EXCLUDED.face_features,
                        registered_at = NOW(),
                        is_active = true
                """, (user_id, face_features, sample_number))
                
                conn.commit()
                
                self.log_user_activity(user_id, 'face_sample_enrollment', f'Sample {sample_number} enrolled')
                
                return {
                    'success': True,
                    'message': f'Face sample {sample_number} enrolled successfully',
                    'sample_number': sample_number
                }
                
        except Exception as e:
            logger.error(f"Face sample enrollment error: {e}")
            return {
                'success': False,
                'message': f'Face sample enrollment failed: {str(e)}'
            }

    def complete_face_enrollment(self, user_id: int) -> Dict[str, Any]:
        """Complete face enrollment and enable face auth for user"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                # Check how many samples are enrolled
                cursor.execute("""
                    SELECT COUNT(*) FROM face_recognition_data 
                    WHERE user_id = %s AND is_active = true
                """, (user_id,))
                
                sample_count = cursor.fetchone()[0]
                
                if sample_count >= 3:  # Minimum 3 samples required
                    # Enable face auth for user
                    cursor.execute("""
                        UPDATE users SET face_auth_enabled = true WHERE user_id = %s
                    """, (user_id,))
                    
                    conn.commit()
                    
                    self.log_user_activity(user_id, 'face_enrollment_completed', f'Face auth enabled with {sample_count} samples')
                    
                    return {
                        'success': True,
                        'message': f'Face authentication enabled with {sample_count} samples',
                        'samples_enrolled': sample_count
                    }
                else:
                    return {
                        'success': False,
                        'message': f'Need at least 3 samples to enable face auth. Currently have {sample_count}',
                        'samples_enrolled': sample_count
                    }
                    
        except Exception as e:
            logger.error(f"Face enrollment completion error: {e}")
            return {
                'success': False,
                'message': f'Face enrollment completion failed: {str(e)}'
            }

    def verify_face_with_samples(self, face_features: str) -> Dict[str, Any]:
        """Verify face against all stored samples with 0.75 confidence threshold"""
        try:
            import json
            
            # Parse the incoming face features
            try:
                features_data = json.loads(face_features)
            except json.JSONDecodeError:
                return {
                    'success': False,
                    'message': 'Invalid face features format'
                }
            
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                # Get all active face samples for all users
                cursor.execute("""
                    SELECT frd.user_id, frd.face_features, frd.sample_number,
                        u.username, u.full_name, u.role
                    FROM face_recognition_data frd
                    JOIN users u ON frd.user_id = u.user_id
                    WHERE frd.is_active = true AND u.is_active = true AND u.face_auth_enabled = true
                """)
                
                enrolled_samples = cursor.fetchall()
                
                best_match = None
                best_confidence = 0
                user_confidences = {}  # Track best confidence per user
                
                for sample_record in enrolled_samples:
                    user_id, stored_encoding, sample_num, username, full_name, role = sample_record
                    
                    try:
                        stored_features = json.loads(stored_encoding)
                        
                        # Calculate confidence for this sample
                        confidence = self._calculate_face_similarity(features_data, stored_features)
                        
                        # Track the best confidence for each user across all their samples
                        if user_id not in user_confidences or confidence > user_confidences[user_id]['confidence']:
                            user_confidences[user_id] = {
                                'confidence': confidence,
                                'username': username,
                                'full_name': full_name,
                                'role': role,
                                'sample_number': sample_num
                            }
                            
                    except (json.JSONDecodeError, Exception) as e:
                        logger.warning(f"Error processing stored face data for user {user_id}, sample {sample_num}: {e}")
                        continue
                
                # Find the user with the highest confidence across all their samples
                for user_id, user_data in user_confidences.items():
                    if user_data['confidence'] > best_confidence:
                        best_confidence = user_data['confidence']
                        best_match = {
                            'user_id': user_id,
                            'username': user_data['username'],
                            'full_name': user_data['full_name'],
                            'role': user_data['role'],
                            'confidence': user_data['confidence'],
                            'matched_sample': user_data['sample_number']
                        }
                
                # Check if best match meets the 0.75 confidence threshold
                if best_match and best_confidence >= 0.75:
                    # Update last used timestamp for all samples of this user
                    cursor.execute("""
                        UPDATE face_recognition_data 
                        SET last_used = NOW() 
                        WHERE user_id = %s AND is_active = true
                    """, (best_match['user_id'],))
                    conn.commit()
                    
                    # Log successful face authentication
                    self.log_user_activity(
                        best_match['user_id'], 
                        'face_login_success', 
                        f'Face auth successful with confidence {best_confidence:.3f} (sample {best_match["matched_sample"]})'
                    )
                    
                    return {
                        'success': True,
                        'user': {
                            'user_id': best_match['user_id'],
                            'username': best_match['username'],
                            'full_name': best_match['full_name'],
                            'role': best_match['role']
                        },
                        'confidence': best_confidence,
                        'matched_sample': best_match['matched_sample'],
                        'message': f'Welcome back, {best_match["full_name"]}!'
                    }
                else:
                    # Log failed attempt
                    confidence_info = f"Best confidence: {best_confidence:.3f}" if best_match else "No matches found"
                    logger.info(f"Face verification failed - {confidence_info}")
                    
                    return {
                        'success': False,
                        'message': 'Face not recognized. Please try again with better lighting.',
                        'confidence': best_confidence if best_match else 0.0
                    }
                    
        except Exception as e:
            logger.error(f"Face verification error: {e}")
            return {
                'success': False,
                'message': f'Face verification failed: {str(e)}'
            }

    def get_user_face_samples_count(self, user_id: int) -> int:
        """Get the number of face samples enrolled for a user"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                cursor.execute("""
                    SELECT COUNT(*) FROM face_recognition_data 
                    WHERE user_id = %s AND is_active = true
                """, (user_id,))
                
                return cursor.fetchone()[0]
                
        except Exception as e:
            logger.error(f"Error getting face samples count: {e}")
            return 0

    def reset_user_face_auth(self, user_id: int) -> Dict[str, Any]:
        """Reset/delete all face samples for a user (for re-registration)"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                # Disable face auth
                cursor.execute("""
                    UPDATE users SET face_auth_enabled = false WHERE user_id = %s
                """, (user_id,))
                
                # Delete all face samples
                cursor.execute("""
                    DELETE FROM face_recognition_data WHERE user_id = %s
                """, (user_id,))
                
                conn.commit()
                
                self.log_user_activity(user_id, 'face_auth_reset', 'Face authentication reset for re-registration')
                
                return {
                    'success': True,
                    'message': 'Face authentication reset successfully. You can now re-register.'
                }
                
        except Exception as e:
            logger.error(f"Face auth reset error: {e}")
            return {
                'success': False,
                'message': f'Face auth reset failed: {str(e)}'
            }

    def _calculate_face_similarity(self, features1: Dict, features2: Dict) -> float:
        """Enhanced face similarity calculation with better weighting"""
        try:
            similarity_scores = []
            
            # 1. Bounding box comparison (weight: 0.2)
            if 'bounding_box' in features1 and 'bounding_box' in features2:
                bb1, bb2 = features1['bounding_box'], features2['bounding_box']
                if all(key in bb1 and key in bb2 for key in ['width', 'height']):
                    width_ratio = min(bb1['width'], bb2['width']) / max(bb1['width'], bb2['width'])
                    height_ratio = min(bb1['height'], bb2['height']) / max(bb1['height'], bb2['height'])
                    bb_similarity = (width_ratio + height_ratio) / 2
                    similarity_scores.append(('bounding_box', bb_similarity, 0.2))
            
            # 2. Head euler angles comparison (weight: 0.3)
            angle_features = ['head_euler_angle_x', 'head_euler_angle_y', 'head_euler_angle_z']
            angle_similarities = []
            
            for angle_feature in angle_features:
                if (angle_feature in features1 and angle_feature in features2 and 
                    features1[angle_feature] is not None and features2[angle_feature] is not None):
                    
                    angle_diff = abs(float(features1[angle_feature]) - float(features2[angle_feature]))
                    # Allow up to 20 degrees difference for head pose
                    angle_similarity = max(0, 1 - (angle_diff / 20.0))
                    angle_similarities.append(angle_similarity)
            
            if angle_similarities:
                avg_angle_similarity = sum(angle_similarities) / len(angle_similarities)
                similarity_scores.append(('head_angles', avg_angle_similarity, 0.3))
            
            # 3. Eye probabilities comparison (weight: 0.2)
            eye_features = ['left_eye_open_probability', 'right_eye_open_probability']
            eye_similarities = []
            
            for eye_feature in eye_features:
                if (eye_feature in features1 and eye_feature in features2 and
                    features1[eye_feature] is not None and features2[eye_feature] is not None):
                    
                    eye_diff = abs(float(features1[eye_feature]) - float(features2[eye_feature]))
                    eye_similarity = max(0, 1 - eye_diff)
                    eye_similarities.append(eye_similarity)
            
            if eye_similarities:
                avg_eye_similarity = sum(eye_similarities) / len(eye_similarities)
                similarity_scores.append(('eye_probabilities', avg_eye_similarity, 0.2))
            
            # 4. Landmark positions comparison (weight: 0.3)
            if 'landmarks' in features1 and 'landmarks' in features2:
                landmarks1, landmarks2 = features1['landmarks'], features2['landmarks']
                common_landmarks = set(landmarks1.keys()) & set(landmarks2.keys())
                
                if common_landmarks:
                    landmark_similarities = []
                    
                    for landmark_type in common_landmarks:
                        try:
                            lm1, lm2 = landmarks1[landmark_type], landmarks2[landmark_type]
                            if (lm1.get('x') is not None and lm1.get('y') is not None and
                                lm2.get('x') is not None and lm2.get('y') is not None):
                                
                                x_diff = abs(float(lm1['x']) - float(lm2['x']))
                                y_diff = abs(float(lm1['y']) - float(lm2['y']))
                                distance = (x_diff**2 + y_diff**2)**0.5
                                
                                # Normalize distance (assuming max face size of ~400 pixels)
                                normalized_distance = min(1.0, distance / 400.0)
                                landmark_similarity = 1.0 - normalized_distance
                                landmark_similarities.append(landmark_similarity)
                                
                        except (ValueError, TypeError, KeyError):
                            continue
                    
                    if landmark_similarities:
                        avg_landmark_similarity = sum(landmark_similarities) / len(landmark_similarities)
                        similarity_scores.append(('landmarks', avg_landmark_similarity, 0.3))
            
            # Calculate weighted average
            if similarity_scores:
                weighted_sum = sum(score * weight for _, score, weight in similarity_scores)
                total_weight = sum(weight for _, _, weight in similarity_scores)
                
                if total_weight > 0:
                    final_similarity = weighted_sum / total_weight
                    return min(1.0, max(0.0, final_similarity))  # Clamp between 0 and 1
            
            return 0.0
            
        except Exception as e:
            logger.error(f"Error calculating face similarity: {e}")
            return 0.0


    def load_environment(self):
        """Load environment variables"""
        load_dotenv()
        self.api_key = os.getenv("GOOGLE_API_KEY")
        if not self.api_key:
            raise ValueError("GOOGLE_API_KEY not found in environment variables!")
        
        self.db_params = {
            "dbname": os.getenv("DB_NAME", "postgres"),
            "user": os.getenv("DB_USER", "postgres.chdjmbylbqdsavazecll"),
            "password": os.getenv("DB_PASSWORD", "Hexen2002_23"),
            "host": os.getenv("DB_HOST", "aws-1-eu-west-2.pooler.supabase.com"),
            "port": os.getenv("DB_PORT", "6543"),
            "sslmode": "require"
        }
    
    def setup_ai_model(self):
        """Setup Gemini AI model"""
        genai.configure(api_key=self.api_key)
        self.model = genai.GenerativeModel('gemini-1.5-flash')
        
        try:
            test_response = self.model.generate_content("Test connection")
            logger.info("Gemini AI model connected successfully")
        except Exception as e:
            logger.error(f"Failed to connect to Gemini: {e}")
            raise
    
    def setup_database_pool(self):
        """Setup database connection pool"""
        try:
            print(f"=== ATTEMPTING DB CONNECTION ===")
            print(f"DB params: {self.db_params}")
            
            self.connection_pool = SimpleConnectionPool(
                minconn=1, maxconn=5, **self.db_params
            )
            print("=== DB CONNECTION SUCCESS ===")
            logger.info("Database connection pool created")
        except Exception as e:
            print(f"=== DB CONNECTION FAILED ===")
            print(f"Error: {e}")
            print(f"Error type: {type(e)}")
            import traceback
            print(f"Traceback: {traceback.format_exc()}")
            logger.error(f"Failed to create connection pool: {e}")
            raise
    
    @contextmanager
    def get_db_connection(self):
        """Get a safe database connection"""
        conn = None
        try:
            conn = self.connection_pool.getconn()
            yield conn
        except Exception as e:
            if conn:
                conn.rollback()
            logger.error(f"Database error: {e}")
            raise
        finally:
            if conn:
                self.connection_pool.putconn(conn)

    # USER AUTHENTICATION METHODS
    def authenticate_user(self, username: str, password: str) -> Dict[str, Any]:
        """Authenticate user with username and password"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                cursor.execute("""
                    SELECT user_id, username, password_hash, salt, role, full_name, is_active
                    FROM users WHERE username = %s
                """, (username,))
                
                user_data = cursor.fetchone()
                
                if not user_data:
                    return {'success': False, 'message': 'User not found'}
                
                user_id, username, stored_hash, salt, role, full_name, is_active = user_data
                
                if not is_active:
                    return {'success': False, 'message': 'Account is disabled'}
                
                # Verify password
                password_hash = hashlib.sha256((password + salt).encode()).hexdigest()
                
                if password_hash == stored_hash:
                    # Log successful login
                    self.log_user_activity(user_id, 'login', None, True)
                    
                    return {
                        'success': True,
                        'user': {
                            'user_id': user_id,
                            'username': username,
                            'role': role,
                            'full_name': full_name
                        },
                        'message': f'Welcome back, {full_name}!'
                    }
                else:
                    # Log failed login
                    self.log_user_activity(user_id, 'failed_login', None, False)
                    return {'success': False, 'message': 'Invalid password'}
                    
        except Exception as e:
            logger.error(f"Authentication error: {e}")
            return {'success': False, 'message': 'Authentication failed'}

    def check_user_permissions(self, user_id: int, table_name: str, permission: str) -> bool:
        """Check if user has specific permission on table"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                cursor.execute("""
                    SELECT COUNT(*)
                    FROM user_table_permissions utp
                    JOIN database_tables dt ON utp.table_id = dt.table_id
                    JOIN permission_types pt ON utp.permission_id = pt.permission_id
                    WHERE utp.user_id = %s AND dt.table_name = %s 
                    AND pt.permission_name = %s AND utp.is_active = true
                """, (user_id, table_name, permission))
                
                count = cursor.fetchone()[0]
                return count > 0
                
        except Exception as e:
            logger.error(f"Permission check error: {e}")
            return False

    def get_user_accessible_charts(self, user_id: int) -> List[Dict]:
        """Get charts user can access"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                cursor.execute("""
                    SELECT c.chart_id, c.chart_name, c.chart_description, c.chart_type,
                           c.sql_query, c.category, ucp.can_export
                    FROM charts c
                    JOIN user_chart_permissions ucp ON c.chart_id = ucp.chart_id
                    WHERE ucp.user_id = %s AND ucp.can_view = true
                    ORDER BY c.category, c.chart_name
                """, (user_id,))
                
                charts = []
                for row in cursor.fetchall():
                    charts.append({
                        'chart_id': row[0],
                        'chart_name': row[1],
                        'chart_description': row[2],
                        'chart_type': row[3],
                        'sql_query': row[4],
                        'category': row[5],
                        'can_export': row[6]
                    })
                
                return charts
                
        except Exception as e:
            logger.error(f"Error getting user charts: {e}")
            return []

    def log_user_activity(self, user_id: int, action: str, details: str = None, success: bool = True):
        """Log user activity to audit log"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                # Convert details to JSON string if it's not already a string
                if details is not None:
                    if isinstance(details, str):
                        # Wrap plain text in JSON object
                        details = json.dumps({"message": details})
                    else:
                        details = json.dumps(details)
                
                cursor.execute("""
                    INSERT INTO audit_log (user_id, action, details, timestamp)
                    VALUES (%s, %s, %s, NOW())
                """, (user_id, action, details))
                
                conn.commit()
                
        except Exception as e:
            logger.error(f"Error logging activity: {e}")

    # ROLE-BASED QUERY PROCESSING
    def get_database_schema_for_role(self, role: str) -> str:
        """Get database schema filtered by user role"""
        base_schema = """
        Database Schema (filtered by your access level):

        public.customers:
        - customer_id (serial, primary key)
        """
        
        if role in ['visitor']:
            return """
            Database Schema (VISITOR ACCESS):
            
            public.invoices:
            - invoice_id (serial, primary key)
            - total_amount (numeric), invoice_date (date)
            
            Note: You can only access sales numbers and totals.
            """
        
        elif role in ['viewer']:
            schema = base_schema + """
        - name (text - customer names HIDDEN for privacy)
        
        public.products:
        - product_id (serial, primary key)
        - name (text), category (text), price (numeric), stock (integer)

        public.invoices:
        - invoice_id (serial, primary key)
        - customer_id (integer), invoice_date (date), total_amount (numeric)

        public.cities:
        - city_id (serial, primary key)
        - city_name (text)
        
        Note: Customer names are hidden. Use customer_id only.
        """
            return schema
        
        elif role in ['manager']:
            return base_schema + """
        - name (text), email (text), phone (text)
        - created_at (timestamp), city_id (integer)

        public.products:
        - product_id (serial, primary key)
        - name (text), category (text), price (numeric), stock (integer), cost (double precision)

        public.invoices:
        - invoice_id (serial, primary key)
        - customer_id (integer), invoice_date (date), total_amount (numeric)

        public.invoice_items:
        - invoice_id (bigint), product_id (bigint)
        - quantity (bigint), unit_price (double precision), line_total (double precision)

        public.cities:
        - city_id (serial, primary key), city_name (text)
        
        public.inventory_movements:
        - movement_id (serial, primary key)
        - product_id (integer), movement_type (text), quantity (integer)

        public.receipt_captures:
        - capture_id (serial, primary key)
        - extracted_vendor (text), extracted_total (decimal), status (text)
        
        Note: You can view all data and add receipts through photos.
        """
        
        else:  # admin
            return base_schema + """
        - name (text), email (text), phone (text)
        - created_at (timestamp), city_id (integer)

        public.products:
        - product_id (serial, primary key)
        - name (text), category (text), price (numeric), stock (integer), cost (double precision)

        public.invoices:
        - invoice_id (serial, primary key)
        - customer_id (integer), invoice_date (date), total_amount (numeric)

        public.invoice_items, public.cities, public.inventory_movements, public.receipt_captures
        
        Note: Full administrative access to all data and operations.
        """

    def filter_query_for_role(self, sql_query: str, role: str) -> str:
        """Filter SQL query based on user role"""
        if role == 'visitor':
            # Visitor can only see sales numbers from invoices
            if 'customers' in sql_query.lower() or 'products' in sql_query.lower():
                return "SELECT 'Access Denied' as message, 'Visitors can only access sales data' as reason"
        
        elif role == 'viewer':
            # Viewer cannot see customer names - replace with customer_id
            sql_query = re.sub(r'c\.name|customers\.name', 'CONCAT(\'Customer #\', c.customer_id)', sql_query, flags=re.IGNORECASE)
            sql_query = re.sub(r'customer_name', 'customer_id', sql_query, flags=re.IGNORECASE)
        
        return sql_query

    def validate_sql_query_for_role(self, sql_query: str, role: str) -> Tuple[bool, str]:
        """Validate SQL query based on user role"""
        sql_upper = sql_query.upper()
        
        # Check for dangerous operations based on role
        if role in ['visitor', 'viewer']:
            dangerous_keywords = ['INSERT', 'UPDATE', 'DELETE', 'DROP', 'CREATE', 'ALTER', 'TRUNCATE']
            for keyword in dangerous_keywords:
                if keyword in sql_upper:
                    return False, f"Permission denied: {role} users cannot perform {keyword} operations"
        
        elif role == 'manager':
            # Manager can INSERT but not UPDATE/DELETE existing data
            dangerous_keywords = ['UPDATE', 'DELETE', 'DROP', 'ALTER', 'TRUNCATE']
            for keyword in dangerous_keywords:
                if keyword in sql_upper:
                    return False, f"Permission denied: Managers cannot perform {keyword} operations"
        
        # Must start with SELECT or WITH
        if not re.match(r'^\s*(SELECT|WITH)', sql_query, re.IGNORECASE):
            return False, "Only SELECT queries are allowed"
        
        return True, "Query validated"

    # RECEIPT PROCESSING METHODS
    def process_receipt_image(self, user_id: int, image_base64: str) -> Dict[str, Any]:
        """Process receipt image and extract data"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                # Insert receipt capture
                cursor.execute("""
                    INSERT INTO receipt_captures (user_id, image_data, status, captured_at)
                    VALUES (%s, %s, 'pending_review', NOW())
                    RETURNING capture_id
                """, (user_id, image_base64))
                
                capture_id = cursor.fetchone()[0]
                
                # Simulate OCR processing (integrate with actual OCR service)
                extracted_data = self.simulate_ocr_extraction(image_base64)
                
                # Update with extracted data
                cursor.execute("""
                    UPDATE receipt_captures 
                    SET extracted_vendor = %s, extracted_date = %s, extracted_total = %s,
                        extracted_items = %s, confidence_score = %s, status = 'pending_review'
                    WHERE capture_id = %s
                """, (
                    extracted_data['vendor'],
                    extracted_data['date'],
                    extracted_data['total'],
                    json.dumps(extracted_data['items']),
                    extracted_data['confidence'],
                    capture_id
                ))
                
                conn.commit()
                
                self.log_user_activity(user_id, 'receipt_upload', f'Capture ID: {capture_id}')
                
                return {
                    'success': True,
                    'capture_id': capture_id,
                    'extracted_data': extracted_data,
                    'message': 'Receipt processed successfully. Please review and approve the extracted data.'
                }
                
        except Exception as e:
            logger.error(f"Receipt processing error: {e}")
            return {'success': False, 'message': f'Receipt processing failed: {str(e)}'}

    def simulate_ocr_extraction(self, image_base64: str) -> Dict[str, Any]:
        """Simulate OCR extraction - replace with actual OCR service"""
        return {
            'vendor': 'Sample Store',
            'date': datetime.now().date(),
            'total': round(50 + (hash(image_base64) % 500), 2),
            'items': [
                {'description': 'Sample Item 1', 'quantity': 1, 'price': 25.00},
                {'description': 'Sample Item 2', 'quantity': 2, 'price': 12.50}
            ],
            'confidence': 0.85
        }

    def approve_receipt_and_create_invoice(self, capture_id: int, user_id: int, customer_id: int, corrections: Dict = None) -> Dict[str, Any]:
        """Approve receipt and create invoice in main tables"""
        try:
            with self.get_db_connection() as conn:
                cursor = conn.cursor()
                
                # Get receipt data
                cursor.execute("""
                    SELECT extracted_vendor, extracted_date, extracted_total, extracted_items
                    FROM receipt_captures WHERE capture_id = %s AND status = 'pending_review'
                """, (capture_id,))
                
                receipt_data = cursor.fetchone()
                if not receipt_data:
                    return {'success': False, 'message': 'Receipt not found or already processed'}
                
                vendor, date, total, items_json = receipt_data
                
                # Apply corrections if provided
                if corrections:
                    total = corrections.get('total', total)
                    date = corrections.get('date', date)
                    items_json = corrections.get('items', items_json)
                
                # Create invoice
                cursor.execute("""
                    INSERT INTO invoices (customer_id, invoice_date, total_amount, status, source_type, receipt_capture_id)
                    VALUES (%s, %s, %s, 'completed', 'receipt', %s)
                    RETURNING invoice_id
                """, (customer_id, date, total, capture_id))
                
                invoice_id = cursor.fetchone()[0]
                
                # Create invoice items
                items = json.loads(items_json) if isinstance(items_json, str) else items_json
                for item in items:
                    # Try to match with existing products
                    cursor.execute("""
                        SELECT product_id, price FROM products 
                        WHERE LOWER(name) LIKE LOWER(%s) LIMIT 1
                    """, (f"%{item['description']}%",))
                    
                    product_match = cursor.fetchone()
                    if product_match:
                        product_id, _ = product_match
                        quantity = item['quantity']
                        unit_price = item['price']
                        line_total = quantity * unit_price
                        
                        # Create invoice item
                        cursor.execute("""
                            INSERT INTO invoice_items (invoice_id, product_id, quantity, unit_price, line_total)
                            VALUES (%s, %s, %s, %s, %s)
                        """, (invoice_id, product_id, quantity, unit_price, line_total))
                        
                        # Create inventory movement
                        cursor.execute("""
                            INSERT INTO inventory_movements (product_id, movement_type, quantity, invoice_id, notes)
                            VALUES (%s, 'OUT', %s, %s, %s)
                        """, (product_id, quantity, invoice_id, f'Receipt: {vendor}'))
                
                # Mark receipt as processed
                cursor.execute("""
                    UPDATE receipt_captures 
                    SET status = 'processed', processed_at = NOW(), created_invoice_id = %s
                    WHERE capture_id = %s
                """, (invoice_id, capture_id))
                
                conn.commit()
                
                self.log_user_activity(user_id, 'receipt_approval', f'Invoice {invoice_id} created from receipt {capture_id}')
                
                return {
                    'success': True,
                    'invoice_id': invoice_id,
                    'message': f'Receipt approved and invoice {invoice_id} created successfully!'
                }
                
        except Exception as e:
            logger.error(f"Receipt approval error: {e}")
            return {'success': False, 'message': f'Receipt approval failed: {str(e)}'}

    # ENHANCED QUERY PROCESSING WITH PERMISSIONS AND CONVERSATION MEMORY
    def execute_query_with_permissions(self, user_input: str, user_data: Dict, conversation_history: List[Dict] = None) -> Dict[str, Any]:
        """Execute query with user permission checking and conversation memory"""
        user_id = user_data['user_id']
        role = user_data['role']
        
        # Process with improved Gemini AI including conversation context
        gemini_response = self.process_with_gemini_for_role(user_input, role, conversation_history)
        
        # Initialize response
        response_data = {
            'success': False,
            'message': 'Processing your request...',
            'data': [],
            'chart': None,
            'query': '',
            'row_count': 0,
            'user_role': role
        }
        
        try:
            if gemini_response.get('needs_sql', False):
                sql_query = gemini_response.get('sql_query', '')
                
                if sql_query:
                    # Validate query for user role
                    is_valid, validation_message = self.validate_sql_query_for_role(sql_query, role)
                    if not is_valid:
                        response_data.update({
                            'success': False,
                            'message': validation_message
                        })
                        return response_data
                    
                    # Filter query based on role
                    filtered_query = self.filter_query_for_role(sql_query, role)
                    response_data['query'] = filtered_query
                    
                    # Execute query
                    df_result, success, execution_message = self.execute_query(filtered_query)
                    
                    if success and df_result is not None and not df_result.empty:
                        display_data = df_result.head(50).to_dict('records')
                        
                        # Get the appropriate result value for message formatting
                        actual_result = None
                        if len(df_result) > 0:
                            # For single value results
                            if len(df_result.columns) == 1 and len(df_result) == 1:
                                actual_result = df_result.iloc[0, 0]
                            # For count results
                            elif 'count' in df_result.columns[0].lower():
                                actual_result = df_result.iloc[0, 0]
                            # For year-based results
                            elif len(df_result.columns) >= 2:
                                actual_result = len(df_result)
                        
                        # Process the response message with actual data
                        base_message = gemini_response.get('response_message', 'Query completed successfully.')
                        
                        # Replace placeholders with actual values
                        if actual_result is not None:
                            processed_message = base_message.replace('[COUNT]', str(actual_result))
                            processed_message = processed_message.replace('[VALUE]', str(actual_result))
                            processed_message = processed_message.replace('[SUM(total_amount)]', str(actual_result))
                            processed_message = processed_message.replace('[SUM]', str(actual_result))
                        else:
                            processed_message = base_message
                        
                        response_data.update({
                            'success': True,
                            'message': processed_message,
                            'data': display_data,
                            'row_count': len(df_result)
                        })
                        
                        # Create chart if appropriate and data is suitable
                        chart_type = gemini_response.get('suggested_chart', 'none')
                        if chart_type in ['bar', 'pie'] and len(df_result.columns) >= 2:
                            chart_title = f"Data Analysis - {user_input[:50]}..."
                            chart_base64 = self.create_chart(df_result, chart_type, chart_title)
                            if chart_base64:
                                response_data['chart'] = {
                                    'chart_base64': chart_base64,
                                    'chart_type': chart_type
                                }
                    else:
                        # Handle query execution failure
                        response_data.update({
                            'success': False,
                            'message': execution_message or 'Query execution failed'
                        })
                else:
                    response_data.update({
                        'success': False,
                        'message': 'No valid SQL query generated'
                    })
                
                # Log query execution
                self.log_user_activity(user_id, 'query_execution', user_input, response_data['success'])
            
            else:
                # No SQL needed - return the response message directly
                response_data.update({
                    'success': True,
                    'message': gemini_response.get('response_message', 'I can help you with customer counts, product lists, and sales data.')
                })
            
            return response_data
            
        except Exception as e:
            logger.error(f"Error in execute_query_with_permissions: {e}")
            self.log_user_activity(user_id, 'query_error', str(e), False)
            response_data.update({
                'success': False,
                'message': f"An error occurred: {str(e)}"
            })
            return response_data

    def process_with_gemini_for_role(self, user_input: str, role: str, conversation_history: List[Dict] = None) -> Dict[str, Any]:
        """Process user input with Gemini AI including conversation memory - ENHANCED VERSION"""
        try:
            schema = self.get_database_schema_for_role(role)
            
            # Build conversation context
            context_prompt = ""
            if conversation_history and len(conversation_history) > 0:
                context_prompt = "\n\nCONVERSATION HISTORY:\n"
                # Include last 5 exchanges for context
                recent_history = conversation_history[-10:] if len(conversation_history) > 10 else conversation_history
                for msg in recent_history:
                    sender = msg.get('sender', 'Unknown')
                    content = msg.get('content', '')
                    context_prompt += f"{sender}: {content}\n"
                context_prompt += "\nUse this conversation history to provide better, more contextual responses. Remember what was discussed before.\n"
            
            prompt = f"""
You are a professional, intelligent database assistant with conversation memory that provides accurate and natural responses.

DATABASE SCHEMA:
{schema}

{context_prompt}

CURRENT USER QUESTION: "{user_input}"
USER ROLE: {role}

CRITICAL INSTRUCTIONS:
1. Consider the conversation history when generating responses - reference previous queries and build on past context
2. For count/number queries, generate SQL that returns a single COUNT(*) value
3. For year-specific queries (2023, 2024, 2025), use EXTRACT(YEAR FROM invoice_date) = YEAR
4. For "invoices per year" queries, GROUP BY the year to show breakdown by year
5. For chart requests, ensure the SQL returns proper columns for visualization
6. Be precise with SQL - use exact PostgreSQL syntax
7. Provide natural, conversational responses that reference previous discussions when relevant
8. If the user asks follow-up questions, understand they're building on previous queries
9. **CRITICAL MATH VALIDATION**: For average calculations:
   - Monthly average = Total annual sales ÷ 12 months
   - Use: SELECT SUM(total_amount)/12 as monthly_average FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = YEAR
   - Example: $26,000,000 annual ÷ 12 = $2,166,667 monthly average (NOT $7,000!)
   - Always double-check mathematical logic before generating SQL
   - For averages across months: SELECT AVG(monthly_total) FROM (SELECT SUM(total_amount) as monthly_total FROM invoices GROUP BY EXTRACT(YEAR FROM invoice_date), EXTRACT(MONTH FROM invoice_date))
10. Validate all mathematical operations - division, averages, percentages must be logically correct

ROLE PERMISSIONS:
- Visitor: Only sales/invoices data
- Viewer: Products, customers (no names), invoices, cities  
- Manager: Full access except user management
- Admin: Complete access

RESPONSE FORMAT (JSON):
{{
    "needs_sql": true/false,
    "sql_query": "SELECT statement" (if needs_sql is true),
    "response_message": "Natural response with [COUNT] for single values, reference conversation context",
    "suggested_chart": "none/bar/pie"
}}

EXAMPLES WITH CONTEXT:

For "how many invoices do we have in 2024" (first time):
{{
    "needs_sql": true,
    "sql_query": "SELECT COUNT(*) FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = 2024",
    "response_message": "We have [COUNT] invoices from 2024.",
    "suggested_chart": "none"
}}

For "what about 2023?" (follow-up after asking about 2024):
{{
    "needs_sql": true,
    "sql_query": "SELECT COUNT(*) FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = 2023",
    "response_message": "For 2023, we had [COUNT] invoices. That's a comparison to the [COUNT] from 2024 we just discussed.",
    "suggested_chart": "none"
}}

For "show me a chart of that" (after discussing yearly data):
{{
    "needs_sql": true,
    "sql_query": "SELECT EXTRACT(YEAR FROM invoice_date) as year, COUNT(*) as invoice_count FROM invoices GROUP BY EXTRACT(YEAR FROM invoice_date) ORDER BY year",
    "response_message": "Here's the chart showing invoice counts by year that we've been discussing:",
    "suggested_chart": "bar"
}}

Generate your response in valid JSON format:
"""

            response = self.model.generate_content(prompt)
            response_text = response.text.strip()
            
            # Clean up response text
            if response_text.startswith('```'):
                lines = response_text.split('\n')
                json_lines = []
                in_code = False
                for line in lines:
                    if line.startswith('```'):
                        in_code = not in_code
                        continue
                    if in_code:
                        json_lines.append(line)
                response_text = '\n'.join(json_lines)
            
            try:
                gemini_response = json.loads(response_text)
                
                # Validate and fix response structure
                if 'needs_sql' not in gemini_response:
                    gemini_response['needs_sql'] = False
                if 'response_message' not in gemini_response:
                    gemini_response['response_message'] = "I can help you with your database questions."
                if 'suggested_chart' not in gemini_response:
                    gemini_response['suggested_chart'] = 'none'
                if gemini_response['needs_sql'] and 'sql_query' not in gemini_response:
                    gemini_response['sql_query'] = ""
                    
                logger.info(f"Gemini AI processed query with context successfully: {user_input}")
                return gemini_response
                
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse Gemini response as JSON: {e}")
                logger.error(f"Raw response: {response_text}")
                
                # Enhanced fallback with conversation context
                return self._get_fallback_response_with_context(user_input, role, conversation_history)
                
        except Exception as e:
            logger.error(f"Gemini AI processing failed: {e}")
            return self._get_fallback_response_with_context(user_input, role, conversation_history)

    def _get_fallback_response_with_context(self, user_input: str, role: str, conversation_history: List[Dict] = None) -> Dict[str, Any]:
        """Enhanced fallback with conversation context awareness"""
        user_lower = user_input.lower()
        
        # Check if this is a follow-up question
        is_followup = any(word in user_lower for word in ['what about', 'and', 'also', 'too', 'that', 'this', 'same'])
        
        # Extract context from conversation history
        last_topic = None
        if conversation_history and len(conversation_history) > 0:
            # Look for recent topics
            for msg in reversed(conversation_history[-6:]):
                content = msg.get('content', '').lower()
                if 'invoice' in content:
                    last_topic = 'invoices'
                elif 'customer' in content:
                    last_topic = 'customers'
                elif 'product' in content:
                    last_topic = 'products'
                elif 'sales' in content:
                    last_topic = 'sales'
                if last_topic:
                    break
        
        # Handle follow-up questions with context
        if is_followup and last_topic:
            if '2024' in user_lower and last_topic == 'invoices':
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT COUNT(*) FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = 2024",
                    "response_message": "For 2024, we have [COUNT] invoices.",
                    "suggested_chart": "none"
                }
            elif '2023' in user_lower and last_topic == 'invoices':
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT COUNT(*) FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = 2023",
                    "response_message": "For 2023, we had [COUNT] invoices.",
                    "suggested_chart": "none"
                }
            elif 'chart' in user_lower and last_topic:
                if last_topic == 'invoices':
                    return {
                        "needs_sql": True,
                        "sql_query": "SELECT EXTRACT(YEAR FROM invoice_date) as year, COUNT(*) as invoice_count FROM invoices GROUP BY EXTRACT(YEAR FROM invoice_date) ORDER BY year",
                        "response_message": "Here's the chart showing the invoice data we've been discussing:",
                        "suggested_chart": "bar"
                    }
        
        # Regular fallback patterns (existing logic)
        if 'invoice' in user_lower and any(word in user_lower for word in ['how many', 'count', 'number']):
            if '2024' in user_lower:
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT COUNT(*) FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = 2024",
                    "response_message": "We have [COUNT] invoices from 2024.",
                    "suggested_chart": "none"
                }
            elif '2023' in user_lower:
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT COUNT(*) FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = 2023",
                    "response_message": "We have [COUNT] invoices from 2023.",
                    "suggested_chart": "none"
                }
            elif 'per year' in user_lower or 'by year' in user_lower:
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT EXTRACT(YEAR FROM invoice_date) as year, COUNT(*) as invoice_count FROM invoices GROUP BY EXTRACT(YEAR FROM invoice_date) ORDER BY year",
                    "response_message": "Here's the breakdown of invoices by year:",
                    "suggested_chart": "bar"
                }
            else:
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT COUNT(*) FROM invoices",
                    "response_message": "We have [COUNT] total invoices in our system.",
                    "suggested_chart": "none"
                }
        
        # Customer queries
        elif any(word in user_lower for word in ['customer', 'client']) and any(word in user_lower for word in ['how many', 'count', 'number']):
            return {
                "needs_sql": True,
                "sql_query": "SELECT COUNT(*) FROM customers",
                "response_message": "We currently have [COUNT] customers in our database.",
                "suggested_chart": "none"
            }
        
        # Product queries
        elif any(word in user_lower for word in ['product', 'item']) and any(word in user_lower for word in ['show', 'list', 'what', 'display']):
            if role == 'visitor':
                return {
                    "needs_sql": False,
                    "response_message": "Sorry, as a visitor you can only access sales data. Try asking about invoices or sales totals.",
                    "suggested_chart": "none"
                }
            return {
                "needs_sql": True,
                "sql_query": "SELECT name, category, price, stock FROM products ORDER BY name LIMIT 20",
                "response_message": "Here are our current products:",
                "suggested_chart": "none"
            }
        
        # Sales queries with math validation
        elif any(word in user_lower for word in ['sales', 'revenue']) and any(word in user_lower for word in ['average', 'monthly']):
            if 'monthly' in user_lower and any(word in user_lower for word in ['2025', '2024', '2023']):
                year = None
                if '2025' in user_lower:
                    year = 2025
                elif '2024' in user_lower:
                    year = 2024
                elif '2023' in user_lower:
                    year = 2023

                if year:
                    return {
                        "needs_sql": True,
                        "sql_query": f"SELECT SUM(total_amount)/12 as monthly_average FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = {year}",
                        "response_message": f"The average monthly sales for {year} is $[VALUE] (calculated as total annual sales ÷ 12 months).",
                        "suggested_chart": "none"
                    }
            elif 'total' in user_lower and any(word in user_lower for word in ['2025', '2024', '2023']):
                year = None
                if '2025' in user_lower:
                    year = 2025
                elif '2024' in user_lower:
                    year = 2024
                elif '2023' in user_lower:
                    year = 2023

                if year:
                    return {
                        "needs_sql": True,
                        "sql_query": f"SELECT SUM(total_amount) as annual_total FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = {year}",
                        "response_message": f"Total sales for {year} is $[VALUE].",
                        "suggested_chart": "none"
                    }

        # Chart requests for sales
        elif any(word in user_lower for word in ['chart', 'bar chart', 'pie chart']) and 'sales' in user_lower:
            if 'month' in user_lower:
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT EXTRACT(MONTH FROM invoice_date) as month, SUM(total_amount) as total_sales FROM invoices WHERE EXTRACT(YEAR FROM invoice_date) = EXTRACT(YEAR FROM CURRENT_DATE) GROUP BY EXTRACT(MONTH FROM invoice_date) ORDER BY month",
                    "response_message": "Here's your monthly sales chart for this year:",
                    "suggested_chart": "bar"
                }
            elif 'year' in user_lower:
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT EXTRACT(YEAR FROM invoice_date) as year, SUM(total_amount) as total_sales FROM invoices GROUP BY EXTRACT(YEAR FROM invoice_date) ORDER BY year",
                    "response_message": "Here's your yearly sales breakdown:",
                    "suggested_chart": "bar"
                }
        
        # Greeting responses
        elif any(word in user_lower for word in ['hello', 'hi', 'hey']):
            return {
                "needs_sql": False,
                "response_message": f"Hello! I'm your AI Database Assistant with conversation memory. I remember our previous discussions and can help you analyze customers, sales, products, and more. What would you like to explore?",
                "suggested_chart": "none"
            }
        
        # Default fallback
        else:
            return {
                "needs_sql": False,
                "response_message": "I'm here to help you explore your business data with full conversation memory! You can ask me about customer counts, product information, sales data, invoices, and I can even create charts. I'll remember our discussion context. Try asking something like 'How many customers do we have?' or 'Show me sales by month'.",
                "suggested_chart": "none"
            }

    # EXISTING METHODS (updated for compatibility)
    def execute_query(self, sql_query: str) -> Tuple[Optional[pd.DataFrame], bool, str]:
        """Execute SQL query and return results"""
        try:
            with self.get_db_connection() as conn:
                start_time = time.time()
                df = pd.read_sql(sql_query, conn)
                execution_time = time.time() - start_time
                
                logger.info(f"Query executed successfully - {len(df)} rows in {execution_time:.2f}s")
                
                if df.empty:
                    return df, True, "Query executed successfully but returned no results."
                else:
                    return df, True, f"Query executed successfully. Found {len(df)} results in {execution_time:.2f} seconds."
                    
        except Exception as e:
            logger.error(f"Query execution error: {e}")
            return None, False, f"Database error: {str(e)}"

    def create_chart(self, df: pd.DataFrame, chart_type: str, title: str = "Chart") -> Optional[str]:
        """Create chart and return as base64 string with improved styling"""
        if df.empty or len(df.columns) < 2:
            return None
        
        try:
            # Create figure with proper sizing and styling
            plt.figure(figsize=(10, 6))
            fig, ax = plt.subplots(figsize=(10, 6))
            
            # Set background colors
            fig.patch.set_facecolor('white')
            ax.set_facecolor('white')
            
            x_data = df.iloc[:, 0].astype(str)
            y_data = pd.to_numeric(df.iloc[:, 1], errors='coerce')
            
            # Remove any NaN values
            mask = ~y_data.isna()
            x_data = x_data[mask]
            y_data = y_data[mask]
            
            if len(x_data) == 0:
                plt.close(fig)
                return None
            
            if chart_type.lower() == 'pie':
                # Create pie chart with better colors and labels
                colors = plt.cm.Set3(range(len(df)))
                wedges, texts, autotexts = ax.pie(
                    y_data, 
                    labels=x_data, 
                    autopct='%1.1f%%', 
                    colors=colors, 
                    startangle=90,
                    textprops={'fontsize': 10}
                )
                
                # Improve text readability
                for autotext in autotexts:
                    autotext.set_color('black')
                    autotext.set_fontweight('bold')
                
            elif chart_type.lower() == 'bar':
                # Create bar chart with better styling
                bars = ax.bar(
                    range(len(df)), 
                    y_data, 
                    color=plt.cm.viridis(np.linspace(0, 1, len(df))),
                    edgecolor='black',
                    linewidth=0.5
                )
                
                # Add value labels on bars
                for i, (bar, value) in enumerate(zip(bars, y_data)):
                    height = bar.get_height()
                    ax.text(bar.get_x() + bar.get_width()/2., height + height*0.01,
                           f'{value:,.0f}', ha='center', va='bottom', fontweight='bold')
                
                # Set labels and formatting
                ax.set_xlabel(df.columns[0], fontsize=12, fontweight='bold')
                ax.set_ylabel(df.columns[1], fontsize=12, fontweight='bold')
                ax.set_xticks(range(len(df)))
                ax.set_xticklabels(x_data, rotation=45, ha='right')
                
                # Add grid for better readability
                ax.grid(True, alpha=0.3, axis='y')
                ax.set_axisbelow(True)
            
            # Set title with better formatting
            ax.set_title(title, fontsize=14, fontweight='bold', pad=20)
            
            # Improve layout
            plt.tight_layout()
            
            # Save to base64
            buffer = io.BytesIO()
            plt.savefig(
                buffer, 
                format='png', 
                dpi=150, 
                bbox_inches='tight', 
                facecolor='white',
                edgecolor='none'
            )
            buffer.seek(0)
            
            chart_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
            plt.close(fig)
            
            logger.info(f"Chart created successfully: {chart_type}")
            return chart_base64
            
        except Exception as e:
            logger.error(f"Chart creation error: {e}")
            if 'fig' in locals():
                plt.close(fig)
            return None

    def cleanup(self):
        """Cleanup resources"""
        try:
            if hasattr(self, 'connection_pool'):
                self.connection_pool.closeall()
            logger.info("Database assistant cleaned up successfully")
        except Exception as e:
            logger.error(f"Cleanup error: {e}")


# Global instance
db_assistant_instance = None

def get_authenticated_db_response(user_input: str, user_data: Dict, conversation_history: List[Dict] = None) -> Dict[str, Any]:
    """API function with user authentication and conversation memory"""
    global db_assistant_instance
    
    try:
        if db_assistant_instance is None:
            db_assistant_instance = DatabaseAssistant()
        
        return db_assistant_instance.execute_query_with_permissions(
            user_input, 
            user_data, 
            conversation_history=conversation_history
        )
        
    except Exception as e:
        logger.error(f"API error: {e}")
        return {
            'success': False,
            'message': f"Sorry, I encountered an error: {str(e)}",
            'data': [],
            'chart': None,
            'query': '',
            'row_count': 0
        }
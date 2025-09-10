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

class DatabaseAssistant:
    def __init__(self):
        """Initialize the Database Assistant with User Authentication"""
        self.load_environment()
        self.setup_ai_model()
        self.setup_database_pool()
        self.conversation_history = []
        
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
            "port": os.getenv("DB_PORT", "6543")
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
            self.connection_pool = SimpleConnectionPool(
                minconn=1, maxconn=5, **self.db_params
            )
            logger.info("Database connection pool created")
        except Exception as e:
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

    # ENHANCED QUERY PROCESSING WITH PERMISSIONS
    def execute_query_with_permissions(self, user_input: str, user_data: Dict) -> Dict[str, Any]:
        """Execute query with user permission checking"""
        user_id = user_data['user_id']
        role = user_data['role']
        
        # Process with simple pattern matching
        gemini_response = self.process_with_gemini_for_role(user_input, role)
        
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
                        
                        # Get the actual result value for message formatting
                        actual_result = df_result.iloc[0, 0] if len(df_result) > 0 else 0
                        
                        # Process the response message with actual data
                        base_message = gemini_response.get('response_message', 'Query completed successfully.')
                        
                        # Replace placeholders with actual values
                        processed_message = base_message.replace('[COUNT]', str(actual_result))
                        
                        response_data.update({
                            'success': True,
                            'message': processed_message,
                            'data': display_data,
                            'row_count': len(df_result)
                        })
                        
                        # Create chart if appropriate
                        chart_type = gemini_response.get('suggested_chart', 'none')
                        if chart_type in ['bar', 'pie']:
                            chart_base64 = self.create_chart(df_result, chart_type, user_input)
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

    def process_with_gemini_for_role(self, user_input: str, role: str) -> Dict[str, Any]:
        """Process user input with Gemini AI for intelligent responses"""
        try:
            # Get database schema for user's role
            schema = self.get_database_schema_for_role(role)
            
            # Create comprehensive prompt for Gemini
            prompt = f"""
    You are an intelligent database assistant. Analyze the user's question and provide a response.

    DATABASE SCHEMA:
    {schema}

    USER QUESTION: "{user_input}"
    USER ROLE: {role}

    IMPORTANT INSTRUCTIONS:
    1. If the question requires a database query, generate ONLY PostgreSQL-compatible SQL
    2. Use CURRENT_DATE for current date, not DATE('now')
    3. Use INTERVAL '1 year' syntax, not SQLite syntax
    4. For role-based access:
       - Visitor: Only access invoices table for sales data
       - Viewer: Cannot see customer names (use customer_id)
       - Manager/Admin: Full access to all tables
    5. Always use proper PostgreSQL syntax
    6. Keep responses natural and conversational

    RESPONSE FORMAT (JSON):
    {{
        "needs_sql": true/false,
        "sql_query": "SELECT statement here" (if needs_sql is true),
        "response_message": "Natural language response with [COUNT] placeholder for numbers",
        "suggested_chart": "none/bar/pie"
    }}

    Examples of good responses:
    - For "how many customers": {{"needs_sql": true, "sql_query": "SELECT COUNT(*) FROM customers", "response_message": "We currently have [COUNT] customers in our database.", "suggested_chart": "none"}}
    - For "show sales by month": Include appropriate GROUP BY and chart suggestion
    - For general questions: {{"needs_sql": false, "response_message": "Helpful response", "suggested_chart": "none"}}

    Generate the JSON response:
    """

            # Call Gemini AI
            response = self.model.generate_content(prompt)
            response_text = response.text.strip()
            
            # Try to parse JSON response
            try:
                # Clean up response text - remove any markdown formatting
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
                
                # Parse the JSON
                gemini_response = json.loads(response_text)
                
                # Validate required fields
                if 'needs_sql' not in gemini_response:
                    gemini_response['needs_sql'] = False
                if 'response_message' not in gemini_response:
                    gemini_response['response_message'] = "I can help you with your database questions."
                if 'suggested_chart' not in gemini_response:
                    gemini_response['suggested_chart'] = 'none'
                if gemini_response['needs_sql'] and 'sql_query' not in gemini_response:
                    gemini_response['sql_query'] = ""
                    
                logger.info(f"Gemini AI processed query successfully: {user_input}")
                return gemini_response
                
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse Gemini response as JSON: {e}")
                logger.error(f"Raw response: {response_text}")
                
                # Fallback: try to extract SQL if present
                sql_match = re.search(r'SELECT[^;]*', response_text, re.IGNORECASE | re.DOTALL)
                if sql_match:
                    return {
                        "needs_sql": True,
                        "sql_query": sql_match.group(0).strip(),
                        "response_message": "Here's what I found:",
                        "suggested_chart": "none"
                    }
                else:
                    # Pure text response fallback
                    return {
                        "needs_sql": False,
                        "sql_query": "",
                        "response_message": response_text,
                        "suggested_chart": "none"
                    }
                    
        except Exception as e:
            logger.error(f"Gemini AI processing failed: {e}")
            
            # Emergency fallback to simple pattern matching
            user_lower = user_input.lower()
            
            if 'customer' in user_lower and ('how many' in user_lower or 'count' in user_lower):
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT COUNT(*) FROM customers",
                    "response_message": "We currently have [COUNT] customers in our database.",
                    "suggested_chart": "none"
                }
            elif 'product' in user_lower and ('what' in user_lower or 'show' in user_lower or 'list' in user_lower):
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT name, category, price, stock FROM products LIMIT 10",
                    "response_message": "Here are our products:",
                    "suggested_chart": "none"
                }
            elif 'sales' in user_lower and ('year' in user_lower or 'total' in user_lower):
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT SUM(total_amount) AS total_sales FROM invoices WHERE invoice_date >= CURRENT_DATE - INTERVAL '1 year'",
                    "response_message": "Here's the total sales from the last year: $[COUNT]",
                    "suggested_chart": "none"
                }
            elif 'invoice' in user_lower and ('how many' in user_lower or 'count' in user_lower):
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT COUNT(*) FROM invoices",
                    "response_message": "We currently have [COUNT] invoices in our system.",
                    "suggested_chart": "none"
                }
            elif 'receipt' in user_lower and ('how many' in user_lower or 'count' in user_lower):
                return {
                    "needs_sql": True,
                    "sql_query": "SELECT COUNT(*) FROM receipt_captures",
                    "response_message": "We currently have [COUNT] receipts in our system.",
                    "suggested_chart": "none"
                }
            else:
                return {
                    "needs_sql": False,
                    "sql_query": "",
                    "response_message": "I'm your AI database assistant. I can help you with customer counts, product information, sales data, invoices, and receipts. Try asking questions like 'How many customers do we have?' or 'Show me our products'.",
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
        """Create chart and return as base64 string"""
        if df.empty or len(df.columns) < 2:
            return None
        
        try:
            fig, ax = plt.subplots(figsize=(12, 8))
            
            x_data = df.iloc[:, 0].astype(str)
            y_data = pd.to_numeric(df.iloc[:, 1], errors='coerce')
            
            if chart_type.lower() == 'pie':
                colors = plt.cm.Set3(range(len(df)))
                ax.pie(y_data, labels=x_data, autopct='%1.1f%%', colors=colors, startangle=90)
                
            elif chart_type.lower() == 'bar':
                bars = ax.bar(range(len(df)), y_data, color=plt.cm.viridis(np.linspace(0, 1, len(df))))
                ax.set_xlabel(df.columns[0], fontsize=12, fontweight='bold')
                ax.set_ylabel(df.columns[1], fontsize=12, fontweight='bold')
                ax.set_xticks(range(len(df)))
                ax.set_xticklabels(x_data, rotation=45, ha='right')
            
            ax.set_title(title, fontsize=16, fontweight='bold', pad=20)
            
            plt.tight_layout()
            buffer = io.BytesIO()
            plt.savefig(buffer, format='png', dpi=300, bbox_inches='tight', facecolor='white')
            buffer.seek(0)
            
            chart_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
            plt.close(fig)
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

def get_authenticated_db_response(user_input: str, user_data: Dict) -> Dict[str, Any]:
    """API function with user authentication"""
    global db_assistant_instance
    
    try:
        if db_assistant_instance is None:
            db_assistant_instance = DatabaseAssistant()
        
        return db_assistant_instance.execute_query_with_permissions(user_input, user_data)
        
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

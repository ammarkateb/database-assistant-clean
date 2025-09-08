#!/usr/bin/env python
# coding: utf-8

import base64
import io
import json
import logging
import os
import re
import time
from contextlib import contextmanager
from datetime import datetime
from typing import Dict, Any, List, Optional, Tuple

import pandas as pd
import psycopg2
from psycopg2.pool import SimpleConnectionPool
import matplotlib.pyplot as plt
import seaborn as sns
import google.generativeai as genai
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
        """Initialize the Simplified Database Assistant"""
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
    
    def get_database_schema(self) -> str:
        """Get database schema for Gemini context"""
        return """
        Database Schema:

        public.customers:
        - customer_id (serial, primary key)
        - name (text), email (text), phone (text)
        - created_at (timestamp), city (varchar)

        public.products:
        - product_id (serial, primary key)
        - name (text), category (text)
        - price (numeric), stock (integer), cost (double precision)

        public.invoices:
        - invoice_id (serial, primary key)
        - customer_id (integer), invoice_date (date), total_amount (numeric)

        public.invoice_items:
        - invoice_id (bigint), product_id (bigint)
        - quantity (bigint), price (double precision)

        public.inventory_movements:
        - movement_id (serial, primary key)
        - product_id (integer), movement_type (text)
        - quantity (integer), movement_date (timestamp), invoice_id (integer)
        """
    
    def get_conversation_context(self) -> str:
        """Get recent conversation context"""
        if not self.conversation_history:
            return "No previous conversation."
        
        # Get last 3 exchanges for context
        recent_history = self.conversation_history[-6:]  # Last 3 user inputs + responses
        context = "Recent conversation:\n"
        
        for i in range(0, len(recent_history), 2):
            if i + 1 < len(recent_history):
                context += f"User: {recent_history[i]}\n"
                context += f"Assistant: {recent_history[i + 1]}\n"
        
        return context
    
    def process_with_gemini(self, user_input: str) -> Dict[str, Any]:
        """Process user input with Gemini and return structured response"""
        
        # Build comprehensive prompt for Gemini
        prompt = f"""You are a helpful database assistant. You help users query their database naturally.

        {self.get_database_schema()}

        {self.get_conversation_context()}

        Current user input: "{user_input}"

        INSTRUCTIONS:
        1. If the user needs data from the database, generate a valid PostgreSQL query
        2. Always respond conversationally and naturally
        3. For monthly data, ensure ALL 12 months are included using generate_series
        4. If user asks for charts after seeing data, suggest chart types
        5. Be helpful and context-aware

        RESPONSE FORMAT (JSON):
        {{
            "needs_sql": true/false,
            "sql_query": "SELECT ... (if needed)",
            "response_message": "Your conversational response",
            "suggested_chart": "bar/pie/none",
            "chart_rationale": "Why this chart type fits the data"
        }}

        Example for monthly data:
        WITH all_months AS (
            SELECT TO_CHAR(generate_series('2024-01-01'::date, '2024-12-01'::date, '1 month'::interval), 'YYYY-MM') AS month
        )
        SELECT am.month, COALESCE(COUNT(i.invoice_id), 0) AS invoice_count
        FROM all_months am
        LEFT JOIN invoices i ON TO_CHAR(i.invoice_date, 'YYYY-MM') = am.month
        GROUP BY am.month
        ORDER BY am.month;

        IMPORTANT: Return valid JSON only.
        """
        
        try:
            response = self.model.generate_content(
                prompt,
                generation_config=genai.types.GenerationConfig(
                    temperature=0.3,
                    max_output_tokens=1000
                )
            )
            
            # Clean and parse JSON response
            response_text = str(response.text).strip()
            
            # Remove code blocks if present
            response_text = re.sub(r'```json\s*', '', response_text)
            response_text = re.sub(r'```\s*$', '', response_text)
            
            # Parse JSON
            try:
                parsed_response = json.loads(response_text)
                return parsed_response
            except json.JSONDecodeError:
                # Fallback if JSON parsing fails
                logger.warning("Failed to parse Gemini JSON response, using fallback")
                return {
                    "needs_sql": False,
                    "sql_query": "",
                    "response_message": response_text,
                    "suggested_chart": "none",
                    "chart_rationale": ""
                }
                
        except Exception as e:
            logger.error(f"Gemini processing error: {e}")
            return {
                "needs_sql": False,
                "sql_query": "",
                "response_message": "I'm having trouble processing that request. Could you try rephrasing it?",
                "suggested_chart": "none",
                "chart_rationale": ""
            }
    
    def validate_sql_query(self, sql_query: str) -> bool:
        """Validate SQL query for security"""
        if not sql_query or len(sql_query.strip()) < 5:
            return False
        
        # Check for dangerous operations
        dangerous_keywords = ['DROP', 'TRUNCATE', 'ALTER', 'CREATE', 'DELETE', 'INSERT', 'UPDATE']
        sql_upper = sql_query.upper()
        
        for keyword in dangerous_keywords:
            if keyword in sql_upper:
                logger.warning(f"Dangerous query detected: {keyword}")
                return False
        
        # Must start with SELECT or WITH
        if not re.match(r'^\s*(SELECT|WITH)', sql_query, re.IGNORECASE):
            return False
        
        return True
    
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
            
            # Prepare data
            x_data = df.iloc[:, 0].astype(str)
            y_data = pd.to_numeric(df.iloc[:, 1], errors='coerce')
            
            if chart_type.lower() == 'pie':
                # Create pie chart
                colors = plt.cm.Set3(range(len(df)))
                wedges, texts, autotexts = ax.pie(
                    y_data, 
                    labels=x_data,
                    autopct='%1.1f%%',
                    colors=colors,
                    startangle=90,
                    explode=[0.02] * len(df)
                )
                
                # Style the text
                for autotext in autotexts:
                    autotext.set_color('white')
                    autotext.set_fontweight('bold')
                
            elif chart_type.lower() == 'bar':
                # Create bar chart
                bars = ax.bar(
                    range(len(df)), 
                    y_data, 
                    color=plt.cm.viridis(np.linspace(0, 1, len(df)))
                )
                
                # Add value labels on bars
                for i, bar in enumerate(bars):
                    height = bar.get_height()
                    ax.annotate(f'{height:,.0f}',
                              xy=(bar.get_x() + bar.get_width() / 2, height),
                              xytext=(0, 3),
                              textcoords="offset points",
                              ha='center', va='bottom',
                              fontweight='bold')
                
                # Style the chart
                ax.set_xlabel(df.columns[0], fontsize=12, fontweight='bold')
                ax.set_ylabel(df.columns[1], fontsize=12, fontweight='bold')
                ax.set_xticks(range(len(df)))
                ax.set_xticklabels(x_data, rotation=45, ha='right')
                ax.grid(True, alpha=0.3)
            
            # Set title
            ax.set_title(title, fontsize=16, fontweight='bold', pad=20)
            
            # Save to base64
            plt.tight_layout()
            buffer = io.BytesIO()
            plt.savefig(buffer, format='png', dpi=300, bbox_inches='tight', facecolor='white')
            buffer.seek(0)
            
            chart_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
            
            plt.close(fig)
            return chart_base64
            
        except Exception as e:
            logger.error(f"Chart creation error: {e}")
            plt.close(fig) if 'fig' in locals() else None
            return None
    
    def should_create_auto_chart(self, df: pd.DataFrame) -> Tuple[bool, str]:
        """Determine if data is suitable for automatic chart creation"""
        if df.empty or len(df.columns) < 2:
            return False, ""
        
        # Check if we have numeric data
        numeric_cols = df.select_dtypes(include=['number']).columns
        if len(numeric_cols) == 0:
            return False, ""
        
        # Auto-chart logic
        row_count = len(df)
        if row_count <= 10 and row_count > 1:
            # Good for pie chart
            return True, "pie"
        elif row_count <= 20 and row_count > 1:
            # Good for bar chart
            return True, "bar"
        
        return False, ""
    
    def execute_query_and_get_results(self, user_input: str) -> Dict[str, Any]:
        """Main method for processing user requests - API compatible"""
        
        # Process with Gemini
        gemini_response = self.process_with_gemini(user_input)
        
        # Initialize response
        response_data = {
            'success': False,
            'message': gemini_response.get('response_message', 'Processing your request...'),
            'data': [],
            'chart': None,
            'query': '',
            'row_count': 0,
            'suggested_chart': gemini_response.get('suggested_chart', 'none')
        }
        
        # Add to conversation history
        self.conversation_history.extend([user_input, response_data['message']])
        
        # Keep history manageable (last 10 exchanges)
        if len(self.conversation_history) > 20:
            self.conversation_history = self.conversation_history[-20:]
        
        try:
            # Handle SQL execution if needed
            if gemini_response.get('needs_sql', False):
                sql_query = gemini_response.get('sql_query', '')
                
                if sql_query and self.validate_sql_query(sql_query):
                    response_data['query'] = sql_query
                    
                    # Execute query
                    df_result, success, execution_message = self.execute_query(sql_query)
                    
                    if success and df_result is not None and not df_result.empty:
                        # Prepare data for response
                        display_data = df_result.head(50).to_dict('records')  # Limit for performance
                        
                        response_data.update({
                            'success': True,
                            'message': f"{response_data['message']}\n\n{execution_message}",
                            'data': display_data,
                            'row_count': len(df_result)
                        })
                        
                        # Create chart if suggested or auto-suitable
                        chart_type = gemini_response.get('suggested_chart', 'none')
                        if chart_type in ['bar', 'pie']:
                            chart_base64 = self.create_chart(df_result, chart_type, user_input)
                            if chart_base64:
                                response_data['chart'] = {
                                    'chart_base64': chart_base64,
                                    'chart_type': chart_type
                                }
                        else:
                            # Check for auto-chart opportunity
                            should_chart, auto_type = self.should_create_auto_chart(df_result)
                            if should_chart:
                                chart_base64 = self.create_chart(df_result, auto_type, user_input)
                                if chart_base64:
                                    response_data['chart'] = {
                                        'chart_base64': chart_base64,
                                        'chart_type': auto_type
                                    }
                                    response_data['message'] += f"\n\nI created a {auto_type} chart to visualize the data!"
                    
                    elif success and df_result is not None and df_result.empty:
                        response_data.update({
                            'success': True,
                            'message': f"{response_data['message']}\n\n{execution_message}"
                        })
                    
                    else:
                        response_data.update({
                            'success': False,
                            'message': f"{response_data['message']}\n\n{execution_message}"
                        })
                
                else:
                    response_data.update({
                        'success': False,
                        'message': response_data['message'] + "\n\nI couldn't generate a valid query for that request."
                    })
            
            else:
                # Pure conversational response
                response_data['success'] = True
            
            return response_data
            
        except Exception as e:
            logger.error(f"Error in execute_query_and_get_results: {e}")
            response_data.update({
                'success': False,
                'message': f"An error occurred while processing your request: {str(e)}"
            })
            return response_data
    
    def get_response_from_db_assistant(self, user_input: str) -> str:
        """Simple text response method for basic integrations"""
        try:
            result = self.execute_query_and_get_results(user_input)
            
            message = result['message']
            
            if result['success'] and result['data']:
                # Add sample data to response
                data_count = result['row_count']
                message += f"\n\nFound {data_count} results."
                
                if result['data']:
                    # Show first few results
                    df_sample = pd.DataFrame(result['data'][:5])
                    message += f"\n\nSample data:\n{df_sample.to_string(index=False)}"
                    
                    if data_count > 5:
                        message += f"\n\n...and {data_count - 5} more results."
            
            if result['chart']:
                message += f"\n\nChart: {result['chart']['chart_type']} visualization created."
            
            return message
            
        except Exception as e:
            return f"Error: {str(e)}"
    
    def run_interactive(self):
        """Run interactive CLI version"""
        print("🤖 Smart Database Assistant - Powered by Gemini AI")
        print("=" * 60)
        print("Ask me anything about your database in plain English!")
        print("I can create bar charts and pie charts automatically.")
        print("Type 'quit' to exit.\n")
        
        while True:
            try:
                user_input = input("💬 You: ").strip()
                
                if not user_input:
                    continue
                
                if user_input.lower() in ['quit', 'exit', 'bye']:
                    print("👋 Goodbye! Thanks for using the database assistant!")
                    break
                
                print("🔍 Processing...")
                result = self.execute_query_and_get_results(user_input)
                
                print(f"\n🤖 Assistant: {result['message']}")
                
                if result['success'] and result['data']:
                    # Display data nicely
                    df_display = pd.DataFrame(result['data'][:10])  # Show first 10 rows
                    print(f"\n📊 Data ({result['row_count']} total rows):")
                    print(df_display.to_string(index=False))
                    
                    if result['row_count'] > 10:
                        print(f"... and {result['row_count'] - 10} more rows")
                
                if result['chart']:
                    chart_type = result['chart']['chart_type']
                    print(f"\n📈 {chart_type.title()} chart created and saved!")
                
                print("\n" + "="*60)
                
            except KeyboardInterrupt:
                print("\n\n👋 Goodbye!")
                break
            except Exception as e:
                logger.error(f"Interactive error: {e}")
                print(f"❌ Error: {e}")
                continue
    
    def cleanup(self):
        """Cleanup resources"""
        try:
            if hasattr(self, 'connection_pool'):
                self.connection_pool.closeall()
            logger.info("Database assistant cleaned up successfully")
        except Exception as e:
            logger.error(f"Cleanup error: {e}")

# Global instance for API usage
db_assistant_instance = None

def get_db_response(user_query: str) -> str:
    """Simple API function for external integrations"""
    global db_assistant_instance
    
    try:
        if db_assistant_instance is None:
            db_assistant_instance = DatabaseAssistant()
        
        return db_assistant_instance.get_response_from_db_assistant(user_query)
        
    except Exception as e:
        logger.error(f"API error: {e}")
        return f"Sorry, I encountered an error: {str(e)}"

def get_db_results(user_query: str) -> Dict[str, Any]:
    """Full API function returning structured data for Flutter/web apps"""
    global db_assistant_instance
    
    try:
        if db_assistant_instance is None:
            db_assistant_instance = DatabaseAssistant()
        
        return db_assistant_instance.execute_query_and_get_results(user_query)
        
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

# Utility functions
def test_connection():
    """Test database connection"""
    try:
        assistant = DatabaseAssistant()
        with assistant.get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT version();")
                version = cur.fetchone()[0]
                print(f"✅ Connected! Running {version.split()[0]} {version.split()[1]}")
        assistant.cleanup()
        return True
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

def main():
    """Main function"""
    try:
        print("🔧 Testing database connection...")
        if not test_connection():
            print("❌ Cannot proceed without database connection.")
            return
        
        print("✅ Connection successful!")
        print("\nStarting interactive mode...")
        
        assistant = DatabaseAssistant()
        assistant.run_interactive()
        assistant.cleanup()
        
    except Exception as e:
        logger.error(f"Main error: {e}")
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    main()

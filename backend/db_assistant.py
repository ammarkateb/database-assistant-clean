#!/usr/bin/env python
# coding: utf-8

import base64
import io
from typing import Optional, Dict, Any, List, Tuple
import pandas as pd
import psycopg2
from psycopg2.pool import SimpleConnectionPool
import matplotlib.pyplot as plt
import seaborn as sns
import warnings
import google.generativeai as genai
import re
import speech_recognition as sr
from datetime import datetime, timedelta
from spellchecker import SpellChecker
from dotenv import load_dotenv
import os
import logging
import json
import hashlib
import time
from contextlib import contextmanager
from dataclasses import dataclass
import numpy as np
import random

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

# Ignore pandas warnings
warnings.filterwarnings('ignore', category=UserWarning)
plt.style.use('seaborn-v0_8')
sns.set_palette("husl")

@dataclass
class ConversationContext:
    """Track conversation context for human-like understanding"""
    last_query: str = ""
    last_results: Optional[pd.DataFrame] = None
    last_question: str = ""
    last_chart_type: Optional[str] = None
    awaiting_chart_choice: bool = False
    awaiting_confirmation: bool = False
    previous_topics: List[str] = None
    user_preferences: Dict[str, Any] = None
    
    def __post_init__(self):
        if self.previous_topics is None:
            self.previous_topics = []
        if self.user_preferences is None:
            self.user_preferences = {'chart_style': 'modern', 'verbosity': 'normal'}

class ResponseHandler:
    """Handle different types of responses appropriately"""
    
    def __init__(self):
        self.simple_responses = {
            'vague_chart': [
                "I'd love to make you a chart! What data should I put in it?",
                "A chart sounds great! What would you like me to show?",
                "Charts are fun! What information should I visualize?"
            ],
            'missing_months': [
                "You want to see all 12 months? Let me fix that for you!",
                "Ah, you want the complete picture! I'll include all months.",
                "Good catch! Let me show you the full year."
            ],
            'need_clarification': [
                "I need a bit more info to help you properly.",
                "Could you tell me what specific data you want to see?",
                "What would you like me to focus on?"
            ],
            'excitement': [
                "That's an interesting question! Let me dive into your data.",
                "Great question! I'm excited to explore this with you.",
                "Perfect! This is exactly the kind of analysis I love doing."
            ],
            'confirmation': [
                "Got it! Let me work on that for you.",
                "Absolutely! Processing your request now.",
                "On it! Give me just a moment."
            ]
        }
    
    def get_helpful_response(self, situation: str, context: str = "") -> str:
        """Get a helpful response for common situations"""
        
        if situation == 'vague_chart':
            response = random.choice(self.simple_responses['vague_chart'])
            suggestions = [
                "Sales trends over time",
                "Customer distribution by location", 
                "Top performing products",
                "Revenue patterns by month"
            ]
            return f"{response}\n\nHere are some popular ideas:\n" + "\n".join(f"• {s}" for s in suggestions)
        
        elif situation == 'missing_months':
            return random.choice(self.simple_responses['missing_months'])
        
        elif situation == 'need_clarification':
            return random.choice(self.simple_responses['need_clarification'])
        
        elif situation == 'excitement':
            return random.choice(self.simple_responses['excitement'])
        
        elif situation == 'confirmation':
            return random.choice(self.simple_responses['confirmation'])
        
        return "I'm not sure what you mean. Could you explain a bit more?"

class HumanLikeUnderstanding:
    """Enhanced natural language understanding for human-like interactions"""
    
    def __init__(self):
        self.chart_keywords = {
            'pie': ['pie', 'circular', 'circle', 'donut', 'wheel', 'round', 'percentage', 'proportion'],
            'bar': ['bar', 'column', 'bars', 'columns', 'vertical', 'histogram', 'compare', 'comparison'],
            'line': ['line', 'trend', 'time', 'timeline', 'over time', 'progression', 'growth', 'change'],
            'scatter': ['scatter', 'plot', 'points', 'correlation', 'relationship', 'distribution']
        }
        
        self.intent_patterns = {
            'vague_chart_request': [
                r'^(what about|how about)\s+(a\s+)?(pie|bar|line|scatter)\s*(chart)?$',
                r'^(pie|bar|line|scatter)\s*(chart)?$',
                r'^(chart|graph|plot)$'
            ],
            'chart_request': [
                r'\b(show|display|plot|chart|graph|visualize)\b.*\b(pie|bar|line|scatter)\b',
                r'\b(pie|bar|line|scatter)\b.*\b(chart|graph)\b',
                r'(as|in|with)\s+(chart|graph)',
                r'\b(make|create|draw)\b.*\b(chart|graph)\b'
            ],
            'same_data_different_viz': [
                r'^(change|switch|convert)\s+to\s+(pie|bar|line|scatter)',
                r'^(make|show)\s+it\s+(as\s+)?(pie|bar|line|scatter)',
                r'^(different|another)\s+(chart|visualization)'
            ],
            'missing_data_complaint': [
                r'why.*not.*all',
                r'missing.*months',
                r'where.*rest',
                r'incomplete.*data',
                r"didn't.*give.*all"
            ],
            'more_details': [
                r'^(more|details|expand|elaborate|explain)',
                r'(tell me more|show more|give me more)',
                r'(what about|how about|what if)',
                r'^(why|how|when|where)'
            ],
            'follow_up': [
                r'^(and|also|plus|additionally)',
                r'(what about|how about)',
                r'(for the same|using the same)',
                r'^(now\s+)?(show|tell|find)'
            ],
            'simple_answer': [
                r'^\s*(yes|yeah|yep|ok|okay|sure|fine)\s*$',
                r'^\s*(no|nope|not really|never mind)\s*$'
            ]
        }
        
        self.context_clues = {
            'temporal': ['today', 'yesterday', 'last week', 'this month', 'recent', 'latest', 'current'],
            'comparison': ['compare', 'vs', 'versus', 'against', 'difference between', 'better', 'worse'],
            'ranking': ['top', 'best', 'worst', 'lowest', 'highest', 'rank', 'order by'],
            'aggregation': ['total', 'sum', 'average', 'count', 'max', 'min', 'group by']
        }

    def classify_intent(self, user_input: str, context: ConversationContext) -> str:
        """Classify user intent based on input and context"""
        user_input_lower = user_input.lower().strip()
        
        # Check for vague chart requests first
        for pattern in self.intent_patterns['vague_chart_request']:
            if re.search(pattern, user_input_lower):
                return 'vague_chart_request'
        
        # Check for missing data complaints
        for pattern in self.intent_patterns['missing_data_complaint']:
            if re.search(pattern, user_input_lower):
                return 'missing_data_complaint'
        
        # Check for simple chart type requests when we just showed results
        if context.last_results is not None and not context.last_results.empty:
            # Direct chart type mention
            for chart_type, keywords in self.chart_keywords.items():
                if any(keyword in user_input_lower for keyword in keywords):
                    if len(user_input_lower.split()) <= 3:  # Short requests like "pie chart"
                        return f'chart_request_{chart_type}'
        
        # Check other intent patterns
        for intent, patterns in self.intent_patterns.items():
            for pattern in patterns:
                if re.search(pattern, user_input_lower):
                    return intent
        
        # Default to new query
        return 'new_query'
    
    def extract_chart_type(self, user_input: str) -> Optional[str]:
        """Extract chart type from user input"""
        user_input_lower = user_input.lower()
        
        for chart_type, keywords in self.chart_keywords.items():
            if any(keyword in user_input_lower for keyword in keywords):
                return chart_type
        
        return None
    
    def understand_reference(self, user_input: str, context: ConversationContext) -> str:
        """Understand references to previous results or context"""
        pronouns = ['it', 'this', 'that', 'these', 'those', 'them', 'they']
        user_lower = user_input.lower()
        
        # If user references previous results
        if any(pronoun in user_lower for pronoun in pronouns) and context.last_results is not None:
            # Replace pronouns with context
            if context.last_question:
                return f"Using the results from '{context.last_question}', {user_input}"
        
        return user_input

class SmartQueryGenerator:
    """Generate appropriate SQL or responses based on context"""
    
    def __init__(self, model, enhanced_prompt):
        self.model = model
        self.enhanced_prompt = enhanced_prompt
        self.response_handler = ResponseHandler()
    
    def should_generate_sql(self, user_input: str, intent: str) -> bool:
        """Determine if we should generate SQL or provide a conversational response"""
        
        # Don't generate SQL for these intents
        non_sql_intents = [
            'vague_chart_request',
            'missing_data_complaint', 
            'simple_answer'
        ]
        
        if intent in non_sql_intents:
            return False
        
        # Don't generate SQL for very short, unclear inputs
        if len(user_input.strip().split()) <= 2 and intent == 'new_query':
            return False
        
        return True
    
    def handle_non_sql_response(self, user_input: str, intent: str, context: ConversationContext) -> str:
        """Handle responses that don't need SQL"""
        
        if intent == 'vague_chart_request':
            return self.response_handler.get_helpful_response('vague_chart')
        
        elif intent == 'missing_data_complaint':
            # If they're asking about missing months and we have recent results
            if context.last_results is not None:
                return "Let me rerun that query to include all months for you!"
            else:
                return self.response_handler.get_helpful_response('missing_months')
        
        elif intent == 'simple_answer':
            if context.awaiting_chart_choice:
                return "Which type of chart would you like? (pie, bar, line, scatter)"
            else:
                return "I'm here to help! What would you like to know about your data?"
        
        else:
            return self.response_handler.get_helpful_response('need_clarification')
    
    def generate_sql_with_complete_months(self, base_query: str) -> str:
        """Modify query to ensure all months are included"""
        
        # Check if this is a monthly query that might be missing months
        if 'month' in base_query.lower() and 'group by' in base_query.lower():
            
            # Enhanced prompt for complete month coverage
            month_prompt = f"""{self.enhanced_prompt}

IMPORTANT: When generating queries that show data by month, ALWAYS ensure ALL 12 months are included, even if some months have zero values. Use a CTE or similar approach to generate all months first.

Example pattern:
```sql
WITH all_months AS (
    SELECT TO_CHAR(generate_series('2024-01-01'::date, '2024-12-01'::date, '1 month'::interval), 'YYYY-MM') AS month
),
monthly_data AS (
    -- Your original query here
)
SELECT am.month, COALESCE(md.value, 0) as value
FROM all_months am
LEFT JOIN monthly_data md ON am.month = md.month
ORDER BY am.month;
```

Original user request: "{base_query}"
Generate a complete SQL query that shows ALL months:"""

            try:
                response = self.model.generate_content(
                    month_prompt,
                    generation_config=genai.types.GenerationConfig(
                        temperature=0.2,
                        max_output_tokens=1000
                    )
                )
                
                return self.clean_sql_response(str(response.text))
            except:
                return base_query
        
        return base_query
    
    def clean_sql_response(self, response: str) -> str:
        """Clean the AI response to extract only SQL"""
        
        # Remove markdown code blocks
        response = re.sub(r'```sql\s*', '', response)
        response = re.sub(r'```\s*$', '', response)
        
        # Split by lines and look for SQL
        lines = response.split('\n')
        sql_lines = []
        found_sql = False
        
        for line in lines:
            line = line.strip()
            
            # Skip explanatory text
            if line.startswith(('The question', 'This query', 'Note:', 'Example:', '--')):
                continue
            
            # Look for SQL keywords at start of line
            if re.match(r'^(SELECT|WITH|INSERT|UPDATE|DELETE)', line, re.IGNORECASE):
                found_sql = True
            
            if found_sql and line:
                sql_lines.append(line)
            
            # Stop if we hit another explanation
            if found_sql and line.startswith(('The result', 'This will', 'Note:')):
                break
        
        if sql_lines:
            return '\n'.join(sql_lines).strip()
        
        # Fallback: try to find any SQL in the response
        sql_match = re.search(r'(SELECT.*?;|SELECT.*?$)', response, re.DOTALL | re.IGNORECASE)
        if sql_match:
            return sql_match.group(1).strip()
        
        return ""

class DatabaseAssistant:
    def __init__(self):
        """Initialize the Human-Like Database Assistant"""
        self.load_environment()
        self.setup_ai_model()
        self.setup_spellchecker()
        self.setup_database_pool()
        self.query_cache = {}
        self.session_history = []
        self.context = ConversationContext()
        self.nlp = HumanLikeUnderstanding()
        self.query_generator = SmartQueryGenerator(self.model, self.get_enhanced_prompt())
    
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
        """Setup AI model with enhanced configuration"""
        genai.configure(api_key=self.api_key)
        self.model = genai.GenerativeModel('gemini-1.5-flash')
        
        try:
            test_response = self.model.generate_content("Test")
            logger.info("AI model connected successfully")
        except Exception as e:
            logger.error(f"Failed to connect to AI model: {e}")
            raise
    
    def setup_spellchecker(self):
        """Setup spellchecker and shortcuts"""
        self.spell = SpellChecker()
        self.shortcuts_map = {
            'u': 'you', 'r': 'are', 'ofc': 'of course', 'btw': 'by the way',
            'cos': 'because', 'cuz': 'because', 'b4': 'before', '2': 'to',
            'ur': 'your', 'thx': 'thanks', 'pls': 'please', 'w/': 'with',
            'w/o': 'without', 'asap': 'as soon as possible', 'rn': 'right now',
            'tbh': 'to be honest', 'imo': 'in my opinion', 'fyi': 'for your information'
        }
    
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
    
    def preprocess_question(self, question: str) -> str:
        """Process and clean the question"""
        cleaned_words = []
        words = question.lower().split()
        
        for word in words:
            if word in self.shortcuts_map:
                cleaned_words.append(self.shortcuts_map[word])
            else:
                if re.match(r'^[a-zA-Z]+$', word):
                    corrected_word = self.spell.correction(word)
                    cleaned_words.append(corrected_word if corrected_word else word)
                else:
                    cleaned_words.append(word)
        
        return ' '.join(cleaned_words)
    
    def get_enhanced_prompt(self) -> str:
        """Generate enhanced prompt for AI"""
        return """You are an advanced PostgreSQL database assistant. Convert natural language questions into single, valid SQL queries ONLY.

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

CRITICAL RULES:
1. Return ONLY valid SQL queries, no explanations or comments
2. Use exact table/column names from schema
3. For monthly data, always include ALL 12 months using generate_series or similar
4. Add "AS PIE CHART" or "AS BAR CHART" for visualizations when requested
5. If the question is unclear, return a sensible default query

Example for monthly data:
WITH all_months AS (
    SELECT TO_CHAR(generate_series('2024-01-01'::date, '2024-12-01'::date, '1 month'::interval), 'YYYY-MM') AS month
)
SELECT am.month, COALESCE(COUNT(i.invoice_id), 0) AS invoice_count
FROM all_months am
LEFT JOIN invoices i ON TO_CHAR(i.invoice_date, 'YYYY-MM') = am.month
GROUP BY am.month
ORDER BY am.month;
"""
    
    def understand_human_input(self, user_input: str) -> Tuple[str, str, Dict[str, Any]]:
        """Advanced human input understanding"""
        # Classify the intent of the input
        intent = self.nlp.classify_intent(user_input, self.context)
        
        # Handle different types of human communication
        interpretation = {
            'action': 'query',
            'needs_confirmation': False,
            'chart_type': None,
            'reference_previous': False,
            'needs_response_only': False
        }
        
        # Handle non-SQL responses
        if intent in ['vague_chart_request', 'missing_data_complaint']:
            interpretation['needs_response_only'] = True
            interpretation['action'] = 'respond_only'
            return user_input, intent, interpretation
        
        if intent.startswith('chart_request_'):
            chart_type = intent.split('_')[-1]
            interpretation['action'] = 'create_chart'
            interpretation['chart_type'] = chart_type
            interpretation['reference_previous'] = True
            
            return f"Show the previous results as a {chart_type} chart", intent, interpretation
        
        elif intent == 'same_data_different_viz':
            chart_type = self.nlp.extract_chart_type(user_input)
            if chart_type:
                interpretation['action'] = 'create_chart'
                interpretation['chart_type'] = chart_type
                interpretation['reference_previous'] = True
                
                return f"Create a {chart_type} chart using the last query results", intent, interpretation
        
        elif intent == 'simple_answer':
            if self.context.awaiting_chart_choice:
                if any(word in user_input.lower() for word in ['yes', 'yeah', 'yep', 'ok', 'sure']):
                    interpretation['action'] = 'create_chart'
                    interpretation['chart_type'] = 'bar'  # default
                    interpretation['reference_previous'] = True
                    return "Create a chart from the previous results", intent, interpretation
        
        elif intent == 'follow_up':
            # User wants to build on previous query
            enhanced_input = self.nlp.understand_reference(user_input, self.context)
            interpretation['reference_previous'] = True
            return enhanced_input, intent, interpretation
        
        # Default: treat as new query but with context
        if self.context.last_question and len(user_input.split()) < 5:
            # Short input might be referring to previous context
            contextual_input = f"Based on the previous question about '{self.context.last_question}', {user_input}"
            interpretation['reference_previous'] = True
            return contextual_input, intent, interpretation
        
        return user_input, intent, interpretation
    
    def generate_human_like_response(self, intent: str, success: bool = True) -> str:
        """Generate contextual, human-like responses"""
        responses = {
            'chart_request_pie': [
                "Great choice! Pie charts are perfect for showing proportions. Creating one now...",
                "Excellent! A pie chart will show the breakdown nicely.",
                "Smart thinking! Pie charts make percentages super clear."
            ],
            'chart_request_bar': [
                "Perfect! Bar charts are great for comparing values. Making one now...",
                "Good call! Bar charts make it easy to compare different items.",
                "Absolutely! Bar charts are ideal for this kind of comparison."
            ],
            'understood_context': [
                "I see what you're getting at! ",
                "Ah, building on the previous results! ",
                "Got it! Using the context from before. ",
                "I understand the connection! "
            ],
            'new_query': [
                "Let me look that up for you!",
                "Interesting question! Let me check the database.",
                "Good question! Searching through the data now.",
                "Let me find that information for you."
            ]
        }
        
        if intent in responses:
            return random.choice(responses[intent])
        return ""
    
    def get_query_and_chart_type(self, question: str, context_aware: bool = False) -> Tuple[Optional[str], Optional[str]]:
        """Generate SQL query with context awareness"""
        try:
            # Build context-aware prompt
            base_prompt = self.get_enhanced_prompt()
            
            if context_aware and self.context.last_query:
                prompt = f"""{base_prompt}
                
CONTEXT: The user previously asked: "{self.context.last_question}"
The last query was: {self.context.last_query}

Now they're asking: "{question}"

This might be a follow-up question or a request to visualize the same data differently.

Generate ONLY a valid SQL query:"""
            else:
                prompt = f"{base_prompt}\n\nQuestion: \"{question}\"\nSQL Query:"
            
            response = self.model.generate_content(
                prompt,
                generation_config=genai.types.GenerationConfig(
                    temperature=0.2,
                    max_output_tokens=1000
                )
            )
            
            sql_query = self.query_generator.clean_sql_response(str(response.text))
            
            # Extract chart type
            chart_type = None
            if "AS PIE CHART" in sql_query.upper():
                chart_type = 'pie'
                sql_query = re.sub(r'\s*AS PIE CHART\s*', '', sql_query, flags=re.IGNORECASE)
            elif "AS BAR CHART" in sql_query.upper():
                chart_type = 'bar'
                sql_query = re.sub(r'\s*AS BAR CHART\s*', '', sql_query, flags=re.IGNORECASE)
            
            # Ensure complete months if needed
            sql_query = self.query_generator.generate_sql_with_complete_months(sql_query)
            
            if not self.validate_sql_query(sql_query):
                return None, None
            
            return sql_query, chart_type
            
        except Exception as e:
            logger.error(f"Error generating query: {e}")
            return None, None
    
    def validate_sql_query(self, sql_query: str) -> bool:
        """Validate SQL query"""
        if not sql_query or len(sql_query.strip()) < 5:
            return False
        
        # Check if it's actually SQL and not explanatory text
        if sql_query.startswith(('The question', 'This query', 'Note:', 'Example:')):
            return False
        
        dangerous_keywords = ['DROP', 'TRUNCATE', 'ALTER', 'CREATE', 'GRANT', 'REVOKE']
        sql_upper = sql_query.upper()
        
        for keyword in dangerous_keywords:
            if keyword in sql_upper:
                logger.warning(f"Dangerous query detected: {keyword}")
                return False
        
        # Must start with valid SQL command
        if not re.match(r'^\s*(SELECT|WITH|INSERT|UPDATE|DELETE)', sql_query, re.IGNORECASE):
            return False
        
        return True
    
    def execute_query(self, sql_query: str) -> Tuple[Optional[pd.DataFrame], bool]:
        """Execute query with enhanced feedback and error handling"""
        try:
            with self.get_db_connection() as conn:
                start_time = time.time()
                
                with conn.cursor() as cur:
                    cur.execute(sql_query)
                    
                    if self.is_modification_query(sql_query):
                        conn.commit()
                        affected_rows = cur.rowcount
                        execution_time = time.time() - start_time
                        
                        logger.info(f"Modification executed - {affected_rows} rows affected")
                        print(f"Done! Updated {affected_rows} rows in {execution_time:.2f} seconds")
                        return None, True
                    else:
                        rows = cur.fetchall()
                        column_names = [desc[0] for desc in cur.description] if cur.description else []
                        
                        execution_time = time.time() - start_time
                        logger.info(f"Query executed - {len(rows)} rows returned")
                        
                        if rows and column_names:
                            df = pd.DataFrame(rows, columns=column_names)
                            if len(rows) == 0:
                                print("No matches found for that query")
                            else:
                                print(f"Found {len(rows)} results in {execution_time:.2f} seconds!")
                            return df, True
                        else:
                            print("No data found for that query")
                            return pd.DataFrame(), True
                            
        except psycopg2.Error as e:
            logger.error(f"Database error: {e}")
            print(f"Whoops! Database hiccup: {e}")
            return None, False
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            print(f"Something unexpected happened: {e}")
            return None, False
    
    def is_modification_query(self, sql_query: str) -> bool:
        """Check if query modifies data"""
        modification_keywords = ['INSERT', 'UPDATE', 'DELETE', 'MERGE']
        sql_upper = sql_query.upper().strip()
        return any(sql_upper.startswith(keyword) for keyword in modification_keywords)
    
    def create_enhanced_chart(self, df: pd.DataFrame, chart_type: str, question: str) -> Optional[Dict[str, Any]]:
        """Create beautiful, enhanced charts and return as base64 for Flutter"""
        if df.empty or len(df.columns) < 2:
            print("Not enough data to create a meaningful chart")
            return None
        
        plt.style.use('default')
        fig, ax = plt.subplots(figsize=(12, 8))
        
        try:
            if chart_type == 'pie':
                # Beautiful pie chart
                colors = plt.cm.Set3(range(len(df)))
                wedges, texts, autotexts = ax.pie(
                    df.iloc[:, 1], 
                    labels=df.iloc[:, 0],
                    autopct='%1.1f%%',
                    colors=colors,
                    startangle=90,
                    explode=[0.05] * len(df),
                    shadow=True,
                    textprops={'fontsize': 11, 'fontweight': 'bold'}
                )
                
                for autotext in autotexts:
                    autotext.set_color('white')
                    autotext.set_fontweight('bold')
                    autotext.set_fontsize(10)
                
                ax.set_title(f"{question}", fontsize=16, fontweight='bold', pad=20)
                
            elif chart_type == 'bar':
                # Beautiful bar chart
                bars = ax.bar(
                    range(len(df)), 
                    df.iloc[:, 1], 
                    color=plt.cm.viridis(np.linspace(0, 1, len(df))),
                    edgecolor='white',
                    linewidth=1.2
                )
                
                # Add value labels
                for i, bar in enumerate(bars):
                    height = bar.get_height()
                    ax.annotate(f'{height:,.0f}',
                              xy=(bar.get_x() + bar.get_width() / 2, height),
                              xytext=(0, 3),
                              textcoords="offset points",
                              ha='center', va='bottom',
                              fontweight='bold')
                
                ax.set_xlabel(df.columns[0], fontsize=12, fontweight='bold')
                ax.set_ylabel(df.columns[1], fontsize=12, fontweight='bold')
                ax.set_title(f"{question}", fontsize=16, fontweight='bold', pad=20)
                ax.set_xticks(range(len(df)))
                ax.set_xticklabels(df.iloc[:, 0], rotation=45, ha='right')
                ax.grid(True, alpha=0.3, linestyle='--')
                ax.spines['top'].set_visible(False)
                ax.spines['right'].set_visible(False)
            
            elif chart_type == 'line':
                # Beautiful line chart
                ax.plot(range(len(df)), df.iloc[:, 1], 
                       marker='o', linewidth=3, markersize=8,
                       color='#2E86C1', markerfacecolor='#F39C12')
                
                ax.set_xlabel(df.columns[0], fontsize=12, fontweight='bold')
                ax.set_ylabel(df.columns[1], fontsize=12, fontweight='bold')
                ax.set_title(f"{question}", fontsize=16, fontweight='bold', pad=20)
                ax.set_xticks(range(len(df)))
                ax.set_xticklabels(df.iloc[:, 0], rotation=45, ha='right')
                ax.grid(True, alpha=0.3, linestyle='--')
                ax.spines['top'].set_visible(False)
                ax.spines['right'].set_visible(False)
            
            plt.tight_layout()
            
            # Convert to base64 for Flutter
            buffer = io.BytesIO()
            plt.savefig(buffer, format='png', dpi=300, bbox_inches='tight', facecolor='white')
            buffer.seek(0)
            
            # Encode to base64
            chart_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
            
            # Also save locally (optional)
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"chart_{chart_type}_{timestamp}.png"
            plt.savefig(filename, dpi=300, bbox_inches='tight', facecolor='white')
            print(f"Saved your {chart_type} chart as: {filename}")
            
            plt.close(fig)  # Important: close figure to free memory
            
            return {
                'chart_base64': chart_base64,
                'chart_type': chart_type,
                'filename': filename
            }
            
        except Exception as e:
            logger.error(f"Chart error: {e}")
            print(f"Couldn't create the chart: {e}")
            plt.close(fig)  # Close even on error
            return None

    def display_results_naturally(self, df: pd.DataFrame, question: str, max_rows: int = 50):
        """Display results in a natural, conversational way with configurable limit"""
        if df.empty:
            print("Didn't find anything matching that query")
            return df.to_dict('records')  # Return empty list for Flutter
        
        row_count = len(df)
        
        if row_count == 1:
            print("Found exactly 1 result:")
        else:
            print(f"Found {row_count} results. Here are the highlights:")
        
        # Show appropriate amount of data - INCREASED LIMIT
        if row_count <= max_rows:  # Changed from 15 to configurable max_rows (default 50)
            print("\n" + df.to_string(index=False))
            display_df = df
        else:
            show_count = min(30, max_rows)  # Show 30 instead of 10 when truncating
            print(f"\nTop {show_count} results:")
            print(df.head(show_count).to_string(index=False))
            print(f"\nWant to see more? I have {row_count - show_count} additional results!")
            display_df = df.head(show_count)
        
        # Natural insights
        if row_count > 1 and len(df.columns) >= 2:
            for col in df.select_dtypes(include=[np.number]).columns:
                if col != df.columns[0]:  # Skip first column if it's an ID
                    max_val = df[col].max()
                    min_val = df[col].min()
                    avg_val = df[col].mean()
                    print(f"\nQuick insights for {col}:")
                    print(f"   Highest: {max_val:,.2f}")
                    print(f"   Lowest: {min_val:,.2f}") 
                    print(f"   Average: {avg_val:,.2f}")
        
        # Return data for Flutter
        return display_df.to_dict('records')

    def execute_query_and_get_results(self, user_input: str) -> Dict[str, Any]:
        """Execute query and return comprehensive results for Flutter"""
        
        # Initialize response structure
        response_data = {
            'success': False,
            'message': '',
            'data': [],
            'chart': None,
            'query': '',
            'intent': '',
            'row_count': 0
        }
        
        try:
            # Process the question
            processed_question = self.preprocess_question(user_input)
            interpreted_input, intent, interpretation = self.understand_human_input(user_input)
            
            response_data['intent'] = intent
            
            # Handle chart creation from previous results
            if interpretation['action'] == 'create_chart':
                if self.context.last_results is not None and not self.context.last_results.empty:
                    chart_type = interpretation['chart_type']
                    print(f"Creating a {chart_type} chart from your last results...")
                    chart_data = self.create_enhanced_chart(
                        self.context.last_results, 
                        chart_type, 
                        self.context.last_question or "Previous Query Results"
                    )
                    
                    response_data.update({
                        'success': True,
                        'message': f"Created {chart_type} chart from previous results",
                        'data': self.context.last_results.to_dict('records'),
                        'chart': chart_data,
                        'row_count': len(self.context.last_results)
                    })
                    
                    self.context.last_chart_type = chart_type
                    return response_data
                else:
                    response_data.update({
                        'success': False,
                        'message': "I don't have any recent results to chart. Ask me a question first!"
                    })
                    return response_data
            
            # Regular query processing
            if not self.query_generator.should_generate_sql(processed_question, intent):
                response_msg = self.query_generator.handle_non_sql_response(processed_question, intent, self.context)
                response_data.update({
                    'success': True,
                    'message': response_msg
                })
                return response_data
            
            # Generate and execute SQL
            sql_query, chart_type = self.get_query_and_chart_type(
                processed_question, 
                context_aware=interpretation['reference_previous']
            )
            
            response_data['query'] = sql_query
            
            if not sql_query:
                response_data.update({
                    'success': False,
                    'message': "I couldn't understand that question. Try asking something like 'How many customers do I have?'"
                })
                return response_data
            
            # Execute query
            df_result, success = self.execute_query(sql_query)
            
            if success and df_result is not None:
                # Convert DataFrame to list of dictionaries for JSON serialization
                display_data = df_result.head(50).to_dict('records')  # Limit to 50 rows for performance
                
                # Create chart if requested or if data is suitable for visualization
                chart_data = None
                if chart_type and len(df_result) > 0 and len(df_result.columns) >= 2:
                    print(f"\nCreating {chart_type} chart!")
                    chart_data = self.create_enhanced_chart(df_result, chart_type, user_input)
                elif len(df_result) > 1 and len(df_result.columns) >= 2:
                    # Auto-suggest chart for suitable data
                    numeric_cols = df_result.select_dtypes(include=['number']).columns
                    if len(numeric_cols) > 0 and len(df_result) <= 20:  # Good for pie chart
                        chart_data = self.create_enhanced_chart(df_result, 'pie', user_input)
                    elif len(numeric_cols) > 0:  # Good for bar chart
                        chart_data = self.create_enhanced_chart(df_result.head(15), 'bar', user_input)
                
                # Update context
                self.context.last_query = sql_query
                self.context.last_question = user_input
                self.context.last_results = df_result
                self.context.last_chart_type = chart_type
                
                # Format message
                message = f"Found {len(df_result)} results"
                if chart_data:
                    message += f" with {chart_type or 'auto-generated'} chart"
                
                response_data.update({
                    'success': True,
                    'message': message,
                    'data': display_data,
                    'chart': chart_data,
                    'row_count': len(df_result)
                })
                
            else:
                response_data.update({
                    'success': False,
                    'message': "No results found or there was an error executing the query."
                })
            
            return response_data
            
        except Exception as e:
            logger.error(f"Error in execute_query_and_get_results: {e}")
            response_data.update({
                'success': False,
                'message': f"An error occurred: {str(e)}"
            })
            return response_data

    def get_response_from_db_assistant(self, user_input: str) -> str:
        """Simple API method for web requests - enhanced version"""
        try:
            if not user_input.strip():
                return "Please ask me a question about your database."
            
            # Use the comprehensive method
            response_data = self.execute_query_and_get_results(user_input)
            
            if response_data['success']:
                result_text = response_data['message']
                
                # Add data preview if available
                if response_data['data'] and len(response_data['data']) > 0:
                    result_text += f"\n\nHere's a preview of your data:\n"
                    
                    # Show first few rows in a readable format
                    for i, row in enumerate(response_data['data'][:5]):
                        row_str = ", ".join([f"{k}: {v}" for k, v in row.items()])
                        result_text += f"Row {i+1}: {row_str}\n"
                    
                    if len(response_data['data']) > 5:
                        result_text += f"\n...and {len(response_data['data']) - 5} more rows"
                
                # Mention chart if created
                if response_data['chart']:
                    result_text += f"\n\nI also created a {response_data['chart']['chart_type']} chart for you!"
                
                return result_text
            else:
                return response_data['message']
                
        except Exception as e:
            logger.error(f"Error in get_response_from_db_assistant: {e}")
            return f"Error: {str(e)}"

    def suggest_next_actions(self, df: pd.DataFrame, chart_type: Optional[str]):
        """Suggest logical next steps"""
        if df.empty:
            return
        
        suggestions = []
        
        # Chart suggestions
        if not chart_type and len(df.columns) >= 2 and len(df) > 1:
            suggestions.append("Want to visualize this? Try asking for a 'pie chart' or 'bar chart'")
        
        # Data exploration suggestions
        if len(df) > 10:
            suggestions.append("Want to filter these results? Try 'show only top 5' or 'filter by...'")
        
        if len(df.columns) > 2:
            suggestions.append("Interested in a specific column? Just ask about it!")
        
        # Smart suggestions based on data
        numeric_cols = df.select_dtypes(include=['number']).columns
        if len(numeric_cols) > 0:
            suggestions.append("Want statistics? Try 'analyze this data' or 'show trends'")
        
        if suggestions:
            print(f"\nWhat's next?")
            for suggestion in suggestions[:2]:  # Limit to 2 suggestions
                print(f"   • {suggestion}")

    def cleanup(self):
        """Human-like cleanup"""
        try:
            if self.session_history:
                print("\nWant me to save our conversation history?")
                save_choice = input("It might be useful for next time! (yes/no): ").strip().lower()
                if save_choice in ['yes', 'y', 'sure', 'ok', 'yeah']:
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    filename = f"our_conversation_{timestamp}.json"
                    
                    with open(filename, 'w', encoding='utf-8') as f:
                        json.dump(self.session_history, f, ensure_ascii=False, indent=2)
                    
                    print(f"Saved as: {filename}")
                    print("You can review our conversation anytime!")
            
            if hasattr(self, 'connection_pool'):
                self.connection_pool.closeall()
            
            print("\nThanks for hanging out with me! Hope I helped you discover some cool insights!")
            print("Come back anytime you want to explore your data!")
            
        except Exception as e:
            logger.error(f"Cleanup error: {e}")

# --- Helper Functions ---

def test_connection():
    """Test database connection"""
    try:
        assistant = DatabaseAssistant()
        with assistant.get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT version();")
                version = cur.fetchone()[0]
                print(f"Connected! Running {version.split()[0]} {version.split()[1]}")
        return True
    except Exception as e:
        print(f"Connection failed: {e}")
        return False

def quick_data_peek():
    """Take a quick peek at the data"""
    try:
        assistant = DatabaseAssistant()
        with assistant.get_db_connection() as conn:
            tables = ['customers', 'products', 'invoices']
            
            print("Quick peek at your data:\n")
            
            for table in tables:
                try:
                    count_query = f"SELECT COUNT(*) FROM {table}"
                    df = pd.read_sql(count_query, conn)
                    count = df.iloc[0, 0]
                    
                    sample_query = f"SELECT * FROM {table} LIMIT 3"
                    df_sample = pd.read_sql(sample_query, conn)
                    
                    print(f"{table.title()}: {count} records")
                    if not df_sample.empty:
                        print(f"   Sample: {', '.join(df_sample.columns[:3])}...")
                    print()
                    
                except Exception as e:
                    print(f"Couldn't peek at {table}: {e}")
                    
    except Exception as e:
        print(f"Data peek error: {e}")

# Global instance for Flask integration
db_assistant_instance = None

def get_db_response(user_query):
    """Main function to call from Flask app"""
    global db_assistant_instance
    
    try:
        if db_assistant_instance is None:
            db_assistant_instance = DatabaseAssistant()
        
        response = db_assistant_instance.get_response_from_db_assistant(user_query)
        return response
        
    except Exception as e:
        return f"Sorry, I encountered an error: {str(e)}"

def main():
    """Main function with enhanced setup"""
    print("Smart Database Assistant - Now with Human-Like Understanding!")
    print("=" * 70)
    
    try:
        # Test connection first
        print("Testing database connection...")
        if not test_connection():
            print("Can't connect to your database. Check your .env file!")
            return
        
        print("Connection successful! Starting assistant...")
        assistant = DatabaseAssistant()
        
        print("\nReady to explore your data! Ask me anything in plain English.")
        print("Examples: 'How many customers do I have?' or 'Show top products as pie chart'")
        
        # Start the interactive session
        while True:
            try:
                user_input = input("\nWhat would you like to know? ").strip()
                
                if not user_input:
                    continue
                
                # Handle exit gracefully
                if user_input.lower() in ['quit', 'exit', 'bye', 'goodbye']:
                    print("Thanks for using the Database Assistant! Goodbye!")
                    break
                
                # Process the query
                result = assistant.execute_query_and_get_results(user_input)
                
                if result['success']:
                    print(f"\n{result['message']}")
                    if result['data']:
                        print(f"Found {result['row_count']} results")
                        assistant.suggest_next_actions(
                            pd.DataFrame(result['data']), 
                            result.get('chart', {}).get('chart_type') if result['chart'] else None
                        )
                else:
                    print(f"\n{result['message']}")
                    
            except KeyboardInterrupt:
                print("\n\nGoodbye!")
                break
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                print(f"Oops! Something went wrong: {e}")
                continue
        
        assistant.cleanup()
        
    except Exception as e:
        logger.error(f"Main error: {e}")
        print(f"Something went wrong during startup: {e}")

if __name__ == "__main__":
    main()

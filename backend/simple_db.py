# simple_db.py
import pandas as pd
import logging

def get_db_response(user_query):
    """Process user query and return database results"""
    try:
        # For now, let's return some sample database-like responses
        query_lower = user_query.lower()
        
        if 'customer' in query_lower:
            return "Found 150 customers in the database. Top customers by sales: ABC Corp ($50K), XYZ Ltd ($45K), Tech Solutions ($40K)"
        elif 'product' in query_lower:
            return "Database contains 89 products across 12 categories. Best sellers: Widget A (234 units), Gadget B (189 units)"
        elif 'sales' in query_lower or 'revenue' in query_lower:
            return "Total sales this month: $125,430. Last month: $118,950. Growth: +5.4%"
        else:
            return f"Analyzing your query: '{user_query}'. Database contains customers, products, orders, and sales data. What would you like to know?"
            
    except Exception as e:
        return f"Database error: {str(e)}"

from flask import Flask, request, jsonify
from flask_cors import CORS
import logging
import os
import sys
import traceback

app = Flask(__name__)
CORS(app)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Global instance
db_assistant = None

def initialize_assistant():
    """Initialize the database assistant with better error handling"""
    global db_assistant
    try:
        if db_assistant is None:
            # Import here to avoid import issues
            sys.path.append(os.path.dirname(__file__))
            
            # Try to import your database assistant
            try:
                from db_assistant import DatabaseAssistant  # Change this to match your actual file
                db_assistant = DatabaseAssistant()
                logger.info("Database Assistant initialized successfully")
                return True
            except ImportError as e:
                logger.error(f"Import error: {e}")
                # Fallback - create a mock assistant for testing
                db_assistant = MockDatabaseAssistant()
                logger.warning("Using mock assistant due to import issues")
                return True
        return True
    except Exception as e:
        logger.error(f"Failed to initialize assistant: {e}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        return False

class MockDatabaseAssistant:
    """Mock assistant for testing when imports fail"""
    def get_response_from_db_assistant(self, query):
        return f"Mock response for: {query}. Database assistant is not fully configured yet."

@app.route('/', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "message": "Database Assistant API is running!",
        "version": "1.0",
        "python_version": sys.version
    })

@app.route('/query', methods=['POST'])
def handle_query():
    """Handle database queries from Flutter app"""
    try:
        # Get the query from request
        data = request.get_json()
        if not data or 'query' not in data:
            return jsonify({
                "error": "Missing 'query' parameter",
                "success": False
            }), 400
        
        user_query = data['query'].strip()
        if not user_query:
            return jsonify({
                "error": "Empty query",
                "success": False
            }), 400
        
        logger.info(f"Received query: {user_query}")
        
        # Initialize assistant if needed
        if not initialize_assistant():
            return jsonify({
                "error": "Failed to initialize database assistant",
                "success": False
            }), 500
        
        # Get response from your existing assistant
        try:
            response = db_assistant.get_response_from_db_assistant(user_query)
            logger.info(f"Generated response successfully")
        except Exception as e:
            logger.error(f"Error processing query: {e}")
            response = f"I encountered an error processing your request: {str(e)}"
        
        return jsonify({
            "response": response,
            "success": True,
            "query": user_query
        })
        
    except Exception as e:
        logger.error(f"Query handling error: {e}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        return jsonify({
            "error": f"Internal server error: {str(e)}",
            "success": False
        }), 500

@app.route('/test', methods=['GET'])
def test_connection():
    """Test database connection"""
    try:
        if not initialize_assistant():
            return jsonify({
                "error": "Failed to initialize assistant",
                "success": False
            }), 500
        
        # Test with a simple query
        try:
            test_response = db_assistant.get_response_from_db_assistant("test connection")
            status = "Connection successful!"
        except Exception as e:
            test_response = f"Test failed: {str(e)}"
            status = "Connection test encountered issues"
        
        return jsonify({
            "message": status,
            "test_response": test_response,
            "success": True,
            "environment": {
                "python_version": sys.version,
                "platform": sys.platform,
                "cwd": os.getcwd(),
                "env_vars": list(os.environ.keys())[:10]  # First 10 env vars
            }
        })
        
    except Exception as e:
        logger.error(f"Test connection error: {e}")
        return jsonify({
            "error": f"Connection test failed: {str(e)}",
            "success": False
        }), 500

@app.route('/debug', methods=['GET'])
def debug_info():
    """Debug endpoint to check deployment status"""
    return jsonify({
        "message": "Debug info",
        "python_version": sys.version,
        "platform": sys.platform,
        "current_directory": os.getcwd(),
        "files_in_directory": os.listdir('.') if os.path.exists('.') else [],
        "environment_variables": {
            "PORT": os.environ.get('PORT', 'Not set'),
            "GOOGLE_API_KEY": "Set" if os.environ.get('GOOGLE_API_KEY') else "Not set",
            "DB_HOST": "Set" if os.environ.get('DB_HOST') else "Not set"
        },
        "sys_path": sys.path[:5]  # First 5 paths
    })

if __name__ == '__main__':
    # Railway will set PORT environment variable
    port = int(os.environ.get('PORT', 5000))
    
    logger.info(f"Starting Flask app on port {port}")
    logger.info(f"Python version: {sys.version}")
    logger.info(f"Current directory: {os.getcwd()}")
    
    app.run(host="0.0.0.0", port=port, debug=True)


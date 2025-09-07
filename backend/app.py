from flask import Flask, jsonify
import os
import sys

app = Flask(__name__)

@app.route('/')
def health():
    return jsonify({
        "status": "healthy",
        "message": "Minimal test app is running!",
        "python_version": sys.version,
        "port": os.environ.get('PORT', 'Not set'),
        "env_vars": list(os.environ.keys())[:10]  # First 10 env vars for debugging
    })

@app.route('/test')
def test():
    return jsonify({"test": "This endpoint works!"})

if __name__ == '__main__':
    # Handle PORT environment variable properly
    port_env = os.environ.get('PORT', '5000')
    print(f"PORT environment variable: {port_env}")
    
    try:
        port = int(port_env)
        print(f"Successfully parsed port: {port}")
    except (ValueError, TypeError):
        print(f"Failed to parse port '{port_env}', using default 5000")
        port = 5000
    
    print(f"Starting Flask app on 0.0.0.0:{port}")
    app.run(host='0.0.0.0', port=port, debug=False)

#!/bin/bash
set -e

echo "🚀 Starting Neural Pulse AI Backend with Ollama + Phi-3 Mini"

# Function to cleanup on exit
cleanup() {
    echo "🛑 Shutting down services..."
    kill $OLLAMA_PID 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# Start Ollama in the background
echo "📡 Starting Ollama service..."
export OLLAMA_HOST=0.0.0.0:11434
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready with health check
echo "⏳ Waiting for Ollama to initialize..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✅ Ollama is ready!"
        break
    fi
    echo "  Attempt $i/30 - waiting for Ollama..."
    sleep 2
done

# Pull phi3:mini model if not already available
echo "📥 Ensuring Phi-3 Mini model is available..."
if ! ollama list | grep -q "phi3:mini"; then
    echo "  Downloading Phi-3 Mini model..."
    ollama pull phi3:mini
else
    echo "  Phi-3 Mini model already available"
fi

# Verify model is loaded
echo "✅ Available models:"
ollama list

# Start the Flask application
echo "🌐 Starting Flask application..."
python app_ollama.py &
FLASK_PID=$!

# Wait for either process to exit
wait $FLASK_PID
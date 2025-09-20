#!/bin/bash

echo "🚀 Starting Neural Pulse AI Backend with Ollama + Phi-3 Mini"

# Start Ollama in the background
echo "📡 Starting Ollama service..."
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
echo "⏳ Waiting for Ollama to initialize..."
sleep 15

# Pull phi3:mini model if not already available
echo "📥 Ensuring Phi-3 Mini model is available..."
ollama pull phi3:mini

# Verify model is loaded
echo "✅ Verifying model availability..."
ollama list

# Start the Flask application
echo "🌐 Starting Flask application..."
python app_ollama.py

# If Flask exits, also kill Ollama
kill $OLLAMA_PID 2>/dev/null
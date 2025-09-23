#!/bin/bash

# Start Ollama in the background
echo "Starting Ollama..."
ollama serve &

# Wait for Ollama to be ready
echo "Waiting for Ollama to be ready..."
sleep 10

# Pull the phi3:mini model
echo "Pulling phi3:mini model..."
ollama pull phi3:mini

# Start Flask app
echo "Starting Flask app..."
python app.py
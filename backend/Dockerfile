FROM python:3.11-slim

WORKDIR /app

# Install system dependencies including Ollama
RUN apt-get update && apt-get install -y curl && \
    # Install Ollama
    curl -fsSL https://ollama.ai/install.sh | sh && \
    rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose ports
EXPOSE 8000
EXPOSE 11434

# Set environment
ENV PYTHONUNBUFFERED=1

# Start script to run both Ollama and Flask
COPY start.sh .
RUN chmod +x start.sh

CMD ["./start.sh"]
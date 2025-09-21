# Use a Python base image and install Ollama differently
FROM python:3.11-slim

# Install system dependencies including glibc and other requirements
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    wget \
    ca-certificates \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Download and install Ollama binary with verification
RUN curl -L https://github.com/ollama/ollama/releases/download/v0.1.47/ollama-linux-amd64 -o /tmp/ollama && \
    chmod +x /tmp/ollama && \
    mv /tmp/ollama /usr/local/bin/ollama && \
    /usr/local/bin/ollama --version

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Make start script executable
RUN chmod +x start.sh

# Expose ports
EXPOSE 8000 11434

# Environment variables
ENV OLLAMA_HOST=0.0.0.0:11434
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
  CMD curl -f http://localhost:8000/system-status || exit 1

# Start both Ollama and the Flask app
CMD ["./start.sh"]
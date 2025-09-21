# Use Python base image - skip Ollama for now, use cloud AI instead
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    wget \
    ca-certificates \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Remove start.sh dependency for clean deployment

# Expose port
EXPOSE 8000

# Environment variables
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
  CMD curl -f http://localhost:8000/system-status || exit 1

# Start the Flask app without Ollama (use Gemini AI instead)
CMD ["python", "app.py"]
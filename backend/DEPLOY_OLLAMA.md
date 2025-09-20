# 🚀 Neural Pulse AI with Ollama + Phi-3 Mini on Railway

## 📋 Deployment Guide

### 1. **Railway Project Setup**
```bash
# Install Railway CLI
npm install -g @railway/cli

# Login to Railway
railway login

# Deploy to Railway
railway up --dockerfile Dockerfile.ollama
```

### 2. **Environment Variables**
Set these in your Railway dashboard:

```env
# Database (your existing Supabase config)
DB_HOST=aws-1-eu-west-2.pooler.supabase.com
DB_USER=postgres.chdjmbylbqdsavazecll
DB_PASSWORD=Hexen2002_23
DB_NAME=postgres
DB_PORT=6543

# Google API (if keeping as fallback)
GOOGLE_API_KEY=AIzaSyDVmC3DZNqvW6LbJ8ofxli5kpNUzcaGLOo

# Ollama Configuration
OLLAMA_HOST=0.0.0.0:11434
OLLAMA_MODELS=phi3:mini

# Flask
SECRET_KEY=your-secret-key-change-this-in-production
PORT=8000
```

### 3. **Resource Requirements**
- **Memory**: 4GB (minimum for Phi-3 Mini)
- **CPU**: 2 vCPUs
- **Storage**: 2GB (for model storage)

### 4. **API Endpoints**

#### Enhanced Query Endpoint
```bash
POST /query
{
  "query": "Who is my top customer?",
  "conversation_history": []
}
```

**Response:**
```json
{
  "success": true,
  "message": "Your top customer is Ahmed Hassan with total spending of $2,300...",
  "model": "phi3:mini",
  "tokens": 156,
  "business_context": true
}
```

#### Health Check
```bash
GET /ollama/health
```

**Response:**
```json
{
  "ollama_available": true,
  "model": "phi3:mini",
  "status": "ready"
}
```

#### Test Endpoint
```bash
POST /ollama/test
{
  "query": "Hello, test the AI"
}
```

### 5. **Bilingual Support**

The Phi-3 Mini model supports both English and Arabic:

**English Query:**
```json
{
  "query": "What's my monthly revenue trend?"
}
```

**Arabic Query:**
```json
{
  "query": "ما هو اتجاه إيراداتي الشهرية؟"
}
```

### 6. **Performance Optimization**

#### Model Specifications
- **Phi-3 Mini**: 3.8B parameters
- **Memory Usage**: ~2.5GB
- **Response Time**: 1-3 seconds
- **Context Length**: 4K tokens

#### Scaling Options
- **Upgrade RAM** to 8GB for faster responses
- **Add more CPU cores** for concurrent requests
- **Consider Phi-3 Medium** for better quality (requires 8GB RAM)

### 7. **Monitoring & Debugging**

#### Check Logs
```bash
railway logs
```

#### Test Local Development
```bash
# Build Docker image
docker build -f Dockerfile.ollama -t neural-pulse-ollama .

# Run locally
docker run -p 8000:8000 -p 11434:11434 neural-pulse-ollama
```

#### Health Checks
- Ollama: `http://localhost:11434/api/tags`
- Flask: `http://localhost:8000/ollama/health`

### 8. **Deployment Commands**

```bash
# Deploy to Railway
cd backend
railway up --dockerfile Dockerfile.ollama

# Set environment variables
railway env set DB_HOST=aws-1-eu-west-2.pooler.supabase.com
railway env set DB_USER=postgres.chdjmbylbqdsavazecll
railway env set DB_PASSWORD=Hexen2002_23
railway env set OLLAMA_HOST=0.0.0.0:11434

# Monitor deployment
railway logs --tail
```

### 9. **Expected Startup Sequence**

1. 🐳 Docker container starts
2. 📡 Ollama service initializes
3. 📥 Phi-3 Mini model downloads (~2.2GB)
4. ✅ Model loads into memory
5. 🌐 Flask app starts
6. 🚀 API ready for requests

**Total startup time**: 3-5 minutes (first deployment)
**Subsequent starts**: 30-60 seconds

### 10. **Integration with Flutter App**

Update your Flutter app's API endpoint:
```dart
// In lib/main.dart
static const String baseUrl = 'https://your-railway-app.railway.app';
```

The `/query` endpoint will now use Phi-3 Mini for intelligent, context-aware responses!

## 🎯 **Benefits**
- ✅ **No API costs** - runs entirely on Railway
- ✅ **Bilingual support** - English + Arabic
- ✅ **Real business data** - analyzes your Supabase data
- ✅ **Fast responses** - 1-3 seconds
- ✅ **Privacy** - all processing on your server
- ✅ **Smart context** - uses actual customer/revenue data
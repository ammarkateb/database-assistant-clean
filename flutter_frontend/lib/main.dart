import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart AI Assistant',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      home: const SmartAssistantPage(),
    );
  }
}

class SmartAssistantPage extends StatefulWidget {
  const SmartAssistantPage({super.key});

  @override
  State<SmartAssistantPage> createState() => _SmartAssistantPageState();
}

class _SmartAssistantPageState extends State<SmartAssistantPage> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;

  // Your Railway URL
  final String apiUrl = 'https://database-assistant-clean-production.up.railway.app';

  @override
  void initState() {
    super.initState();
    _addMessage('AI', 'Hello! I\'m your smart AI assistant. I can help you with:\n\n• Database queries (customers, products, sales)\n• General questions about anything\n• Creating charts and reports\n\nWhat would you like to know?', 'assistant');
  }

  void _addMessage(String sender, String message, String type) {
    setState(() {
      _messages.add(ChatMessage(sender: sender, message: message, type: type));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendQuery() async {
    final String query = _queryController.text.trim();
    
    if (query.isEmpty) return;
    
    // Add user message
    _addMessage('You', query, 'user');
    _queryController.clear();

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/query'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({'query': query}),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String responseText = data['response'] ?? 'No response received';
        String responseType = data['type'] ?? 'unknown';
        String source = data['source'] ?? 'unknown';
        
        // Format response based on type
        String formattedResponse = _formatResponse(responseText, responseType, source);
        
        _addMessage('AI', formattedResponse, responseType);
      } else {
        _addMessage('AI', 'Sorry, I encountered an error. Please try again.', 'error');
      }
    } catch (e) {
      _addMessage('AI', 'Connection error. Please check your internet connection and try again.', 'error');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatResponse(String response, String type, String source) {
    switch (type) {
      case 'database':
        return '📊 DATABASE RESULT:\n\n$response\n\n💡 This data comes from your PostgreSQL database.';
      case 'general':
        return '🤖 AI RESPONSE:\n\n$response';
      case 'database_fallback':
        return '⚠️ DATABASE UNAVAILABLE:\n\n$response';
      default:
        return response;
    }
  }

  Widget _buildMessageBubble(ChatMessage message) {
    bool isUser = message.sender == 'You';
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: _getTypeColor(message.type),
              child: Icon(
                _getTypeIcon(message.type),
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue[600] : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser) ...[
                    Text(
                      message.sender,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getTypeColor(message.type),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    message.message,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Icon(Icons.person, size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'database':
        return Colors.green;
      case 'general':
        return Colors.purple;
      case 'assistant':
        return Colors.blue;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'database':
        return Icons.storage;
      case 'general':
        return Icons.psychology;
      case 'assistant':
        return Icons.assistant;
      case 'error':
        return Icons.error;
      default:
        return Icons.smart_toy;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart AI Assistant'),
        backgroundColor: Colors.blue[700],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[700]!, Colors.blue[50]!],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 5,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      decoration: InputDecoration(
                        hintText: 'Ask me anything...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendQuery(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue[600],
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _isLoading ? null : _sendQuery,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Smart AI Assistant'),
        content: const Text(
          'This app can help you with:\n\n'
          '📊 Database Questions:\n'
          '• Customer information\n'
          '• Product data\n'
          '• Sales reports\n'
          '• Charts and analytics\n\n'
          '🤖 General Questions:\n'
          '• Any topic you\'re curious about\n'
          '• Explanations and advice\n'
          '• Problem solving\n\n'
          'Just type your question and I\'ll figure out how to help!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String sender;
  final String message;
  final String type;

  ChatMessage({required this.sender, required this.message, required this.type});
}
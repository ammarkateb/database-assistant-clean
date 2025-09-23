import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_database.dart';
import 'sync_manager.dart';
import 'api_service.dart';

class DataService {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  final SyncManager _syncManager = SyncManager();
  final ApiService _apiService = ApiService();

  // Initialize data service
  Future<void> initialize() async {
    await _syncManager.initialize();
  }

  // User operations
  Future<Map<String, dynamic>?> login(String username, String password) async {
    try {
      // Always check local database first for cached login
      final localUser = await LocalDatabase.getUser(username);

      if (_syncManager.isOnline) {
        // Try online login
        try {
          final response = await _apiService.login(username, password);
          if (response['success']) {
            final userData = response['user'];

            // Update/insert user in local database
            if (localUser != null) {
              await LocalDatabase.updateUser(localUser['id'], userData);
            } else {
              await LocalDatabase.insertUser(userData);
            }

            return userData;
          }
        } catch (e) {
          debugPrint('DataService: Online login failed, trying offline - $e');
        }
      }

      // Fall back to offline login
      if (localUser != null) {
        // Verify password hash
        if (_verifyPasswordHash(password, localUser['password_hash'])) {
          debugPrint('DataService: Offline login successful');
          return localUser;
        }
      }

      return null;
    } catch (e) {
      debugPrint('DataService: Login error - $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> register(String username, String email, String password) async {
    try {
      if (_syncManager.isOnline) {
        // Try online registration
        final response = await _apiService.register(username, email, password);
        if (response['success']) {
          final userData = response['user'];
          await LocalDatabase.insertUser(userData);
          return userData;
        }
      } else {
        // Offline registration - store locally and sync later
        final userData = {
          'username': username,
          'email': email,
          'password_hash': _hashPassword(password),
          'created_at': DateTime.now().toIso8601String(),
        };

        final userId = await LocalDatabase.insertUser(userData);
        userData['id'] = userId.toString();

        debugPrint('DataService: User registered offline, will sync when online');
        return userData;
      }
    } catch (e) {
      debugPrint('DataService: Registration error - $e');
    }
    return null;
  }

  // Chat operations
  Future<int> createChatSession(int userId, {String? sessionName}) async {
    final sessionData = {
      'user_id': userId,
      'session_name': sessionName ?? 'Chat ${DateTime.now().toLocal()}',
      'created_at': DateTime.now().toIso8601String(),
    };

    // Always save locally first
    final sessionId = await LocalDatabase.insertChatSession(sessionData);

    // Try to sync with server if online
    if (_syncManager.isOnline) {
      try {
        final response = await _apiService.createChatSession(sessionData);
        if (response['success'] && response['session_id'] != null) {
          // Update local record with server ID if different
          if (response['session_id'] != sessionId) {
            await LocalDatabase.updateUser(sessionId, {'server_id': response['session_id']});
          }
        }
      } catch (e) {
        debugPrint('DataService: Failed to sync chat session - $e');
      }
    }

    return sessionId;
  }

  Future<List<Map<String, dynamic>>> getChatSessions(int userId) async {
    // Always get from local database for fast response
    final localSessions = await LocalDatabase.getChatSessions(userId);

    // If online, try to sync recent sessions
    if (_syncManager.isOnline && !_syncManager.isSyncing) {
      try {
        await _syncManager.forcSync();
      } catch (e) {
        debugPrint('DataService: Failed to sync chat sessions - $e');
      }
    }

    return localSessions;
  }

  Future<int> sendChatMessage(int sessionId, int userId, String message) async {
    final messageData = {
      'session_id': sessionId,
      'user_id': userId,
      'message': message,
      'message_type': 'text',
      'created_at': DateTime.now().toIso8601String(),
    };

    // Save locally first
    final messageId = await LocalDatabase.insertChatMessage(messageData);

    // Try to get AI response
    String? response;
    if (_syncManager.isOnline) {
      try {
        final aiResponse = await _apiService.sendChatMessage(message);
        if (aiResponse['success']) {
          response = aiResponse['response'];
        }
      } catch (e) {
        debugPrint('DataService: Failed to get online AI response - $e');
      }
    }

    // If no online response, use offline fallback
    if (response == null) {
      response = await _getOfflineAIResponse(message);
    }

    // Update message with response
    await LocalDatabase.database.then((db) => db.update(
      'chat_messages',
      {'response': response},
      where: 'id = ?',
      whereArgs: [messageId],
    ));

    return messageId;
  }

  Future<List<Map<String, dynamic>>> getChatMessages(int sessionId) async {
    return await LocalDatabase.getChatMessages(sessionId);
  }

  // Database query operations
  Future<Map<String, dynamic>> executeDatabaseQuery(int userId, String queryText) async {
    final queryData = {
      'user_id': userId,
      'query_text': queryText,
      'created_at': DateTime.now().toIso8601String(),
    };

    Map<String, dynamic> result = {
      'success': false,
      'data': [],
      'message': 'Query failed',
    };

    if (_syncManager.isOnline) {
      try {
        result = await _apiService.executeDatabaseQuery(queryText);
        queryData['sql_query'] = result['sql_query'];
        queryData['result_data'] = jsonEncode(result['data']);
      } catch (e) {
        debugPrint('DataService: Online query failed - $e');
        result['message'] = 'Online query failed, trying offline cache';
      }
    }

    // If online query failed or we're offline, try local cache
    if (!result['success']) {
      result = await _getOfflineQueryResponse(queryText);
      queryData['result_data'] = jsonEncode(result['data']);
    }

    // Save query to local database
    await LocalDatabase.insertDatabaseQuery(queryData);

    return result;
  }

  Future<List<Map<String, dynamic>>> getDatabaseQueryHistory(int userId) async {
    return await LocalDatabase.getDatabaseQueries(userId);
  }

  // Offline AI response (placeholder implementation)
  Future<String> _getOfflineAIResponse(String message) async {
    // This is a placeholder. In Week 2, we'll implement local AI
    return "I'm currently offline, but I've saved your message. I'll respond when I'm back online!";
  }

  // Offline database query response
  Future<Map<String, dynamic>> _getOfflineQueryResponse(String queryText) async {
    // This is a placeholder. Could cache common query patterns
    return {
      'success': false,
      'data': [],
      'message': 'Database queries require internet connection. Your query has been saved and will be executed when online.',
      'sql_query': null,
    };
  }

  // Utility functions
  String _hashPassword(String password) {
    // Simple hash implementation - use proper hashing in production
    return password.hashCode.toString();
  }

  bool _verifyPasswordHash(String password, String hash) {
    return _hashPassword(password) == hash;
  }

  // Invoice operations
  Future<List<Map<String, dynamic>>> getInvoices(int userId) async {
    if (_syncManager.isOnline && !await _syncManager.shouldWorkOffline()) {
      // Try to get fresh data from server and cache it
      try {
        final response = await _apiService.getInvoices(userId);
        if (response['success']) {
          final invoices = response['invoices'] as List;

          // Cache invoices locally
          for (final invoice in invoices) {
            await LocalDatabase.insertInvoice(invoice);
          }

          return invoices.cast<Map<String, dynamic>>();
        }
      } catch (e) {
        debugPrint('DataService: Failed to fetch invoices online, using cache - $e');
      }
    }

    // Return cached data
    return await LocalDatabase.getInvoices(userId);
  }

  Future<Map<String, dynamic>> createInvoice(Map<String, dynamic> invoiceData) async {
    // Always save to local database first
    final localId = await LocalDatabase.insertInvoice(invoiceData);

    if (_syncManager.isOnline && !await _syncManager.shouldWorkOffline()) {
      try {
        final response = await _apiService.createInvoice(invoiceData);
        if (response['success']) {
          // Update local record with server ID
          final serverInvoice = response['invoice'];
          await LocalDatabase.updateInvoice(localId, serverInvoice);
          return serverInvoice;
        }
      } catch (e) {
        debugPrint('DataService: Failed to create invoice online, queued for sync - $e');
      }
    }

    // Return local invoice data
    invoiceData['id'] = localId;
    return {'success': true, 'invoice': invoiceData};
  }

  Future<Map<String, dynamic>> updateInvoice(int invoiceId, Map<String, dynamic> updates) async {
    // Always update local database first
    await LocalDatabase.updateInvoice(invoiceId, updates);

    if (_syncManager.isOnline && !await _syncManager.shouldWorkOffline()) {
      try {
        final response = await _apiService.updateInvoice(invoiceId, updates);
        if (response['success']) {
          return response;
        }
      } catch (e) {
        debugPrint('DataService: Failed to update invoice online, queued for sync - $e');
      }
    }

    return {'success': true, 'message': 'Invoice updated locally'};
  }

  Future<Map<String, dynamic>> deleteInvoice(int invoiceId) async {
    // Delete from local database
    await LocalDatabase.deleteInvoice(invoiceId);

    if (_syncManager.isOnline && !await _syncManager.shouldWorkOffline()) {
      try {
        final response = await _apiService.deleteInvoice(invoiceId);
        if (response['success']) {
          return response;
        }
      } catch (e) {
        debugPrint('DataService: Failed to delete invoice online, queued for sync - $e');
      }
    }

    return {'success': true, 'message': 'Invoice deleted locally'};
  }

  // Message operations
  Future<List<Map<String, dynamic>>> getMessages({int? sessionId, int? userId}) async {
    if (_syncManager.isOnline && !await _syncManager.shouldWorkOffline()) {
      try {
        final response = await _apiService.getMessages(sessionId: sessionId, userId: userId);
        if (response['success']) {
          final messages = response['messages'] as List;

          // Cache messages locally
          for (final message in messages) {
            await LocalDatabase.insertMessage(message);
          }

          return messages.cast<Map<String, dynamic>>();
        }
      } catch (e) {
        debugPrint('DataService: Failed to fetch messages online, using cache - $e');
      }
    }

    // Return cached data
    return await LocalDatabase.getMessages(sessionId: sessionId, userId: userId);
  }

  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> messageData) async {
    // Always save to local database first
    final localId = await LocalDatabase.insertMessage(messageData);

    if (_syncManager.isOnline && !await _syncManager.shouldWorkOffline()) {
      try {
        final response = await _apiService.sendMessage(messageData);
        if (response['success']) {
          // Update local record with server response
          final serverMessage = response['message'];
          await LocalDatabase.updateMessage(localId, serverMessage);
          return serverMessage;
        }
      } catch (e) {
        debugPrint('DataService: Failed to send message online, queued for sync - $e');
      }
    }

    // Return local message data
    messageData['id'] = localId;
    return {'success': true, 'message': messageData};
  }

  // Face encoding operations
  Future<void> updateFaceEncoding(int userId, String faceEncoding) async {
    await LocalDatabase.updateUser(userId, {'face_encoding': faceEncoding});
  }

  Future<String?> getFaceEncoding(int userId) async {
    final db = await LocalDatabase.database;
    final results = await db.query(
      'users',
      columns: ['face_encoding'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (results.isNotEmpty && results.first['face_encoding'] != null) {
      return results.first['face_encoding'] as String;
    }

    return null;
  }

  // Sync status methods
  Stream<SyncStatus> get syncStatusStream => _syncManager.syncStatusStream;
  Stream<bool> get connectivityStream => _syncManager.connectivityStream;
  bool get isOnline => _syncManager.isOnline;
  bool get isSyncing => _syncManager.isSyncing;

  Future<void> forceSync() async {
    await _syncManager.forcSync();
  }

  Future<SyncStats> getSyncStats() async {
    return await _syncManager.getSyncStats();
  }

  Future<void> setOfflineMode(bool enabled) async {
    await _syncManager.setOfflineMode(enabled);
  }

  Future<bool> shouldWorkOffline() async {
    return await _syncManager.shouldWorkOffline();
  }

  // Clear all local data (for logout)
  Future<void> clearAllData() async {
    await LocalDatabase.clearAllData();
  }

  // Chat query operations (handles both online and offline)
  Future<Map<String, dynamic>> sendQuery(String query, {List<dynamic>? conversationHistory}) async {
    try {
      if (_syncManager.isOnline && !await _syncManager.shouldWorkOffline()) {
        // Try online AI query first
        try {
          final response = await _apiService.sendQuery(query, conversationHistory: conversationHistory);
          if (response['success']) {
            // Store the query and response locally
            await LocalDatabase.insertDatabaseQuery({
              'user_id': 1, // TODO: Get actual user ID
              'query_text': query,
              'result_data': response['message'],
            });
            return response;
          }
        } catch (e) {
          debugPrint('DataService: Failed to get online AI response - $e');
        }
      }

      // Fallback to offline response
      return await _getOfflineResponse(query);
    } catch (e) {
      return {
        'success': false,
        'message': 'Query failed: $e'
      };
    }
  }

  // Generate offline AI response
  Future<Map<String, dynamic>> _getOfflineResponse(String query) async {
    // Store the query locally
    await LocalDatabase.insertDatabaseQuery({
      'user_id': 1, // TODO: Get actual user ID
      'query_text': query,
      'result_data': 'Offline response',
    });

    // Generate a helpful offline response
    String response;
    final lowerQuery = query.toLowerCase();

    if (lowerQuery.contains('invoice') || lowerQuery.contains('bill')) {
      response = "I can help you with invoices when you're back online. In the meantime, you can view your cached invoices in the invoice section.";
    } else if (lowerQuery.contains('customer') || lowerQuery.contains('client')) {
      response = "Customer data is available offline. Your cached customer information is available in the system.";
    } else if (lowerQuery.contains('revenue') || lowerQuery.contains('sales') || lowerQuery.contains('profit')) {
      response = "Financial reports require online connectivity for the most up-to-date data. Please connect to the internet for current revenue information.";
    } else {
      response = "I'm currently working in offline mode. Some features may be limited, but I can help you with basic operations and cached data.";
    }

    return {
      'success': true,
      'message': response,
      'offline': true
    };
  }

  // Dispose resources
  void dispose() {
    _syncManager.dispose();
  }
}

// Update your existing ApiService to work with this new architecture
extension ApiServiceExtension on ApiService {
  Future<Map<String, dynamic>> login(String username, String password) async {
    // Implement your existing login logic here
    // This should return: {'success': bool, 'user': Map<String, dynamic>}
    throw UnimplementedError('Implement existing login logic');
  }

  Future<Map<String, dynamic>> register(String username, String email, String password) async {
    // Implement your existing registration logic here
    throw UnimplementedError('Implement existing registration logic');
  }

  Future<Map<String, dynamic>> createChatSession(Map<String, dynamic> sessionData) async {
    // Implement chat session creation
    throw UnimplementedError('Implement chat session creation');
  }

  Future<Map<String, dynamic>> sendChatMessage(String message) async {
    // Implement your existing AI chat logic here
    throw UnimplementedError('Implement existing AI chat logic');
  }

  Future<Map<String, dynamic>> sendQuery(String query, {List<dynamic>? conversationHistory}) async {
    return await ApiService.sendQuery(query, conversationHistory: conversationHistory);
  }

  Future<Map<String, dynamic>> executeDatabaseQuery(String queryText) async {
    // Implement your existing database query logic here
    throw UnimplementedError('Implement existing database query logic');
  }

  // Invoice API methods
  Future<Map<String, dynamic>> getInvoices(int userId) async {
    // Implement invoice fetching from your existing API
    throw UnimplementedError('Implement invoice fetching');
  }

  Future<Map<String, dynamic>> createInvoice(Map<String, dynamic> invoiceData) async {
    // Implement invoice creation via your existing API
    throw UnimplementedError('Implement invoice creation');
  }

  Future<Map<String, dynamic>> updateInvoice(int invoiceId, Map<String, dynamic> updates) async {
    // Implement invoice updating via your existing API
    throw UnimplementedError('Implement invoice updating');
  }

  Future<Map<String, dynamic>> deleteInvoice(int invoiceId) async {
    // Implement invoice deletion via your existing API
    throw UnimplementedError('Implement invoice deletion');
  }

  // Message API methods
  Future<Map<String, dynamic>> getMessages({int? sessionId, int? userId}) async {
    // Implement message fetching from your existing API
    throw UnimplementedError('Implement message fetching');
  }

  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> messageData) async {
    // Implement message sending via your existing API
    throw UnimplementedError('Implement message sending');
  }
}
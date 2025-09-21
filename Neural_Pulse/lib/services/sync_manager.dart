import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'local_database.dart';

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  // Configuration
  static const String baseUrl = 'http://192.168.8.155:5000';
  static const Duration syncInterval = Duration(minutes: 5);
  static const int maxRetryAttempts = 3;

  // State management
  bool _isOnline = false;
  bool _isSyncing = false;
  Timer? _syncTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Stream controllers for state updates
  final _connectivityController = StreamController<bool>.broadcast();
  final _syncStatusController = StreamController<SyncStatus>.broadcast();

  // Getters for streams
  Stream<bool> get connectivityStream => _connectivityController.stream;
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;

  // Initialize sync manager
  Future<void> initialize() async {
    await _checkInitialConnectivity();
    _setupConnectivityListener();
    _setupPeriodicSync();

    if (_isOnline) {
      _performInitialSync();
    }
  }

  // Check initial connectivity
  Future<void> _checkInitialConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    _updateConnectivity([connectivityResult]);
  }

  // Setup connectivity listener
  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      _updateConnectivity([result]);
    });
  }

  // Update connectivity status
  void _updateConnectivity(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = results.any((result) => result != ConnectivityResult.none);

    if (wasOnline != _isOnline) {
      _connectivityController.add(_isOnline);

      if (_isOnline) {
        debugPrint('SyncManager: Device went online - starting sync');
        _triggerSync();
      } else {
        debugPrint('SyncManager: Device went offline');
        _updateSyncStatus(SyncStatus.offline);
      }
    }
  }

  // Setup periodic sync when online
  void _setupPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(syncInterval, (timer) {
      if (_isOnline && !_isSyncing) {
        _triggerSync();
      }
    });
  }

  // Trigger sync operation
  Future<void> _triggerSync() async {
    if (_isSyncing) {
      debugPrint('SyncManager: Sync already in progress');
      return;
    }

    _isSyncing = true;
    _updateSyncStatus(SyncStatus.syncing);

    try {
      await _performBidirectionalSync();
      _updateSyncStatus(SyncStatus.success);
      await LocalDatabase.setSetting('last_successful_sync', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('SyncManager: Sync failed - $e');
      _updateSyncStatus(SyncStatus.failed);
    } finally {
      _isSyncing = false;
    }
  }

  // Perform initial sync when app starts
  Future<void> _performInitialSync() async {
    try {
      final lastSync = await LocalDatabase.getSetting('last_full_sync');
      if (lastSync == null) {
        debugPrint('SyncManager: Performing first-time sync');
        await _downloadInitialData();
      } else {
        debugPrint('SyncManager: Performing incremental sync');
        await _triggerSync();
      }
    } catch (e) {
      debugPrint('SyncManager: Initial sync failed - $e');
    }
  }

  // Download initial data from server
  Future<void> _downloadInitialData() async {
    try {
      // This would typically download user data, chat history, etc.
      // For now, we'll just mark the initial sync as complete
      await LocalDatabase.setSetting('last_full_sync', DateTime.now().toIso8601String());
      debugPrint('SyncManager: Initial data download complete');
    } catch (e) {
      debugPrint('SyncManager: Initial data download failed - $e');
      rethrow;
    }
  }

  // Perform bidirectional sync
  Future<void> _performBidirectionalSync() async {
    debugPrint('SyncManager: Starting bidirectional sync');

    // Step 1: Upload local changes
    await _uploadLocalChanges();

    // Step 2: Download remote changes
    await _downloadRemoteChanges();

    // Step 3: Clean up sync queue
    await _cleanupSyncQueue();

    debugPrint('SyncManager: Bidirectional sync complete');
  }

  // Upload local changes to server
  Future<void> _uploadLocalChanges() async {
    final pendingItems = await LocalDatabase.getPendingSyncItems();

    for (final item in pendingItems) {
      try {
        await _uploadSyncItem(item);
        await LocalDatabase.removeSyncItem(item['id']);
      } catch (e) {
        debugPrint('SyncManager: Failed to upload item ${item['id']} - $e');
        await LocalDatabase.incrementSyncRetry(item['id']);

        // Remove items that have failed too many times
        if (item['retry_count'] >= maxRetryAttempts) {
          await LocalDatabase.removeSyncItem(item['id']);
          debugPrint('SyncManager: Removed item ${item['id']} after max retries');
        }
      }
    }
  }

  // Upload individual sync item
  Future<void> _uploadSyncItem(Map<String, dynamic> item) async {
    final tableName = item['table_name'];
    final operation = item['operation'];
    final data = jsonDecode(item['data']);

    String endpoint;
    String method;

    switch (tableName) {
      case 'users':
        endpoint = '/api/users';
        break;
      case 'chat_sessions':
        endpoint = '/api/chat-sessions';
        break;
      case 'chat_messages':
        endpoint = '/api/chat-messages';
        break;
      case 'messages':
        endpoint = '/api/messages';
        break;
      case 'invoices':
        endpoint = '/api/invoices';
        break;
      case 'database_queries':
        endpoint = '/api/database-queries';
        break;
      default:
        throw Exception('Unknown table: $tableName');
    }

    switch (operation) {
      case 'INSERT':
        method = 'POST';
        break;
      case 'UPDATE':
        method = 'PUT';
        endpoint = '$endpoint/${item['record_id']}';
        break;
      case 'DELETE':
        method = 'DELETE';
        endpoint = '$endpoint/${item['record_id']}';
        break;
      default:
        throw Exception('Unknown operation: $operation');
    }

    final response = await _makeHttpRequest(method, endpoint, data);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    // Mark as synced in local database
    if (operation != 'DELETE') {
      await LocalDatabase.markAsSynced(tableName, item['record_id']);
    }
  }

  // Download remote changes
  Future<void> _downloadRemoteChanges() async {
    final lastSync = await LocalDatabase.getSetting('last_sync_timestamp') ??
                    DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    try {
      // Download updates for each table
      await _downloadTableUpdates('users', lastSync);
      await _downloadTableUpdates('chat_sessions', lastSync);
      await _downloadTableUpdates('chat_messages', lastSync);
      await _downloadTableUpdates('messages', lastSync);
      await _downloadTableUpdates('invoices', lastSync);
      await _downloadTableUpdates('database_queries', lastSync);

      // Update last sync timestamp
      await LocalDatabase.setSetting('last_sync_timestamp', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('SyncManager: Download remote changes failed - $e');
      rethrow;
    }
  }

  // Download updates for specific table
  Future<void> _downloadTableUpdates(String tableName, String lastSync) async {
    final endpoint = '/api/sync/$tableName?since=$lastSync';
    final response = await _makeHttpRequest('GET', endpoint, null);

    if (response.statusCode == 200) {
      final updates = jsonDecode(response.body);

      for (final update in updates['data']) {
        await _applyRemoteUpdate(tableName, update);
      }
    }
  }

  // Apply remote update to local database
  Future<void> _applyRemoteUpdate(String tableName, Map<String, dynamic> update) async {
    final db = await LocalDatabase.database;

    // Check if record exists locally
    final existing = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [update['id']],
      limit: 1,
    );

    if (existing.isEmpty) {
      // Insert new record
      update['is_synced'] = 1;
      update['last_sync'] = DateTime.now().toIso8601String();
      await db.insert(tableName, update);
    } else {
      // Update existing record if remote is newer
      final localUpdated = DateTime.parse((existing.first['updated_at'] ?? existing.first['created_at']) as String);
      final remoteUpdated = DateTime.parse((update['updated_at'] ?? update['created_at']) as String);

      if (remoteUpdated.isAfter(localUpdated)) {
        update['is_synced'] = 1;
        update['last_sync'] = DateTime.now().toIso8601String();
        await db.update(tableName, update, where: 'id = ?', whereArgs: [update['id']]);
      }
    }
  }

  // Clean up old sync queue items
  Future<void> _cleanupSyncQueue() async {
    final db = await LocalDatabase.database;
    final cutoff = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();

    await db.delete(
      'sync_queue',
      where: 'created_at < ? AND retry_count >= ?',
      whereArgs: [cutoff, maxRetryAttempts],
    );
  }

  // Make HTTP request with proper headers
  Future<http.Response> _makeHttpRequest(String method, String endpoint, Map<String, dynamic>? data) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // Add authentication token if available
    final token = await _getAuthToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(url, headers: headers);
      case 'POST':
        return await http.post(url, headers: headers, body: jsonEncode(data));
      case 'PUT':
        return await http.put(url, headers: headers, body: jsonEncode(data));
      case 'DELETE':
        return await http.delete(url, headers: headers);
      default:
        throw Exception('Unsupported HTTP method: $method');
    }
  }

  // Get authentication token (implement based on your auth system)
  Future<String?> _getAuthToken() async {
    // This should integrate with your existing auth system
    // For now, return null - implement based on your auth flow
    return null;
  }

  // Update sync status
  void _updateSyncStatus(SyncStatus status) {
    _syncStatusController.add(status);
  }

  // Force sync (called manually)
  Future<void> forcSync() async {
    if (_isOnline) {
      await _triggerSync();
    } else {
      throw Exception('Cannot sync while offline');
    }
  }

  // Check if app should work in offline mode
  Future<bool> shouldWorkOffline() async {
    if (!_isOnline) return true;

    final offlineMode = await LocalDatabase.getSetting('offline_mode');
    return offlineMode == 'true';
  }

  // Set offline mode preference
  Future<void> setOfflineMode(bool enabled) async {
    await LocalDatabase.setSetting('offline_mode', enabled.toString());
  }

  // Get sync statistics
  Future<SyncStats> getSyncStats() async {
    final db = await LocalDatabase.database;

    final pendingCount = await db.rawQuery('SELECT COUNT(*) as count FROM sync_queue');
    final lastSync = await LocalDatabase.getSetting('last_successful_sync');

    return SyncStats(
      pendingSyncItems: pendingCount.first['count'] as int,
      lastSyncTime: lastSync != null ? DateTime.parse(lastSync) : null,
      isOnline: _isOnline,
      isSyncing: _isSyncing,
    );
  }

  // Dispose resources
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _connectivityController.close();
    _syncStatusController.close();
  }
}

// Enum for sync status
enum SyncStatus {
  idle,
  syncing,
  success,
  failed,
  offline,
}

// Class for sync statistics
class SyncStats {
  final int pendingSyncItems;
  final DateTime? lastSyncTime;
  final bool isOnline;
  final bool isSyncing;

  SyncStats({
    required this.pendingSyncItems,
    required this.lastSyncTime,
    required this.isOnline,
    required this.isSyncing,
  });

  @override
  String toString() {
    return 'SyncStats(pending: $pendingSyncItems, lastSync: $lastSyncTime, online: $isOnline, syncing: $isSyncing)';
  }
}
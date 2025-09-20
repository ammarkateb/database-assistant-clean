import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class LocalDatabase {
  static Database? _database;
  static const String dbName = 'neural_pulse.db';
  static const int dbVersion = 1;

  // Get database instance
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Initialize database
  static Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), dbName);
    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Create tables matching PostgreSQL schema
  static Future<void> _onCreate(Database db, int version) async {
    // Users table (matching your app's User model)
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        role TEXT NOT NULL,
        full_name TEXT,
        email TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        biometric_enabled INTEGER DEFAULT 0,
        face_auth_enabled INTEGER DEFAULT 0,
        last_synced TEXT,
        is_dirty INTEGER DEFAULT 0
      )
    ''');

    // Chat sessions table
    await db.execute('''
      CREATE TABLE chat_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        session_name TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        last_sync TEXT DEFAULT CURRENT_TIMESTAMP,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    // Chat messages table
    await db.execute('''
      CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        message TEXT NOT NULL,
        response TEXT,
        message_type TEXT DEFAULT 'text',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        last_sync TEXT DEFAULT CURRENT_TIMESTAMP,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES chat_sessions (id),
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    // Invoices table (matching your app's Invoice model)
    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        due_date TEXT,
        description TEXT,
        image_path TEXT,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        last_sync TEXT DEFAULT CURRENT_TIMESTAMP,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    // Messages table (matching your app's Message model)
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT NOT NULL,
        content TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        chart_data TEXT,
        session_id INTEGER,
        user_id INTEGER,
        last_sync TEXT DEFAULT CURRENT_TIMESTAMP,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES chat_sessions (id),
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    // Database queries table (for AI assistant)
    await db.execute('''
      CREATE TABLE database_queries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        query_text TEXT NOT NULL,
        sql_query TEXT,
        result_data TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        last_sync TEXT DEFAULT CURRENT_TIMESTAMP,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    // Sync queue table (tracks changes for syncing)
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        operation TEXT NOT NULL,
        data TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        retry_count INTEGER DEFAULT 0
      )
    ''');

    // App settings table
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Insert default settings
    await db.insert('app_settings', {
      'key': 'last_full_sync',
      'value': DateTime.now().toIso8601String(),
    });

    await db.insert('app_settings', {
      'key': 'offline_mode',
      'value': 'false',
    });
  }

  // Handle database upgrades
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future schema changes
    if (oldVersion < newVersion) {
      // Add migration logic here as needed
    }
  }

  // User operations
  static Future<int> insertUser(Map<String, dynamic> user) async {
    final db = await database;
    user['last_sync'] = DateTime.now().toIso8601String();
    user['is_synced'] = 0;
    return await db.insert('users', user);
  }

  static Future<Map<String, dynamic>?> getUser(String username) async {
    final db = await database;
    final results = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  static Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await database;
    final results = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  static Future<void> updateUser(int userId, Map<String, dynamic> updates) async {
    final db = await database;
    updates['updated_at'] = DateTime.now().toIso8601String();
    updates['is_synced'] = 0;
    await db.update('users', updates, where: 'id = ?', whereArgs: [userId]);

    // Add to sync queue
    await _addToSyncQueue('users', userId, 'UPDATE', updates);
  }

  // Chat operations
  static Future<int> insertChatSession(Map<String, dynamic> session) async {
    final db = await database;
    session['last_sync'] = DateTime.now().toIso8601String();
    session['is_synced'] = 0;
    int id = await db.insert('chat_sessions', session);

    // Add to sync queue
    await _addToSyncQueue('chat_sessions', id, 'INSERT', session);
    return id;
  }

  static Future<List<Map<String, dynamic>>> getChatSessions(int userId) async {
    final db = await database;
    return await db.query(
      'chat_sessions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
  }

  static Future<int> insertChatMessage(Map<String, dynamic> message) async {
    final db = await database;
    message['last_sync'] = DateTime.now().toIso8601String();
    message['is_synced'] = 0;
    int id = await db.insert('chat_messages', message);

    // Add to sync queue
    await _addToSyncQueue('chat_messages', id, 'INSERT', message);
    return id;
  }

  static Future<List<Map<String, dynamic>>> getChatMessages(int sessionId) async {
    final db = await database;
    return await db.query(
      'chat_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
  }

  // Invoice operations
  static Future<int> insertInvoice(Map<String, dynamic> invoice) async {
    final db = await database;
    invoice['last_sync'] = DateTime.now().toIso8601String();
    invoice['is_synced'] = 0;
    int id = await db.insert('invoices', invoice);

    // Add to sync queue
    await _addToSyncQueue('invoices', id, 'INSERT', invoice);
    return id;
  }

  static Future<List<Map<String, dynamic>>> getInvoices(int userId) async {
    final db = await database;
    return await db.query(
      'invoices',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
  }

  static Future<void> updateInvoice(int invoiceId, Map<String, dynamic> updates) async {
    final db = await database;
    updates['last_sync'] = DateTime.now().toIso8601String();
    updates['is_synced'] = 0;
    await db.update('invoices', updates, where: 'id = ?', whereArgs: [invoiceId]);

    // Add to sync queue
    await _addToSyncQueue('invoices', invoiceId, 'UPDATE', updates);
  }

  static Future<void> deleteInvoice(int invoiceId) async {
    final db = await database;
    await db.delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);

    // Add to sync queue
    await _addToSyncQueue('invoices', invoiceId, 'DELETE', {});
  }

  // Message operations
  static Future<int> insertMessage(Map<String, dynamic> message) async {
    final db = await database;
    message['last_sync'] = DateTime.now().toIso8601String();
    message['is_synced'] = 0;
    int id = await db.insert('messages', message);

    // Add to sync queue
    await _addToSyncQueue('messages', id, 'INSERT', message);
    return id;
  }

  static Future<List<Map<String, dynamic>>> getMessages({int? sessionId, int? userId}) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (sessionId != null) {
      whereClause = 'session_id = ?';
      whereArgs.add(sessionId);
    } else if (userId != null) {
      whereClause = 'user_id = ?';
      whereArgs.add(userId);
    }

    return await db.query(
      'messages',
      where: whereClause.isNotEmpty ? whereClause : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'timestamp ASC',
    );
  }

  static Future<void> updateMessage(int messageId, Map<String, dynamic> updates) async {
    final db = await database;
    updates['last_sync'] = DateTime.now().toIso8601String();
    updates['is_synced'] = 0;
    await db.update('messages', updates, where: 'id = ?', whereArgs: [messageId]);

    // Add to sync queue
    await _addToSyncQueue('messages', messageId, 'UPDATE', updates);
  }

  // Database query operations
  static Future<int> insertDatabaseQuery(Map<String, dynamic> query) async {
    final db = await database;
    query['last_sync'] = DateTime.now().toIso8601String();
    query['is_synced'] = 0;
    int id = await db.insert('database_queries', query);

    // Add to sync queue
    await _addToSyncQueue('database_queries', id, 'INSERT', query);
    return id;
  }

  static Future<List<Map<String, dynamic>>> getDatabaseQueries(int userId) async {
    final db = await database;
    return await db.query(
      'database_queries',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: 100,
    );
  }

  // Sync queue operations
  static Future<void> _addToSyncQueue(String tableName, int recordId, String operation, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('sync_queue', {
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation,
      'data': jsonEncode(data),
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    final db = await database;
    return await db.query(
      'sync_queue',
      orderBy: 'created_at ASC',
      limit: 50,
    );
  }

  static Future<void> removeSyncItem(int syncId) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [syncId]);
  }

  static Future<void> incrementSyncRetry(int syncId) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'retry_count': 'retry_count + 1'},
      where: 'id = ?',
      whereArgs: [syncId],
    );
  }

  // Settings operations
  static Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return results.isNotEmpty ? results.first['value'] as String? : null;
  }

  // Utility operations
  static Future<void> markAsSynced(String tableName, int recordId) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'is_synced': 1,
        'last_sync': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedRecords(String tableName) async {
    final db = await database;
    return await db.query(
      tableName,
      where: 'is_synced = ?',
      whereArgs: [0],
    );
  }

  static Future<void> clearAllData() async {
    final db = await database;
    await db.delete('chat_messages');
    await db.delete('chat_sessions');
    await db.delete('database_queries');
    await db.delete('sync_queue');
    await db.delete('users');
  }

  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
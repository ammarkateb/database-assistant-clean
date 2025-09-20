import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'data_service.dart';
import 'sync_manager.dart';

class AuthService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _userIdKey = 'user_id';
  static const String _usernameKey = 'username';
  static const String _emailKey = 'email';
  static const String _isLoggedInKey = 'is_logged_in';

  static final DataService _dataService = DataService();

  // Initialize auth service
  static Future<void> initialize() async {
    await _dataService.initialize();
  }

  // Login with username and password
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final result = await _dataService.login(username, password);

    if (result != null) {
      await _storeUserData(result);
      return {
        'success': true,
        'user': result,
        'message': 'Login successful',
      };
    } else {
      return {
        'success': false,
        'message': 'Invalid username or password',
      };
    }
  }

  // Register new user
  static Future<Map<String, dynamic>> register(String username, String email, String password) async {
    final result = await _dataService.register(username, email, password);

    if (result != null) {
      await _storeUserData(result);
      return {
        'success': true,
        'user': result,
        'message': 'Registration successful',
      };
    } else {
      return {
        'success': false,
        'message': 'Registration failed. Username or email may already exist.',
      };
    }
  }

  // Face authentication login
  static Future<Map<String, dynamic>> loginWithFace(String faceEncoding) async {
    try {
      // First try to find user locally by face encoding
      final userId = await getCurrentUserId();
      if (userId != null) {
        final storedEncoding = await _dataService.getFaceEncoding(userId);
        if (storedEncoding != null && _compareFaceEncodings(faceEncoding, storedEncoding)) {
          final userData = await _getCurrentUserData();
          if (userData != null) {
            return {
              'success': true,
              'user': userData,
              'message': 'Face authentication successful (offline)',
            };
          }
        }
      }

      // If online, try server verification
      if (_dataService.isOnline) {
        // This would typically call your existing face verification API
        // For now, we'll implement a placeholder
        return {
          'success': false,
          'message': 'Face authentication not fully implemented for online mode',
        };
      }

      return {
        'success': false,
        'message': 'Face authentication failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Face authentication error: $e',
      };
    }
  }

  // Store face encoding for user
  static Future<bool> storeFaceEncoding(String faceEncoding) async {
    try {
      final userId = await getCurrentUserId();
      if (userId != null) {
        await _dataService.updateFaceEncoding(userId, faceEncoding);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Logout
  static Future<void> logout() async {
    await _clearUserData();
    // Optionally clear local database for security
    // await _dataService.clearAllData();
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final isLoggedIn = await _secureStorage.read(key: _isLoggedInKey);
    return isLoggedIn == 'true';
  }

  // Get current user ID
  static Future<int?> getCurrentUserId() async {
    final userIdStr = await _secureStorage.read(key: _userIdKey);
    return userIdStr != null ? int.tryParse(userIdStr) : null;
  }

  // Get current username
  static Future<String?> getCurrentUsername() async {
    return await _secureStorage.read(key: _usernameKey);
  }

  // Get current user email
  static Future<String?> getCurrentUserEmail() async {
    return await _secureStorage.read(key: _emailKey);
  }

  // Get current user data
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final username = await getCurrentUsername();
    if (username != null) {
      return await _getCurrentUserData();
    }
    return null;
  }

  // Check network status
  static bool get isOnline => _dataService.isOnline;

  // Check sync status
  static bool get isSyncing => _dataService.isSyncing;

  // Get sync status stream
  static Stream<SyncStatus> get syncStatusStream => _dataService.syncStatusStream;

  // Get connectivity stream
  static Stream<bool> get connectivityStream => _dataService.connectivityStream;

  // Force sync
  static Future<void> forceSync() async {
    await _dataService.forceSync();
  }

  // Get sync statistics
  static Future<SyncStats> getSyncStats() async {
    return await _dataService.getSyncStats();
  }

  // Private helper methods
  static Future<void> _storeUserData(Map<String, dynamic> userData) async {
    await _secureStorage.write(key: _userIdKey, value: userData['id'].toString());
    await _secureStorage.write(key: _usernameKey, value: userData['username']);
    await _secureStorage.write(key: _emailKey, value: userData['email']);
    await _secureStorage.write(key: _isLoggedInKey, value: 'true');
  }

  static Future<void> _clearUserData() async {
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _usernameKey);
    await _secureStorage.delete(key: _emailKey);
    await _secureStorage.delete(key: _isLoggedInKey);
  }

  static Future<Map<String, dynamic>?> _getCurrentUserData() async {
    final userId = await getCurrentUserId();
    final username = await getCurrentUsername();
    final email = await getCurrentUserEmail();

    if (userId != null && username != null && email != null) {
      return {
        'id': userId,
        'username': username,
        'email': email,
      };
    }

    return null;
  }

  // Simple face encoding comparison (placeholder)
  static bool _compareFaceEncodings(String encoding1, String encoding2) {
    // This is a placeholder implementation
    // In a real app, you'd use proper face recognition algorithms
    return encoding1 == encoding2;
  }
}
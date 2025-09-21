import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'biometric_auth_service.dart';
import '../main.dart'; // Import to access ApiService

// Platform-specific face authentication
class PlatformFaceAuth {

  // Helper method to parse cookies (copied from ApiService)
  static Map<String, String> _parseCookies(String? setCookieHeader) {
    Map<String, String> cookies = {};
    if (setCookieHeader != null) {
      List<String> allCookies = setCookieHeader.split(',');
      for (String cookieString in allCookies) {
        String cookiePair = cookieString.split(';')[0].trim();
        if (cookiePair.contains('=')) {
          List<String> parts = cookiePair.split('=');
          if (parts.length >= 2) {
            String name = parts[0].trim();
            String value = parts.sublist(1).join('=').trim();
            cookies[name] = value;
          }
        }
      }
    }
    return cookies;
  }

  // Setup face authentication based on platform
  static Future<Map<String, dynamic>> setupFaceAuth(String username, String password) async {
    if (Platform.isIOS) {
      // Use native Face ID/Touch ID for iOS
      return await BiometricAuthService.enableBiometricAuth(username, password);
    } else {
      // Use ML Kit face detection for Android
      return await _setupAndroidFaceAuth(username, password);
    }
  }

  // Authenticate with face based on platform
  static Future<Map<String, dynamic>> authenticateWithFace() async {
    if (Platform.isIOS) {
      // Use native Face ID/Touch ID for iOS
      final result = await BiometricAuthService.authenticateWithBiometrics();

      if (result['success'] == true && result['username'] != null && result['password'] != null) {
        // Need to login with the retrieved credentials to get user data
        try {
          final response = await http.post(
            Uri.parse('http://192.168.8.155:5000/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'username': result['username'],
              'password': result['password']
            }),
          );

          if (response.statusCode == 200) {
            final loginData = json.decode(response.body);

            // Store cookies like regular login does
            String? setCookieHeader = response.headers['set-cookie'];
            if (setCookieHeader != null) {
              Map<String, String> cookies = _parseCookies(setCookieHeader);
              ApiService.storeCookies(cookies);
            }

            return {
              'success': true,
              'user': loginData['user'],
              'message': 'Face ID authentication successful'
            };
          } else {
            return {
              'success': false,
              'message': 'Failed to authenticate with server'
            };
          }
        } catch (e) {
          return {
            'success': false,
            'message': 'Network error: $e'
          };
        }
      } else {
        return result;
      }
    } else {
      // Use ML Kit face detection for Android
      return await _authenticateAndroidFace();
    }
  }

  // Check if face auth is available
  static Future<bool> isFaceAuthAvailable() async {
    if (Platform.isIOS) {
      return await BiometricAuthService.isBiometricAvailable();
    } else {
      // For Android, always return true as ML Kit can work on most devices
      return true;
    }
  }

  // Check if face auth is enabled
  static Future<bool> isFaceAuthEnabled() async {
    if (Platform.isIOS) {
      return await BiometricAuthService.isBiometricEnabled();
    } else {
      // Check Android face auth storage
      return await _isAndroidFaceAuthEnabled();
    }
  }

  // Get platform-specific auth type name
  static Future<String> getAuthTypeName() async {
    if (Platform.isIOS) {
      return await BiometricAuthService.getBiometricTypeName();
    } else {
      return 'Face Authentication';
    }
  }

  // Disable face authentication
  static Future<void> disableFaceAuth() async {
    if (Platform.isIOS) {
      await BiometricAuthService.disableBiometricAuth();
    } else {
      await _disableAndroidFaceAuth();
    }
  }

  // Android-specific implementations (placeholders for now)
  static Future<Map<String, dynamic>> _setupAndroidFaceAuth(String username, String password) async {
    // TODO: Implement ML Kit face enrollment for Android
    // For now, return a placeholder
    return {
      'success': false,
      'message': 'Android face authentication will be implemented with ML Kit'
    };
  }

  static Future<Map<String, dynamic>> _authenticateAndroidFace() async {
    // TODO: Implement ML Kit face authentication for Android
    return {
      'success': false,
      'message': 'Android face authentication will be implemented with ML Kit'
    };
  }

  static Future<bool> _isAndroidFaceAuthEnabled() async {
    // TODO: Check Android face auth status
    return false;
  }

  static Future<void> _disableAndroidFaceAuth() async {
    // TODO: Disable Android face auth
  }
}
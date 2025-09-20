import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricAuthService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final LocalAuthentication _localAuth = LocalAuthentication();

  // Check if biometric authentication is available
  static Future<bool> isBiometricAvailable() async {
    try {
      final bool isAvailable = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      debugPrint('Error checking biometric availability: $e');
      return false;
    }
  }

  // Get available biometric types
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('Error getting available biometrics: $e');
      return [];
    }
  }

  // Enable biometric authentication for user
  static Future<Map<String, dynamic>> enableBiometricAuth(String username, String password) async {
    try {
      // First verify the user's credentials
      if (username.isEmpty || password.isEmpty) {
        return {
          'success': false,
          'message': 'Username and password are required to enable biometric authentication'
        };
      }

      // Check if biometrics are available
      final bool isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return {
          'success': false,
          'message': 'Biometric authentication is not available on this device'
        };
      }

      // Prompt user to authenticate with biometrics
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: Platform.isIOS
          ? 'Enable Face ID/Touch ID for Neural Pulse login'
          : 'Enable fingerprint/face authentication for Neural Pulse login',
        options: AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        // Store credentials securely
        await _secureStorage.write(key: 'biometric_username', value: username);
        await _secureStorage.write(key: 'biometric_password', value: password);
        await _secureStorage.write(key: 'biometric_enabled', value: 'true');

        return {
          'success': true,
          'message': Platform.isIOS
            ? 'Face ID/Touch ID enabled successfully'
            : 'Biometric authentication enabled successfully'
        };
      } else {
        return {
          'success': false,
          'message': 'Biometric authentication failed'
        };
      }
    } catch (e) {
      debugPrint('Error enabling biometric auth: $e');
      return {
        'success': false,
        'message': 'Failed to enable biometric authentication: $e'
      };
    }
  }

  // Authenticate using biometrics
  static Future<Map<String, dynamic>> authenticateWithBiometrics() async {
    try {
      // Check if biometric auth is enabled
      final String? isEnabled = await _secureStorage.read(key: 'biometric_enabled');
      if (isEnabled != 'true') {
        return {
          'success': false,
          'message': 'Biometric authentication is not enabled'
        };
      }

      // Check if biometrics are available
      final bool isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return {
          'success': false,
          'message': 'Biometric authentication is not available'
        };
      }

      // Prompt user to authenticate
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: Platform.isIOS
          ? 'Use Face ID/Touch ID to login to Neural Pulse'
          : 'Use your fingerprint/face to login to Neural Pulse',
        options: AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        // Retrieve stored credentials
        final String? username = await _secureStorage.read(key: 'biometric_username');
        final String? password = await _secureStorage.read(key: 'biometric_password');

        if (username != null && password != null) {
          return {
            'success': true,
            'username': username,
            'password': password,
            'message': 'Biometric authentication successful'
          };
        } else {
          return {
            'success': false,
            'message': 'Stored credentials not found'
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Biometric authentication failed'
        };
      }
    } catch (e) {
      debugPrint('Error during biometric auth: $e');
      return {
        'success': false,
        'message': 'Biometric authentication error: $e'
      };
    }
  }

  // Disable biometric authentication
  static Future<void> disableBiometricAuth() async {
    try {
      await _secureStorage.delete(key: 'biometric_username');
      await _secureStorage.delete(key: 'biometric_password');
      await _secureStorage.delete(key: 'biometric_enabled');
    } catch (e) {
      debugPrint('Error disabling biometric auth: $e');
    }
  }

  // Check if biometric auth is enabled
  static Future<bool> isBiometricEnabled() async {
    try {
      final String? isEnabled = await _secureStorage.read(key: 'biometric_enabled');
      return isEnabled == 'true';
    } catch (e) {
      debugPrint('Error checking biometric status: $e');
      return false;
    }
  }

  // Get user-friendly biometric type name
  static Future<String> getBiometricTypeName() async {
    try {
      final biometrics = await getAvailableBiometrics();

      if (Platform.isIOS) {
        if (biometrics.contains(BiometricType.face)) {
          return 'Face ID';
        } else if (biometrics.contains(BiometricType.fingerprint)) {
          return 'Touch ID';
        }
      } else {
        if (biometrics.contains(BiometricType.face)) {
          return 'Face Authentication';
        } else if (biometrics.contains(BiometricType.fingerprint)) {
          return 'Fingerprint';
        }
      }

      return 'Biometric Authentication';
    } catch (e) {
      return 'Biometric Authentication';
    }
  }
}
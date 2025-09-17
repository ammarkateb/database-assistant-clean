import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';


class BiometricAuthService {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> isBiometricLoginEnabled() async {
    final enabled = await _secureStorage.read(key: 'biometric_enabled');
    return enabled == 'true';
  }

  static Future<String> getBiometricCapabilitiesDescription() async {
    try {
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      if (availableBiometrics.contains(BiometricType.face)) {
        return 'Face ID available';
      } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
        return 'Fingerprint available';
      } else {
        return 'No biometric authentication available';
      }
    } catch (e) {
      return 'Biometric status unknown';
    }
  }

  static Future<bool> enableBiometricLogin(User user) async {
    try {
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Enable biometric login for your account',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (isAuthenticated) {
        await _secureStorage.write(key: 'biometric_enabled', value: 'true');
        await _secureStorage.write(key: 'stored_username', value: user.username);
        await _secureStorage.write(key: 'stored_user_id', value: user.id.toString());
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> disableBiometricLogin() async {
    try {
      await _secureStorage.delete(key: 'biometric_enabled');
      await _secureStorage.delete(key: 'stored_username');
      await _secureStorage.delete(key: 'stored_user_id');
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<LoginResult> loginWithBiometric() async {
    try {
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Use biometric authentication to login',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (isAuthenticated) {
        final username = await _secureStorage.read(key: 'stored_username');
        final userId = await _secureStorage.read(key: 'stored_user_id');
        
        if (username != null && userId != null) {
          final user = User(
            id: int.parse(userId),
            username: username,
            role: 'user',
            fullName: username,
            email: '',
            isActive: true,
            createdAt: DateTime.now(),
            biometricEnabled: true,
          );
          return LoginResult.success(user);
        }
      }
      return LoginResult.error('Biometric authentication failed');
    } catch (e) {
      return LoginResult.error('Biometric authentication error: ${e.toString()}');
    }
  }

  static Future<void> clearStoredData() async {
    await _secureStorage.deleteAll();
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neural Pulse - AI Database Assistant',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF0D1B2A),
        scaffoldBackgroundColor: const Color(0xFF0D1B2A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF64FFDA),      // Professional teal accent
          secondary: Color(0xFF7C4DFF),    // Purple accent
          tertiary: Color(0xFF40C4FF),     // Light blue accent
          surface: Color(0xFF1B263B),      // Dark blue-gray surfaces
          background: Color(0xFF0D1B2A),   // Deep navy background
          onPrimary: Color(0xFF000000),    // Black text on primary
          onSecondary: Color(0xFFFFFFFF),  // White text on secondary
          onSurface: Color(0xFFFFFFFF),    // White text on surfaces
          onBackground: Color(0xFFE0E1DD), // Light gray text on background
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B263B),
          elevation: 8,
          foregroundColor: Colors.white,
          shadowColor: Color(0xFF64FFDA),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 8,
            shadowColor: const Color(0xFF64FFDA).withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white, width: 1.5),
            ),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 12,
          shadowColor: const Color(0xFF64FFDA).withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1),
          ),
        ),
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Enums
enum MessageType { user, assistant, system, error, chart }

// Models
class User {
  final int id;
  final String username;
  final String role;
  final String fullName;
  final String email;
  final bool isActive;
  final DateTime createdAt;
  final bool biometricEnabled;
  final bool faceAuthEnabled;

  User({
    required this.id,
    required this.username,
    required this.role,
    required this.fullName,
    required this.email,
    required this.isActive,
    required this.createdAt,
    this.biometricEnabled = false,
    this.faceAuthEnabled = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['user_id'] ?? json['id'] ?? 1,
      username: json['username'],
      role: json['role'],
      fullName: json['full_name'] ?? json['name'] ?? '',
      email: json['email'] ?? '',
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      biometricEnabled: json['biometric_enabled'] ?? false,
      faceAuthEnabled: json['face_auth_enabled'] ?? false,
    );
  }

  bool get canManageUsers => role == 'admin';
  bool get canCreateInvoices => ['manager', 'admin'].contains(role);
  
  Color get roleColor {
    switch (role) {
      case 'visitor': return const Color(0xFF7B1FA2);
      case 'viewer': return const Color(0xFF64FFDA);
      case 'manager': return const Color(0xFFFFB74D);
      case 'admin': return const Color(0xFFFF6B6B);
      default: return const Color(0xFF808080);
    }
  }
}

class Message {
  final String sender;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final Map<String, dynamic>? chartData;

  Message({
    required this.sender,
    required this.content,
    required this.type,
    required this.timestamp,
    this.chartData,
  });
}

class Invoice {
  final int? id;
  final String customerName;
  final double amount;
  final DateTime date;
  final DateTime? dueDate;
  final String? description;
  final String? imagePath;
  final int userId;
  final DateTime createdAt;
  final String status;

  Invoice({
    this.id,
    required this.customerName,
    required this.amount,
    required this.date,
    this.dueDate,
    this.description,
    this.imagePath,
    required this.userId,
    required this.createdAt,
    this.status = 'pending',
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['invoice_id'],  // ✅ Fixed field name
      customerName: json['customer_id']?.toString() ?? 'Unknown Customer',  // ✅ Convert customer_id to string
      amount: (json['total_amount'] as num).toDouble(),  // ✅ Fixed field name
      date: DateTime.parse(json['invoice_date']),  // ✅ This looks correct
      userId: json['customer_id'] ?? 0,  // ✅ Use customer_id for userId
      createdAt: DateTime.now(),  // ✅ Backend doesn't return created_at
      status: json['status'] ?? 'pending',  // ✅ This looks correct
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customer_name': customerName,
      'amount': amount,
      'date': date.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'description': description,
      'image_base64': imagePath,
      'user_id': userId,
      'status': status,
    };
  }
}

class LoginResult {
  final bool success;
  final User? user;
  final String? error;

  LoginResult.success(this.user) : success = true, error = null;
  LoginResult.error(this.error) : success = false, user = null;
}

// Services
class CameraService {
  static final ImagePicker _picker = ImagePicker();

  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status == PermissionStatus.granted;
  }

  static Future<File?> captureImage() async {
    try {
      final hasPermission = await requestCameraPermission();
      if (!hasPermission) return null;

      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      return image != null ? File(image.path) : null;
    } catch (e) {
      print('Error capturing image: $e');
      return null;
    }
  }

  static Future<File?> pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      return image != null ? File(image.path) : null;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }

  static Future<String> convertToBase64(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      throw Exception('Failed to convert image to base64: $e');
    }
  }
}

// Enhanced Face Authentication Service with Multi-Sample Support
class FaceAuthService {
  static final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: true,
    ),
  );

  // NEW METHOD 1: Simple face image capture
  static Future<File?> captureFaceImage() async {
    return await CameraService.captureImage();
  }


  // Enroll multiple face samples (3-5 required)
  static Future<Map<String, dynamic>> enrollMultipleFaces(String userId) async {
    try {
      List<Map<String, dynamic>> samples = [];
      
      // Guide user through multiple captures
      for (int i = 1; i <= 5; i++) {
        final result = await _captureFaceSample(i);
        if (result['success']) {
          samples.add({
            'sample_number': i,
            'face_features': result['face_features']
          });
        } else {
          // Allow skipping after 3 samples
          if (i > 3) {
            break;
          }
          return result; // Return error if first 3 fail
        }
      }

      if (samples.length < 3) {
        return {
          'success': false,
          'message': 'Need at least 3 face samples for reliable recognition'
        };
      }

      // Send all samples to server
      final enrollResults = [];
      for (var sample in samples) {
        final result = await ApiService.enrollFaceSample(
          userId, 
          sample['face_features'], 
          sample['sample_number']
        );
        enrollResults.add(result);
      }

      // Complete enrollment
      final completionResult = await ApiService.completeFaceEnrollment(userId);
      
      return {
        'success': true,
        'samples_enrolled': samples.length,
        'completion_result': completionResult,
        'message': 'Face enrollment completed with ${samples.length} samples!'
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Face enrollment failed: $e'
      };
    }
  }

  static Future<Map<String, dynamic>> _captureFaceSample(int sampleNumber) async {
    try {
      final imageFile = await CameraService.captureImage();
      if (imageFile == null) {
        return {
          'success': false,
          'message': 'Failed to capture image for sample $sampleNumber'
        };
      }

      // Process with ML Kit
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return {
          'success': false,
          'message': 'No face detected in sample $sampleNumber. Please try again.'
        };
      }

      if (faces.length > 1) {
        return {
          'success': false,
          'message': 'Multiple faces detected in sample $sampleNumber. Please ensure only one person is in frame.'
        };
      }

      final face = faces.first;
      final faceFeatures = _extractEnhancedFaceFeatures(face, imageFile);

      return {
        'success': true,
        'face_features': faceFeatures,
        'sample_number': sampleNumber
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error processing sample $sampleNumber: $e'
      };
    }
  }

  static String _extractEnhancedFaceFeatures(Face face, File imageFile) {
    // More comprehensive feature extraction
    Map<String, dynamic> features = {
      'version': '2.0', // Version identifier for compatibility
      'bounding_box': {
        'left': face.boundingBox.left,
        'top': face.boundingBox.top,
        'width': face.boundingBox.width,
        'height': face.boundingBox.height,
        'center_x': face.boundingBox.left + (face.boundingBox.width / 2),
        'center_y': face.boundingBox.top + (face.boundingBox.height / 2),
      },
      'head_rotation': {
        'x': face.headEulerAngleX ?? 0.0,
        'y': face.headEulerAngleY ?? 0.0, 
        'z': face.headEulerAngleZ ?? 0.0,
      },
      'eye_probabilities': {
        'left_open': face.leftEyeOpenProbability ?? 0.5,
        'right_open': face.rightEyeOpenProbability ?? 0.5,
      },
      'smile_probability': face.smilingProbability ?? 0.0,
      'tracking_id': face.trackingId,
    };
    
    // Enhanced landmark extraction with null safety
    Map<String, Map<String, double?>> landmarkData = {};
    if (face.landmarks.isNotEmpty) {
      for (var entry in face.landmarks.entries) {
        if (entry.value != null) {
          landmarkData[entry.key.toString()] = {
            'x': entry.value!.position.x.toDouble(),
            'y': entry.value!.position.y.toDouble(),
          };
        }
      }
      features['landmarks'] = landmarkData;
    }
    
    // Enhanced contour extraction
    Map<String, List<Map<String, double>>> contourData = {};
    if (face.contours.isNotEmpty) {
      for (var entry in face.contours.entries) {
        if (entry.value != null && entry.value!.points.isNotEmpty) {
          contourData[entry.key.toString()] = entry.value!.points.map((point) => {
            'x': point.x.toDouble(),
            'y': point.y.toDouble(),
          }).toList();
        }
      }
      features['contours'] = contourData;
    }
    
    // Add image metadata for better matching
    features['image_info'] = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'face_confidence': _calculateFaceConfidence(face),
    };
    
    return json.encode(features);
  }

  static double _calculateFaceConfidence(Face face) {
    double confidence = 1.0;

    // EXTREMELY STRICT: Very restrictive head rotation limits for security
    if (face.headEulerAngleX != null) {
      double xAngle = face.headEulerAngleX!.abs();
      if (xAngle > 5) confidence *= 0.4;   // Very strict rotation limit
      if (xAngle > 10) confidence *= 0.1;  // Extremely strict for any rotation
    }

    if (face.headEulerAngleY != null) {
      double yAngle = face.headEulerAngleY!.abs();
      if (yAngle > 5) confidence *= 0.4;   // Very strict rotation limit
      if (yAngle > 10) confidence *= 0.1;  // Extremely strict for any rotation
    }

    if (face.headEulerAngleZ != null) {
      double zAngle = face.headEulerAngleZ!.abs();
      if (zAngle > 5) confidence *= 0.5;   // Head tilt penalty
      if (zAngle > 10) confidence *= 0.2;  // Strong penalty for head tilt
    }

    // EXTREMELY STRICT: Both eyes must be clearly open and looking straight
    if (face.leftEyeOpenProbability != null && face.leftEyeOpenProbability! < 0.9) {
      confidence *= 0.2;  // Extremely strict eye requirement
    }
    if (face.rightEyeOpenProbability != null && face.rightEyeOpenProbability! < 0.9) {
      confidence *= 0.2;  // Extremely strict eye requirement
    }

    // STRICTER: Require larger, clearer faces for better security
    double faceArea = face.boundingBox.width * face.boundingBox.height;
    if (faceArea < 30000) confidence *= 0.1; // Much larger minimum face required
    if (faceArea < 20000) confidence *= 0.05; // Extremely small faces rejected

    // STRICTER: Require minimum face dimensions for clarity
    if (face.boundingBox.width < 250 || face.boundingBox.height < 250) {
      confidence *= 0.1; // Much larger minimum face size required
    }

    // ADDITIONAL SECURITY: Check for smile (prevent photos/spoofing)
    if (face.smilingProbability != null) {
      // Neutral expression preferred for security
      if (face.smilingProbability! > 0.7) confidence *= 0.7; // Slight penalty for big smiles
      if (face.smilingProbability! < 0.2) confidence *= 0.8; // Slight penalty for frowning
    }

    // SECURITY CHECK: Reject artificially perfect detection (possible spoofing)
    if (confidence > 0.98) {
      confidence *= 0.9; // Perfect scores are suspicious
    }

    return confidence.clamp(0.0, 1.0);
  }
  static Future<Map<String, dynamic>> getFaceAuthStatus() async {
    try {
      return await ApiService.getFaceAuthStatus();
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to get face auth status: $e'
      };
    }
  }

  static Future<Map<String, dynamic>> resetFaceAuth() async {
    try {
      return await ApiService.resetFaceAuth();
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to reset face auth: $e'
      };
    }
  }

  // Interactive enrollment with UI guidance
  static Future<Map<String, dynamic>> interactiveEnrollment(
    String userId, 
    Function(String) onStatusUpdate,
    Function(int, int) onProgressUpdate
  ) async {
    try {
      onStatusUpdate('Starting face enrollment...');
      onProgressUpdate(0, 5);

      List<String> instructions = [
        'Look straight at the camera',
        'Turn your head slightly to the left',
        'Turn your head slightly to the right', 
        'Tilt your head slightly up',
        'Look straight again with a slight smile'
      ];

      List<Map<String, dynamic>> samples = [];
      
      for (int i = 0; i < 5; i++) {
        onStatusUpdate('Sample ${i + 1}/5: ${instructions[i]}');
        onProgressUpdate(i, 5);

        // Give user time to position
        await Future.delayed(const Duration(seconds: 2));
        
        final result = await _captureFaceSample(i + 1);
        if (result['success']) {
          samples.add({
            'sample_number': i + 1,
            'face_features': result['face_features']
          });
          
          // Send sample immediately
          final enrollResult = await ApiService.enrollFaceSample(
            userId,
            result['face_features'],
            i + 1
          );

          if (!enrollResult['success']) {
            onStatusUpdate('Failed to save sample ${i + 1}. Please try again.');
            i--; // Retry this sample
            continue;
          }
        } else {
          if (i < 3) {
            onStatusUpdate('Sample ${i + 1} failed: ${result['message']}');
            i--; // Retry this sample
            continue;
          } else {
            // Optional samples can be skipped
            onStatusUpdate('Skipping optional sample ${i + 1}');
          }
        }
      }

      if (samples.length < 3) {
        return {
          'success': false,
          'message': 'Need at least 3 successful samples for enrollment'
        };
      }

      onStatusUpdate('Completing enrollment...');
      onProgressUpdate(5, 5);

      final completionResult = await ApiService.completeFaceEnrollment(userId);
      
      if (completionResult['success']) {
        onStatusUpdate('Face enrollment completed successfully!');
        return {
          'success': true,
          'samples_enrolled': samples.length,
          'message': 'Face enrollment completed with ${samples.length} samples!'
        };
      } else {
        return completionResult;
      }

    } catch (e) {
      return {
        'success': false,
        'message': 'Interactive enrollment failed: $e'
      };
    }
  }
}


class ApiService {
  static const String baseUrl = 'https://database-assistant-clean-production.up.railway.app';
  static Map<String, String> _cookies = {};
  
  static Map<String, String> _getHeaders() {
    Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    if (_cookies.isNotEmpty) {
      String cookieString = _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
      headers['Cookie'] = cookieString;
    }
    
    return headers;
  }
  
  static void storeCookies(Map<String, String> cookies) {
    _cookies.addAll(cookies);
  }

  static Future<Map<String, dynamic>> completeFaceEnrollment(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/face-auth/complete-enrollment'),
        headers: _getHeaders(),
        body: json.encode({
          'user_id': int.parse(userId),
        }),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> enrollFaceSample(String userId, String faceFeatures, int sampleNumber) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/face-auth/enroll-sample'),
        headers: _getHeaders(),
        body: json.encode({
          'user_id': int.parse(userId),
          'face_features': faceFeatures,
          'sample_number': sampleNumber,
        }),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getFaceSamplesCount() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/face-auth/samples-count'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> verifyFaceLogin(String faceFeatures) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/face-auth/verify'),
        headers: _getHeaders(),
        body: json.encode({
          'face_features': faceFeatures,
        }),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getFaceAuthStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/face-auth/status'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> resetFaceAuth() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/face-auth/reset'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> clearFaceAuthAttempts() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/face-auth/clear-attempts'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Invoice Management Methods
  static Future<Map<String, dynamic>> createInvoice(Invoice invoice) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/invoices'),
        headers: _getHeaders(),
        body: json.encode(invoice.toJson()),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getInvoices({int? userId}) async {
    try {
      String url = '$baseUrl/invoices';
      if (userId != null) {
        url += '?user_id=$userId';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateInvoice(int invoiceId, Invoice invoice) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/invoices/$invoiceId'),
        headers: _getHeaders(),
        body: json.encode(invoice.toJson()),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> deleteInvoice(int invoiceId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/invoices/$invoiceId'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Receipt Processing Methods
  static Future<Map<String, dynamic>> uploadReceipt(String imageBase64) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/receipt/upload'),
        headers: _getHeaders(),
        body: json.encode({
          'image': imageBase64,
        }),
      ).timeout(const Duration(seconds: 60));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getPendingReceipts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/receipt/pending'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> approveReceipt(int captureId, int customerId, {Map<String, dynamic>? corrections}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/receipt/approve'),
        headers: _getHeaders(),
        body: json.encode({
          'capture_id': captureId,
          'customer_id': customerId,
          'corrections': corrections,
        }),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // User Management Methods
  static Future<Map<String, dynamic>> getAllUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/users'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> createUser({
    required String username,
    required String password,
    required String fullName,
    required String email,
    required String role,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/admin/create-user'),
        headers: _getHeaders(),
        body: json.encode({
          'username': username,
          'password': password,
          'full_name': fullName,
          'email': email,
          'role': role,
        }),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateUser(int userId, {
    String? username,
    String? fullName,
    String? email,
    String? role,
    bool? isActive,
  }) async {
    try {
      Map<String, dynamic> updateData = {};
      if (username != null) updateData['username'] = username;
      if (fullName != null) updateData['full_name'] = fullName;
      if (email != null) updateData['email'] = email;
      if (role != null) updateData['role'] = role;
      if (isActive != null) updateData['is_active'] = isActive;

      final response = await http.put(
        Uri.parse('$baseUrl/admin/users/$userId'),
        headers: _getHeaders(),
        body: json.encode(updateData),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> deleteUser(int userId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/admin/delete-user/$userId'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> changeUserPassword(int userId, String newPassword) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/admin/users/$userId/password'),
        headers: _getHeaders(),
        body: json.encode({
          'new_password': newPassword,
        }),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Query and Chat Methods
  static Future<Map<String, dynamic>> sendQuery(String query, {List<Message>? conversationHistory}) async {
    try {
      Map<String, dynamic> requestBody = {'query': query};
      
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        requestBody['conversation_history'] = conversationHistory.map((msg) => {
          'sender': msg.sender,
          'content': msg.content,
          'timestamp': msg.timestamp.toIso8601String(),
        }).toList();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/query'),
        headers: _getHeaders(),
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 60));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getSystemStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/system-status'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}

class AuthService {
  static const String baseUrl = 'https://database-assistant-clean-production.up.railway.app';
  static User? _currentUser;

  static User? get currentUser => _currentUser;

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



  static Future<LoginResult> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: const {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        String? setCookieHeader = response.headers['set-cookie'];
        if (setCookieHeader != null) {
          Map<String, String> cookies = _parseCookies(setCookieHeader);
          ApiService.storeCookies(cookies);
        }
        
        if (result['success'] == true) {
          _currentUser = User.fromJson(result['user']);
          return LoginResult.success(_currentUser!);
        } else {
          return LoginResult.error(result['message'] ?? 'Login failed');
        }
      } else {
        return LoginResult.error('Server error: ${response.statusCode}');
      }
    } catch (e) {
      return LoginResult.error('Network error: Please check your connection');
    }
  }

  static Future<LoginResult> loginWithBiometric() async {
    return await BiometricAuthService.loginWithBiometric();
  }

  // Setup face authentication for current user
  static Future<Map<String, dynamic>> setupFaceAuth() async {
    if (_currentUser == null) {
      return {
        'success': false,
        'message': 'User must be logged in to setup face authentication'
      };
    }

    try {
      return await FaceAuthService.interactiveEnrollment(
        _currentUser!.id.toString(),
        (status) => print('Face setup status: $status'),
        (current, total) => print('Progress: $current/$total')
      );
    } catch (e) {
      return {
        'success': false,
        'message': 'Face authentication setup failed: $e'
      };
    }
  }

  static Future<LoginResult> loginWithFace() async {
      try {
        // Clear any previous face auth attempts
        await ApiService.clearFaceAuthAttempts();
        
        // Capture image
        final imageFile = await FaceAuthService.captureFaceImage();
        if (imageFile == null) {
          return LoginResult.error('Failed to capture image');
        }
        
        // Process with ML Kit
        final inputImage = InputImage.fromFile(imageFile);
        final faces = await FaceDetector(
          options: FaceDetectorOptions(
            enableContours: true,
            enableLandmarks: true,
            enableClassification: true,
            enableTracking: true,
          ),
        ).processImage(inputImage);
        
        if (faces.isEmpty) {
          return LoginResult.error('No face detected');
        }
        
        if (faces.length > 1) {
          return LoginResult.error('Multiple faces detected. Please ensure only you are in the frame.');
        }
        
        // Extract features in the format your backend expects
        final faceFeatures = FaceAuthService._extractEnhancedFaceFeatures(faces.first, imageFile);
        
        // Use the enhanced face verification
        final result = await ApiService.verifyFaceLogin(faceFeatures);
        
        if (result['success'] == true) {
          if (result['user'] != null) {
            _currentUser = User.fromJson(result['user']);
            return LoginResult.success(_currentUser!);
          } else {
            return LoginResult.error('User data not received from server');
          }
        } else {
          String errorMessage = result['message'] ?? 'Face authentication failed';
          
          // Handle specific error cases
          if (result['redirect_to_login'] == true) {
            errorMessage += '\nPlease use username/password login.';
          } else if (result['attempts_remaining'] != null) {
            int remaining = result['attempts_remaining'];
            errorMessage += '\n$remaining attempts remaining.';
          }
          
          return LoginResult.error(errorMessage);
        }
      } catch (e) {
        return LoginResult.error('Face authentication error: ${e.toString()}');
      }
    }

  // Get face authentication status for current user
  static Future<Map<String, dynamic>> getFaceAuthStatus() async {
    if (_currentUser == null) {
      return {
        'success': false,
        'message': 'User must be logged in'
      };
    }

    try {
      return await FaceAuthService.getFaceAuthStatus();
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to get face auth status: $e'
      };
    }
  }

  // Reset face authentication for current user
  static Future<Map<String, dynamic>> resetFaceAuth() async {
    if (_currentUser == null) {
      return {
        'success': false,
        'message': 'User must be logged in'
      };
    }

    try {
      return await FaceAuthService.resetFaceAuth();
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to reset face auth: $e'
      };
    }
  }

  // Update current user data
  static Future<LoginResult> updateUser({
    String? username,
    String? fullName,
    String? email,
    String? role,
  }) async {
    if (_currentUser == null) {
      return LoginResult.error('User must be logged in');
    }

    try {
      final result = await ApiService.updateUser(
        _currentUser!.id,
        username: username,
        fullName: fullName,
        email: email,
        role: role,
      );

      if (result['success'] == true) {
        // Update the current user object
        User updatedUser = User(
          id: _currentUser!.id,
          username: username ?? _currentUser!.username,
          role: role ?? _currentUser!.role,
          fullName: fullName ?? _currentUser!.fullName,
          email: email ?? _currentUser!.email,
          isActive: _currentUser!.isActive,
          createdAt: _currentUser!.createdAt,
          biometricEnabled: _currentUser!.biometricEnabled,
          faceAuthEnabled: _currentUser!.faceAuthEnabled,
        );

        _currentUser = updatedUser;
        return LoginResult.success(_currentUser!);
      } else {
        return LoginResult.error(result['message'] ?? 'Update failed');
      }
    } catch (e) {
      return LoginResult.error('Update error: ${e.toString()}');
    }
  }

// Change password for current user
  static Future<Map<String, dynamic>> changePassword(String newPassword) async {
    if (_currentUser == null) {
      return {
        'success': false,
        'message': 'User must be logged in'
      };
    }

    try {
      final result = await ApiService.changeUserPassword(_currentUser!.id, newPassword);
      return result;
    } catch (e) {
      return {
        'success': false,
        'message': 'Password change failed: ${e.toString()}'
      };
    }
  }

  // Refresh current user data
  static Future<LoginResult> refreshUserData() async {
    if (_currentUser == null) {
      return LoginResult.error('No user logged in');
    }

    try {
      // Get updated user data from server
      final response = await http.get(
        Uri.parse('$baseUrl/user/profile'),
        headers: const {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['success'] == true) {
          _currentUser = User.fromJson(result['user']);
          return LoginResult.success(_currentUser!);
        } else {
          return LoginResult.error(result['message'] ?? 'Failed to refresh user data');
        }
      } else {
        return LoginResult.error('Server error: ${response.statusCode}');
      }
    } catch (e) {
      return LoginResult.error('Network error: ${e.toString()}');
    }
  }

  // Check if user has specific permission
  static bool hasPermission(String permission) {
    if (_currentUser == null) return false;

    switch (permission) {
      case 'manage_users':
        return _currentUser!.role == 'admin';
      case 'create_invoices':
        return ['manager', 'admin'].contains(_currentUser!.role);
      case 'view_customers':
        return ['viewer', 'manager', 'admin'].contains(_currentUser!.role);
      case 'view_products':
        return ['viewer', 'manager', 'admin'].contains(_currentUser!.role);
      case 'view_invoices':
        return ['visitor', 'viewer', 'manager', 'admin'].contains(_currentUser!.role);
      case 'process_receipts':
        return ['manager', 'admin'].contains(_currentUser!.role);
      default:
        return false;
    }
  }

  // Logout and cleanup
  static Future<void> logout() async {
    try {
      // Call logout endpoint if needed
      await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: const {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      // Ignore logout endpoint errors
    }

    _currentUser = null;
    await BiometricAuthService.clearStoredData();
    
    // Clear API cookies
    ApiService.storeCookies({});
  }

  // Validate session
  static Future<bool> validateSession() async {
    if (_currentUser == null) return false;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/validate-session'),
        headers: const {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return result['valid'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}


// User Edit Screen for Admin
class UserEditScreen extends StatefulWidget {
  final User user;
  final bool isCurrentUser;

  const UserEditScreen({Key? key, required this.user, this.isCurrentUser = false}) : super(key: key);

  @override
  _UserEditScreenState createState() => _UserEditScreenState();
}

class _UserEditScreenState extends State<UserEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  
  String _selectedRole = 'viewer';
  bool _isActive = true;
  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _roles = ['visitor', 'viewer', 'manager', 'admin'];

  @override
  void initState() {
    super.initState();
    _initializeFormData();
  }

  void _initializeFormData() {
    _usernameController.text = widget.user.username;
    _fullNameController.text = widget.user.fullName;
    _emailController.text = widget.user.email;
    _selectedRole = widget.user.role;
    _isActive = widget.user.isActive;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _updateUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.updateUser(
        widget.user.id,
        username: _usernameController.text.trim(),
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        role: _selectedRole,
        isActive: _isActive,
      );

      if (result['success'] == true) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Update failed';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error updating user: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _changePassword() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Change Password for ${widget.user.username}', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'New Password',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passwordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password cannot be empty'), backgroundColor: Colors.red),
                );
                return;
              }
              if (passwordController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match'), backgroundColor: Colors.red),
                );
                return;
              }

              try {
                final result = await ApiService.changeUserPassword(widget.user.id, passwordController.text);
                if (result['success'] == true) {
                  Navigator.pop(context, true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password changed successfully!'), backgroundColor: Colors.green),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result['message'] ?? 'Password change failed'), backgroundColor: Colors.red),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B263B)),
            child: const Text('Change Password', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    passwordController.dispose();
    confirmController.dispose();
  }

  Future<void> _resetFaceAuth() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Reset Face Authentication', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to reset face authentication for ${widget.user.username}? This will delete all their face samples.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await http.delete(
          Uri.parse('${ApiService.baseUrl}/admin/users/${widget.user.id}/face-auth'),
          headers: const {'Content-Type': 'application/json'},
        );

        final result = json.decode(response.body);
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Face authentication reset successfully!'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Reset failed'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit User - ${widget.user.username}', style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (widget.user.faceAuthEnabled)
            IconButton(
              onPressed: _resetFaceAuth,
              icon: const Icon(Icons.face_retouching_off, color: Colors.red),
              tooltip: 'Reset Face Auth',
            ),
          IconButton(
            onPressed: _changePassword,
            icon: const Icon(Icons.lock_reset, color: Colors.white),
            tooltip: 'Change Password',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
              Color(0xFF64FFDA),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Info Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [widget.user.roleColor, widget.user.roleColor.withValues(alpha: 0.7)]),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Icon(
                            widget.user.faceAuthEnabled ? Icons.face : Icons.person,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.user.username,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.user.roleColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: widget.user.roleColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            widget.user.role.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (widget.user.faceAuthEnabled) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                            ),
                            child: const Text(
                              'FACE AUTH ENABLED',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Form Fields
                  const Text('User Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.person, color: Colors.white),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white30, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Username is required';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _fullNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.badge, color: Colors.white),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white30, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Full name is required';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.email, color: Colors.white),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white30, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 20),

                  // Role Selection
                  const Text('Role', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30, width: 1),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedRole,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.admin_panel_settings, color: Colors.white),
                      ),
                      dropdownColor: const Color(0xFF1A1A1A),
                      items: _roles.map((role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.toUpperCase(), style: const TextStyle(color: Colors.white)),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedRole = value;
                          });
                        }
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Active Status
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.toggle_on, color: Colors.white),
                        const SizedBox(width: 12),
                        const Text('Account Status', style: TextStyle(color: Colors.white, fontSize: 16)),
                        const Spacer(),
                        Switch(
                          value: _isActive,
                          onChanged: (value) {
                            setState(() {
                              _isActive = value;
                            });
                          },
                          activeColor: const Color(0xFF1B263B),
                        ),
                        Text(
                          _isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            color: _isActive ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _updateUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B263B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Update User', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// Enhanced Invoice List Screen with Receipt Integration
class EnhancedInvoiceListScreen extends StatefulWidget {
  final User user;

  const EnhancedInvoiceListScreen({Key? key, required this.user}) : super(key: key);

  @override
  _EnhancedInvoiceListScreenState createState() => _EnhancedInvoiceListScreenState();
}

class _EnhancedInvoiceListScreenState extends State<EnhancedInvoiceListScreen> {
  List<Invoice> _invoices = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedTab = 'invoices';

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final response = await ApiService.getInvoices(userId: widget.user.id);
      
      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _invoices = (response['invoices'] as List)
                .map((invoice) => Invoice.fromJson(invoice))
                .toList();
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response['message'] ?? 'Failed to load invoices';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading invoices: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _uploadReceipt() async {
    final imageSource = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Add Receipt', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF1B263B)),
              title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF1B263B)),
              title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (imageSource != null) {
      try {
        File? imageFile;
        if (imageSource == ImageSource.camera) {
          imageFile = await CameraService.captureImage();
        } else {
          imageFile = await CameraService.pickFromGallery();
        }

        if (imageFile != null) {
          setState(() => _isLoading = true);
          
          final imageBase64 = await CameraService.convertToBase64(imageFile);
          final result = await ApiService.uploadReceipt(imageBase64);

          setState(() => _isLoading = false);

          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Receipt uploaded successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            _loadInvoices(); // Refresh the list
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message'] ?? 'Upload failed'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading receipt: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editInvoice(Invoice invoice) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InvoiceEditScreen(invoice: invoice, user: widget.user),
      ),
    );
    if (result == true) {
      _loadInvoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Tab Bar
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _selectedTab = 'invoices'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedTab == 'invoices' ? const Color(0xFF1B263B) : Colors.transparent,
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF1B263B)),
                    ),
                    child: const Text('Invoices'),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.user.canCreateInvoices) ...[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _selectedTab = 'receipts'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedTab == 'receipts' ? const Color(0xFF1B263B) : Colors.transparent,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF1B263B)),
                      ),
                      child: const Text('Receipts'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          Expanded(
            child: _selectedTab == 'invoices' ? _buildInvoicesTab() : _buildReceiptsTab(),
          ),
        ],
      ),
      floatingActionButton: _selectedTab == 'invoices'
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InvoiceCreateScreen(user: widget.user),
                  ),
                );
                if (result == true) {
                  _loadInvoices();
                }
              },
              backgroundColor: const Color(0xFF1B263B),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : FloatingActionButton(
              onPressed: _uploadReceipt,
              backgroundColor: const Color(0xFF64FFDA),
              child: const Icon(Icons.camera_alt, color: Colors.white),
            ),
    );
  }

  Widget _buildInvoicesTab() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Loading invoices...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInvoices,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B263B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_invoices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.white54),
            SizedBox(height: 16),
            Text('No invoices found', style: TextStyle(color: Colors.white70, fontSize: 16)),
            SizedBox(height: 8),
            Text('Tap the + button to create your first invoice', style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _invoices.length,
      itemBuilder: (context, index) {
        final invoice = _invoices[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: invoice.imagePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(invoice.imagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => 
                            const Icon(Icons.receipt_long, color: Colors.white),
                      ),
                    )
                  : const Icon(Icons.receipt_long, color: Colors.white),
            ),
            title: Text(invoice.customerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('\$${invoice.amount.toStringAsFixed(2)}', 
                     style: const TextStyle(color: Color(0xFF64FFDA), fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('${invoice.date.day}/${invoice.date.month}/${invoice.date.year}', 
                     style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (invoice.status.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: invoice.status == 'paid' ? Colors.green.withOpacity(0.2) : 
                             invoice.status == 'pending' ? Colors.orange.withOpacity(0.2) :
                             Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      invoice.status.toUpperCase(),
                      style: TextStyle(
                        color: invoice.status == 'paid' ? Colors.green : 
                               invoice.status == 'pending' ? Colors.orange :
                               Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: const Color(0xFF1A1A1A),
              onSelected: (value) async {
                if (value == 'edit') {
                  _editInvoice(invoice);
                } else if (value == 'delete') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1A1A),
                      title: const Text('Delete Invoice', style: TextStyle(color: Colors.white)),
                      content: Text('Are you sure you want to delete this invoice for ${invoice.customerName}?', 
                                   style: const TextStyle(color: Colors.white70)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && invoice.id != null) {
                    final response = await ApiService.deleteInvoice(invoice.id!);
                    if (response['success'] == true) {
                      _loadInvoices();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invoice deleted successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(response['message'] ?? 'Failed to delete invoice'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Edit', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => InvoiceDetailScreen(invoice: invoice),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceiptsTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getPendingReceipts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('Loading receipts...', style: TextStyle(color: Colors.white70)),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
              ],
            ),
          );
        }

        final data = snapshot.data;
        if (data == null || data['success'] != true) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_outlined, size: 64, color: Colors.white54),
                const SizedBox(height: 16),
                Text(data?['message'] ?? 'Failed to load receipts', 
                     style: const TextStyle(color: Colors.white70)),
              ],
            ),
          );
        }

        final receipts = data['pending_receipts'] as List? ?? [];

        if (receipts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_outlined, size: 64, color: Colors.white54),
                SizedBox(height: 16),
                Text('No pending receipts', style: TextStyle(color: Colors.white70, fontSize: 16)),
                SizedBox(height: 8),
                Text('Upload receipts using the camera button', style: TextStyle(color: Colors.white54, fontSize: 14)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: receipts.length,
          itemBuilder: (context, index) {
            final receipt = receipts[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF64FFDA), Color(0xFF1B263B)]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt, color: Colors.white),
                ),
                title: Text(receipt['vendor'] ?? 'Unknown Vendor', 
                           style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('\$${(receipt['total'] ?? 0.0).toStringAsFixed(2)}', 
                         style: const TextStyle(color: Color(0xFF64FFDA), fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('Confidence: ${((receipt['confidence'] ?? 0.0) * 100).toStringAsFixed(0)}%', 
                         style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('Uploaded: ${receipt['uploaded_by'] ?? 'Unknown'}', 
                         style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _approveReceipt(receipt),
                      icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: 'Approve',
                    ),
                    IconButton(
                      onPressed: () => _rejectReceipt(receipt),
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: 'Reject',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _approveReceipt(Map<String, dynamic> receipt) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ReceiptApprovalDialog(receipt: receipt),
    );

    if (result != null) {
      try {
        final response = await ApiService.approveReceipt(
          result['capture_id'],
          result['customer_id'],
          corrections: result['corrections'],
        );

        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Receipt approved! Invoice ${response['invoice_id']} created.'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {}); // Refresh receipts tab
          _loadInvoices(); // Refresh invoices tab
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Approval failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectReceipt(Map<String, dynamic> receipt) async {
    final reasonController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Reject Receipt', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Why are you rejecting this receipt?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter reason...',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, reasonController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    reasonController.dispose();

    if (result != null && result.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('${ApiService.baseUrl}/receipt/reject'),
          headers: const {'Content-Type': 'application/json'},
          body: json.encode({
            'capture_id': receipt['capture_id'],
            'reason': result,
          }),
        );

        final data = json.decode(response.body);
        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Receipt rejected'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {}); // Refresh receipts tab
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Rejection failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Receipt Approval Dialog
class ReceiptApprovalDialog extends StatefulWidget {
  final Map<String, dynamic> receipt;

  const ReceiptApprovalDialog({Key? key, required this.receipt}) : super(key: key);

  @override
  _ReceiptApprovalDialogState createState() => _ReceiptApprovalDialogState();
}

class _ReceiptApprovalDialogState extends State<ReceiptApprovalDialog> {
  final _customerIdController = TextEditingController();
  final _totalController = TextEditingController();
  final _vendorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _customerIdController.text = '1'; // Default customer
    _totalController.text = (widget.receipt['total'] ?? 0.0).toString();
    _vendorController.text = widget.receipt['vendor'] ?? '';
  }

  @override
  void dispose() {
    _customerIdController.dispose();
    _totalController.dispose();
    _vendorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Approve Receipt', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _vendorController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Vendor',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _totalController,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Total Amount',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customerIdController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Customer ID',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () {
            final corrections = <String, dynamic>{};
            if (_totalController.text != (widget.receipt['total'] ?? 0.0).toString()) {
              corrections['total'] = double.tryParse(_totalController.text) ?? widget.receipt['total'];
            }
            if (_vendorController.text != (widget.receipt['vendor'] ?? '')) {
              corrections['vendor'] = _vendorController.text;
            }

            Navigator.pop(context, {
              'capture_id': widget.receipt['capture_id'],
              'customer_id': int.tryParse(_customerIdController.text) ?? 1,
              'corrections': corrections.isEmpty ? null : corrections,
            });
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('Approve', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// Invoice Edit Screen
class InvoiceEditScreen extends StatefulWidget {
  final Invoice invoice;
  final User user;

  const InvoiceEditScreen({Key? key, required this.invoice, required this.user}) : super(key: key);

  @override
  _InvoiceEditScreenState createState() => _InvoiceEditScreenState();
}

class _InvoiceEditScreenState extends State<InvoiceEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  String _selectedStatus = 'pending';
  bool _isLoading = false;

  final List<String> _statusOptions = ['pending', 'paid', 'overdue', 'cancelled'];

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  void _initializeForm() {
    _customerNameController.text = widget.invoice.customerName;
    _amountController.text = widget.invoice.amount.toString();
    _descriptionController.text = widget.invoice.description ?? '';
    _selectedDate = widget.invoice.date;
    _selectedStatus = widget.invoice.status;
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final updatedInvoice = Invoice(
        id: widget.invoice.id,
        customerName: _customerNameController.text.trim(),
        amount: double.parse(_amountController.text.trim()),
        date: _selectedDate,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        userId: widget.user.id,
        createdAt: widget.invoice.createdAt,
        status: _selectedStatus,
      );

      final response = await ApiService.updateInvoice(widget.invoice.id!, updatedInvoice);

      if (response['success'] == true) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Update failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Invoice', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
              Color(0xFF64FFDA),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _customerNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Customer Name',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.person, color: Colors.white),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  validator: (value) => value?.trim().isEmpty == true ? 'Customer name is required' : null,
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _amountController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.attach_money, color: Colors.white),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value?.trim().isEmpty == true) return 'Amount is required';
                    if (double.tryParse(value!.trim()) == null) return 'Enter a valid amount';
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Status',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.flag, color: Colors.white),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  dropdownColor: const Color(0xFF1A1A1A),
                  items: _statusOptions.map((status) => DropdownMenuItem(
                    value: status,
                    child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white)),
                  )).toList(),
                  onChanged: (value) => setState(() => _selectedStatus = value!),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateInvoice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B263B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                        : const Text('Update Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// Face Authentication Setup Screen
class FaceAuthSetupScreen extends StatefulWidget {
  final User user;

  const FaceAuthSetupScreen({Key? key, required this.user}) : super(key: key);

  @override
  _FaceAuthSetupScreenState createState() => _FaceAuthSetupScreenState();
}

class _FaceAuthSetupScreenState extends State<FaceAuthSetupScreen> {
  bool _isEnrolling = false;
  String _statusMessage = 'Ready to begin face enrollment';
  int _currentSample = 0;
  int _totalSamples = 5;
  List<bool> _sampleCompleted = [false, false, false, false, false];

  final List<String> _instructions = [
    'Look straight at the camera with a neutral expression',
    'Turn your head slightly to the left',
    'Turn your head slightly to the right',
    'Tilt your head slightly up',
    'Look straight with a slight smile'
  ];

  Future<void> _startEnrollment() async {
    setState(() {
      _isEnrolling = true;
      _currentSample = 0;
      _sampleCompleted = [false, false, false, false, false];
    });

    try {
      final result = await FaceAuthService.interactiveEnrollment(
        widget.user.id.toString(),
        _updateStatus,
        _updateProgress
      );

      if (result['success'] == true) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Face enrollment completed!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Enrollment failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isEnrolling = false;
      });
    }
  }

  void _updateStatus(String status) {
    setState(() {
      _statusMessage = status;
    });
  }

  void _updateProgress(int current, int total) {
    setState(() {
      _currentSample = current;
      if (current > 0 && current <= _sampleCompleted.length) {
        _sampleCompleted[current - 1] = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Authentication Setup', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
              Color(0xFF64FFDA),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Face Authentication',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We\'ll capture 5 face samples for secure authentication',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                
                const SizedBox(height: 40),
                
                // Progress Indicator
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Progress',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '$_currentSample/$_totalSamples',
                            style: const TextStyle(color: Color(0xFF64FFDA), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Sample indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(5, (index) {
                          return Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: _sampleCompleted[index] 
                                  ? Colors.green 
                                  : index == _currentSample 
                                      ? const Color(0xFF64FFDA)
                                      : Colors.grey.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(
                                color: _sampleCompleted[index] 
                                    ? Colors.green 
                                    : Colors.white.withValues(alpha: 0.3)
                              ),
                            ),
                            child: Center(
                              child: _sampleCompleted[index]
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          );
                        }),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Linear progress bar
                      LinearProgressIndicator(
                        value: _currentSample / _totalSamples,
                        backgroundColor: Colors.grey.withValues(alpha: 0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF64FFDA)),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Instructions
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info, color: Color(0xFF64FFDA)),
                          SizedBox(width: 8),
                          Text(
                            'Instructions',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      ...List.generate(_instructions.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _sampleCompleted[index] 
                                      ? Colors.green 
                                      : index == _currentSample 
                                          ? const Color(0xFF64FFDA)
                                          : Colors.grey.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: _sampleCompleted[index]
                                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                                      : Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _instructions[index],
                                  style: TextStyle(
                                    color: _sampleCompleted[index] 
                                        ? Colors.white70 
                                        : index == _currentSample 
                                            ? Colors.white 
                                            : Colors.white54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Status message
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E0249).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF64FFDA).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                const Spacer(),
                
                // Start button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isEnrolling ? null : _startEnrollment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B263B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isEnrolling
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Enrolling Face...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          )
                        : const Text('Start Face Enrollment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                
                const SizedBox(height: 20),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}


// UI Components - Starting with AuthWrapper
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  User? _currentUser;
  bool _hasBiometricCapability = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final biometricAvailable = await BiometricAuthService.isBiometricAvailable();
    
    setState(() {
      _hasBiometricCapability = biometricAvailable;
      _currentUser = AuthService.currentUser;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF000000),
                Color(0xFF2E0249),
                Color(0xFF1B263B),
                Color(0xFF64FFDA),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.psychology, size: 64, color: Colors.white),
                ),
                const SizedBox(height: 24),
                const Text('Neural Pulse', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('AI Database Assistant', style: TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 32),
                const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              ],
            ),
          ),
        ),
      );
    }

    return _currentUser != null 
        ? MainNavigationScreen(user: _currentUser!) 
        : LoginSelectionScreen(hasBiometricCapability: _hasBiometricCapability);
  }
}

class LoginSelectionScreen extends StatefulWidget {
  final bool hasBiometricCapability;
  
  const LoginSelectionScreen({Key? key, required this.hasBiometricCapability}) : super(key: key);
  
  @override
  _LoginSelectionScreenState createState() => _LoginSelectionScreenState();
}

class _LoginSelectionScreenState extends State<LoginSelectionScreen> {
  Future<void> _loginWithBiometric(BuildContext context) async {
    final result = await AuthService.loginWithBiometric();
    
    if (result.success && result.user != null) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => MainNavigationScreen(user: result.user!)),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Biometric authentication failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loginWithFace(BuildContext context) async {
    final result = await AuthService.loginWithFace();
    
    if (result.success && result.user != null) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => MainNavigationScreen(user: result.user!)),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Face authentication failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
              Color(0xFF64FFDA),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.psychology, size: 64, color: Colors.white),
                  ),
                  const SizedBox(height: 32),
                  const Text('Neural Pulse', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('AI Database Assistant', style: TextStyle(color: Colors.white70, fontSize: 18)),
                  const SizedBox(height: 48),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B263B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.login, color: Colors.white),
                      label: const Text('Login with Username', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // BIOMETRIC LOGIN - TEMPORARILY COMMENTED OUT
                  // if (widget.hasBiometricCapability) ...[
                  //   SizedBox(
                  //     width: double.infinity,
                  //     child: OutlinedButton.icon(
                  //       onPressed: () => _loginWithBiometric(context),
                  //       style: OutlinedButton.styleFrom(
                  //         side: const BorderSide(color: Colors.white, width: 2),
                  //         foregroundColor: Colors.white,
                  //         padding: const EdgeInsets.symmetric(vertical: 16),
                  //         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  //       ),
                  //       icon: const Icon(Icons.fingerprint, color: Colors.white),
                  //       label: const Text('Login with Biometric', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  //     ),
                  //   ),
                  //   const SizedBox(height: 16),
                  // ],
                  
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _loginWithFace(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF64FFDA), width: 2),
                        foregroundColor: const Color(0xFF64FFDA),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      icon: const Icon(Icons.face, color: Color(0xFF64FFDA)),
                      label: const Text('Login with Face', style: TextStyle(color: Color(0xFF64FFDA), fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  
                  // BIOMETRIC STATUS - TEMPORARILY COMMENTED OUT
                  // if (widget.hasBiometricCapability) ...[
                  //   const SizedBox(height: 16),
                  //   Container(
                  //     width: double.infinity,
                  //     padding: const EdgeInsets.all(16),
                  //     decoration: BoxDecoration(
                  //       color: Colors.grey.withOpacity(0.2),
                  //       borderRadius: BorderRadius.circular(15),
                  //     ),
                  //     child: const Row(
                  //       mainAxisAlignment: MainAxisAlignment.center,
                  //       children: [
                  //         Icon(Icons.info, color: Colors.white70, size: 20),
                  //         SizedBox(width: 8),
                  //         Text(
                  //           'Biometric authentication not available',
                  //           style: TextStyle(color: Colors.white70, fontSize: 14),
                  //         ),
                  //       ],
                  //     ),
                  //   ),
                  // ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final result = await AuthService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      
      if (result.success && result.user != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => MainNavigationScreen(user: result.user!)),
          (route) => false,
        );
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Login failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Login error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
              Color(0xFF64FFDA),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.psychology, size: 64, color: Colors.white),
                    ),
                    const SizedBox(height: 32),
                    const Text('Welcome Back', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Sign in to continue', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 48),
                    
                    TextFormField(
                      controller: _usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.person, color: Colors.white),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(color: Colors.white30, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your username';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 20),
                    
                    TextFormField(
                      controller: _passwordController,
                      style: const TextStyle(color: Colors.white),
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.lock, color: Colors.white),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(color: Colors.white30, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _login(),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
                          ],
                        ),
                      ),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B263B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final User user;

  const MainNavigationScreen({Key? key, required this.user}) : super(key: key);

  @override
  _MainNavigationScreenState createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  List<Message> _messages = [];

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    final welcomeMessage = Message(
      sender: 'AI Assistant',
      content: 'Welcome to Neural Pulse, ${widget.user.fullName}! I\'m your AI database assistant. Ask me about sales data, customer information, product details, or any business insights you need.',
      type: MessageType.system,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.add(welcomeMessage);
    });
  }

  void _onMessageAdded(Message message) {
    setState(() {
      _messages.add(message);
    });
  }

  List<NavigationItem> _getNavigationItems() {
    List<NavigationItem> items = [
      NavigationItem(
        icon: Icons.chat,
        label: 'Chat',
        screen: ChatScreen(
          user: widget.user,
          messages: _messages,
          onMessageAdded: _onMessageAdded,
        ),
      ),
    ];

    // Add invoice management for managers and admins
    if (widget.user.canCreateInvoices) {
      items.add(NavigationItem(
        icon: Icons.receipt_long,
        label: 'Invoices',
        screen: InvoiceListScreen(user: widget.user),
      ));
    }

    items.addAll([
      NavigationItem(
        icon: Icons.person,
        label: 'Profile',
        screen: ProfileScreen(user: widget.user),
      ),
      NavigationItem(
        icon: Icons.settings,
        label: 'Settings',
        screen: const SettingsScreen(),
      ),
    ]);

    // Add user management for admins only
    if (widget.user.canManageUsers) {
      items.add(NavigationItem(
        icon: Icons.group,
        label: 'Users',
        screen: UserManagementScreen(user: widget.user),
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final navigationItems = _getNavigationItems();
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.psychology, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Neural Pulse', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.user.roleColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: widget.user.roleColor.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person, color: widget.user.roleColor, size: 16),
                const SizedBox(width: 4),
                Text(
                  widget.user.role.toUpperCase(),
                  style: TextStyle(
                    color: widget.user.roleColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF1A1A1A),
            onSelected: (value) async {
              if (value == 'logout') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Logout', style: TextStyle(color: Colors.white)),
                    content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Logout', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  await AuthService.logout();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const AuthWrapper()),
                    (route) => false,
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
              Color(0xFF64FFDA),
            ],
          ),
        ),
        child: navigationItems[_selectedIndex].screen,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2))),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          selectedItemColor: const Color(0xFF64FFDA),
          unselectedItemColor: Colors.white54,
          elevation: 0,
          items: navigationItems.map((item) => BottomNavigationBarItem(
            icon: Icon(item.icon),
            label: item.label,
          )).toList(),
        ),
      ),
      floatingActionButton: _selectedIndex == 1 && widget.user.canCreateInvoices
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InvoiceCreateScreen(user: widget.user),
                  ),
                );
                if (result == true) {
                  // Refresh the invoice list
                  setState(() {});
                }
              },
              backgroundColor: const Color(0xFF1B263B),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}

class NavigationItem {
  final IconData icon;
  final String label;
  final Widget screen;

  NavigationItem({
    required this.icon,
    required this.label,
    required this.screen,
  });
}

// Invoice List Screen
class InvoiceListScreen extends StatefulWidget {
  final User user;

  const InvoiceListScreen({Key? key, required this.user}) : super(key: key);

  @override
  _InvoiceListScreenState createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  List<Invoice> _invoices = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final response = await ApiService.getInvoices(userId: widget.user.id);
      
      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _invoices = (response['invoices'] as List)
                .map((invoice) => Invoice.fromJson(invoice))
                .toList();
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response['message'] ?? 'Failed to load invoices';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading invoices: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteInvoice(Invoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Invoice', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete this invoice for ${invoice.customerName}?', 
                     style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && invoice.id != null) {
      final response = await ApiService.deleteInvoice(invoice.id!);
      if (response['success'] == true) {
        _loadInvoices(); // Refresh the list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to delete invoice'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Loading invoices...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadInvoices,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B263B),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('My Invoices', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          IconButton(
                            onPressed: _loadInvoices,
                            icon: const Icon(Icons.refresh, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _invoices.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.receipt_long_outlined, size: 64, color: Colors.white54),
                                  SizedBox(height: 16),
                                  Text('No invoices found', style: TextStyle(color: Colors.white70, fontSize: 16)),
                                  SizedBox(height: 8),
                                  Text('Tap the + button to create your first invoice', style: TextStyle(color: Colors.white54, fontSize: 14)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _invoices.length,
                              itemBuilder: (context, index) {
                                final invoice = _invoices[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)]),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: invoice.imagePath != null
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.memory(
                                                base64Decode(invoice.imagePath!),
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) => 
                                                    const Icon(Icons.receipt_long, color: Colors.white),
                                              ),
                                            )
                                          : const Icon(Icons.receipt_long, color: Colors.white),
                                    ),
                                    title: Text(invoice.customerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('\$${invoice.amount.toStringAsFixed(2)}', 
                                             style: const TextStyle(color: Color(0xFF64FFDA), fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text('${invoice.date.day}/${invoice.date.month}/${invoice.date.year}', 
                                             style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                        if (invoice.status.isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: invoice.status == 'paid' ? Colors.green.withOpacity(0.2) : 
                                                     invoice.status == 'pending' ? Colors.orange.withOpacity(0.2) :
                                                     Colors.red.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              invoice.status.toUpperCase(),
                                              style: TextStyle(
                                                color: invoice.status == 'paid' ? Colors.green : 
                                                       invoice.status == 'pending' ? Colors.orange :
                                                       Colors.red,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        if (invoice.description != null && invoice.description!.isNotEmpty)
                                          Text(invoice.description!, 
                                               style: const TextStyle(color: Colors.white60, fontSize: 12),
                                               maxLines: 1,
                                               overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteInvoice(invoice),
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => InvoiceDetailScreen(invoice: invoice),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

// Invoice Create Screen
class InvoiceCreateScreen extends StatefulWidget {
  final User user;

  const InvoiceCreateScreen({Key? key, required this.user}) : super(key: key);

  @override
  _InvoiceCreateScreenState createState() => _InvoiceCreateScreenState();
}

class _InvoiceCreateScreenState extends State<InvoiceCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  DateTime? _selectedDueDate;
  File? _selectedImage;
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedStatus = 'pending';

  final List<String> _statusOptions = ['pending', 'paid', 'overdue', 'cancelled'];

  @override
  void dispose() {
    _customerNameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1B263B),
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1B263B),
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDueDate = picked;
      });
    }
  }

  Future<void> _showImageSourceDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Add Invoice Image', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF1B263B)),
              title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final image = await CameraService.captureImage();
                if (image != null) {
                  setState(() {
                    _selectedImage = image;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF1B263B)),
              title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final image = await CameraService.pickFromGallery();
                if (image != null) {
                  setState(() {
                    _selectedImage = image;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      String? imageBase64;
      if (_selectedImage != null) {
        imageBase64 = await CameraService.convertToBase64(_selectedImage!);
      }

      final invoice = Invoice(
        customerName: _customerNameController.text.trim(),
        amount: double.parse(_amountController.text.trim()),
        date: _selectedDate,
        dueDate: _selectedDueDate,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        imagePath: imageBase64,
        userId: widget.user.id,
        createdAt: DateTime.now(),
        status: _selectedStatus,
      );

      final response = await ApiService.createInvoice(invoice);
      
      if (response['success'] == true) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Failed to create invoice';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error creating invoice: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Invoice', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
              Color(0xFF64FFDA),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image Section
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: _selectedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo, size: 48, color: Colors.white54),
                            const SizedBox(height: 8),
                            const Text('Add Invoice Image', style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _showImageSourceDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B263B),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.camera_alt, color: Colors.white),
                              label: const Text('Add Image', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                ),
                
                if (_selectedImage != null) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: _showImageSourceDialog,
                      icon: const Icon(Icons.edit, color: Color(0xFF64FFDA)),
                      label: const Text('Change Image', style: TextStyle(color: Color(0xFF64FFDA))),
                    ),
                  ),
                ],
                
                const SizedBox(height: 32),
                
                // Form Fields
                const Text('Invoice Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _customerNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Customer Name',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.person, color: Colors.white),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter the customer name';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _amountController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.attach_money, color: Colors.white),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter the amount';
                    }
                    if (double.tryParse(value.trim()) == null) {
                      return 'Please enter a valid amount';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Status Dropdown
                DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Status',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.flag, color: Colors.white),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  dropdownColor: const Color(0xFF1A1A1A),
                  items: _statusOptions.map((status) => DropdownMenuItem(
                    value: status,
                    child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white)),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedStatus = value;
                      });
                    }
                  },
                ),
                
                const SizedBox(height: 16),
                
                GestureDetector(
                  onTap: _selectDate,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Invoice Date', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            Text(
                              '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                GestureDetector(
                  onTap: _selectDueDate,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event, color: Colors.white),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Due Date (Optional)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            Text(
                              _selectedDueDate != null 
                                  ? '${_selectedDueDate!.day}/${_selectedDueDate!.month}/${_selectedDueDate!.year}'
                                  : 'Not set',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _descriptionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.description, color: Colors.white),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
                      ],
                    ),
                  ),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createInvoice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B263B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Create Invoice', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Invoice Detail Screen
class InvoiceDetailScreen extends StatelessWidget {
  final Invoice invoice;

  const InvoiceDetailScreen({Key? key, required this.invoice}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(invoice.customerName, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
              Color(0xFF64FFDA),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Invoice Image
              if (invoice.imagePath != null) ...[
                Container(
                  width: double.infinity,
                  height: 300,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(invoice.imagePath!),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => 
                          const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.white54)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
              
              // Invoice Details
              const Text('Invoice Details', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              _buildDetailCard('Customer', invoice.customerName, Icons.person),
              _buildDetailCard('Amount', '\$${invoice.amount.toStringAsFixed(2)}', Icons.attach_money),
              _buildDetailCard('Invoice Date', '${invoice.date.day}/${invoice.date.month}/${invoice.date.year}', Icons.calendar_today),
              
              if (invoice.dueDate != null)
                _buildDetailCard('Due Date', '${invoice.dueDate!.day}/${invoice.dueDate!.month}/${invoice.dueDate!.year}', Icons.event),
              
              _buildDetailCard('Status', invoice.status.toUpperCase(), Icons.flag, statusColor: _getStatusColor(invoice.status)),
              _buildDetailCard('Created', '${invoice.createdAt.day}/${invoice.createdAt.month}/${invoice.createdAt.year}', Icons.add_circle),
              
              if (invoice.description != null && invoice.description!.isNotEmpty)
                _buildDetailCard('Description', invoice.description!, Icons.description),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'overdue':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.white;
    }
  }

  Widget _buildDetailCard(String title, String value, IconData icon, {Color? statusColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                value, 
                style: TextStyle(
                  color: statusColor ?? Colors.white, 
                  fontSize: 16, 
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Enhanced Chat Screen (same as before but included for completeness)
class ChatScreen extends StatefulWidget {
  final User user;
  final List<Message> messages;
  final Function(Message) onMessageAdded;

  const ChatScreen({Key? key, required this.user, required this.messages, required this.onMessageAdded}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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

  void _sendMessage() async {
    String message = _controller.text.trim();
    if (message.isEmpty) return;
    
    _controller.clear();
    
    final userMessage = Message(
      sender: 'You',
      content: message,
      type: MessageType.user,
      timestamp: DateTime.now(),
    );
    widget.onMessageAdded(userMessage);
    
    setState(() => _isLoading = true);
    
    try {
      Map<String, dynamic> response = await ApiService.sendQuery(
        message, 
        conversationHistory: widget.messages.where((m) => m.type != MessageType.chart).toList()
      );
      
      if (response['success'] == true) {
        String responseText = response['message'] ?? 'Query completed successfully.';
        
        Map<String, dynamic>? chartData;
        if (response['chart'] != null) {
          chartData = response['chart'];
        }
        
        final aiMessage = Message(
          sender: 'AI Assistant',
          content: responseText,
          type: MessageType.assistant,
          timestamp: DateTime.now(),
          chartData: chartData,
        );
        widget.onMessageAdded(aiMessage);
      } else {
        String errorMessage = response['message'] ?? 'An error occurred while processing your request.';
        final errorMsg = Message(
          sender: 'AI Assistant',
          content: errorMessage,
          type: MessageType.error,
          timestamp: DateTime.now(),
        );
        widget.onMessageAdded(errorMsg);
      }
    } catch (e) {
      final errorMsg = Message(
        sender: 'AI Assistant',
        content: 'Network error: Please check your connection and try again.',
        type: MessageType.error,
        timestamp: DateTime.now(),
      );
      widget.onMessageAdded(errorMsg);
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.user.role == 'visitor')
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.user.roleColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.user.roleColor.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You have visitor access - sales queries only',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: widget.messages.length,
            itemBuilder: (context, index) {
              final message = widget.messages[index];
              return MessageBubble(message: message);
            },
          ),
        ),
        
        if (_isLoading)
          Container(
            padding: const EdgeInsets.all(16),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Processing...', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 60),
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Ask me anything...',
                        hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Colors.white30, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Colors.white, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendMessage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(12),
                    ),
                    child: const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: message.type == MessageType.user ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (message.type != MessageType.user) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: message.type == MessageType.error
                    ? LinearGradient(colors: [Colors.red, Colors.red.shade700])
                    : message.type == MessageType.system
                        ? const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF0D1B2A)])
                        : const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                message.type == MessageType.error
                    ? Icons.error
                    : message.type == MessageType.system
                        ? Icons.memory
                        : Icons.psychology,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
          ],
          
          Flexible(
            child: Column(
              crossAxisAlignment: message.type == MessageType.user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: message.type == MessageType.user
                        ? const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)])
                        : null,
                    color: message.type == MessageType.user
                        ? null
                        : message.type == MessageType.error
                            ? const Color(0xFF7F1D1D)
                            : message.type == MessageType.system
                                ? const Color(0xFF2E0249).withValues(alpha: 0.5)
                                : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(20),
                    border: message.type == MessageType.user
                        ? null
                        : Border.all(
                            color: message.type == MessageType.error
                                ? Colors.red
                                : message.type == MessageType.system
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.white.withOpacity(0.2),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content,
                        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                
                if (message.chartData != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bar_chart, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Chart: ${message.chartData!['chart_type'] ?? 'data visualization'}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (message.chartData!['chart_base64'] != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              base64Decode(message.chartData!['chart_base64']),
                              fit: BoxFit.contain,
                            ),
                          )
                        else
                          const SizedBox(
                            height: 100,
                            child: Center(
                              child: Text(
                                'Chart data available',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          if (message.type == MessageType.user) ...[
            const SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

// Enhanced Profile Screen with Face Authentication
class ProfileScreen extends StatefulWidget {
  final User user;

  const ProfileScreen({Key? key, required this.user}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  bool _isFaceAuthEnabled = false;
  String _biometricDescription = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final available = await BiometricAuthService.isBiometricAvailable();
    final enabled = await BiometricAuthService.isBiometricLoginEnabled();
    final description = await BiometricAuthService.getBiometricCapabilitiesDescription();
    
    setState(() {
      _isBiometricAvailable = available;
      _isBiometricEnabled = enabled;
      _isFaceAuthEnabled = widget.user.faceAuthEnabled;
      _biometricDescription = description;
    });
  }

  Future<void> _toggleBiometricLogin() async {
    setState(() => _isLoading = true);
    
    try {
      if (_isBiometricEnabled) {
        final success = await BiometricAuthService.disableBiometricLogin();
        if (success) {
          setState(() => _isBiometricEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Biometric login disabled'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to disable biometric login'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        final success = await BiometricAuthService.enableBiometricLogin(widget.user);
        if (success) {
          setState(() => _isBiometricEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Biometric login enabled successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to enable biometric login. Authentication may have been cancelled.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setupFaceAuth() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceAuthSetupScreen(user: widget.user),
      ),
    );
    
    if (result == true) {
      setState(() => _isFaceAuthEnabled = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face authentication set up successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } // Close _setupFaceAuth here

  // _buildInfoCard should be a separate method at the class level
  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }

  


  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [widget.user.roleColor, widget.user.roleColor.withValues(alpha: 0.7)]),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Icon(
                      _isFaceAuthEnabled ? Icons.face : 
                      _isBiometricEnabled ? Icons.fingerprint : Icons.person,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(widget.user.username, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(widget.user.fullName, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.user.roleColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: widget.user.roleColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      widget.user.role.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            const Text('Profile Information', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            _buildInfoCard('User ID', widget.user.id.toString(), Icons.tag),
            _buildInfoCard('Email', widget.user.email.isNotEmpty ? widget.user.email : 'Not provided', Icons.email),
            _buildInfoCard('Account Status', widget.user.isActive ? 'Active' : 'Inactive', Icons.verified),
            _buildInfoCard('Created', '${widget.user.createdAt.day}/${widget.user.createdAt.month}/${widget.user.createdAt.year}', Icons.calendar_today),
            
            const SizedBox(height: 32),
            
            // Face Authentication Section
            const Text('Face Authentication', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _isFaceAuthEnabled ? Icons.face : Icons.face_outlined,
                        color: _isFaceAuthEnabled ? Colors.green : Colors.white54,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isFaceAuthEnabled ? 'Face Authentication Enabled' : 'Face Authentication Disabled',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _isFaceAuthEnabled 
                                  ? 'You can login using face recognition'
                                  : 'Set up face recognition for quick login',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : (_isFaceAuthEnabled ? null : _setupFaceAuth),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFaceAuthEnabled ? Colors.grey : const Color(0xFF64FFDA),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isLoading 
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(_isFaceAuthEnabled ? Icons.check : Icons.face, color: Colors.white),
                      label: Text(
                        _isLoading 
                            ? 'Processing...'
                            : _isFaceAuthEnabled ? 'Face Auth Enabled' : 'Set Up Face Authentication',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Biometric Authentication Section
            const Text('Biometric Authentication', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _isBiometricEnabled ? Icons.fingerprint : Icons.fingerprint_outlined,
                        color: _isBiometricEnabled ? Colors.green : Colors.white54,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isBiometricEnabled ? 'Biometric Login Enabled' : 'Biometric Login Disabled',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _biometricDescription,
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isBiometricAvailable) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _toggleBiometricLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isBiometricEnabled ? Colors.red : const Color(0xFF1B263B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _isLoading 
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(_isBiometricEnabled ? Icons.fingerprint_outlined : Icons.fingerprint, color: Colors.white),
                        label: Text(
                          _isLoading 
                              ? 'Processing...'
                              : _isBiometricEnabled ? 'Disable Biometric Login' : 'Enable Biometric Login',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info, color: Colors.white70, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Biometric authentication not available on this device',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// Settings Screen
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF64FFDA)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.settings, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 24),
          const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('Settings features coming soon...', style: TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }
}

// User Management Screen (Enhanced)
class UserManagementScreen extends StatefulWidget {
  final User user;

  const UserManagementScreen({Key? key, required this.user}) : super(key: key);

  @override
  _UserManagementScreenState createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<User> _users = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.getAllUsers();

      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _users = (response['users'] as List)
                .map((user) => User.fromJson(user))
                .toList();
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response['message'] ?? 'Failed to load users';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading users: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createUser() async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController usernameController = TextEditingController();
    final TextEditingController fullNameController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    String selectedRole = 'user';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Create New User', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        content: Container(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF64FFDA)),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Username is required';
                      if (value.trim().length < 3) return 'Username must be at least 3 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: fullNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF64FFDA)),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Full name is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF64FFDA)),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Email is required';
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF64FFDA)),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Password is required';
                      if (value.length < 6) return 'Password must be at least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    style: const TextStyle(color: Colors.white),
                    dropdownColor: const Color(0xFF2A2A2A),
                    decoration: InputDecoration(
                      labelText: 'Role',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF64FFDA)),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('User')),
                      DropdownMenuItem(value: 'manager', child: Text('Manager')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged: (value) => selectedRole = value!,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);

                try {
                  setState(() => _isLoading = true);

                  final response = await http.post(
                    Uri.parse('${ApiService.baseUrl}/admin/create-user'),
                    headers: const {'Content-Type': 'application/json'},
                    body: json.encode({
                      'username': usernameController.text.trim(),
                      'full_name': fullNameController.text.trim(),
                      'email': emailController.text.trim(),
                      'password': passwordController.text,
                      'role': selectedRole,
                    }),
                  );

                  final result = json.decode(response.body);

                  if (result['success'] == true) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('User created successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _loadUsers(); // Refresh user list
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result['message'] ?? 'Failed to create user'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error creating user: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF64FFDA),
              foregroundColor: Colors.black,
            ),
            child: const Text('Create User', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _editUser(User user) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserEditScreen(user: user),
      ),
    );
    if (result == true) {
      _loadUsers();
    }
  }

  Future<void> _deleteUser(User user) async {
    if (user.id == widget.user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot delete your own account'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete User', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete ${user.username}? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await ApiService.deleteUser(user.id);
        if (response['success'] == true) {
          _loadUsers();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to delete user'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Loading users...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUsers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B263B),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('User Management', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          IconButton(
                            onPressed: _loadUsers,
                            icon: const Icon(Icons.refresh, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _users.isEmpty
                          ? const Center(
                              child: Text('No users found', style: TextStyle(color: Colors.white70, fontSize: 16)),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _users.length,
                              itemBuilder: (context, index) {
                                final user = _users[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: [user.roleColor, user.roleColor.withValues(alpha: 0.7)]),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Icon(
                                        user.faceAuthEnabled ? Icons.face :
                                        user.biometricEnabled ? Icons.fingerprint : Icons.person,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    title: Text(user.username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(user.fullName, style: const TextStyle(color: Colors.white70)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: user.roleColor.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: user.roleColor.withValues(alpha: 0.5)),
                                              ),
                                              child: Text(
                                                user.role.toUpperCase(),
                                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (user.faceAuthEnabled)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                                                ),
                                                child: const Text(
                                                  'FACE',
                                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            if (user.biometricEnabled) ...[
                                              if (user.faceAuthEnabled) const SizedBox(width: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                                                ),
                                                child: const Text(
                                                  'BIOMETRIC',
                                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, color: Colors.white),
                                      color: const Color(0xFF1A1A1A),
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          _editUser(user);
                                        } else if (value == 'delete') {
                                          _deleteUser(user);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit, color: Colors.white, size: 18),
                                              SizedBox(width: 8),
                                              Text('Edit', style: TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete, color: Colors.red, size: 18),
                                              SizedBox(width: 8),
                                              Text('Delete', style: TextStyle(color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createUser,
        backgroundColor: const Color(0xFF64FFDA),
        tooltip: 'Add New User',
        child: const Icon(Icons.person_add, color: Colors.black),
      ),
    );
  }
}
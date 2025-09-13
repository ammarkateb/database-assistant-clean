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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A148C),
          brightness: Brightness.dark,
          primary: const Color(0xFF4A148C),
          secondary: const Color(0xFF6A1B9A),
          tertiary: const Color(0xFF4A148C),
          surface: const Color(0xFF000000),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
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
  bool get canUploadReceipts => ['manager', 'admin'].contains(role);
  
  Color get roleColor {
    switch (role) {
      case 'visitor': return const Color(0xFF7B1FA2);
      case 'viewer': return const Color(0xFF6A1B9A);
      case 'manager': return const Color(0xFF4A148C);
      case 'admin': return const Color(0xFF2E0249);
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

class Receipt {
  final int? id;
  final String vendor;
  final double amount;
  final DateTime date;
  final String? description;
  final String? imagePath;
  final int userId;
  final DateTime uploadedAt;

  Receipt({
    this.id,
    required this.vendor,
    required this.amount,
    required this.date,
    this.description,
    this.imagePath,
    required this.userId,
    required this.uploadedAt,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'],
      vendor: json['vendor'],
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date']),
      description: json['description'],
      imagePath: json['image_path'],
      userId: json['user_id'],
      uploadedAt: DateTime.parse(json['uploaded_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vendor': vendor,
      'amount': amount,
      'date': date.toIso8601String(),
      'description': description,
      'image_base64': imagePath,
      'user_id': userId,
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

class FaceAuthService {
  static const String _awsAccessKey = 'YOUR_AWS_ACCESS_KEY'; // Replace with your AWS credentials
  static const String _awsSecretKey = 'YOUR_AWS_SECRET_KEY';
  static const String _awsRegion = 'us-east-1';
  static const String _collectionId = 'neural-pulse-faces';

  // Note: In production, use AWS SDK with proper credential management
  static Future<Map<String, dynamic>> enrollFace(File imageFile, String userId) async {
    try {
      final imageBase64 = await CameraService.convertToBase64(imageFile);
      
      // This would integrate with AWS Rekognition API
      // For now, returning mock response - you'll need to implement AWS SDK integration
      
      final response = await ApiService.enrollFaceWithServer(imageBase64, userId);
      return response;
      
    } catch (e) {
      return {'success': false, 'message': 'Face enrollment failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> verifyFace(File imageFile) async {
    try {
      final imageBase64 = await CameraService.convertToBase64(imageFile);
      
      final response = await ApiService.verifyFaceWithServer(imageBase64);
      return response;
      
    } catch (e) {
      return {'success': false, 'message': 'Face verification failed: $e'};
    }
  }

  static Future<File?> captureFaceImage() async {
    return await CameraService.captureImage();
  }
}

class BiometricAuthService {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<bool> isBiometricAvailable() async {
    try {
      final bool isAvailable = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  static Future<bool> authenticate() async {
    try {
      final bool isAvailable = await isBiometricAvailable();
      if (!isAvailable) return false;

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access your account',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      return didAuthenticate;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> storeUserCredentials(User user) async {
    try {
      final userJson = json.encode({
        'user_id': user.id,
        'username': user.username,
        'role': user.role,
        'full_name': user.fullName,
        'email': user.email,
        'is_active': user.isActive,
        'created_at': user.createdAt.toIso8601String(),
        'biometric_enabled': true,
        'face_auth_enabled': user.faceAuthEnabled,
      });
      
      await _secureStorage.write(key: 'user_credentials', value: userJson);
      await _secureStorage.write(key: 'biometric_enabled', value: 'true');
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> isBiometricLoginEnabled() async {
    try {
      final biometricEnabled = await _secureStorage.read(key: 'biometric_enabled');
      final userCredentials = await _secureStorage.read(key: 'user_credentials');
      return biometricEnabled == 'true' && userCredentials != null;
    } catch (e) {
      return false;
    }
  }

  static Future<User?> getStoredUserCredentials() async {
    try {
      final userJson = await _secureStorage.read(key: 'user_credentials');
      if (userJson != null) {
        final userData = json.decode(userJson);
        return User.fromJson(userData);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<LoginResult> loginWithBiometric() async {
    try {
      final isEnabled = await isBiometricLoginEnabled();
      if (!isEnabled) {
        return LoginResult.error('Biometric login not set up. Please login with username/password first.');
      }

      final authenticated = await authenticate();
      if (authenticated) {
        final user = await getStoredUserCredentials();
        if (user != null) {
          return LoginResult.success(user);
        } else {
          return LoginResult.error('Stored credentials not found. Please login with username/password.');
        }
      } else {
        return LoginResult.error('Biometric authentication failed or cancelled');
      }
    } catch (e) {
      return LoginResult.error('Biometric login error: ${e.toString()}');
    }
  }

  static Future<bool> enableBiometricLogin(User user) async {
    try {
      final authenticated = await authenticate();
      if (authenticated) {
        return await storeUserCredentials(user);
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> disableBiometricLogin() async {
    try {
      await _secureStorage.delete(key: 'user_credentials');
      await _secureStorage.delete(key: 'biometric_enabled');
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> clearStoredData() async {
    try {
      await _secureStorage.deleteAll();
    } catch (e) {
      // Ignore errors during cleanup
    }
  }

  static Future<String> getBiometricCapabilitiesDescription() async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return 'Biometric authentication not available on this device';
      }

      final biometrics = await getAvailableBiometrics();
      if (biometrics.isEmpty) {
        return 'No biometric methods set up. Please configure in device settings.';
      }

      List<String> availableTypes = [];
      if (biometrics.contains(BiometricType.fingerprint)) {
        availableTypes.add('Fingerprint');
      }
      if (biometrics.contains(BiometricType.face)) {
        availableTypes.add('Face recognition');
      }
      if (biometrics.contains(BiometricType.iris)) {
        availableTypes.add('Iris scan');
      }
      if (biometrics.contains(BiometricType.strong)) {
        availableTypes.add('Strong biometrics');
      }
      if (biometrics.contains(BiometricType.weak)) {
        availableTypes.add('Device authentication');
      }

      if (availableTypes.isNotEmpty) {
        return 'Available: ${availableTypes.join(', ')}';
      } else {
        return 'Biometric authentication available';
      }
    } catch (e) {
      return 'Unable to determine biometric capabilities';
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

  // Receipt API methods
  static Future<Map<String, dynamic>> uploadReceipt(Receipt receipt) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/receipts/upload'),
        headers: _getHeaders(),
        body: json.encode(receipt.toJson()),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getReceipts({int? userId}) async {
    try {
      String url = '$baseUrl/receipts';
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

  static Future<Map<String, dynamic>> deleteReceipt(int receiptId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/receipts/$receiptId'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Face authentication API methods
  static Future<Map<String, dynamic>> enrollFaceWithServer(String imageBase64, String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/face-auth/enroll'),
        headers: _getHeaders(),
        body: json.encode({
          'user_id': userId,
          'image_base64': imageBase64,
        }),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> verifyFaceWithServer(String imageBase64) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/face-auth/verify'),
        headers: _getHeaders(),
        body: json.encode({
          'image_base64': imageBase64,
        }),
      ).timeout(const Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Existing user management methods
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

  static Future<LoginResult> loginWithFace() async {
    try {
      final imageFile = await FaceAuthService.captureFaceImage();
      if (imageFile == null) {
        return LoginResult.error('Failed to capture face image');
      }

      final result = await FaceAuthService.verifyFace(imageFile);
      if (result['success'] == true && result['user'] != null) {
        _currentUser = User.fromJson(result['user']);
        return LoginResult.success(_currentUser!);
      } else {
        return LoginResult.error(result['message'] ?? 'Face authentication failed');
      }
    } catch (e) {
      return LoginResult.error('Face authentication error: ${e.toString()}');
    }
  }

  static Future<void> logout() async {
    _currentUser = null;
    await BiometricAuthService.clearStoredData();
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
                Color(0xFF4A148C),
                Color(0xFF6A1B9A),
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
                    gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)]),
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

class LoginSelectionScreen extends StatelessWidget {
  final bool hasBiometricCapability;

  const LoginSelectionScreen({Key? key, required this.hasBiometricCapability}) : super(key: key);

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
              Color(0xFF000000),
              Color(0xFF2E0249),
              Color(0xFF4A148C),
              Color(0xFF6A1B9A),
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
                      gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)]),
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
                        backgroundColor: const Color(0xFF4A148C),
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
                  
                  if (hasBiometricCapability) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _loginWithBiometric(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white, width: 2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        icon: const Icon(Icons.fingerprint, color: Colors.white),
                        label: const Text('Login with Biometric', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _loginWithFace(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF6A1B9A), width: 2),
                        foregroundColor: const Color(0xFF6A1B9A),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      icon: const Icon(Icons.face, color: Color(0xFF6A1B9A)),
                      label: const Text('Login with Face', style: TextStyle(color: Color(0xFF6A1B9A), fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  
                  if (!hasBiometricCapability) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info, color: Colors.white70, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Biometric authentication not available',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

// Receipt List Screen
class ReceiptListScreen extends StatefulWidget {
  final User user;

  const ReceiptListScreen({Key? key, required this.user}) : super(key: key);

  @override
  _ReceiptListScreenState createState() => _ReceiptListScreenState();
}

class _ReceiptListScreenState extends State<ReceiptListScreen> {
  List<Receipt> _receipts = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final response = await ApiService.getReceipts(userId: widget.user.id);
      
      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _receipts = (response['receipts'] as List)
                .map((receipt) => Receipt.fromJson(receipt))
                .toList();
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response['message'] ?? 'Failed to load receipts';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading receipts: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteReceipt(Receipt receipt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Receipt', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete this receipt from ${receipt.vendor}?', 
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

    if (confirmed == true && receipt.id != null) {
      final response = await ApiService.deleteReceipt(receipt.id!);
      if (response['success'] == true) {
        _loadReceipts(); // Refresh the list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to delete receipt'),
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
                  Text('Loading receipts...', style: TextStyle(color: Colors.white70)),
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
                        onPressed: _loadReceipts,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4A148C),
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
                          const Text('My Receipts', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          IconButton(
                            onPressed: _loadReceipts,
                            icon: const Icon(Icons.refresh, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _receipts.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.receipt_outlined, size: 64, color: Colors.white54),
                                  SizedBox(height: 16),
                                  Text('No receipts found', style: TextStyle(color: Colors.white70, fontSize: 16)),
                                  SizedBox(height: 8),
                                  Text('Tap the + button to add your first receipt', style: TextStyle(color: Colors.white54, fontSize: 14)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _receipts.length,
                              itemBuilder: (context, index) {
                                final receipt = _receipts[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)]),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: receipt.imagePath != null
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.memory(
                                                base64Decode(receipt.imagePath!),
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) => 
                                                    const Icon(Icons.receipt, color: Colors.white),
                                              ),
                                            )
                                          : const Icon(Icons.receipt, color: Colors.white),
                                    ),
                                    title: Text(receipt.vendor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('\$${receipt.amount.toStringAsFixed(2)}', 
                                             style: const TextStyle(color: Color(0xFF6A1B9A), fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text('${receipt.date.day}/${receipt.date.month}/${receipt.date.year}', 
                                             style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                        if (receipt.description != null && receipt.description!.isNotEmpty)
                                          Text(receipt.description!, 
                                               style: const TextStyle(color: Colors.white60, fontSize: 12),
                                               maxLines: 1,
                                               overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteReceipt(receipt),
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ReceiptDetailScreen(receipt: receipt),
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

// Receipt Upload Screen
class ReceiptUploadScreen extends StatefulWidget {
  final User user;

  const ReceiptUploadScreen({Key? key, required this.user}) : super(key: key);

  @override
  _ReceiptUploadScreenState createState() => _ReceiptUploadScreenState();
}

class _ReceiptUploadScreenState extends State<ReceiptUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vendorController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  File? _selectedImage;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _vendorController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF4A148C),
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

  Future<void> _showImageSourceDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Add Receipt Image', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF4A148C)),
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
              leading: const Icon(Icons.photo_library, color: Color(0xFF4A148C)),
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

  Future<void> _uploadReceipt() async {
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

      final receipt = Receipt(
        vendor: _vendorController.text.trim(),
        amount: double.parse(_amountController.text.trim()),
        date: _selectedDate,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        imagePath: imageBase64,
        userId: widget.user.id,
        uploadedAt: DateTime.now(),
      );

      final response = await ApiService.uploadReceipt(receipt);
      
      if (response['success'] == true) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Failed to upload receipt';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error uploading receipt: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Receipt', style: TextStyle(color: Colors.white)),
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
              Color(0xFF000000),
              Color(0xFF2E0249),
              Color(0xFF4A148C),
              Color(0xFF6A1B9A),
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
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                            const Text('Add Receipt Image', style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _showImageSourceDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A148C),
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
                      icon: const Icon(Icons.edit, color: Color(0xFF6A1B9A)),
                      label: const Text('Change Image', style: TextStyle(color: Color(0xFF6A1B9A))),
                    ),
                  ),
                ],
                
                const SizedBox(height: 32),
                
                // Form Fields
                const Text('Receipt Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _vendorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Vendor/Store Name',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.store, color: Colors.white),
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
                      return 'Please enter the vendor name';
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
                            const Text('Date', style: TextStyle(color: Colors.white70, fontSize: 12)),
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
                    onPressed: _isLoading ? null : _uploadReceipt,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A148C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Upload Receipt', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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

// Receipt Detail Screen
class ReceiptDetailScreen extends StatelessWidget {
  final Receipt receipt;

  const ReceiptDetailScreen({Key? key, required this.receipt}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(receipt.vendor, style: const TextStyle(color: Colors.white)),
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
              Color(0xFF000000),
              Color(0xFF2E0249),
              Color(0xFF4A148C),
              Color(0xFF6A1B9A),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Receipt Image
              if (receipt.imagePath != null) ...[
                Container(
                  width: double.infinity,
                  height: 300,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(receipt.imagePath!),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => 
                          const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.white54)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
              
              // Receipt Details
              const Text('Receipt Details', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              _buildDetailCard('Vendor', receipt.vendor, Icons.store),
              _buildDetailCard('Amount', '\${receipt.amount.toStringAsFixed(2)}', Icons.attach_money),
              _buildDetailCard('Date', '${receipt.date.day}/${receipt.date.month}/${receipt.date.year}', Icons.calendar_today),
              _buildDetailCard('Uploaded', '${receipt.uploadedAt.day}/${receipt.uploadedAt.month}/${receipt.uploadedAt.year}', Icons.upload),
              
              if (receipt.description != null && receipt.description!.isNotEmpty)
                _buildDetailCard('Description', receipt.description!, Icons.description),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailCard(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
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
                    gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)]),
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
                        ? const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF2E0249)])
                        : const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)]),
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
                        ? const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)])
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
                                    : Colors.white.withValues(alpha: 0.2),
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
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
    setState(() => _isLoading = true);
    
    try {
      final imageFile = await FaceAuthService.captureFaceImage();
      if (imageFile != null) {
        final result = await FaceAuthService.enrollFace(imageFile, widget.user.id.toString());
        
        if (result['success'] == true) {
          setState(() => _isFaceAuthEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Face authentication set up successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to set up face authentication'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to capture face image'),
            backgroundColor: Colors.red,
          ),
        );
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

  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
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
                      color: widget.user.roleColor.withValues(alpha: 0.2),
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                        backgroundColor: _isFaceAuthEnabled ? Colors.grey : const Color(0xFF6A1B9A),
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                          backgroundColor: _isBiometricEnabled ? Colors.red : const Color(0xFF4A148C),
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
                        color: Colors.grey.withValues(alpha: 0.2),
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
              gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)]),
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
                          backgroundColor: const Color(0xFF4A148C),
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
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                                                color: user.roleColor.withValues(alpha: 0.2),
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
                                                  color: Colors.blue.withValues(alpha: 0.2),
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
                                                  color: Colors.green.withValues(alpha: 0.2),
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
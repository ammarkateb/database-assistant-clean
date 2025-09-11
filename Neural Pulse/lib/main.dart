import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Force portrait orientation only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neural Pulse - AI Database Assistant',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00FFFF), // Bright cyan from icon
          brightness: Brightness.dark,
          primary: const Color(0xFF00FFFF), // Bright cyan
          secondary: const Color(0xFF0080FF), // Electric blue
          tertiary: const Color(0xFF8000FF), // Purple
          surface: const Color(0xFF000000), // Black background
          background: const Color(0xFF000000), // Black background
        ),
        scaffoldBackgroundColor: const Color(0xFF000000), // Pure black like icon
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: const Color(0xFF00FFFF),
        ),
      ),
      home: AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// User Model
class User {
  final int id;
  final String username;
  final String role;
  final String fullName;
  final String email;
  final bool isActive;
  final DateTime createdAt;
  final bool faceRecognitionEnabled;

  User({
    required this.id,
    required this.username,
    required this.role,
    required this.fullName,
    required this.email,
    required this.isActive,
    required this.createdAt,
    this.faceRecognitionEnabled = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['user_id'] ?? json['id'] ?? 1,
      username: json['username'],
      role: json['role'],
      fullName: json['full_name'] ?? json['name'] ?? '',
      email: json['email'] ?? '',
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      faceRecognitionEnabled: json['face_recognition_enabled'] ?? false,
    );
  }

  bool get canManageUsers => role == 'admin';
  bool get canUploadReceipts => ['manager', 'admin'].contains(role);
  
  Color get roleColor {
    switch (role) {
      case 'visitor': return const Color(0xFF00FF80);  // Bright green from icon
      case 'viewer': return const Color(0xFF00FFFF);   // Bright cyan
      case 'manager': return const Color(0xFF0080FF);  // Electric blue
      case 'admin': return const Color(0xFF8000FF);    // Purple from icon
      default: return const Color(0xFF808080);
    }
  }
}

// Message Model
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

enum MessageType { user, assistant, system, error, chart }

// API Service
class ApiService {
  static const String baseUrl = 'https://database-assistant-clean-production.up.railway.app';
  static Map<String, String> _cookies = {};
  
  static Map<String, String> _getHeaders() {
    Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    if (_cookies.isNotEmpty) {
      String cookieString = _cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
      headers['Cookie'] = cookieString;
    }
    
    return headers;
  }
  
  static void storeCookies(Map<String, String> cookies) {
    _cookies.addAll(cookies);
  }
  
  static Future<Map<String, dynamic>> sendQuery(String query) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/query'),
        headers: _getHeaders(),
        body: json.encode({'query': query}),
      ).timeout(Duration(seconds: 60));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getAllUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/users'),
        headers: _getHeaders(),
      ).timeout(Duration(seconds: 30));
      
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
      ).timeout(Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> registerFace(String imageBase64) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/facial-auth/register'),
        headers: _getHeaders(),
        body: json.encode({'image': imageBase64}),
      ).timeout(Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}

// Facial Auth Service
class FacialAuthService {
  static const String baseUrl = 'https://database-assistant-clean-production.up.railway.app';

  static Future<Map<String, dynamic>> authenticateWithFace(String imageBase64) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/facial-auth/authenticate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'image': imageBase64}),
      ).timeout(Duration(seconds: 30));
      
      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}

// Auth Service
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
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      ).timeout(Duration(seconds: 30));

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

  static Future<LoginResult> loginWithFace(String imageBase64) async {
    try {
      final result = await FacialAuthService.authenticateWithFace(imageBase64);
      
      if (result['success'] == true) {
        _currentUser = User(
          id: 1,
          username: result['user']['name'],
          role: result['permission_level'],
          fullName: result['user']['name'],
          email: '',
          isActive: true,
          createdAt: DateTime.now(),
          faceRecognitionEnabled: true,
        );
        return LoginResult.success(_currentUser!);
      } else {
        return LoginResult.error(result['message'] ?? 'Facial authentication failed');
      }
    } catch (e) {
      return LoginResult.error('Network error: Please check your connection');
    }
  }

  static Future<void> logout() async {
    _currentUser = null;
  }
}

class LoginResult {
  final bool success;
  final User? user;
  final String? error;

  LoginResult.success(this.user) : success = true, error = null;
  LoginResult.error(this.error) : success = false, user = null;
}

// Auth Wrapper
class AuthWrapper extends StatefulWidget {
  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    await Future.delayed(Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _currentUser = AuthService.currentUser;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF000000), 
                Color(0xFF1A1A1A),
                Color(0xFF2A2A2A),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00FFFF), Color(0xFF0080FF)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.psychology, size: 64, color: Colors.white),
                ),
                SizedBox(height: 24),
                Text('Neural Pulse', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('AI Database Assistant', style: TextStyle(color: Color(0xFF00FFFF), fontSize: 16)),
                SizedBox(height: 32),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FFFF)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _currentUser != null
        ? MainNavigationScreen(user: _currentUser!)
        : LoginSelectionScreen();
  }
}

// Login Selection Screen
class LoginSelectionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF000000), 
              Color(0xFF1A1A1A),
              Color(0xFF2A2A2A),
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
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF00FFFF), Color(0xFF0080FF)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.psychology, size: 64, color: Colors.white),
                  ),
                  SizedBox(height: 32),
                  Text('Neural Pulse', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('AI Database Assistant', style: TextStyle(color: Color(0xFF00FFFF), fontSize: 18)),
                  SizedBox(height: 48),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => LoginScreen()));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF00FFFF),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      icon: Icon(Icons.login, color: Colors.white),
                      label: Text('Login with Username', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => FacialLoginScreen()));
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Color(0xFF0080FF), width: 2),
                        foregroundColor: Color(0xFF0080FF),
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      icon: Icon(Icons.face, color: Color(0xFF0080FF)),
                      label: Text('Login with Face Recognition', style: TextStyle(color: Color(0xFF0080FF), fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Username Login Screen
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
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
        if (mounted) {
          setState(() {
            _errorMessage = result.error;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF000000), 
              Color(0xFF1A1A1A),
              Color(0xFF2A2A2A),
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
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF00FFFF), Color(0xFF0080FF)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.login, size: 48, color: Colors.white),
                    ),
                    SizedBox(height: 32),
                    Text('Username Login', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    SizedBox(height: 48),
                    
                    TextFormField(
                      controller: _usernameController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.person, color: Color(0xFF00FFFF)),
                        filled: true,
                        fillColor: Color(0xFF1A1A1A).withOpacity(0.6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: Colors.white30, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: Color(0xFF00FFFF), width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your username';
                        }
                        return null;
                      },
                    ),
                    
                    SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _passwordController,
                      style: TextStyle(color: Colors.white),
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.lock, color: Color(0xFF00FFFF)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility : Icons.visibility_off,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: Color(0xFF1A1A1A).withOpacity(0.6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: Colors.white30, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: Color(0xFF00FFFF), width: 2),
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
                    
                    SizedBox(height: 24),
                    
                    if (_errorMessage != null)
                      Container(
                        padding: EdgeInsets.all(12),
                        margin: EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      ),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF00FFFF),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
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

// Facial Recognition Login Screen
class FacialLoginScreen extends StatefulWidget {
  @override
  _FacialLoginScreenState createState() => _FacialLoginScreenState();
}

class _FacialLoginScreenState extends State<FacialLoginScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Camera permission is required for facial recognition';
          });
        }
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'No cameras available on this device';
          });
        }
        return;
      }

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera, 
        ResolutionPreset.high, 
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize camera: $e';
        });
      }
    }
  }

  Future<void> _takePictureAndAuthenticate() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final XFile picture = await _cameraController!.takePicture();
      final Uint8List imageBytes = await picture.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      final result = await AuthService.loginWithFace(base64Image);

      if (result.success && result.user != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => MainNavigationScreen(user: result.user!)),
          (route) => false,
        );
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = result.error;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Authentication failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Facial Recognition Login', style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF000000), 
              Color(0xFF1A1A1A),
              Color(0xFF2A2A2A),
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
                  if (!_isCameraInitialized) ...[
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF00FFFF), Color(0xFF0080FF)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.face, size: 48, color: Colors.white),
                    ),
                    SizedBox(height: 32),
                    Text('Initializing Camera...', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: 16),
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FFFF)),
                    ),
                  ] else ...[
                    Container(
                      width: 280,
                      height: 350,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Color(0xFF00FFFF), width: 3),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: AspectRatio(
                          aspectRatio: 3/4, // Fixed aspect ratio for portrait
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                    ),
                    SizedBox(height: 32),
                    Text('Position your face in the frame', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Make sure your face is well-lit and clearly visible', style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                  ],
                  
                  SizedBox(height: 48),
                  
                  if (_errorMessage != null)
                    Container(
                      padding: EdgeInsets.all(12),
                      margin: EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),
                  
                  if (_isCameraInitialized)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _takePictureAndAuthenticate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF00FFFF),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        icon: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(Icons.camera_alt, color: Colors.white),
                        label: Text(
                          _isLoading ? 'Authenticating...' : 'Authenticate with Face',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Main Navigation Screen
class MainNavigationScreen extends StatefulWidget {
  final User user;

  const MainNavigationScreen({Key? key, required this.user}) : super(key: key);

  @override
  _MainNavigationScreenState createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  Widget _getCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return ChatScreen(user: widget.user);
      case 1:
        if (widget.user.canManageUsers) {
          return UserManagementScreen(user: widget.user);
        } else {
          return SettingsScreen(user: widget.user);
        }
      case 2:
        if (widget.user.canManageUsers) {
          return SettingsScreen(user: widget.user);
        } else {
          return ProfileScreen(user: widget.user);
        }
      case 3:
        return ProfileScreen(user: widget.user);
      default:
        return ChatScreen(user: widget.user);
    }
  }

  List<BottomNavigationBarItem> _getBottomNavItems() {
    List<BottomNavigationBarItem> items = [
      BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Chat'),
    ];
    
    if (widget.user.canManageUsers) {
      items.add(BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Users'));
      items.add(BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'));
    } else {
      items.add(BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'));
    }
    
    items.add(BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'));
    
    return items;
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Logout', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Logout', style: TextStyle(color: Color(0xFF8000FF))),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await AuthService.logout();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginSelectionScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF000000), 
              Color(0xFF1A1A1A),
              Color(0xFF2A2A2A),
            ],
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00FFFF).withOpacity(0.3), Color(0xFF0080FF).withOpacity(0.2)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF00FFFF), Color(0xFF0080FF)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.user.faceRecognitionEnabled ? Icons.face : Icons.psychology,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Neural Pulse', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              Text('Welcome, ${widget.user.username}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                              SizedBox(width: 8),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: widget.user.roleColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: widget.user.roleColor.withOpacity(0.5)),
                                ),
                                child: Text(
                                  widget.user.role.toUpperCase(),
                                  style: TextStyle(color: widget.user.roleColor, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _logout,
                      icon: Icon(Icons.logout, color: Color(0xFF8000FF), size: 20),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _getCurrentScreen()),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Color(0xFF1A1A1A),
        selectedItemColor: Color(0xFF00FFFF),
        unselectedItemColor: Colors.white.withOpacity(0.6),
        items: _getBottomNavItems(),
      ),
    );
  }
}

// Chat Screen
class ChatScreen extends StatefulWidget {
  final User user;

  const ChatScreen({Key? key, required this.user}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeChat() {
    _addMessage('AI Assistant', _getWelcomeMessage(), MessageType.system);
  }

  String _getWelcomeMessage() {
    String baseMessage = 'Hi ${widget.user.username}! I\'m your AI Database Assistant.';
    
    switch (widget.user.role) {
      case 'visitor':
        return '$baseMessage I can help you with sales-related queries only.';
      case 'viewer':
        return '$baseMessage I can show you products, cities, invoices, and customer information.';
      case 'manager':
        return '$baseMessage I have full access to help you with products, invoices, customers, and receipt processing.';
      case 'admin':
        return '$baseMessage I have complete access to all database operations. How can I help you today?';
      default:
        return '$baseMessage How can I help you explore your data today?';
    }
  }

  void _addMessage(String sender, String content, MessageType type, {Map<String, dynamic>? chartData}) {
    setState(() {
      _messages.add(Message(
        sender: sender,
        content: content,
        type: type,
        timestamp: DateTime.now(),
        chartData: chartData,
      ));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    String message = _controller.text.trim();
    if (message.isEmpty) return;
    
    _controller.clear();
    _addMessage('You', message, MessageType.user);
    
    setState(() => _isLoading = true);
    
    try {
      Map<String, dynamic> response = await ApiService.sendQuery(message);
      
      if (response['success'] == true) {
        String responseText = response['message'] ?? 'Query completed successfully.';
        
        // Handle chart data if present
        Map<String, dynamic>? chartData;
        if (response['chart'] != null) {
          chartData = response['chart'];
        }
        
        _addMessage('AI Assistant', responseText, MessageType.assistant, chartData: chartData);
        
        // Show data if present
        if (response['data'] != null && response['data'].isNotEmpty) {
          List<dynamic> data = response['data'];
          if (data.length <= 10) {
            // Show small datasets inline
            String dataText = '\n\nData:\n';
            for (var row in data.take(5)) {
              dataText += '• ${row.values.join(' | ')}\n';
            }
            if (data.length > 5) {
              dataText += '... and ${data.length - 5} more rows';
            }
            _addMessage('AI Assistant', dataText, MessageType.assistant);
          } else {
            // Summarize large datasets
            _addMessage('AI Assistant', '\n\nFound ${data.length} records. Showing summary of first few rows...', MessageType.assistant);
          }
        }
      } else {
        String errorMessage = response['message'] ?? 'An error occurred while processing your request.';
        _addMessage('AI Assistant', errorMessage, MessageType.error);
      }
    } catch (e) {
      _addMessage('AI Assistant', 'Network error: Please check your connection and try again.', MessageType.error);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.user.role == 'visitor')
          Container(
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.user.roleColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.user.roleColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: widget.user.roleColor, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You have visitor access - sales queries only',
                    style: TextStyle(color: widget.user.roleColor, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return MessageBubble(message: message);
            },
          ),
        ),
        
        if (_isLoading)
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FFFF)),
                ),
                SizedBox(width: 12),
                Text('Processing your request...', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        
        Container(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: Color(0xFF1A1A1A).withOpacity(0.9),
            border: Border(top: BorderSide(color: Color(0xFF00FFFF).withOpacity(0.3))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    constraints: BoxConstraints(maxHeight: 60),
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: Colors.white),
                      maxLines: 2,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Ask me about your data...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: Colors.white30, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: Color(0xFF00FFFF), width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        filled: true,
                        fillColor: Color(0xFF1A1A1A).withOpacity(0.6),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00FFFF), Color(0xFF0080FF)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendMessage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: CircleBorder(),
                      padding: EdgeInsets.all(12),
                    ),
                    child: Icon(Icons.send, color: Colors.white, size: 20),
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

// Message Bubble
class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: message.type == MessageType.user 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        children: [
          if (message.type != MessageType.user) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: message.type == MessageType.error
                    ? LinearGradient(colors: [Colors.red, Colors.red.shade700])
                    : message.type == MessageType.system
                        ? LinearGradient(colors: [Color(0xFF0080FF), Color(0xFF8000FF)])
                        : LinearGradient(colors: [Color(0xFF00FFFF), Color(0xFF0080FF)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                message.type == MessageType.error
                    ? Icons.error
                    : message.type == MessageType.system
                        ? Icons.info
                        : Icons.psychology,
                color: Colors.white,
                size: 16,
              ),
            ),
            SizedBox(width: 12),
          ],
          
          Flexible(
            child: Column(
              crossAxisAlignment: message.type == MessageType.user 
                  ? CrossAxisAlignment.end 
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: message.type == MessageType.user
                        ? LinearGradient(colors: [Color(0xFF00FFFF), Color(0xFF0080FF)])
                        : null,
                    color: message.type == MessageType.user
                        ? null
                        : message.type == MessageType.error
                            ? Color(0xFF7F1D1D)
                            : Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(20),
                    border: message.type == MessageType.user
                        ? null
                        : Border.all(
                            color: message.type == MessageType.error
                                ? Colors.red
                                : Color(0xFF00FFFF).withOpacity(0.3),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content,
                        style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                
                // Chart display if present
                if (message.chartData != null) ...[
                  SizedBox(height: 8),
                  Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Color(0xFF00FFFF).withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.bar_chart, color: Color(0xFF00FFFF), size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Chart: ${message.chartData!['chart_type'] ?? 'data visualization'}',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        if (message.chartData!['chart_base64'] != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              base64Decode(message.chartData!['chart_base64']),
                              fit: BoxFit.contain,
                            ),
                          )
                        else
                          Container(
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
            SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFF00FFFF).withOpacity(0.5)),
              ),
              child: Icon(Icons.person, color: Color(0xFF00FFFF), size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

// Settings Screen with Face Registration
class SettingsScreen extends StatefulWidget {
  final User user;

  const SettingsScreen({Key? key, required this.user}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _faceRecognitionEnabled = false;

  @override
  void initState() {
    super.initState();
    _faceRecognitionEnabled = widget.user.faceRecognitionEnabled;
  }

  void _showFaceRegistrationDialog() {
    showDialog(
      context: context,
      builder: (context) => FaceRegistrationDialog(
        user: widget.user,
        onRegistrationComplete: () {
          setState(() {
            _faceRecognitionEnabled = true;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 24),
          
          // Face Recognition Section
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Color(0xFF00FFFF).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF00FFFF), Color(0xFF0080FF)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.face, color: Colors.white, size: 24),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Face Recognition',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Login with your face for quick access',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                
                if (_faceRecognitionEnabled) ...[
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color(0xFF00FF80).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Color(0xFF00FF80).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Color(0xFF00FF80), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Face recognition is enabled',
                          style: TextStyle(color: Color(0xFF00FF80), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showFaceRegistrationDialog,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Color(0xFF0080FF), width: 2),
                        foregroundColor: Color(0xFF0080FF),
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(Icons.update),
                      label: Text('Update Face Data'),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Set up face recognition for faster login',
                            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showFaceRegistrationDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF00FFFF),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      icon: Icon(Icons.face),
                      label: Text('Set Up Face Recognition'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          SizedBox(height: 20),
          
          // Account Settings
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Color(0xFF0080FF).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0080FF), Color(0xFF8000FF)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.settings, color: Colors.white, size: 24),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'Account Settings',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                
                _buildSettingItem('Username', widget.user.username, Icons.person),
                _buildSettingItem('Role', widget.user.role.toUpperCase(), Icons.security, color: widget.user.roleColor),
                _buildSettingItem('Full Name', widget.user.fullName.isNotEmpty ? widget.user.fullName : 'Not set', Icons.badge),
                _buildSettingItem('Account Status', widget.user.isActive ? 'Active' : 'Inactive', 
                    widget.user.isActive ? Icons.check_circle : Icons.cancel,
                    color: widget.user.isActive ? Color(0xFF00FF80) : Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSettingItem(String label, String value, IconData icon, {Color? color}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.white.withOpacity(0.5), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Face Registration Dialog
class FaceRegistrationDialog extends StatefulWidget {
  final User user;
  final VoidCallback? onRegistrationComplete;

  const FaceRegistrationDialog({Key? key, required this.user, this.onRegistrationComplete}) : super(key: key);

  @override
  _FaceRegistrationDialogState createState() => _FaceRegistrationDialogState();
}

class _FaceRegistrationDialogState extends State<FaceRegistrationDialog> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        setState(() => _errorMessage = 'Camera permission required');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMessage = 'No cameras available');
        return;
      }

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera, 
        ResolutionPreset.high, 
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to initialize camera: $e');
    }
  }

  Future<void> _registerFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final XFile picture = await _cameraController!.takePicture();
      final Uint8List imageBytes = await picture.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      final result = await ApiService.registerFace(base64Image);

      if (result['success'] == true) {
        Navigator.pop(context);
        if (widget.onRegistrationComplete != null) {
          widget.onRegistrationComplete!();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Face registration successful!'),
            backgroundColor: Color(0xFF00FF80),
          ),
        );
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Face registration failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Face registration failed: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Color(0xFF000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: EdgeInsets.all(24),
        constraints: BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Set Up Face Recognition',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            SizedBox(height: 16),
            
            if (!_isCameraInitialized) ...[
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00FFFF), Color(0xFF0080FF)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.face, size: 48, color: Colors.white),
              ),
              SizedBox(height: 16),
              Text('Initializing Camera...', style: TextStyle(color: Colors.white, fontSize: 16)),
              SizedBox(height: 16),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FFFF)),
              ),
            ] else ...[
              Container(
                width: 240,
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Color(0xFF00FFFF), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: AspectRatio(
                    aspectRatio: 3/4, // Fixed aspect ratio for portrait
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Position your face in the frame',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Make sure your face is well-lit and clearly visible',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
            
            SizedBox(height: 20),
            
            if (_errorMessage != null)
              Container(
                padding: EdgeInsets.all(12),
                margin: EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            
            if (_isCameraInitialized) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _registerFace,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF00FFFF),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(Icons.camera_alt),
                  label: Text(_isLoading ? 'Registering...' : 'Register Face'),
                ),
              ),
              SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Simple User Management Screen
class UserManagementScreen extends StatelessWidget {
  final User user;

  const UserManagementScreen({Key? key, required this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00FFFF), Color(0xFF0080FF)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.people, size: 64, color: Colors.white),
          ),
          SizedBox(height: 24),
          Text(
            'User Management',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Text(
            'Admin features coming soon...',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// Profile Screen
class ProfileScreen extends StatelessWidget {
  final User user;

  const ProfileScreen({Key? key, required this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [user.roleColor.withOpacity(0.3), user.roleColor.withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: user.roleColor.withOpacity(0.5)),
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: user.roleColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: user.roleColor, width: 3),
                  ),
                  child: Icon(
                    user.faceRecognitionEnabled ? Icons.face : Icons.person,
                    size: 40,
                    color: user.roleColor,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  user.fullName.isNotEmpty ? user.fullName : user.username,
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text('@${user.username}', style: TextStyle(color: Colors.white70, fontSize: 16)),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: user.roleColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: user.roleColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    user.role.toUpperCase(),
                    style: TextStyle(color: user.roleColor, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 24),
          
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Color(0xFF00FFFF).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account Information', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 16),
                
                if (user.email.isNotEmpty)
                  _buildInfoRow('Email', user.email, Icons.email),
                
                _buildInfoRow(
                  'Account Created',
                  '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}',
                  Icons.calendar_today,
                ),
                
                _buildInfoRow(
                  'Account Status',
                  user.isActive ? 'Active' : 'Inactive',
                  user.isActive ? Icons.check_circle : Icons.cancel,
                  color: user.isActive ? Color(0xFF00FF80) : Colors.red,
                ),
                
                _buildInfoRow(
                  'Authentication Method',
                  user.faceRecognitionEnabled ? 'Facial Recognition' : 'Username & Password',
                  user.faceRecognitionEnabled ? Icons.face : Icons.password,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value, IconData icon, {Color? color}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.white.withOpacity(0.5), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
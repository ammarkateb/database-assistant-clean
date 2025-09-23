import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://neural-pulse-production.up.railway.app';
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

  // User authentication methods
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: _getHeaders(),
        body: json.encode({
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 30));

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        // Store cookies if authentication successful
        if (response.headers['set-cookie'] != null) {
          final cookies = _parseCookies(response.headers['set-cookie']);
          storeCookies(cookies);
        }

        return {
          'success': true,
          'user': responseData['user'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Login failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> register(String username, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: _getHeaders(),
        body: json.encode({
          'username': username,
          'email': email,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 30));

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'user': responseData['user'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Registration failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  // Chat methods
  static Future<Map<String, dynamic>> createChatSession(Map<String, dynamic> sessionData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/sessions'),
        headers: _getHeaders(),
        body: json.encode(sessionData),
      ).timeout(const Duration(seconds: 30));

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'session_id': responseData['session_id'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to create chat session',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> sendChatMessage(String message) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/message'),
        headers: _getHeaders(),
        body: json.encode({
          'message': message,
        }),
      ).timeout(const Duration(seconds: 30));

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'response': responseData['response'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to get AI response',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> sendQuery(String query, {List<dynamic>? conversationHistory}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/query'),
        headers: _getHeaders(),
        body: json.encode({
          'query': query,
        }),
      ).timeout(const Duration(seconds: 30));

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'message': responseData['message'],
          'data': responseData['data'] ?? [],
          'sql_query': responseData['sql_query'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Query failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> executeDatabaseQuery(String queryText) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/query'),
        headers: _getHeaders(),
        body: json.encode({
          'question': queryText,
        }),
      ).timeout(const Duration(seconds: 30));

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'sql_query': responseData['sql_query'],
          'message': responseData['message'],
        };
      } else {
        return {
          'success': false,
          'data': [],
          'message': responseData['message'] ?? 'Query failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'data': [],
        'message': 'Network error: $e',
      };
    }
  }

  // Face authentication methods (keeping your existing ones)
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

      // Extract and store cookies from successful face authentication
      if (response.statusCode == 200) {
        if (response.headers['set-cookie'] != null) {
          final cookies = _parseCookies(response.headers['set-cookie']);
          storeCookies(cookies);
        }
      }

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
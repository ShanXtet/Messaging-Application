import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'storage_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Base HTTP client
  final http.Client _client = http.Client();

  // Get auth headers
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await StorageService.getAuthToken();
    if (token != null) {
      return ApiConstants.authHeaders(token);
    }
    return ApiConstants.defaultHeaders;
  }

  // Generic GET request
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final headers = await _getAuthHeaders();
      final url = '${ApiConstants.baseUrl}$endpoint';
      print('[API] GET $url'); // Debug log
      
      final response = await _client.get(
        Uri.parse(url),
        headers: headers,
      );
      
      print('[API] Response status: ${response.statusCode}'); // Debug log
      print('[API] Response headers: ${response.headers}'); // Debug log
      print('[API] Response body preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}'); // Debug log

      if (response.statusCode == 200) {
        try {
          return jsonDecode(response.body);
        } catch (parseError) {
          throw Exception('Invalid JSON response from server');
        }
      } else if (response.statusCode == 401) {
        // Token expired or invalid
        await StorageService.clearAll();
        throw Exception('Unauthorized - Please login again');
      } else {
        // Try to parse error response as JSON, but handle non-JSON responses gracefully
        try {
          final errorBody = jsonDecode(response.body);
          throw Exception(errorBody['error'] ?? 'Request failed with status: ${response.statusCode}');
        } catch (parseError) {
          // If response body is not JSON (e.g., HTML error page), throw a generic error
          throw Exception('Request failed with status: ${response.statusCode}. Server returned: ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}');
        }
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Generic POST request
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data) async {
    try {
      final headers = await _getAuthHeaders();
      final url = '${ApiConstants.baseUrl}$endpoint';
      print('[API] POST $url'); // Debug log
      print('[API] POST data: $data'); // Debug log
      
      final response = await _client.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(data),
      );
      
      print('[API] Response status: ${response.statusCode}'); // Debug log
      print('[API] Response headers: ${response.headers}'); // Debug log
      print('[API] Response body preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}'); // Debug log

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        await StorageService.clearAll();
        throw Exception('Unauthorized - Please login again');
      } else {
        // Try to parse error response as JSON, but handle non-JSON responses gracefully
        try {
          final errorBody = jsonDecode(response.body);
          throw Exception(errorBody['error'] ?? 'Request failed with status: ${response.statusCode}');
        } catch (parseError) {
          // If response body is not JSON (e.g., HTML error page), throw a generic error
          throw Exception('Request failed with status: ${response.statusCode}. Server returned: ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}');
        }
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Auth endpoints
  Future<Map<String, dynamic>> login(String email, String password) async {
    return await post(ApiConstants.login, {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
  }

  Future<Map<String, dynamic>> register(String name, String email, String password, String? phone) async {
    return await post(ApiConstants.register, {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
    });
  }

  Future<Map<String, dynamic>> getProfile() async {
    return await get(ApiConstants.me);
  }

  // Chat endpoints
  Future<Map<String, dynamic>> getThreads() async {
    return await get(ApiConstants.threads);
  }

  Future<Map<String, dynamic>> getMessages({
    String? peerId,
    String? peerEmail,
    String? conversationId,
    int limit = 30,
    DateTime? before,
  }) async {
    final queryParams = <String, String>{};
    
    if (conversationId != null) {
      queryParams['conversationId'] = conversationId;
    } else if (peerId != null) {
      queryParams['peerId'] = peerId;
    } else if (peerEmail != null) {
      queryParams['peerEmail'] = peerEmail;
    }
    
    queryParams['limit'] = limit.toString();
    if (before != null) {
      queryParams['before'] = before.toIso8601String();
    }

    final queryString = Uri(queryParameters: queryParams).query;
    return await get('${ApiConstants.messages}?$queryString');
  }

  Future<Map<String, dynamic>> sendMessage({
    String? toId,
    String? toEmail,
    required String text,
  }) async {
    return await post(ApiConstants.messages, {
      if (toId != null) 'toId': toId,
      if (toEmail != null) 'toEmail': toEmail,
      'text': text.trim(),
    });
  }

  Future<Map<String, dynamic>> createConversation(String peerId) async {
    return await post(ApiConstants.conversations, {
      'peerId': peerId,
    });
  }

  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    return await get('${ApiConstants.conversations}/$conversationId');
  }

  // Mark messages as read for a conversation
  Future<Map<String, dynamic>> markMessagesAsRead(String conversationId) async {
    return await post('${ApiConstants.conversations}/$conversationId/read', {});
  }


  Future<Map<String, dynamic>> getConnectedUsers() async {
    return await get(ApiConstants.connectedUsers);
  }

  Future<Map<String, dynamic>> getUserStatus(String userId) async {
    return await get('/api/users/$userId/status');
  }

  // User discovery endpoints
  Future<Map<String, dynamic>> searchUsers(String query, {int limit = 20}) async {
    final queryParams = <String, String>{
      'q': query.trim(),
      'limit': limit.toString(),
    };
    final queryString = Uri(queryParameters: queryParams).query;
    return await get('${ApiConstants.userSearch}?$queryString');
  }

  Future<Map<String, dynamic>> getUsers({int limit = 50, int offset = 0}) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    final queryString = Uri(queryParameters: queryParams).query;
    return await get('${ApiConstants.users}?$queryString');
  }

  Future<Map<String, dynamic>> getUserById(String userId) async {
    return await get('${ApiConstants.users}/$userId');
  }

  // File upload
  Future<Map<String, dynamic>> uploadFile(File file) async {
    try {
      final headers = await _getAuthHeaders();
      // Remove Content-Type for multipart upload
      headers.remove('Content-Type');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}/api/upload'),
      );
      
      request.headers.addAll(headers);
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        await StorageService.clearAll();
        throw Exception('Unauthorized - Please login again');
      } else {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? 'Upload failed');
      }
    } catch (e) {
      throw Exception('Upload error: $e');
    }
  }

  // Dispose
  void dispose() {
    _client.close();
  }
}

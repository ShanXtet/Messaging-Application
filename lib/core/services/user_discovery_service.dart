import '../models/user.dart';
import 'api_service.dart';

class UserDiscoveryService {
  static final UserDiscoveryService _instance = UserDiscoveryService._internal();
  factory UserDiscoveryService() => _instance;
  UserDiscoveryService._internal();

  final ApiService _apiService = ApiService();

  // Search users by name or email
  Future<List<User>> searchUsers(String query, {int limit = 20}) async {
    try {
      final response = await _apiService.searchUsers(query, limit: limit);
      final usersData = response['users'] as List<dynamic>;
      
      return usersData.map((userData) => User.fromJson(userData)).toList();
    } catch (e) {
      print('[UserDiscovery] Search error: $e');
      return [];
    }
  }

  // Get all users with pagination
  Future<Map<String, dynamic>> getUsers({int limit = 50, int offset = 0}) async {
    try {
      final response = await _apiService.getUsers(limit: limit, offset: offset);
      final usersData = response['users'] as List<dynamic>;
      
      final users = usersData.map((userData) => User.fromJson(userData)).toList();
      
      return {
        'users': users,
        'total': response['total'] ?? 0,
        'hasMore': response['hasMore'] ?? false,
      };
    } catch (e) {
      print('[UserDiscovery] Get users error: $e');
      return {
        'users': <User>[],
        'total': 0,
        'hasMore': false,
      };
    }
  }

  // Get specific user by ID
  Future<User?> getUserById(String userId) async {
    try {
      final response = await _apiService.getUserById(userId);
      final userData = response['user'] as Map<String, dynamic>;
      
      return User.fromJson(userData);
    } catch (e) {
      print('[UserDiscovery] Get user error: $e');
      return null;
    }
  }

  // Get user with conversation info
  Future<Map<String, dynamic>?> getUserWithConversation(String userId) async {
    try {
      final response = await _apiService.getUserById(userId);
      final userData = response['user'] as Map<String, dynamic>;
      final existingConversationId = response['existingConversationId'];
      
      return {
        'user': User.fromJson(userData),
        'existingConversationId': existingConversationId,
      };
    } catch (e) {
      print('[UserDiscovery] Get user with conversation error: $e');
      return null;
    }
  }
}

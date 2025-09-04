import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/models/user.dart';

class AuthController extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  // State
  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  // Getters
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;
  
  // Get auth token
  Future<String?> get token async {
    return await StorageService.getAuthToken();
  }

  // Initialize controller
  Future<void> initialize() async {
    _setLoading(true);
    try {
      final isLoggedIn = await StorageService.isLoggedIn();
      if (isLoggedIn) {
        await _loadProfile();
      }
    } catch (e) {
      _setError('Failed to initialize: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Login
  Future<bool> login(String email, String password) async {
    _setLoading(true);
    _clearError();
    
    try {
      final response = await _apiService.login(email, password);
      final token = response['token'] as String;
      
      // Store token
      await StorageService.setAuthToken(token);
      
      // Load user profile
      await _loadProfile();
      
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Register
  Future<bool> register(String name, String email, String password, String? phone) async {
    _setLoading(true);
    _clearError();
    
    try {
      await _apiService.register(name, email, password, phone);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Load user profile
  Future<void> _loadProfile() async {
    try {
      final response = await _apiService.getProfile();
      final userData = response['user'] as Map<String, dynamic>;
      
      _currentUser = User.fromJson(userData);
      
      // Store user data
      await StorageService.setUserData(
        userId: _currentUser!.id,
        email: _currentUser!.email,
        name: _currentUser!.name,
      );
      
      notifyListeners();
    } catch (e) {
      _setError('Failed to load profile: $e');
      await logout();
    }
  }

  // Logout
  Future<void> logout() async {
    _setLoading(true);
    
    try {
      await StorageService.clearAll();
      _currentUser = null;
      _clearError();
    } catch (e) {
      _setError('Logout failed: $e');
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  // Refresh profile
  Future<void> refreshProfile() async {
    if (_currentUser != null) {
      await _loadProfile();
    }
  }

  // Private methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  // Update user data
  void updateUser(User user) {
    _currentUser = user;
    notifyListeners();
  }


}

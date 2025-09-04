import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/storage_service.dart';

class ChatController extends ChangeNotifier with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  final NotificationService _notificationService = NotificationService();
  
  // State
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _threads = [];
  String? _currentUserId;

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get threads => _threads;
  String? get currentUserId => _currentUserId;

  // Start a conversation with a user
  Future<String?> startConversation(String userId) async {
    _setLoading(true);
    _clearError();
    
    try {
      // First, check if there's already a conversation
      final userInfo = await _apiService.getUserById(userId);
      final existingConversationId = userInfo['existingConversationId'];
      
      if (existingConversationId != null) {
        debugPrint('[ChatController] Found existing conversation: $existingConversationId');
        _setLoading(false);
        return existingConversationId;
      }
      
      // If no existing conversation, create a new one
      debugPrint('[ChatController] No existing conversation found, creating new one...');
      final response = await _apiService.createConversation(userId);
      
      if (response != null && response['conversationId'] != null) {
        final conversationId = response['conversationId'] as String;
        debugPrint('[ChatController] ✅ Successfully created new conversation: $conversationId');
        
        // Send an initial greeting message
        try {
          await _apiService.sendMessage(
            toId: userId,
            text: 'Hello! 👋',
          );
        } catch (e) {
          debugPrint('[ChatController] Warning: Failed to send greeting message: $e');
          // Don't fail the conversation creation if greeting fails
        }
        
        _setLoading(false);
        return conversationId;
      } else {
        _setError('Failed to create conversation');
        _setLoading(false);
        return null;
      }
    } catch (e) {
      debugPrint('[ChatController] Error starting conversation: $e');
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  // Send a message
  Future<bool> sendMessage({
    String? toId,
    String? toEmail,
    required String text,
  }) async {
    _setLoading(true);
    _clearError();
    
    try {
      await _apiService.sendMessage(
        toId: toId,
        toEmail: toEmail,
        text: text,
      );
      
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Get conversation messages
  Future<Map<String, dynamic>?> getMessages({
    String? peerId,
    String? peerEmail,
    String? conversationId,
    int limit = 30,
    DateTime? before,
  }) async {
    _setLoading(true);
    _clearError();
    
    try {
      final response = await _apiService.getMessages(
        peerId: peerId,
        peerEmail: peerEmail,
        conversationId: conversationId,
        limit: limit,
        before: before,
      );
      
      _setLoading(false);
      return response;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  // Get conversation threads
  Future<Map<String, dynamic>?> getThreads() async {
    _setLoading(true);
    _clearError();
    
    try {
      final response = await _apiService.getThreads();
      if (response != null && response['threads'] != null) {
        _threads = List<Map<String, dynamic>>.from(response['threads']);
        notifyListeners();
      }
      _setLoading(false);
      return response;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  // Set current user ID
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
    notifyListeners();
  }

  // Get conversation details
  Future<Map<String, dynamic>?> getConversation(String conversationId) async {
    _setLoading(true);
    _clearError();
    
    try {
      final response = await _apiService.getConversation(conversationId);
      _setLoading(false);
      return response;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  // Connect to socket for real-time messaging
  Future<void> connectSocket([String? token]) async {
    try {
      // Initialize notification service first
      await _notificationService.initialize();
      
      // Add app lifecycle observer
      WidgetsBinding.instance.addObserver(this);
      
      // Try to connect to socket
      await _socketService.connect(token);
      
      // Set up real-time message listeners
      _setupSocketListeners();
      
      debugPrint('[ChatController] Socket connected successfully');
    } catch (e) {
      debugPrint('[ChatController] Socket connection failed: $e');
      
      // Don't set error immediately - allow app to work in offline mode
      // _setError('Failed to connect to real-time messaging: $e');
      
      // Show a warning instead
      debugPrint('[ChatController] Running in offline mode - some features may be limited');
    }
  }

  // Set up socket event listeners for real-time updates
  void _setupSocketListeners() {
    // Listen for new messages
    _socketService.onMessage((messageData) {
      debugPrint('[ChatController] Received new message: $messageData');
      
      // Show notification for new messages (only if not from current user)
      _handleNewMessageNotification(messageData);
      
      // Notify listeners that a new message arrived
      notifyListeners();
    });

    // Listen for thread updates
    _socketService.onThreadUpdate((threadData) {
      debugPrint('[ChatController] Thread updated: $threadData');
      // Refresh threads list
      getThreads();
    });

    // Listen for typing indicators
    _socketService.onTypingStart((data) {
      debugPrint('[ChatController] User started typing: $data');
      notifyListeners();
    });

    _socketService.onTypingStop((data) {
      debugPrint('[ChatController] User stopped typing: $data');
      notifyListeners();
    });

    // Listen for message read receipts
    _socketService.onMessageRead((data) {
      debugPrint('[ChatController] Message read: $data');
      notifyListeners();
    });
  }

  // Disconnect from socket
  void disconnectSocket() {
    _socketService.disconnect();
  }

  // Send message via socket for real-time delivery
  Future<bool> sendMessageViaSocket({
    String? toId,
    String? toEmail,
    String? text,
    String? messageType,
    Map<String, dynamic>? fileAttachment,
  }) async {
    if (!_socketService.isConnected) {
      _setError('Socket not connected. Please check your connection.');
      return false;
    }

    try {
      debugPrint('[ChatController] Sending message via socket to: $toId');
      await _socketService.sendMessage(
        toId: toId,
        toEmail: toEmail,
        text: text,
        messageType: messageType,
        fileAttachment: fileAttachment,
      );
      debugPrint('[ChatController] Message sent successfully via socket');
      return true;
    } catch (e) {
      debugPrint('[ChatController] Failed to send message via socket: $e');
      _setError('Failed to send message: $e');
      return false;
    }
  }

  // Send typing indicator
  void sendTypingIndicator(String toId, bool isTyping) {
    if (!_socketService.isConnected) return;
    
    if (isTyping) {
      _socketService.sendTypingStart(toId);
    } else {
      _socketService.sendTypingStop(toId);
    }
  }

  // Mark message as read
  void markMessageAsRead(String messageId) {
    if (!_socketService.isConnected) return;
    _socketService.markMessageAsRead(messageId);
  }

  // Upload file
  Future<Map<String, dynamic>?> uploadFile(File file) async {
    _setLoading(true);
    _clearError();
    
    try {
      final response = await _apiService.uploadFile(file);
      _setLoading(false);
      return response;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  // Handle new message notification
  void _handleNewMessageNotification(Map<String, dynamic> messageData) {
    try {
      // Only show notification if message is not from current user
      final messageFrom = messageData['from'];
      if (messageFrom == _currentUserId) {
        return; // Don't show notification for own messages
      }

      // Extract message details
      final conversationId = messageData['conversationId'] ?? '';
      final messageText = messageData['text'] ?? '';
      final messageType = messageData['messageType'] ?? 'text';
      final fileAttachment = messageData['fileAttachment'];
      
      // Get peer information (you might need to adjust this based on your data structure)
      String peerName = 'Unknown User';
      String peerId = messageFrom;
      
      // Try to get peer name from threads
      for (final thread in _threads) {
        if (thread['conversationId'] == conversationId) {
          peerName = thread['name'] ?? 'Unknown User';
          peerId = thread['peerId'] ?? messageFrom;
          break;
        }
      }

      // Show notification
      _notificationService.showMessageNotification(
        conversationId: conversationId,
        peerName: peerName,
        peerId: peerId,
        messageText: messageText,
        messageType: messageType,
        imageUrl: fileAttachment?['url'],
      );

      debugPrint('[ChatController] Notification shown for message from $peerName');
    } catch (e) {
      debugPrint('[ChatController] Failed to show notification: $e');
    }
  }

  // Show test notification
  Future<void> showTestNotification() async {
    await _notificationService.showTestNotification();
  }

  // Request notification permissions
  Future<bool> requestNotificationPermissions() async {
    return await _notificationService.requestPermissions();
  }

  // Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    return await _notificationService.areNotificationsEnabled();
  }

  // Get connection status
  Map<String, dynamic> getConnectionStatus() {
    return _socketService.getConnectionStatus();
  }

  // Retry connection
  Future<void> retryConnection() async {
    try {
      final token = await StorageService.getAuthToken();
      await connectSocket(token);
    } catch (e) {
      debugPrint('[ChatController] Retry connection failed: $e');
    }
  }

  // App lifecycle management
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('[ChatController] App resumed - checking connection');
        _handleAppResumed();
        break;
      case AppLifecycleState.paused:
        debugPrint('[ChatController] App paused');
        _handleAppPaused();
        break;
      case AppLifecycleState.detached:
        debugPrint('[ChatController] App detached');
        _handleAppDetached();
        break;
      case AppLifecycleState.inactive:
        debugPrint('[ChatController] App inactive');
        break;
      case AppLifecycleState.hidden:
        debugPrint('[ChatController] App hidden');
        break;
    }
  }

  // Handle app resumed
  void _handleAppResumed() async {
    // Check if socket is still connected, reconnect if needed
    if (!_socketService.isConnected) {
      debugPrint('[ChatController] Socket disconnected while app was in background, reconnecting...');
      try {
        final token = await StorageService.getAuthToken();
        if (token != null) {
          await _socketService.connect(token);
        }
      } catch (e) {
        debugPrint('[ChatController] Failed to reconnect after app resume: $e');
      }
    }
  }

  // Handle app paused
  void _handleAppPaused() {
    // Keep connection alive but reduce activity
    debugPrint('[ChatController] App paused - maintaining connection');
  }

  // Handle app detached
  void _handleAppDetached() {
    // Clean up resources
    debugPrint('[ChatController] App detached - cleaning up');
    _socketService.setAutoReconnect(false);
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

  // Dispose resources
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socketService.dispose();
    super.dispose();
  }
}

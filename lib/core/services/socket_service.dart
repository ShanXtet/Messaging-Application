import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import 'storage_service.dart';

class SocketService {
  IO.Socket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _connectionAttempts = 0;
  static const int _maxConnectionAttempts = 3;
  static const Duration _retryDelay = Duration(seconds: 5);
  Timer? _reconnectTimer;
  bool _shouldAutoReconnect = true;

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  IO.Socket? get socket => _socket;

  // Initialize and connect
  Future<void> connect([String? token]) async {
    if (_isConnected || _isConnecting) return;

    _isConnecting = true;
    _connectionAttempts = 0;

    while (_connectionAttempts < _maxConnectionAttempts && !_isConnected) {
      try {
        _connectionAttempts++;
        debugPrint('[SocketService] Connection attempt $_connectionAttempts/$_maxConnectionAttempts');
        
        final authToken = token ?? await StorageService.getAuthToken();
        if (authToken == null) {
          throw Exception('No auth token available');
        }

        debugPrint('[SocketService] Connecting to: ${ApiConstants.baseUrl}');
        debugPrint('[SocketService] Using token: ${authToken.substring(0, 20)}...');

        // Dispose previous socket if exists
        _socket?.dispose();

        _socket = IO.io(
          ApiConstants.baseUrl,
          IO.OptionBuilder()
              .setTransports(['websocket', 'polling'])
              .setAuth({'token': authToken})
              .setQuery({'token': authToken}) // Fallback for older versions
              .enableReconnection()
              .setReconnectionAttempts(3)
              .setReconnectionDelay(2000)
              .setTimeout(10000) // Reduced to 10 second timeout
              .build(),
        );

        _setupEventListeners();
        await _connect();
        
        if (_isConnected) {
          debugPrint('[SocketService] Successfully connected on attempt $_connectionAttempts');
          break;
        }
      } catch (e) {
        debugPrint('[SocketService] Connection attempt $_connectionAttempts failed: $e');
        
        if (_connectionAttempts >= _maxConnectionAttempts) {
          debugPrint('[SocketService] All connection attempts failed');
          _isConnecting = false;
          throw Exception('Failed to connect after $_maxConnectionAttempts attempts: $e');
        }
        
        // Wait before retrying
        debugPrint('[SocketService] Retrying in ${_retryDelay.inSeconds} seconds...');
        await Future.delayed(_retryDelay);
      }
    }
    
    _isConnecting = false;
  }

  // Setup event listeners
  void _setupEventListeners() {
    _socket?.onConnect((_) {
      debugPrint('[SocketService] Connected successfully');
      _isConnected = true;
      _isConnecting = false;
      _connectionAttempts = 0;
    });

    _socket?.onDisconnect((reason) {
      debugPrint('[SocketService] Disconnected - Reason: $reason');
      _isConnected = false;
      _isConnecting = false;
      
      // Auto-reconnect on disconnect (unless it's a manual disconnect)
      if (reason != 'io client disconnect') {
        _scheduleReconnect();
      }
    });

    _socket?.onConnectError((error) {
      debugPrint('[SocketService] Connection error: $error');
      debugPrint('[SocketService] Error details: ${error.toString()}');
      _isConnected = false;
      _isConnecting = false;
    });

    _socket?.onError((error) {
      debugPrint('[SocketService] Socket error: $error');
      debugPrint('[SocketService] Error details: ${error.toString()}');
      _isConnected = false;
      _isConnecting = false;
    });

    // Listen for authentication errors
    _socket?.on('auth_error', (error) {
      debugPrint('[SocketService] Auth error: $error');
      _isConnected = false;
      _isConnecting = false;
    });

    // Listen for server errors
    _socket?.on('error', (error) {
      debugPrint('[SocketService] Server error: $error');
    });
  }

  // Connect to socket
  Future<void> _connect() async {
    if (_socket != null) {
      _socket!.connect();
      
      // Wait for connection or timeout (reduced to 10 seconds)
      int attempts = 0;
      while (!_isConnected && attempts < 20) {
        await Future.delayed(Duration(milliseconds: 500));
        attempts++;
      }
      
      if (!_isConnected) {
        throw Exception('Socket connection timeout after 10 seconds');
      }
    }
  }

  // Send message
  Future<void> sendMessage({
    String? toId,
    String? toEmail,
    String? text,
    String? messageType,
    Map<String, dynamic>? fileAttachment,
  }) async {
    if (!_isConnected) {
      throw Exception('Socket not connected');
    }
    
    final messageData = <String, dynamic>{};
    
    if (text != null) {
      messageData['text'] = text.trim();
    }
    if (messageType != null) {
      messageData['messageType'] = messageType;
    }
    if (fileAttachment != null) {
      messageData['fileAttachment'] = fileAttachment;
    }
    if (toId != null) {
      messageData['toId'] = toId;
    }
    if (toEmail != null) {
      messageData['toEmail'] = toEmail;
    }
    
    debugPrint('[SocketService] Sending message: $messageData');
    _socket?.emit(ApiConstants.messageSend, messageData);
  }

  // Listen for new messages
  void onMessage(Function(Map<String, dynamic>) callback) {
    _socket?.on(ApiConstants.messageNew, (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  // Listen for thread updates
  void onThreadUpdate(Function(Map<String, dynamic>) callback) {
    _socket?.on(ApiConstants.threadUpdate, (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  // Listen for typing events
  void onTypingStart(Function(Map<String, dynamic>) callback) {
    _socket?.on(ApiConstants.typingStart, (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onTypingStop(Function(Map<String, dynamic>) callback) {
    _socket?.on(ApiConstants.typingStop, (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  // Listen for message read events
  void onMessageRead(Function(Map<String, dynamic>) callback) {
    _socket?.on(ApiConstants.messageRead, (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  // Join room (conversation)
  void joinRoom(String roomId) {
    if (!_isConnected) return;
    _socket?.emit('join', roomId);
  }

  // Leave room
  void leaveRoom(String roomId) {
    if (!_isConnected) return;
    _socket?.emit('leave', roomId);
  }

  // Send typing indicator
  void sendTyping(String conversationId, bool isTyping) {
    if (!_isConnected) return;
    
    final event = isTyping ? ApiConstants.typingStart : ApiConstants.typingStop;
    _socket?.emit(event, {'conversationId': conversationId});
  }

  // Send typing start
  void sendTypingStart(String toId) {
    if (!_isConnected) return;
    _socket?.emit(ApiConstants.typingStart, {'toId': toId});
  }

  // Send typing stop
  void sendTypingStop(String toId) {
    if (!_isConnected) return;
    _socket?.emit(ApiConstants.typingStop, {'toId': toId});
  }

  // Mark message as read
  void markMessageAsRead(String messageId) {
    if (!_isConnected) return;
    _socket?.emit(ApiConstants.messageRead, {'messageId': messageId});
  }

  // Check server connectivity
  Future<bool> checkServerConnectivity() async {
    try {
      // Try to make a simple HTTP request to check if server is reachable
      final response = await Future.any([
        Future.delayed(Duration(seconds: 5), () => throw TimeoutException('Server check timeout')),
        // You could add an HTTP request here to check server health
        Future.value(true), // Placeholder - replace with actual server health check
      ]);
      return response;
    } catch (e) {
      debugPrint('[SocketService] Server connectivity check failed: $e');
      return false;
    }
  }

  // Get connection status info
  Map<String, dynamic> getConnectionStatus() {
    return {
      'isConnected': _isConnected,
      'isConnecting': _isConnecting,
      'connectionAttempts': _connectionAttempts,
      'maxAttempts': _maxConnectionAttempts,
      'serverUrl': ApiConstants.baseUrl,
      'shouldAutoReconnect': _shouldAutoReconnect,
    };
  }

  // Ensure connection is active
  Future<void> ensureConnection() async {
    if (!_isConnected && !_isConnecting) {
      debugPrint('[SocketService] Ensuring connection...');
      await connect();
    }
  }

  // Force connection status refresh
  void refreshConnectionStatus() {
    // This will trigger a rebuild of any widgets listening to connection status
    debugPrint('[SocketService] Connection status: connected=$_isConnected, connecting=$_isConnecting, autoReconnect=$_shouldAutoReconnect');
  }

  // Schedule automatic reconnection
  void _scheduleReconnect() {
    if (!_shouldAutoReconnect || _isConnecting) return;
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_retryDelay, () async {
      if (!_isConnected && _shouldAutoReconnect) {
        debugPrint('[SocketService] Attempting auto-reconnect...');
        try {
          final token = await StorageService.getAuthToken();
          if (token != null) {
            await connect(token);
          }
        } catch (e) {
          debugPrint('[SocketService] Auto-reconnect failed: $e');
        }
      }
    });
  }

  // Enable/disable auto-reconnect
  void setAutoReconnect(bool enabled) {
    _shouldAutoReconnect = enabled;
    if (!enabled) {
      _reconnectTimer?.cancel();
    }
  }

  // Disconnect
  void disconnect() {
    _shouldAutoReconnect = false;
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _isConnecting = false;
    _connectionAttempts = 0;
  }

  // Soft disconnect - keeps auto-reconnect enabled
  void softDisconnect() {
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _isConnecting = false;
    _connectionAttempts = 0;
    // Keep _shouldAutoReconnect = true for automatic reconnection
  }

  // Dispose
  void dispose() {
    disconnect();
  }
}

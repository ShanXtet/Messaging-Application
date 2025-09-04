import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request permissions first
      await _requestPermissions();

      // Android initialization settings
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization settings
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      _isInitialized = true;
      debugPrint('Notification service initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize notification service: $e');
    }
  }

  /// Request notification permissions
  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // For Android 13+ (API level 33+)
      if (await Permission.notification.isDenied) {
        final status = await Permission.notification.request();
        return status.isGranted;
      }
      return true;
    } else if (Platform.isIOS) {
      // iOS permissions are handled in the initialization settings
      return true;
    }
    return false;
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    
    // Parse the payload to get conversation details
    if (response.payload != null) {
      final payload = response.payload!;
      final parts = payload.split('|');
      if (parts.length >= 3) {
        final conversationId = parts[0];
        final peerName = parts[1];
        final peerId = parts[2];
        
        // Navigate to the conversation
        _navigateToConversation(conversationId, peerName, peerId);
      }
    }
  }

  /// Navigate to conversation (this will be called from the main app)
  void _navigateToConversation(String conversationId, String peerName, String peerId) {
    // This will be implemented in the main app to handle navigation
    debugPrint('Navigate to conversation: $conversationId with $peerName');
  }

  /// Show a message notification
  Future<void> showMessageNotification({
    required String conversationId,
    required String peerName,
    required String peerId,
    required String messageText,
    required String messageType,
    String? imageUrl,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Create notification title and body
      String title = peerName;
      String body = _formatMessageBody(messageText, messageType);
      
      // Create payload for navigation
      final payload = '$conversationId|$peerName|$peerId';

      // Android notification details
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'chat_messages',
        'Chat Messages',
        channelDescription: 'Notifications for new chat messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(''),
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
      );

      // iOS notification details
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: 1,
        threadIdentifier: 'chat_messages',
        categoryIdentifier: 'MESSAGE_CATEGORY',
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Generate unique notification ID based on conversation
      final notificationId = conversationId.hashCode;

      await _notifications.show(
        notificationId,
        title,
        body,
        details,
        payload: payload,
      );

      debugPrint('Message notification shown for $peerName');
    } catch (e) {
      debugPrint('Failed to show message notification: $e');
    }
  }

  /// Format message body based on message type
  String _formatMessageBody(String messageText, String messageType) {
    switch (messageType) {
      case 'image':
        return '📷 Sent a photo';
      case 'file':
        return '📎 Sent a file';
      case 'multi_image':
        return '🖼️ Sent multiple photos';
      default:
        return messageText.isNotEmpty ? messageText : 'New message';
    }
  }

  /// Show a typing notification (optional)
  Future<void> showTypingNotification({
    required String peerName,
    required String conversationId,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'typing_status',
        'Typing Status',
        channelDescription: 'Notifications for typing status',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: false,
        enableVibration: false,
        playSound: false,
        silent: true,
        ongoing: true,
        autoCancel: false,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
        threadIdentifier: 'typing_status',
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final notificationId = 'typing_${conversationId.hashCode}';

      await _notifications.show(
        notificationId.hashCode,
        '$peerName is typing...',
        '',
        details,
      );
    } catch (e) {
      debugPrint('Failed to show typing notification: $e');
    }
  }

  /// Cancel typing notification
  Future<void> cancelTypingNotification(String conversationId) async {
    try {
      final notificationId = 'typing_${conversationId.hashCode}';
      await _notifications.cancel(notificationId.hashCode);
    } catch (e) {
      debugPrint('Failed to cancel typing notification: $e');
    }
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      debugPrint('All notifications cancelled');
    } catch (e) {
      debugPrint('Failed to cancel all notifications: $e');
    }
  }

  /// Cancel notifications for a specific conversation
  Future<void> cancelConversationNotifications(String conversationId) async {
    try {
      final notificationId = conversationId.hashCode;
      await _notifications.cancel(notificationId);
      debugPrint('Notifications cancelled for conversation: $conversationId');
    } catch (e) {
      debugPrint('Failed to cancel conversation notifications: $e');
    }
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      return await Permission.notification.isGranted;
    } else if (Platform.isIOS) {
      // For iOS, we can't directly check, but we can try to show a test notification
      return true;
    }
    return false;
  }

  /// Request notification permissions explicitly
  Future<bool> requestPermissions() async {
    return await _requestPermissions();
  }

  /// Show a test notification
  Future<void> showTestNotification() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'test_channel',
        'Test Notifications',
        channelDescription: 'Test notifications for debugging',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        999,
        'Test Notification',
        'This is a test notification to verify the setup is working correctly.',
        details,
      );

      debugPrint('Test notification shown');
    } catch (e) {
      debugPrint('Failed to show test notification: $e');
    }
  }


}

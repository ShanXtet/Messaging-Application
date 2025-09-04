class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.2.252:4000',
  );

  // Auth endpoints
  static const String login = '/api/login';
  static const String register = '/api/register';
  static const String me = '/api/me';

  // Chat endpoints
  static const String threads = '/api/threads';
  static const String messages = '/api/messages';
  static const String conversations = '/api/conversations';
  static const String connectedUsers = '/api/connected-users';
  static const String userStatus = '/api/users';
  
  // User discovery endpoints
  static const String users = '/api/users';
  static const String userSearch = '/api/users/search';

  // Socket events
  static const String messageNew = 'message:new';
  static const String messageSend = 'message:send';
  static const String threadUpdate = 'thread:update';
  static const String typingStart = 'typing:start';
  static const String typingStop = 'typing:stop';
  static const String messageRead = 'message:read';

  // Headers
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
  };

  static Map<String, String> authHeaders(String token) => {
    ...defaultHeaders,
    'Authorization': 'Bearer $token',
  };
}

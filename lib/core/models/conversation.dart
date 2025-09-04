class Conversation {
  final String id;
  final List<String> participants;
  final LastMessage? lastMessage;
  final Map<String, int> unreadCount;
  final bool isGroup;
  final String? groupName;
  final String? groupAdmin;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.participants,
    this.lastMessage,
    this.unreadCount = const {},
    this.isGroup = false,
    this.groupName,
    this.groupAdmin,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['_id'] ?? json['id'] ?? '',
      participants: List<String>.from(json['participants'] ?? []),
      lastMessage: json['lastMessage'] != null 
          ? LastMessage.fromJson(json['lastMessage']) 
          : null,
      unreadCount: Map<String, int>.from(json['unreadCount'] ?? {}),
      isGroup: json['isGroup'] ?? false,
      groupName: json['groupName'],
      groupAdmin: json['groupAdmin'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participants': participants,
      'lastMessage': lastMessage?.toJson(),
      'unreadCount': unreadCount,
      'isGroup': isGroup,
      'groupName': groupName,
      'groupAdmin': groupAdmin,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Conversation copyWith({
    String? id,
    List<String>? participants,
    LastMessage? lastMessage,
    Map<String, int>? unreadCount,
    bool? isGroup,
    String? groupName,
    String? groupAdmin,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      participants: participants ?? this.participants,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isGroup: isGroup ?? this.isGroup,
      groupName: groupName ?? this.groupName,
      groupAdmin: groupAdmin ?? this.groupAdmin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String? getOtherParticipant(String currentUserId) {
    return participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
  }

  int getUnreadCount(String userId) {
    return unreadCount[userId] ?? 0;
  }

  @override
  String toString() {
    return 'Conversation(id: $id, participants: $participants, isGroup: $isGroup)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Conversation && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class LastMessage {
  final String text;
  final String from;
  final DateTime timestamp;

  LastMessage({
    required this.text,
    required this.from,
    required this.timestamp,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    return LastMessage(
      text: json['text'] ?? '',
      from: json['from'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'from': from,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

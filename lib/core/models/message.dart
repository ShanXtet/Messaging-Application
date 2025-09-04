enum MessageStatus { sent, delivered, read }
enum MessageType { text, image, file }

class Message {
  final String id;
  final String conversationId;
  final String from;
  final String to;
  final String text;
  final MessageStatus status;
  final DateTime? seenAt;
  final MessageType messageType;
  final DateTime createdAt;
  final DateTime updatedAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.from,
    required this.to,
    required this.text,
    this.status = MessageStatus.sent,
    this.seenAt,
    this.messageType = MessageType.text,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['_id'] ?? json['id'] ?? '',
      conversationId: json['conversationId'] ?? '',
      from: json['from'] ?? json['sender'] ?? '',
      to: json['to'] ?? json['receiver'] ?? '',
      text: json['text'] ?? '',
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.sent,
      ),
      seenAt: json['seenAt'] != null ? DateTime.parse(json['seenAt']) : null,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == json['messageType'],
        orElse: () => MessageType.text,
      ),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'from': from,
      'to': to,
      'text': text,
      'status': status.name,
      'seenAt': seenAt?.toIso8601String(),
      'messageType': messageType.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? from,
    String? to,
    String? text,
    MessageStatus? status,
    DateTime? seenAt,
    MessageType? messageType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      from: from ?? this.from,
      to: to ?? this.to,
      text: text ?? this.text,
      status: status ?? this.status,
      seenAt: seenAt ?? this.seenAt,
      messageType: messageType ?? this.messageType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isFromMe => from == 'currentUserId'; // Will be set by controller

  @override
  String toString() {
    return 'Message(id: $id, from: $from, to: $to, text: $text, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

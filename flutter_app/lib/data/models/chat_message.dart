import 'package:json_annotation/json_annotation.dart';

part 'chat_message.g.dart';

/// `chat_messages.attachments` JSONB içindeki tek ek — web `ChatAttachment`.
@JsonSerializable(explicitToJson: true)
class ChatAttachment {
  const ChatAttachment({
    required this.path,
    required this.name,
    required this.type,
    required this.size,
    this.signedUrl,
  });

  /// Storage bucket `chat-attachments` içindeki yol
  /// (`{userId}/{threadId}/{uuid}.{ext}`).
  final String path;

  final String name;
  final String type;
  final int size;

  /// 1 saatlik imzalı URL (yükleme sırasında veya `signAttachments` ile üretilir).
  @JsonKey(name: 'signedUrl')
  final String? signedUrl;

  factory ChatAttachment.fromJson(Map<String, dynamic> json) =>
      _$ChatAttachmentFromJson(json);

  Map<String, dynamic> toJson() => _$ChatAttachmentToJson(this);
}

/// Bir araç çağrısı (`tool_calls` JSONB dizisi elemanı) — web `tool_calls`.
@JsonSerializable(explicitToJson: true)
class ChatToolCall {
  const ChatToolCall({
    this.id,
    this.name,
    this.arguments,
  });

  final String? id;
  final String? name;

  @JsonKey(name: 'arguments')
  final Map<String, dynamic>? arguments;

  factory ChatToolCall.fromJson(Map<String, dynamic> json) =>
      _$ChatToolCallFromJson(json);

  Map<String, dynamic> toJson() => _$ChatToolCallToJson(this);
}

/// Bir araç sonucu (`tool_results` JSONB dizisi elemanı) — web `tool_results`.
@JsonSerializable(explicitToJson: true)
class ChatToolResult {
  const ChatToolResult({
    this.id,
    this.name,
    this.summary,
    this.result,
  });

  final String? id;
  final String? name;
  final String? summary;
  final dynamic result;

  factory ChatToolResult.fromJson(Map<String, dynamic> json) =>
      _$ChatToolResultFromJson(json);

  Map<String, dynamic> toJson() => _$ChatToolResultToJson(this);
}

/// `chat_messages` tablosu — web `ChatMessage` karşılığı.
///
/// `role`: user | assistant | system | tool.
/// `content` null olabilir (yalnızca ek içeren kullanıcı mesajı, veya araç sonucu).
@JsonSerializable(explicitToJson: true)
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.userId,
    required this.role,
    required this.createdAt,
    this.content,
    this.attachments = const [],
    this.toolCalls = const [],
    this.toolResults = const [],
    this.deletedAt,
  });

  final String id;

  @JsonKey(name: 'thread_id')
  final String threadId;

  @JsonKey(name: 'user_id')
  final String userId;

  final String role;

  final String? content;

  @JsonKey(name: 'attachments')
  final List<ChatAttachment> attachments;

  @JsonKey(name: 'tool_calls')
  final List<ChatToolCall> toolCalls;

  @JsonKey(name: 'tool_results')
  final List<ChatToolResult> toolResults;

  @JsonKey(name: 'created_at')
  final String createdAt;

  @JsonKey(name: 'deleted_at')
  final String? deletedAt;

  /// Senkron bir "hoş geldiniz" mesajı için kullanılır (id: 'welcome').
  factory ChatMessage.welcome({
    required String threadId,
    required String userId,
    required String content,
  }) {
    return ChatMessage(
      id: 'welcome',
      threadId: threadId,
      userId: userId,
      role: 'assistant',
      content: content,
      createdAt: '',
      attachments: const [],
      toolCalls: const [],
      toolResults: const [],
    );
  }

  bool get isUser => role == 'user';
  bool get isWelcome => id == 'welcome';

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  Map<String, dynamic> toJson() => _$ChatMessageToJson(this);
}

/// `chat_threads` tablosu — web `chat_threads` satırı.
@JsonSerializable(explicitToJson: true)
class ChatThread {
  const ChatThread({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  final String id;

  @JsonKey(name: 'user_id')
  final String userId;

  final String? title;

  @JsonKey(name: 'archived_at')
  final String? archivedAt;

  @JsonKey(name: 'created_at')
  final String createdAt;

  @JsonKey(name: 'updated_at')
  final String updatedAt;

  factory ChatThread.fromJson(Map<String, dynamic> json) =>
      _$ChatThreadFromJson(json);

  Map<String, dynamic> toJson() => _$ChatThreadToJson(this);
}

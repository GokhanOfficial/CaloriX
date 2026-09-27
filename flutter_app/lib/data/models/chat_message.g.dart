// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatAttachment _$ChatAttachmentFromJson(Map<String, dynamic> json) =>
    ChatAttachment(
      path: json['path'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      size: (json['size'] as num).toInt(),
      signedUrl: json['signedUrl'] as String?,
    );

Map<String, dynamic> _$ChatAttachmentToJson(ChatAttachment instance) =>
    <String, dynamic>{
      'path': instance.path,
      'name': instance.name,
      'type': instance.type,
      'size': instance.size,
      'signedUrl': instance.signedUrl,
    };

ChatToolCall _$ChatToolCallFromJson(Map<String, dynamic> json) => ChatToolCall(
  id: json['id'] as String?,
  name: json['name'] as String?,
  arguments: json['arguments'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$ChatToolCallToJson(ChatToolCall instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'arguments': instance.arguments,
    };

ChatToolResult _$ChatToolResultFromJson(Map<String, dynamic> json) =>
    ChatToolResult(
      id: json['id'] as String?,
      name: json['name'] as String?,
      summary: json['summary'] as String?,
      result: json['result'],
    );

Map<String, dynamic> _$ChatToolResultToJson(ChatToolResult instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'summary': instance.summary,
      'result': instance.result,
    };

ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => ChatMessage(
  id: json['id'] as String,
  threadId: json['thread_id'] as String,
  userId: json['user_id'] as String,
  role: json['role'] as String,
  createdAt: json['created_at'] as String,
  content: json['content'] as String?,
  attachments:
      (json['attachments'] as List<dynamic>?)
          ?.map((e) => ChatAttachment.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  toolCalls:
      (json['tool_calls'] as List<dynamic>?)
          ?.map((e) => ChatToolCall.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  toolResults:
      (json['tool_results'] as List<dynamic>?)
          ?.map((e) => ChatToolResult.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  deletedAt: json['deleted_at'] as String?,
  pendingAction: json['pending_action'] == null
      ? null
      : ChatPendingAction.fromJson(
          json['pending_action'] as Map<String, dynamic>,
        ),
  actionStatus: json['action_status'] as String?,
  metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
);

Map<String, dynamic> _$ChatMessageToJson(ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'thread_id': instance.threadId,
      'user_id': instance.userId,
      'role': instance.role,
      'content': instance.content,
      'attachments': instance.attachments.map((e) => e.toJson()).toList(),
      'tool_calls': instance.toolCalls.map((e) => e.toJson()).toList(),
      'tool_results': instance.toolResults.map((e) => e.toJson()).toList(),
      'pending_action': instance.pendingAction?.toJson(),
      'action_status': instance.actionStatus,
      'metadata': instance.metadata,
      'created_at': instance.createdAt,
      'deleted_at': instance.deletedAt,
    };

ChatThread _$ChatThreadFromJson(Map<String, dynamic> json) => ChatThread(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  title: json['title'] as String?,
  createdAt: json['created_at'] as String,
  updatedAt: json['updated_at'] as String,
  archivedAt: json['archived_at'] as String?,
);

Map<String, dynamic> _$ChatThreadToJson(ChatThread instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'title': instance.title,
      'archived_at': instance.archivedAt,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };

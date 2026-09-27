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

/// `ai-chat` önerilen eylemi (bkz. `supabase/functions/ai-chat/index.ts`
/// `PendingAction`) — `chat_messages.pending_action` JSONB gövdesi.
///
/// Alan adları edge function'ın `buildPendingAction` çıktısıyla birebir
/// eşleşir; bilinmeyen anahtarlar `raw` içinde korunur (sözleşme ileride
/// genişlerse veri kaybı olmaz).
class ChatPendingAction {
  const ChatPendingAction({
    required this.type,
    this.mealType,
    this.customName,
    this.foodId,
    this.amountGMl,
    this.calculatedKcal,
    this.calculatedProtein,
    this.calculatedCarbs,
    this.calculatedFat,
    this.note,
    this.entryDate,
    this.amountMl,
    this.weightKg,
    this.raw = const {},
  });

  /// `add_meal` | `add_water` | `update_weight` …
  @JsonKey(name: 'type')
  final String type;

  @JsonKey(name: 'meal_type')
  final String? mealType;

  @JsonKey(name: 'custom_name')
  final String? customName;

  @JsonKey(name: 'food_id')
  final String? foodId;

  @JsonKey(name: 'amount_g_ml')
  final double? amountGMl;

  @JsonKey(name: 'calculated_kcal')
  final double? calculatedKcal;

  @JsonKey(name: 'calculated_protein')
  final double? calculatedProtein;

  @JsonKey(name: 'calculated_carbs')
  final double? calculatedCarbs;

  @JsonKey(name: 'calculated_fat')
  final double? calculatedFat;

  final String? note;

  @JsonKey(name: 'entry_date')
  final String? entryDate;

  @JsonKey(name: 'amount_ml')
  final double? amountMl;

  @JsonKey(name: 'weight_kg')
  final double? weightKg;

  /// Şemada listelenmeyen alanlar (ileride edge function genişlerse).
  final Map<String, dynamic> raw;

  factory ChatPendingAction.fromJson(Map<String, dynamic> json) {
    const known = <String>{
      'type',
      'meal_type',
      'custom_name',
      'food_id',
      'amount_g_ml',
      'calculated_kcal',
      'calculated_protein',
      'calculated_carbs',
      'calculated_fat',
      'note',
      'entry_date',
      'amount_ml',
      'weight_kg',
    };
    return ChatPendingAction(
      type: (json['type'] as String?) ?? '',
      mealType: json['meal_type'] as String?,
      customName: json['custom_name'] as String?,
      foodId: json['food_id'] as String?,
      amountGMl: _num(json['amount_g_ml']),
      calculatedKcal: _num(json['calculated_kcal']),
      calculatedProtein: _num(json['calculated_protein']),
      calculatedCarbs: _num(json['calculated_carbs']),
      calculatedFat: _num(json['calculated_fat']),
      note: json['note'] as String?,
      entryDate: json['entry_date'] as String?,
      amountMl: _num(json['amount_ml']),
      weightKg: _num(json['weight_kg']),
      raw: <String, dynamic>{
        for (final e in json.entries)
          if (!known.contains(e.key)) e.key: e.value,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (mealType != null) 'meal_type': mealType,
        if (customName != null) 'custom_name': customName,
        if (foodId != null) 'food_id': foodId,
        if (amountGMl != null) 'amount_g_ml': amountGMl,
        if (calculatedKcal != null) 'calculated_kcal': calculatedKcal,
        if (calculatedProtein != null) 'calculated_protein': calculatedProtein,
        if (calculatedCarbs != null) 'calculated_carbs': calculatedCarbs,
        if (calculatedFat != null) 'calculated_fat': calculatedFat,
        if (note != null) 'note': note,
        if (entryDate != null) 'entry_date': entryDate,
        if (amountMl != null) 'amount_ml': amountMl,
        if (weightKg != null) 'weight_kg': weightKg,
        ...raw,
      };

  static double? _num(Object? v) {
    if (v is num) {
      final d = v.toDouble();
      return d.isFinite ? d : null;
    }
    return null;
  }
}

/// `chat_messages` tablosu — web `ChatMessage` karşılığı.
///
/// `role`: user | assistant | system | tool.
/// `content` null olabilir (yalnızca ek içeren kullanıcı mesajı, veya araç sonucu).
///
/// `pending_action` / `action_status` / `metadata` kolonları migration'da
/// (`20260518080500_add_ai_chat.sql:44-46`) tanımlıdır. Flutter modelinde
/// bulunmadığı için **onay/ret akışı taşınamıyordu** ve `action_status`
/// güncellendiği halde istemci bunu hiç okumuyordu. Artık modellendi:
/// `pendingAction` öneriyi, `actionStatus` durumu (`null` = onay bekleyen
/// öneri yok), `metadata` ise ham JSONB'yi taşır.
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
    this.pendingAction,
    this.actionStatus,
    this.metadata = const {},
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

  /// Asistanın önerdiği, henüz uygulanmamış eylem (`pending_action`).
  @JsonKey(name: 'pending_action')
  final ChatPendingAction? pendingAction;

  /// `pending_action` durumu — DB CHECK:
  /// `pending | approved | rejected | executed | failed`. Null ise öneri yok.
  @JsonKey(name: 'action_status')
  final String? actionStatus;

  /// Serbest JSONB (`metadata` kolonu) — şemada `NOT NULL DEFAULT '{}'`.
  final Map<String, dynamic> metadata;

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

  /// Onay bekleyen bir eylem önerisi var mı?
  bool get hasPendingAction =>
      pendingAction != null && actionStatus == ChatActionStatus.pending;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  Map<String, dynamic> toJson() => _$ChatMessageToJson(this);
}

/// `chat_messages.action_status` CHECK değerleri (migration
/// `20260518080500_add_ai_chat.sql:45`).
///
/// Web (`ChatPage.tsx`) `src/hooks/useChat.ts` içinde aynı string'leri
/// kullanıyor; Dart tarafında enum değil düz `String` tutulur çünkü kolon
/// nullable ve yeni değer eklenmesi modeli kırmamalıdır.
abstract final class ChatActionStatus {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
  static const String executed = 'executed';
  static const String failed = 'failed';

  /// CHECK kısıtındaki izin verilen değerler.
  static const Set<String> dbValues = {
    pending,
    approved,
    rejected,
    executed,
    failed,
  };
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

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/num_parsing.dart';
import '../models/chat_message.dart';
import '../supabase/supabase_client_provider.dart';

/// AI sohbet edge fonksiyonu ve `chat_threads` / `chat_messages` CRUD.
///
/// Web referansı: `src/pages/ChatPage.tsx`. Çağrı imzaları, sorgu şekilleri
/// ve `ai-chat` edge fonksiyon gövdesi birebir eşleşir:
///
///  - Kullanıcı mesajı ÖNCE `chat_messages`'a insert edilir, sonra
///    `supabase.functions.invoke('ai-chat', body: {mode, threadId, locale,
///    language, timeZone, currentDate})` çağrılır. Edge fonksiyonu son 50
///    mesajı DB'den okur — kullanıcı metni gövdeye gönderilmez.
///  - Tek invoke, stream/poll yok. Fonksiyon asistan cevabını (araç döngüsü
///    dahil) tamamen üretip `{message: <row>}` döndürür.
///  - Ekler `chat-attachments` private bucket'ına yüklenir, 1 saatlik imzalı
///    URL `attachments` JSONB'inde saklanır.
class ChatRepository {
  ChatRepository(this._client);

  final SupabaseClient _client;

  static const _bucket = 'chat-attachments';
  static const _pageSize = 10;

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// `new Date().toLocaleDateString("en-CA")` → `yyyy-MM-dd` (web parity).
  ///
  /// Ortak uygulama `core/utils/num_parsing.dart` → `formatDateOnly`
  /// (aynı mantık `DiaryRepository.formatEntryDate` içinde de vardı).
  static String localDateOnly(DateTime now) => formatDateOnly(now);

  /// `chat_threads` insert gövdesi (saf, test edilebilir).
  ///
  /// [title] verilmezse (ya da boşsa) kolon **NULL** bırakılır: thread
  /// başlığı kullanıcının diline göre değişen bir metindir ve veri
  /// katmanında üretilemez. Daha önce buraya sabit bir çeviri **anahtarı**
  /// (`'chat.newThread'`) yazılıyor, hiç güncellenmediği için veri dışa
  /// aktarımında kalıcılaşıyordu.
  static Map<String, dynamic> threadInsertPayload(
    String userId, {
    String? title,
  }) {
    final trimmed = title?.trim();
    return {
      'user_id': userId,
      'title': (trimmed != null && trimmed.isNotEmpty) ? trimmed : null,
    };
  }

  /// En yeni arşivlenmemiş thread'i bulur, yoksa oluşturur (web `ensureThread`).
  ///
  /// **Başlık veri katmanında üretilmez** — bkz. [threadInsertPayload].
  Future<String> ensureThread(String userId, {String? title}) async {
    final existing = await _client
        .from('chat_threads')
        .select('id')
        .eq('user_id', userId)
        .isFilter('archived_at', null)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final existingId = existing?['id'] as String?;
    if (existingId != null) return existingId;

    final created = await _client
        .from('chat_threads')
        .insert(threadInsertPayload(userId, title: title))
        .select('id')
        .single();

    return created['id'] as String;
  }

  /// En yeni `pageSize` mesajı yükler (web `loadInitial`). Eskiden yeniye
  /// sıralayıp alır, UI için ters çevirir (eskiden yeniye döndürür).
  /// Ayrıca eklerin imzalı URL'lerini tazeler.
  Future<({List<ChatMessage> messages, bool hasMore})> loadInitial(
    String userId,
    String threadId,
  ) async =>
      _loadPage(userId, threadId);

  /// Daha eski mesajları yükler (web `loadMore`). `oldestCreatedAt`'tan
  /// daha eskileri çeker. UI scroll konumunu korumalıdır.
  Future<({List<ChatMessage> messages, bool hasMore})> loadMore(
    String userId,
    String threadId,
    String oldestCreatedAt,
  ) async {
    // `created_at` timestamptz'dir ve iki mesaj aynı mikrosaniyede yazılmış
    // olabilir (toplu ekleme, edge function'ın araç döngüsü). Yalnızca
    // `lt(created_at, oldest)` filtresi kullanılırsa **o mesajlar kalıcı
    // olarak atlanır**: her "daha eski mesajlar" isteğinde aynı son sayfa
    // döner, `hasMore` true kalır ve kullanıcı listeyi aşağı kaydıramaz.
    // Çakışan `created_at` satırlarının `id`'leri de alınır ve
    // `created_at`'tan **daha eski** olanlar çekilir (klasik "keyset" /
    // "seek" pagination — `tut` engellenir, hiçbir mesaj atlanmaz).
    final page = await _loadPage(
      userId,
      threadId,
      cursor: oldestCreatedAt,
    );
    if (page.messages.isEmpty) {
      return (messages: const <ChatMessage>[], hasMore: false);
    }
    final last = page.messages.last;
    final tieIds = await _tieIdsAt(userId, threadId, last);
    if (tieIds.isEmpty) {
      return (messages: page.messages, hasMore: page.hasMore);
    }
    // Çakışan `created_at` satırları id kümesinde zaten olduğundan
    // PostgREST `not.in.(...)` ile filtrelendiğinde tekrar gelmezler.
    final older = await _loadPage(
      userId,
      threadId,
      cursor: last.createdAt,
      excludeIds: tieIds,
    );
    return (
      messages: [...older.messages, ...page.messages],
      hasMore: older.hasMore,
    );
  }

  /// `cursor` damgasına sahip ama [pivot]'un dışında kalan mesajların
  /// `id`leri — aynı `created_at`'lı kardeşler.
  ///
  /// `pivot` şu an listede **en eski** mesaj olduğu için, aynı damgaya sahip
  /// ama listede bulunmayan satırlar önceki sayfada atlanmış olanlardır; onları
  /// bilmemiz `loadMore`'un `tut`'a vurmasını engeller.
  Future<List<String>> _tieIdsAt(
    String userId,
    String threadId,
    ChatMessage pivot,
  ) async {
    final rows = await _client
        .from('chat_messages')
        .select('id')
        .eq('thread_id', threadId)
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .eq('created_at', pivot.createdAt);
    return rows
        .map((r) => r['id'])
        .whereType<String>()
        .where((id) => id != pivot.id)
        .toList();
  }

  /// Sayfalarken kullanılacak en küçük `created_at` imzası (test edilebilir).
  ///
  /// `createdAt` boşsa (sanal "hoş geldiniz" mesajı ya da bozuk satır) null
  /// döner; çağıran o zaman yalnızca ilk sayfayı yükler.
  static String? oldestTimestamp(List<ChatMessage> messages) {
    if (messages.isEmpty) return null;
    final stamps = messages
        .map((m) => m.createdAt)
        .where((s) => s.isNotEmpty)
        .toList();
    if (stamps.isEmpty) return null;
    stamps.sort();
    return stamps.first;
  }

  /// Tek mesaj sayfası (web `loadMessages` — `order + limit`).
  ///
  /// Sıralama **her zaman** `(created_at desc, id desc)` — belirsiz sıralama
  /// olmadan `limit` uygulanmaz. İkinci anahtar olmadan aynı `created_at`'lı
  /// satırların hangisinin sayfaya girdiği tanımsızdır (Postgres sıralaması
  /// kararlı değildir) ve [loadMore] imleci tutar.
  Future<({List<ChatMessage> messages, bool hasMore})> _loadPage(
    String userId,
    String threadId, {
    String? cursor,
    List<String> excludeIds = const [],
  }) async {
    // `select()` `PostgrestFilterBuilder` üretir (filtre metotları burada);
    // `order()`/`limit()` döndürdüğü `PostgrestTransformBuilder`'da filtre
    // metotları **yoktur** — bu yüzden önce tüm filtreler, sonra sıralama ve
    // limit uygulanır. Sıralama ikincil anahtarı (`id`) belirsiz
    // `limit`'i ve `loadMore` imlecini güvenilir kılar.
    var filtered = _client
        .from('chat_messages')
        .select()
        .eq('thread_id', threadId)
        .eq('user_id', userId)
        .isFilter('deleted_at', null);
    if (cursor != null) filtered = filtered.lt('created_at', cursor);
    if (excludeIds.isNotEmpty) {
      filtered = filtered.not('id', 'in', '(${excludeIds.join(',')})');
    }
    final rows = await filtered
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(_pageSize);

    final messages =
        rows.map((r) => ChatMessage.fromJson(Map<String, dynamic>.from(r))).toList();
    final signed = await _signAttachments(messages);
    final reversed = signed.reversed.toList();
    return (messages: reversed, hasMore: rows.length == _pageSize);
  }

  /// Kullanıcı mesajını insert eder (web `sendMessage` içi). Ekleri önce
  /// storage'a yükler. Dönüş: DB'den dönen tam satır.
  Future<ChatMessage> insertUserMessage(
    String userId,
    String threadId, {
    required String content,
    List<({String name, String type, List<int> bytes})>? files,
  }) async {
    final attachments = await _uploadAttachments(userId, threadId, files ?? []);

    final saved = await _client
        .from('chat_messages')
        .insert({
          'thread_id': threadId,
          'user_id': userId,
          'role': 'user',
          'content': content.trim().isEmpty ? null : content.trim(),
          'attachments': attachments,
        })
        .select()
        .single();

    return ChatMessage.fromJson(saved);
  }

  /// Asistanı çağırır (web `invokeAssistant`). Gövde alan adları birebir:
  /// `{mode, threadId, locale, language, timeZone, currentDate}`.
  ///
  /// Edge function hata gövdesi döndürürse (`{error: ...}`) istisna fırlatır;
  /// aksi halde `invokeAssistant` null döner ve kullanıcı mesajı göndermiş
  /// olmasına rağmen cevap gelmeyen bir sohbet görür (sessiz hata).
  /// Dönüş: ekleri imzalanmış asistan mesajı.
  Future<ChatMessage?> invokeAssistant({
    required String threadId,
    required String locale,
    required String language,
    required String timeZone,
    required String currentDate,
  }) async {
    final response = await _client.functions.invoke(
      'ai-chat',
      body: {
        'mode': 'chat',
        'threadId': threadId,
        'locale': locale,
        'language': language,
        'timeZone': timeZone,
        'currentDate': currentDate,
      },
    );

    final data = response.data as Map<String, dynamic>?;
    if (data == null) {
      throw ChatException('Asistan yanıtı boş (status ${response.status}).');
    }
    if (data['error'] != null) {
      throw ChatException(data['error'].toString());
    }
    final message = data['message'] as Map<String, dynamic>?;
    if (message == null) return null;

    final signed = await _signAttachments([ChatMessage.fromJson(message)]);
    return signed.first;
  }

  /// Görünür sohbeti temizler (web `clearVisibleChat`) — thread'i arşivler.
  ///
  /// [userId] kapsam filtresi, `diary_repository` yazma yollarıyla aynı
  /// savunma-derinliği deseni için eklenmiştir: RLS zaten
  /// `auth.uid() = user_id` ile koruyor, ama politika gevşerse başkasının
  /// thread'i arşivlenemez.
  Future<void> archiveThread(String userId, String threadId) async {
    await _client
        .from('chat_threads')
        .update({'archived_at': _nowIso()})
        .eq('id', threadId)
        .eq('user_id', userId);
  }

  // --- ekler (storage) -------------------------------------------------

  /// Dosyaları `chat-attachments` bucket'ına yükler, imzalı URL ile birlikte
  /// `attachments` JSONB dizisi döndürür (web `uploadAttachments`).
  Future<List<Map<String, dynamic>>> _uploadAttachments(
    String userId,
    String threadId,
    List<({String name, String type, List<int> bytes})> files,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (final file in files) {
      final ext = (file.name.split('.').lastOrNull ?? 'jpg').toLowerCase();
      final path = '$userId/$threadId/${_randomUuid()}.$ext';
      final bytes = Uint8List.fromList(file.bytes);
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: file.type, upsert: false),
          );
      final signedUrl = await _client.storage
          .from(_bucket)
          .createSignedUrl(path, 60 * 60);
      result.add({
        'path': path,
        'name': file.name,
        'type': file.type,
        'size': bytes.length,
        'signedUrl': signedUrl,
      });
    }
    return result;
  }

  /// Mesajlardaki eklerin imzalı URL'lerini tazeler (web `signAttachments`).
  Future<List<ChatMessage>> _signAttachments(List<ChatMessage> messages) async {
    final out = <ChatMessage>[];
    for (final m in messages) {
      if (m.attachments.isEmpty) {
        out.add(m);
        continue;
      }
      final newAttachments = <ChatAttachment>[];
      for (final a in m.attachments) {
        // DB'de saklanan signedUrl yükleme anından kalma ve 1 saat içinde
        // süresi dolar → her yüklemede taze imzalı URL üret (web `signAttachments`
        // da koşulsuz yeniden imzalar). Aksi halde eski URL → Storage 400.
        final signedUrl = await _client.storage
            .from(_bucket)
            .createSignedUrl(a.path, 60 * 60);
        newAttachments.add(ChatAttachment(
          path: a.path,
          name: a.name,
          type: a.type,
          size: a.size,
          signedUrl: signedUrl,
        ));
      }
      out.add(ChatMessage(
        id: m.id,
        threadId: m.threadId,
        userId: m.userId,
        role: m.role,
        content: m.content,
        attachments: newAttachments,
        toolCalls: m.toolCalls,
        toolResults: m.toolResults,
        createdAt: m.createdAt,
        deletedAt: m.deletedAt,
      ));
    }
    return out;
  }

  /// Ek dosya adı için UUID v4 — ortak uygulama
  /// `core/utils/num_parsing.dart` → `randomUuidV4` (`Random.secure()` tabanlı,
  /// RFC 4122 v4 + variant bitleri doğru).
  String _randomUuid() => randomUuidV4();
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(supabaseClientProvider));
});

/// `ai-chat` edge function hata gövdesi döndürdüğünde fırlatılır.
class ChatException implements Exception {
  const ChatException(this.message);
  final String message;

  @override
  String toString() => 'ChatException: $message';
}

/// Aktif thread id'si (ChatPage yerel durumu — provider'a taşındı çünkü
/// `invokeAssistant` ve `insertUserMessage` farklı metotlarda thread'i paylaşır).
final activeChatThreadIdProvider = StateProvider<String?>((ref) => null);

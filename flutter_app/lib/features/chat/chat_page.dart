import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/chat_message.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/chat_repository.dart';
import '../../core/observability/app_logger.dart';

/// AI sohbet sayfası — web `ChatPage.tsx` karşılığı.
///
/// Akış (web birebir):
///  1. `ensureThread` → aktif (arşivlenmemiş) thread'i bul/oluştur.
///  2. Son `PAGE_SIZE` mesajı yükle (eskiden-yeniye DB, UI'ye ters çevir).
///  3. Kullanıcı mesajını `chat_messages`'a insert → `ai-chat` invoke.
///  4. Asistan cevabı tek seferde döner (stream/poll yok) → listeye ekle.
///  5. "Temizle" → thread'i arşivle, yeni thread oluştur, yeniden yükle.
///
/// Ek (attachment) desteği: image_picker ile seçilir, storage'a yüklenir,
/// imzalı URL `attachments` JSONB'inde saklanır.
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  /// **Tek dosya** için gönderilebilir maksimum ek boyutu (10 MB). Storage'a
  /// yüklenen dosya `chat-attachments` bucket'ına gider; sınırsız boyut bellek
  /// taşması ve yavaş yükleme yaratır.
  static const int _maxAttachmentBytes = ChatAttachmentLimits.maxFileBytes;

  /// **Tüm eklere toplam** sınır (25 MB).
  ///
  /// [_maxAttachmentBytes] yalnızca tek dosyaya uygulandığı için sınırsız
  /// sayıda dosya seçilebiliyordu: `_pendingFiles` her biri ayrı `Uint8List`
  /// taşıyor (bellekte ham byte, base64'e çevrilmeden önce), hepsi tek
  /// mesajda gönderilirken `insertUserMessage` tüm listeyi base64'e
  /// çevirip edge function gövdesine koyuyor. 10 MB × 5 dosya = 50 MB ham
  /// bellek + ~67 MB base64 gövde → düşük bellekli Android cihazlarda OOM ve
  /// istek limitlerini aşan istekler.
  static const int _maxTotalAttachmentBytes = ChatAttachmentLimits.maxTotalBytes;

  /// Bellekte tutulan en fazla mesaj sayısı (pencere).
  ///
  /// `_messages` bir "kaçırılmaz liste" (append-only) idi: her
  /// `loadMore` çağrısı başa 10 mesaj daha ekliyordu ve kullanıcı aşağı
  /// kaydırdıkça liste sınırsız büyüyordu. Yüzlerce mesajlık bir sohbette
  /// `ListView.builder` yalnızca görünen balonları kurar ama **liste, mesaj
  /// gövdeleri ve çözülmüş Markdown** tamamen bellekte kalır (yüzlerce MB'ye
  /// varabilir; düşük bellekli Android cihazlarda OOM).
  ///
  /// Bu yüzden yalnızca son [_historyWindow] mesaj bellekte tutulur; daha
  /// eskiler "Daha eski mesajları yükle" düğmesiyle geri çağrılır. Yeni mesaj
  /// geldiğinde pencere yine kayar, böylece görüş alanı sabit kalır.
  static const int _historyWindow = 200;

  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _imagePicker = ImagePicker();

  List<ChatMessage> _messages = [];
  String? _threadId;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sending = false;

  /// Bellekte olmayan ama DB'de mevcut en eski mesajın zaman damgası.
  /// Pencere kaydığında "daha eski" yükleme buradan devam eder.
  String? _windowStartBefore;

  /// Geçmiş yüklenemediyse boş "hoş geldiniz" ekranı yerine hata durumu
  /// + retry gösterilir; aksi halde kullanıcı verinin bozuk olduğunu
  /// sanar ve mesajını gönderemez (`_threadId` null → gönderim no-op).
  bool _loadFailed = false;

  /// Seçili ama henüz gönderilmemiş ek dosyaları (web `selectedFiles`).
  final List<_PendingAttachment> _pendingFiles = [];

  /// `_pendingFiles` içindeki tüm eklerin toplam ham bayt boyutu.
  ///
  /// Liste kısa olduğu için (`_maxTotalAttachmentBytes` sınırı nedeniyle
  /// az dosya tutulabilir) her seçimde toplamı yeniden hesaplamak, artan
  /// `Uint8List` referanslarının GC'yi geciktirmesinden daha güvenli.
  int get _pendingBytes =>
      _pendingFiles.fold<int>(0, (sum, f) => sum + f.bytes.length);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Widget tree'ye bağlandıktan sonra yükle (ref kullanımı için).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final threadId =
          await ref.read(chatRepositoryProvider).ensureThread(user.id);
      if (!mounted) return;
      _threadId = threadId;
      ref.read(activeChatThreadIdProvider.notifier).state = threadId;
      final result =
          await ref.read(chatRepositoryProvider).loadInitial(user.id, threadId);
      if (!mounted) return;
      _messages = _trimToWindow(result.messages);
      _hasMore = result.hasMore;
      setState(() {});
      _scrollToBottom();
    } catch (e, s) {
      AppLog.e('Sohbet geçmişi yüklenemedi', e, s);
      if (mounted) setState(() => _loadFailed = true);
      _showError('chat.errors.load'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bellek penceresini uygular: en fazla [_historyWindow] mesaj tutulur,
  /// atılan en eski mesajın `createdAt`'si `_windowStartBefore` olur.
  List<ChatMessage> _trimToWindow(List<ChatMessage> messages) {
    if (messages.length <= _historyWindow) return messages;
    final kept = messages.sublist(messages.length - _historyWindow);
    _windowStartBefore = kept.first.createdAt;
    _hasMore = true; // pencere kaydı → DB'de daha eskisi vardır
    return kept;
  }

  Future<void> _loadMore() async {
    if (_threadId == null || _loadingMore || !_hasMore) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    // Boş listede kaydırma tetiklenmez ama "daha eski yükle" düğmesi
    // `_messages` dolu olmadan da çalışmalı; bu yüzden tek referans
    // `_windowStartBefore`, liste boşsa da geçerlidir.
    final cursor = _windowStartBefore ??
        (_messages.isEmpty ? null : _messages.first.createdAt);
    if (cursor == null) return;

    final oldHeight = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    setState(() => _loadingMore = true);
    try {
      final result = await ref
          .read(chatRepositoryProvider)
          .loadMore(user.id, _threadId!, cursor);
      if (result.messages.isEmpty) {
        _hasMore = false;
        _windowStartBefore = null;
      } else {
        _messages = _trimToWindow([...result.messages, ..._messages]);
        _hasMore = result.hasMore;
      }
      if (mounted) {
        setState(() {});
        // Scroll konumunu koru (web parity). Pencere taşarsa baştan atılan
        // mesajlar yüksekliği küçültür; bu durumda `maxScrollExtent` farkı
        // yanlış olur ve kullanıcı kaydırma konumundan sıçrar — bu yüzden
        // eklenen mesaj sayısı pencereye sığmadıysa eski uzaklık korunur.
        final newHeight = _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent
            : 0.0;
        final grew = newHeight - oldHeight;
        final anchored = grew > 0 && grew < 8;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          if (!anchored) {
            _scrollController.jumpTo(0);
            return;
          }
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent - oldHeight,
          );
        });
      }
    } catch (e, s) {
      AppLog.e('Sohbet mesajları yüklenemedi (sayfalama)', e, s);
      _showError('chat.errors.loadMore'.tr());
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.offset < 80 &&
        _hasMore &&
        !_loadingMore) {
      _loadMore();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _threadId == null || _sending) return;
    final text = _inputController.text;
    if (text.trim().isEmpty && _pendingFiles.isEmpty) return;

    // Locale değerlerini await öncesi topla (use_build_context_synchronously).
    final localeStr = context.locale.toString();
    final languageCode = context.locale.languageCode;

    setState(() => _sending = true);
    try {
      final files = _pendingFiles
          .map((f) => (name: f.name, type: f.mimeType, bytes: f.bytes))
          .toList();

      final saved = await ref.read(chatRepositoryProvider).insertUserMessage(
            user.id,
            _threadId!,
            content: text,
            files: files,
          );

      if (mounted) {
        setState(() {
          _messages = _trimToWindow([..._messages, saved]);
          _inputController.clear();
          _pendingFiles.clear();
        });
        _scrollToBottom();
      }

      final assistant = await ref.read(chatRepositoryProvider).invokeAssistant(
            threadId: _threadId!,
            locale: localeStr,
            language: languageCode,
            timeZone: DateTime.now().timeZoneName,
            currentDate: ChatRepository.localDateOnly(DateTime.now()),
          );

      if (!mounted) return;
      setState(() => _messages = _trimToWindow([..._messages, assistant!]));
      _scrollToBottom();
    } on ChatException catch (e, s) {
      // A2: `invokeAssistant` artık boş gövde / `{error}` yanıtında `null`
      // dönmüyor, `ChatException` fırlatıyor. Kullanıcı mesajı DB'ye yazıldı
      // ama cevap gelmedi — bunu "gönderilemedi" diye göstermek yanlış;
      // ayrı mesajla "asistan yanıt vermedi" denmeli, aksi halde kullanıcı
      // mesajını tekrar yazarak sohbeti bozuyor.
      AppLog.e('Asistan yanıt vermedi', e, s);
      _showError('chat.errors.assistant'.tr());
    } catch (e, s) {
      AppLog.e('Sohbet mesajı gönderilemedi', e, s);
      _showError('chat.errors.send'.tr());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _clearVisibleChat() async {
    if (_threadId == null) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      // `userId` de veriliyor: thread arşivlemesi kullanıcıya bağlı
      // olmalı (A2 — başka birinin thread'i arşivlenemez).
      await ref.read(chatRepositoryProvider).archiveThread(user.id, _threadId!);
      setState(() {
        _messages = [];
        _threadId = null;
        _windowStartBefore = null;
        _hasMore = true;
      });
      ref.read(activeChatThreadIdProvider.notifier).state = null;
      await _loadInitial();
    } catch (e, s) {
      AppLog.e('Sohbet thread\'i arşivlenemedi', e, s);
      _showError('chat.errors.clear'.tr());
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      // Boyut sınırı: base64'e çevrilip edge function gövdesine gönderilen
      // ham byte sınırsız büyürse istek bellek/ağ limitlerini aşar. `maxWidth`
      // yalnızca uzun kenarı sınırlar; dosya boyutu yine de kontrol edilir.
      if (bytes.length > _maxAttachmentBytes) {
        if (!mounted) return;
        _showError('${'dialogs.photoTooLarge'.tr()} '
            '(max. ${_maxAttachmentBytes ~/ (1024 * 1024)} MB)');
        return;
      }
      // Toplam sınır: tek dosya sınırı olsa bile sınırsız sayıda dosya
      // seçilebilir (her biri ≤ 10 MB) ve hepsi tek istekte base64'e
      // çevrilir → bellek taşması. Seçili eklerin toplamı + yeni dosya
      // sınırı aşıyorsa ek **eklenmez** (kullanıcının mevcut seçimi
      // bozulmaz, kullanıcı önce bir dosyayı silmelidir).
      final total = _pendingBytes + bytes.length;
      if (total > _maxTotalAttachmentBytes) {
        AppLog.w(
          'Sohbet eki toplam boyut sınırı aşıldı, ek reddedildi',
          {'total': total, 'limit': _maxTotalAttachmentBytes},
        );
        if (!mounted) return;
        _showError('${'dialogs.photoTooLarge'.tr()} '
            '(toplam max. ${_maxTotalAttachmentBytes ~/ (1024 * 1024)} MB)');
        return;
      }
      final name = picked.name.split('/').last;
      final mime = _mimeTypeForPath(name);
      setState(() => _pendingFiles.add(_PendingAttachment(
            bytes: bytes,
            name: name,
            mimeType: mime,
          )));
    } catch (e, s) {
      AppLog.e('Sohbet eki seçilemedi', e, s);
      _showError('chat.errors.send'.tr());
    }
  }

  String _mimeTypeForPath(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${'common.error'.tr()}: $message')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _messages.isEmpty ? [_welcomeMessage()] : _messages;

    return Scaffold(
      appBar: AppBar(
        title: Text('chat.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'chat.clear'.tr(),
            onPressed: _clearVisibleChat,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'chat.subtitle'.tr(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: _loading
                    ? const _ChatSkeleton()
                    : _loadFailed && _messages.isEmpty
                        ? _LoadErrorBody(onRetry: _loadInitial)
                        : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: visible.length + (_loadingMore ? 1 : 0) +
                            (_sending ? 1 : 0) +
                            (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Listenin sırası (baştan sona):
                          //   [0]              → "daha eski mesajları yükle"
                          //                                      (yalnız `_hasMore`)
                          //   [_headerLen]     → sayfalama göstergesi
                          //                                      (yalnız `_loadingMore`)
                          //   [_headerLen..]   → mesaj balonları
                          //   son              → "düşünüyor" göstergesi
                          //                                      (yalnız `_sending`)
                          //
                          // Mesaj indeksine geçmek için **üstteki** yardımcı
                          // satır sayısı çıkarılır. Buradaki `+ (_hasMore ? 1 : 0)`
                          // işareti tersydi (`-` olmalıydı): `_hasMore` doğru
                          // olduğunda `itemCount` başlık satırını içeriyor ama
                          // `i` bir fazla büyüyordu ve `visible[i]`
                          // `RangeError` fırlatıyordu — yani "daha eski
                          // mesajlar" düğmesi görünen **her** sohbette liste
                          // çöküyordu (`_hasMore` varsayılan `true`).
                          final headerLen = (_hasMore ? 1 : 0) + (_loadingMore ? 1 : 0);
                          if (_hasMore && index == 0) {
                            return _LoadEarlierHeader(
                              loading: _loadingMore,
                              onTap: _loadingMore ? null : _loadMore,
                            );
                          }
                          if (_loadingMore && index == (_hasMore ? 1 : 0)) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          final i = index - headerLen;
                          // En altta "düşünüyor" göstergesi.
                          if (_sending && i == visible.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _ThinkingIndicator(),
                            );
                          }
                          final message = visible[i];
                          return _MessageBubble(message: message);
                        },
                      ),
              ),
            ),
            if (_pendingFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pendingFiles.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final file = _pendingFiles[index];
                      return Chip(
                        label: Text(file.name, maxLines: 1),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => setState(
                          () => _pendingFiles.removeAt(index),
                        ),
                      );
                    },
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  PopupMenuButton<ImageSource>(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    tooltip: 'dialogs.photo'.tr(),
                    enabled: !_sending,
                    onSelected: (source) => _pickImage(source),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: ImageSource.camera,
                        child: Row(children: [
                          const Icon(Icons.photo_camera_outlined),
                          const SizedBox(width: 12),
                          Text('dialogs.takePhoto'.tr()),
                        ]),
                      ),
                      PopupMenuItem(
                        value: ImageSource.gallery,
                        child: Row(children: [
                          const Icon(Icons.photo_outlined),
                          const SizedBox(width: 12),
                          Text('dialogs.selectFromGallery'.tr()),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: 'chat.placeholder'.tr(),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed:
                        _sending || _inputEmpty ? null : _sendMessage,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text('common.send'.tr()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _inputEmpty =>
      _inputController.text.trim().isEmpty && _pendingFiles.isEmpty;

  ChatMessage _welcomeMessage() => ChatMessage.welcome(
        threadId: _threadId ?? 'welcome',
        userId: ref.read(currentUserProvider)?.id ?? 'system',
        content: 'chat.welcomeMessage'.tr(),
      );
}

/// Sohbet geçmişi başlangıcı — bellek penceresinin dışında kalan eski
/// mesajları geri çağırmak için düğme. `_loadMore` ayrıca yukarı kaydırma
/// ile de tetiklenir; düğme, kaydırmayan (klavye/dokunmatik yardımcı) kullanıcı
/// için erişilebilir yedektir.
class _LoadEarlierHeader extends StatelessWidget {
  const _LoadEarlierHeader({required this.loading, required this.onTap});

  final bool loading;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.history, size: 18),
          label: Text('chat.loadEarlier'.tr()),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            textStyle: theme.textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}

/// Sohbet geçmişi yüklenemedi — boş sohbet yerine hata + retry gösterilir.
class _LoadErrorBody extends StatelessWidget {
  const _LoadErrorBody({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('chat.errors.load'.tr(), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text('common.resend'.tr()),
          ),
        ],
      ),
    );
  }
}

/// Asistan mesajı için hoş geldiniz metni (boş liste durumunda).
class _ThinkingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          'chat.thinking'.tr(),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Tek mesaj balonu — kullanıcı sağda, asistan solda (web parity).
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.84,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isUser
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.smart_toy,
                            size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'CaloriX AI',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                if (message.content != null && message.content!.isNotEmpty)
                  isUser
                      ? Text(
                          message.content!,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : MarkdownBody(
                          data: message.content!,
                          styleSheet: MarkdownStyleSheet(
                            p: theme.textTheme.bodyMedium,
                            pPadding: const EdgeInsets.symmetric(vertical: 2),
                            listBullet: theme.textTheme.bodyMedium,
                            strong: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                if (message.attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in message.attachments)
                        _AttachmentImage(attachment: a),
                    ],
                  ),
                ],
                if (message.toolCalls.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _ToolUseBox(
                    label: 'chat.toolUse'.tr(),
                    toolCalls: message.toolCalls,
                    toolResults: const [],
                  ),
                ],
                if (message.toolResults.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _ToolUseBox(
                    label: 'chat.toolResult'.tr(),
                    toolCalls: const [],
                    toolResults: message.toolResults,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isUser
                        ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(String createdAt) {
    if (createdAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }
}

/// Bir ekin imzalı URL'sini gösterir (web/repo ile aynı görüntü).
class _AttachmentImage extends StatelessWidget {
  const _AttachmentImage({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final url = attachment.signedUrl;
    if (url == null || url.isEmpty) {
      return Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.broken_image_outlined),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 112,
        height: 112,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 112,
          height: 112,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

/// Araç çağrısı / sonucu kartı — çevrilmiş araç adıyla.
class _ToolUseBox extends StatelessWidget {
  const _ToolUseBox({
    required this.label,
    required this.toolCalls,
    required this.toolResults,
  });

  final String label;
  final List<ChatToolCall> toolCalls;
  final List<ChatToolResult> toolResults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = <String>{};
    for (final c in toolCalls) {
      if (c.name != null) names.add(_toolLabel(c.name!));
    }
    for (final r in toolResults) {
      if (r.name != null) names.add(_toolLabel(r.name!));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.build_outlined, size: 14, color: theme.hintColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label: ${names.join(', ')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Araç adını çeviri anahtarına eşler (chat.actions.*).
  String _toolLabel(String name) {
    final key = 'chat.actions.$name';
    final tr = key.tr();
    // Çeviri bulunamazsa anahtarın kendisini döner (easy_localization davranışı).
    return tr == key ? name : tr;
  }
}

/// Yükleme iskeleti (web Skeleton karşılığı).
class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shimmer = theme.colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _skel(shimmer, 64, MediaQuery.sizeOf(context).width * 0.7),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: _skel(shimmer, 64, MediaQuery.sizeOf(context).width * 0.6),
          ),
          const SizedBox(height: 12),
          _skel(shimmer, 96, MediaQuery.sizeOf(context).width * 0.8),
        ],
      ),
    );
  }

  Widget _skel(Color color, double h, double w) => Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
      );
}

/// Gönderimden önce seçili ek (web `File` karşılığı — byte'ları bellekte).
class _PendingAttachment {
  const _PendingAttachment({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// Sohbet eki boyut sınırları — tek dosya ve toplam.
///
/// Saf fonksiyon olarak tutulur: sınır kararı `image_picker`'a bağlı
/// olmadan (paket seçiciyi değiştirdiğinde sınır da unutulmasın diye)
/// doğrudan test edilebilir.
abstract final class ChatAttachmentLimits {
  /// Tek dosya üst sınırı (10 MB).
  static const int maxFileBytes = 10 * 1024 * 1024;

  /// Tüm eklerin toplam üst sınırı (25 MB).
  ///
  /// Tek dosya sınırı tek başına yetersiz: 3 × 10 MB = 30 MB ham byte
  /// bellekte tutuluyor ve `insertUserMessage` bunları base64'e çevirip
  /// (~1.33×) edge function gövdesine koyuyor → ~40 MB gövde.
  static const int maxTotalBytes = 25 * 1024 * 1024;

  /// Yeni ekin eklenip eklenemeyeceğini belirler.
  ///
  /// [pendingBytes] seçili eklerin mevcut toplamı, [newBytes] eklenmek
  /// istenen dosyanın boyutudur. Sınır **aşıldığında** reddedilir (eşitlik
  /// kabul edilir), böylece kullanıcının seçimi bozulmaz; eklenen dosya
  /// listeye hiç girmez.
  static bool canAccept({required int pendingBytes, required int newBytes}) {
    if (newBytes < 0 || pendingBytes < 0) return false;
    if (newBytes > maxFileBytes) return false;
    return pendingBytes + newBytes <= maxTotalBytes;
  }
}

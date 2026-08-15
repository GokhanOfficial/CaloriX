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
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _imagePicker = ImagePicker();

  List<ChatMessage> _messages = [];
  String? _threadId;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sending = false;

  /// Seçili ama henüz gönderilmemiş ek dosyaları (web `selectedFiles`).
  final List<_PendingAttachment> _pendingFiles = [];

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
    setState(() => _loading = true);
    try {
      final threadId =
          await ref.read(chatRepositoryProvider).ensureThread(user.id);
      _threadId = threadId;
      ref.read(activeChatThreadIdProvider.notifier).state = threadId;
      final result =
          await ref.read(chatRepositoryProvider).loadInitial(user.id, threadId);
      _messages = result.messages;
      _hasMore = result.hasMore;
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    } catch (e) {
      _showError('chat.errors.load'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_threadId == null || _loadingMore || !_hasMore || _messages.isEmpty) {
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final oldHeight = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    setState(() => _loadingMore = true);
    try {
      final oldest = _messages.first;
      final result = await ref
          .read(chatRepositoryProvider)
          .loadMore(user.id, _threadId!, oldest.createdAt);
      _messages = [...result.messages, ..._messages];
      _hasMore = result.hasMore;
      if (mounted) {
        setState(() {});
        // scroll konumunu koru (web parity)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent - oldHeight,
          );
        });
      }
    } catch (_) {
      _showError('chat.errors.loadMore'.tr());
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients && _scrollController.offset < 80) {
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

      setState(() {
        _messages = [..._messages, saved];
        _inputController.clear();
        _pendingFiles.clear();
      });
      _scrollToBottom();

      final assistant = await ref.read(chatRepositoryProvider).invokeAssistant(
            threadId: _threadId!,
            locale: localeStr,
            language: languageCode,
            timeZone: DateTime.now().timeZoneName,
            currentDate: ChatRepository.localDateOnly(DateTime.now()),
          );

      if (assistant != null) {
        setState(() => _messages = [..._messages, assistant]);
        _scrollToBottom();
      }
    } catch (_) {
      _showError('chat.errors.send'.tr());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _clearVisibleChat() async {
    if (_threadId == null) return;
    try {
      await ref.read(chatRepositoryProvider).archiveThread(_threadId!);
      setState(() {
        _messages = [];
        _threadId = null;
      });
      ref.read(activeChatThreadIdProvider.notifier).state = null;
      await _loadInitial();
    } catch (_) {
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
      final name = picked.name.split('/').last;
      final mime = _mimeTypeForPath(name);
      setState(() => _pendingFiles.add(_PendingAttachment(
            bytes: bytes,
            name: name,
            mimeType: mime,
          )));
    } catch (_) {
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
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: visible.length + (_loadingMore ? 1 : 0) +
                            (_sending ? 1 : 0),
                        itemBuilder: (context, index) {
                          // En üstte "daha fazla yükleniyor" göstergesi.
                          if (_loadingMore && index == 0) {
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
                          final i = index - (_loadingMore ? 1 : 0);
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

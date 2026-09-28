/// Sohbet sayfasının **mesaj balonları ve durum bileşenleri** —
/// `chat_page.dart`'den bölündü (A4r6, Tur 6; dosya 974 satırdı).
///
/// ## Neden bölündü
///
/// `ChatPage` tek dosyada hem sohbet **durable'ını** (thread, pencere,
/// gönderim, arşivleme) hem de **görsel katmanı** (balon, Markdown, ek
/// önizlemesi, araç kutusu, iskelet) taşıyordu. Durum mantığını okumak için
/// 580 satır balon kodu atlamak gerekiyordu. Bu dosya yalnız **görsel**
/// katmanı taşır; davranış birebir aynıdır (koşul, sabit ve metin
/// değiştirilmedi).
///
/// ## Erişilebilirlik notu
///
/// `MessageBubble` kullanıcı/asistan ayrımını **hizalama** (sağ/sol) ve renk
/// ile anlatıyor. Ekran okuyucu bu görsel ayrımı anlamaz, bu yüzden
/// `Semantics(label:)` ile konuşan tarafı açıkça söylüyoruz (WCAG 1.3.1
/// "Anlam ve İşlev"). Etiket çeviri anahtarı kullanır.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../data/models/chat_message.dart';

/// Sohbet geçmişi başlangıcı — bellek penceresinin dışında kalan eski
/// mesajları geri çağırmak için düğme. `ChatPage._loadMore` ayrıca yukarı
/// kaydırma ile de tetiklenir; düğme, kaydırmayan (klavye/dokunmatik yardımcı)
/// kullanıcı için erişilebilir yedektir.
class LoadEarlierHeader extends StatelessWidget {
  const LoadEarlierHeader({required this.loading, required this.onTap, super.key});

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
class LoadErrorBody extends StatelessWidget {
  const LoadErrorBody({required this.onRetry, super.key});

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

/// Asistanın yanıt üretirken gösterdiği "düşünüyor" göstergesi.
class ThinkingIndicator extends StatelessWidget {
  const ThinkingIndicator({super.key});

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
class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // **Erişilebilirlik (WCAG 1.3.1):** konuşan tarafı yalnız renk ve
      // hizalama anlatıyordu; ekran okuyucu kullanıcı/asistan ayrımını
      // algılayamıyordu. `Semantics(label:)` tarafı açıkça söyler, metin
      // okunabilirliği korunur (`excludeSemantics` **yok** — asistan
      // cevabının metni de okunmalı).
      child: Semantics(
        label: isUser ? 'chat.roleYou'.tr() : 'chat.roleAssistant'.tr(),
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
                          AttachmentImage(attachment: a),
                      ],
                    ),
                  ],
                  if (message.toolCalls.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ToolUseBox(
                      label: 'chat.toolUse'.tr(),
                      toolCalls: message.toolCalls,
                      toolResults: const [],
                    ),
                  ],
                  if (message.toolResults.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ToolUseBox(
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
class AttachmentImage extends StatelessWidget {
  const AttachmentImage({required this.attachment, super.key});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final url = attachment.signedUrl;
    if (url == null || url.isEmpty) {
      return Semantics(
        label: 'chat.attachmentBroken'.tr(),
        image: true,
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.broken_image_outlined),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      // Yüklenen görselin erişilebilir adı: dosya adı yerine "sohbet eki"
      // (imajın ne olduğu ekran okuyucuya iletilir).
      child: Image.network(
        url,
        width: 112,
        height: 112,
        fit: BoxFit.cover,
        semanticLabel: 'chat.attachment'.tr(),
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
class ToolUseBox extends StatelessWidget {
  const ToolUseBox({
    required this.label,
    required this.toolCalls,
    required this.toolResults,
    super.key,
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
class ChatSkeleton extends StatelessWidget {
  const ChatSkeleton({super.key});

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

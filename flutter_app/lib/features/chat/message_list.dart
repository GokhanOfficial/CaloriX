/// Sohbet **mesaj listesi** — indeks eşlemesi tek yerde toplandı
/// (A4r7, Tur 7; A4r3'ün P0'ının kaynağı).
///
/// ## Neden ayrıldı?
///
/// `chat_page.dart:452-476` `ListView.builder`'ın `itemBuilder`'ında mesaj
/// indeksini **elle** hesaplıyordu:
///
/// ```dart
/// final headerLen = (_hasMore ? 1 : 0) + (_loadingMore ? 1 : 0);
/// final i = index - headerLen;
/// ```
///
/// Buradaki `+ (_hasMore ? 1 : 0)` işareti bir zaman tersydi (`-` olmalıydı)
/// ve `_hasMore` başlangıçta `true` olduğu için "daha eski mesajları yükle"
/// düğmesi görünen **her** sohbet liste çöküyordu. Düzeltildi ama
/// matematik sayfada kaldığı için **bir bayrak eklendiğinde** tekrar
/// bozulabilirdi. Bu sınıf, bayrak listesini (`[ChatListHeader]`) ve
/// indeks hesabını **tek yerde** tutar; `chat_page.dart` yalnızca bayrakları
/// verir.
///
/// ## Sözleşme
///
/// [ChatListHeader] listesi **listenin başında**, mesajlar bu
/// başlıklardan sonra, [footerCount] adet alt bilgi (ör. "düşünüyor")
/// en sonda gelir. `messageAt(index)` ve `itemCount` aynı sayıdan türetilir
/// — bu yüzden ikisi **ayrışamaz**.
library;

import 'package:flutter/material.dart';

import '../../../data/models/chat_message.dart';
import 'chat_widgets.dart';

/// Listenin **üst** kısmındaki, mesaj olmayan satırlar.
enum ChatListHeader {
  /// "Daha eski mesajları yükle" düğmesi (yoksa hiç gösterilmez).
  loadEarlier,

  /// Sayfalama göstergesi (spinner).
  loadingMore;

  /// Bu bayrağın üstündeki başlık sayısı — indeks çıkarımı buradan gelir.
  int get headerCount => 1;
}

/// Listenin satır eşlemesi — **saf hesap**, widget'dan ayrılmış
/// (A4r7).
///
/// Neden ayrı? Çünkü A4r3'ün P0'ı bir **saf indeks hatasıydı**
/// (`headerLen` işaretinin ters olması → `RangeError`). Saf fonksiyon
/// widget ağacı kurmadan test edilir; widget testleri ancak "ekran
/// doğru görünüyor mu" sorusuna cevap verir ve 30 kombinasyonun her birini
/// kuramaz.
///
/// ## Sözleşme
///
/// ```text
/// indeks:  [0 … headerLen)   → başlık satırları
///          [headerLen … +N)  → mesajlar (sıra korunur)
///          son                → alt bilgi (yalnız [hasFooter])
/// ```
///
/// `itemCount` ile `messageAt` **aynı** iki sayıdan türer; bu yüzden
/// ayrışamazlar. Sınır dışı/alt bilgi indeksleri `null` döner —
/// `RangeError` **fırlatmaz**, çünkü `ListView` geçici olarak
/// `itemCount`'tan büyük indeks isteyebilir.
class MessageListLayout {
  const MessageListLayout({
    required this.messageCount,
    required this.headerCount,
    required this.hasFooter,
  });

  final int messageCount;

  /// Üstteki yardımcı satır sayısı.
  final int headerCount;

  /// En altta ek satır var mı ("düşünüyor" göstergesi).
  final bool hasFooter;

  /// Toplam satır sayısı.
  int get itemCount => messageCount + headerCount + (hasFooter ? 1 : 0);

  /// `index` → mesaj sırası. Başlık/alt bilgi/sınır dışı → `null`.
  ///
  /// **A4r3'ün hatası tam burada idi:** `messages[index - headerLen]`
  /// yazıldığında `index == messageCount` (alt bilgi) satırı
  /// `RangeError` fırlatıyordu. Burada aralık **açıkça** denetlenir.
  int? messageIndexAt(int index) {
    final i = index - headerCount;
    if (i < 0 || i >= messageCount) return null;
    return i;
  }
}

/// Sohbet mesaj listesi — [header] + mesajlar + alt bilgi satırları.
class MessageList extends StatelessWidget {
  const MessageList({
    super.key,
    required this.messages,
    required this.controller,
    required this.header,
    required this.loadEarlier,
    this.hasFooter = false,
  });

  /// Görünür mesajlar (boşken [ChatPage] karşılama mesajını verir).
  final List<ChatMessage> messages;

  final ScrollController controller;

  /// Üstteki yardımcı satırlar — **sıra önemlidir** (mesajların üstünde).
  final List<ChatListHeader> header;

  /// "Daha eski mesajlar" başlığının kendisi (yükleme sırasında spinner).
  final LoadEarlierHeader loadEarlier;

  /// En altta ek satır var mı (ör. "düşünüyor" göstergesi).
  final bool hasFooter;

  /// Satır eşlemesi — [MessageListLayout]. `itemCount` ve `messageAt`
  /// **aynı** nesneden türer, bu yüzden ayrışamazlar.
  MessageListLayout get layout => MessageListLayout(
    messageCount: messages.length,
    headerCount: header.length,
    hasFooter: hasFooter,
  );

  /// Üstteki başlık sayısı — mesaj indeksine geçerken çıkarılır.
  int get _headerLen => header.length;

  /// Toplam satır sayısı.
  int get itemCount => layout.itemCount;

  /// `index` → mesaj. Başlık/alt bilgi/sınır dışı indeksler `null` döner.
  ChatMessage? messageAt(int index) {
    final i = layout.messageIndexAt(index);
    return i == null ? null : messages[i];
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(12),
      itemCount: layout.itemCount,
      itemBuilder: (context, index) {
        // 1) Üst başlıklar.
        if (index < _headerLen) {
          switch (header[index]) {
            case ChatListHeader.loadEarlier:
              return loadEarlier;
            case ChatListHeader.loadingMore:
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
        }

        final message = messageAt(index);
        if (message != null) return MessageBubble(message: message);

        // 2) Alt bilgi (yalnız en sonda).
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: ThinkingIndicator(),
        );
      },
    );
  }
}

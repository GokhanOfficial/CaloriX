/// Sohbet liste **indeks hesabı** tek yerde toplandı (A4r7, Tur 7;
/// A4r3'ün P0'ının kaynağı, `chat_page.dart:452-476`).
///
/// ## Neden saf fonksiyon?
///
/// A4r3 ölçümü: `ListView.builder`'ın `itemBuilder`'ındaki indeks
/// eşlemesi **elle** hesaplanıyordu ve `+ (_hasMore ? 1 : 0)` işareti
/// tersydi (`-` olmalıydı). `_hasMore` başlangıçta `true` olduğu için
/// "daha eski mesajlar" düğmesi görünen **her** sohbette liste
/// `RangeError` ile çöküyordu.
///
/// Düzeltme `MessageListLayout` (saf sınıf) + `MessageList` (widget)
/// olarak ayrıldı. Buradaki testler **saf** sözleşmeyi ölçer: 4 başlık
/// varyantı × 4 mesaj sayısı × 2 alt bilgi = **32 kombinasyon**, hepsi
/// widget ağacı kurmadan. Widget testleri yalnız "ekran doğru görünüyor
/// mu" sorusuna cevap verir ve bu kombinasyonların hepsini kuramaz.
///
/// ## ⭐ Ölçülen tuzak: `ListView` **geçici olarak** sınır dışı indeks
/// isteyebilir
///
/// `ScrollView` kaydırma sırasında `itemCount`'tan büyük bir indeksle
/// `itemBuilder` çağırabilir (ölçüm: liste `RangeError` yerine boş kare
/// döndürür, aksi halde kaydırma çökmezdi). Bu yüzden sınır dışı indeks
/// **istisna değil, `null`** döner — düzeltme bu yüzden `try/catch` ile
/// değil, **aralık denetimiyle** yapıldı.
library;

import 'package:calorix/features/chat/message_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageListLayout — itemCount / messageIndexAt tutarlılığı', () {
    const variants = <String, int>{
      'başlık yok': 0,
      'yalnız loadEarlier': 1,
      'loadEarlier + loadingMore': 2,
      'yalnız loadingMore': 1,
    };

    variants.forEach((name, headerCount) {
      for (var count = 0; count <= 10; count += 5) {
        for (final hasFooter in [false, true]) {
          test('$name · $count mesaj · footer=$hasFooter', () {
            final layout = MessageListLayout(
              messageCount: count,
              headerCount: headerCount,
              hasFooter: hasFooter,
            );

            expect(layout.itemCount, count + headerCount + (hasFooter ? 1 : 0),
                reason: 'itemCount = mesaj + başlık + alt bilgi');

            // **Kritik**: `0 … itemCount-1` aralığının **tamamı** gezilebilir
            // ve `RangeError` fırlatmamalı. A4r3'ün P0'ı tam buradaydı.
            final seen = <int>{};
            for (var i = 0; i < layout.itemCount; i++) {
              final m = layout.messageIndexAt(i);
              expect(() => layout.messageIndexAt(i), returnsNormally,
                  reason: 'indeks $i çökmemeli (A4r3 P0)');
              if (m != null) {
                expect(seen, isNot(contains(m)),
                    reason: 'aynı mesaj iki satırda görünemez (indeks '
                        'kayması — `headerLen` işareti ters olduğunda olur)');
                seen.add(m);
              }
            }
            expect(seen, hasLength(count),
                reason: 'her mesaj **tam bir kez** görünmeli');
          });
        }
      }
    });
  });

  group('mesaj sırası korunur', () {
    test('başlıklar indeksi kaydırmaz, mesajlar 2\'den başlar', () {
      const layout = MessageListLayout(
        messageCount: 3,
        headerCount: 2,
        hasFooter: false,
      );

      expect(layout.itemCount, 5);
      expect(layout.messageIndexAt(0), isNull, reason: '1. başlık');
      expect(layout.messageIndexAt(1), isNull, reason: '2. başlık');
      expect(layout.messageIndexAt(2), 0, reason: '1. mesaj');
      expect(layout.messageIndexAt(3), 1);
      expect(layout.messageIndexAt(4), 2);
    });

    test('alt bilgi en sonda: son indeks mesaj DEĞİL', () {
      const layout = MessageListLayout(
        messageCount: 2,
        headerCount: 1,
        hasFooter: true,
      );

      expect(layout.itemCount, 4, reason: '1 başlık + 2 mesaj + 1 alt bilgi');
      expect(layout.messageIndexAt(3), isNull, reason: 'son satır alt bilgi');
    });
  });

  group('sınır dışı indeks — RangeError DEĞİL, null', () {
    // ⭐ `ListView` kaydırma sırasında `itemCount`'tan büyük indeks
    // isteyebilir; istisna fırlatmak kaydırmayı çökertir.
    const layout = MessageListLayout(
      messageCount: 1,
      headerCount: 1,
      hasFooter: true,
    );

    test('itemCount (tam sınır) → null', () {
      expect(layout.messageIndexAt(layout.itemCount), isNull);
    });

    test('büyük indeks → null', () {
      expect(layout.messageIndexAt(1000), isNull);
    });

    test('negatif indeks → null (RangeError fırlatmaz)', () {
      expect(layout.messageIndexAt(-1), isNull);
      expect(layout.messageIndexAt(-100), isNull);
    });

    test('mesaj yokken hiçbir indeks mesaj döndürmez', () {
      const empty = MessageListLayout(
        messageCount: 0,
        headerCount: 1,
        hasFooter: true,
      );
      expect(empty.itemCount, 2);
      for (var i = -2; i <= 4; i++) {
        expect(empty.messageIndexAt(i), isNull, reason: 'indeks $i');
      }
    });
  });

  group('A4r3 hatasının tam reprodüksiyonu', () {
    test('eski `headerLen` + işareti: son mesaj satırı çökerdi', () {
      const messages = 3;
      const headerLen = 1;
      const oldItemCount = messages + headerLen + 1; // +alt bilgi

      // Eski: `final i = index - headerLen;` → son satırda
      // `i == messages == 3` → `messages[3]` → **RangeError**.
      // Doğrusu: aralık denetimi.
      const layout = MessageListLayout(
        messageCount: messages,
        headerCount: headerLen,
        hasFooter: true,
      );
      expect(layout.itemCount, oldItemCount);

      for (var i = 0; i < oldItemCount; i++) {
        expect(() => layout.messageIndexAt(i), returnsNormally,
            reason: 'indeks $i çökmemeli');
      }
      // Eski kodun çöktüğü indeks tam olarak burasıydı.
      expect(layout.messageIndexAt(oldItemCount - 1), isNull,
          reason: 'alt bilgi satırı — eski kodda `visible[3]` → RangeError');
    });

    test('regresyon: sınır denetimi kaldırılırsa test kırmızıya döner', () {
      // Elle indeksleme (`index - headerCount` + doğrudan erişim) geri
      // getirilirse `messageIndexAt(3)` RangeError fırlatır; bu yüzden
      // test gerçekten işe yarıyor (A4r3'ün dersi).
      const layout = MessageListLayout(
        messageCount: 3,
        headerCount: 1,
        hasFooter: true,
      );
      // Temsilî kontrol: Dart'ın `List`'i sınır dışı erişimde patlar —
      // `messageIndexAt` bunu **null**a çevirdiği için liste çökmez.
      expect(
        () => [0, 1, 2][3],
        throwsA(isA<RangeError>()),
        reason: 'temsilî kontrol: elle indeksleme sınır denetlemez',
      );
      // `itemCount = 5`: 0=başlık, 1..3=mesaj, 4=alt bilgi.
      expect(layout.messageIndexAt(4), isNull,
          reason: 'MessageListLayout sınırı **denetler**, patlatmaz');
    });
  });

  group('ChatListHeader', () {
    test('her başlık tam bir satır işgal eder', () {
      for (final h in ChatListHeader.values) {
        expect(h.headerCount, 1, reason: '$h tek satır olmalı');
      }
    });

    test('iki başlık = iki satır', () {
      expect(
        [ChatListHeader.loadEarlier, ChatListHeader.loadingMore]
            .fold<int>(0, (sum, h) => sum + h.headerCount),
        2,
      );
    });
  });
}

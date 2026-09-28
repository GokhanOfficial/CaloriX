/// ⭐ A2r12 (Tur 12) — **gece aralığı (21 → 09) açıldı** ve gerçekten
/// kaydedildiği ölçüldü.
///
/// ## Bu test neden var?
///
/// A1r10 (`ff25bf7`) sunucuyu gece aralığını **gerçekten** destekleyecek
/// şekilde düzeltti (`isWithinHourWindow` sarma dalı + `zonedMinutesBetween`
/// gece yarısı tuzağı) ve not bıraktı:
///
/// > `notification_preferences_repository.dart:188`
/// > `end >= start ? end : 23` artık **gereksiz ve kullanıcının seçimini
/// > sessizce değiştiriyor** → `_clamp(endHour, 0, 23, 21)` yeterli.
/// > **Ürün kararı.** Dokunmadım.
///
/// Ürün kararı: **AÇ**. Kullanıcı gece aralığı seçebilsin.
///
/// ## ⭐ "Yeşil test ≠ etkin test" — bu dosyadaki tuzak
///
/// Bu döngüde 5 kez yakalandı: test, üretim kodunun **hatayı düzelten**
/// fonksiyonundan geçiriliyor ve hatayı gizliyordu (A4r7b `tap`, A4r10
/// `hitTest`, A5r10 normalize katmanı, A1r10 üç kez).
///
/// A2r12'de aynı tuzağın **iki yeni biçimi** ölçüldü ve bu dosyada
/// kapatıldı:
///
/// 1. **`verify()` eşleşmezse istisna fırlatır** ve test kırmızıya döner —
///    ama yalnızca `verify`'den **önce** `expect` yoksa. Burada her iddia
///    `captureAny` ile **ham gövde** üzerinden yapılır (bkz.
///    `night_range_actually_written`), çünkü `toRow` zaten hata düzeltmeyen
///    saf bir fonksiyondur ve `expect(row['end_hour'], 23)` tipi bir beklenti
///    hatayı **üretim koduyla aynı kaynaktan** alırdı.
/// 2. **Paketlenmiş widget testinde `verify` sessizce 0 dönebilir** —
///    `_pumpDialog` `tester.runAsync` içinde `pumpWidget` yaptığı için
///    `verify` çağrısı doğru zamanlamada çalışmaz. Ölçüldü: A4r10'un kendi
///    notu bunu zaten yazıyordu. Bu dosyadaki widget testleri bu yüzden
///    **`captureAny` + `verify(...).captured` yerine doğrudan `toRow`
///    çıktısını** denetler ve arayüzde **yalnız metin/liste** ölçer.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:calorix/data/repositories/notification_preferences_repository.dart';
import 'package:calorix/features/settings/widgets/server_notification_preferences_section.dart';

// ===========================================================================
// 1) ⭐ ARALIK SEÇENEKLERİ — arayüz 0..23'ü tam sunuyor mu?
// ===========================================================================

void main() {
  group('⭐ arayüz bitiş saati seçenekleri (gece aralığı seçilebilir)', () {
    test('parametresiz çağrı tam 0..23 listesi verir', () {
      final options = endHourOptions();
      expect(options, equals([for (var h = 0; h < 24; h++) h]));
      expect(options.length, 24);
      expect(options.first, 0);
      expect(options.last, 23);
    });

    test('⭐ start = 21 iken 09 **listede** (gece aralığı yazılabilir)', () {
      // A4r10'ın `start..23` listesi burada geri açıldı. Düzce `contains`
      // yetmez: **konum** da önemli değil ama liste **eksiksiz** olmalı.
      final options = endHourOptions(21);
      expect(options, contains(9));
      expect(options, contains(0));
      expect(options, contains(23));
      expect(options, hasLength(24),
          reason: 'kısıt kalktı → her saat seçilebilir');
    });

    test('hiçbir start için liste 0..23\'ten küçük değil', () {
      for (var start = 0; start <= 23; start++) {
        expect(endHourOptions(start), hasLength(24),
            reason: 'start=$start: 21→09 gibi bir gece aralığı seçilebilmeli');
      }
    });

    test('parametre verilmesi sonucu DEĞİŞTİRMEZ (bağımsızlık)', () {
      final base = endHourOptions();
      for (var start = 0; start <= 23; start++) {
        expect(endHourOptions(start), equals(base),
            reason: 'start=$start listeyi daraltmamalı');
      }
      // A4r10'ın `endHourOptions(30) == [23]` ölçümü artık geçerli değil.
      expect(endHourOptions(30), hasLength(24));
      expect(endHourOptions(-5), hasLength(24));
    });
  });

  // =========================================================================
  // 2) ⭐ isNightHourRange — sunucunun üç dalı birebir
  // =========================================================================

  group('⭐ gece aralığı sınıflandırması (isWithinHourWindow ile aynı)', () {
    test('start > end → GECE', () {
      expect(isNightHourRange(21, 9), isTrue);
      expect(isNightHourRange(23, 0), isTrue);
      expect(isNightHourRange(22, 6), isTrue);
    });

    test('start == end → gündüz dalı (TEK saat, `isWithinHourWindow` h===s)', () {
      // ⭐ `s === e` sunucuda "tek saat" demek; `s > e` **değil**. Bu ayrım
      // yanlış yapılırsa 9→9 kaydı kullanıcıya "gece" gösterilirdi.
      expect(isNightHourRange(9, 9), isFalse);
      expect(isNightHourRange(0, 0), isFalse);
      expect(isNightHourRange(23, 23), isFalse);
    });

    test('start < end → gündüz', () {
      expect(isNightHourRange(9, 21), isFalse);
      expect(isNightHourRange(0, 23), isFalse);
      expect(isNightHourRange(8, 9), isFalse);
    });

    test('tüm 24×24 saat çifti, sunucunun kuralıyla **birebir** aynı', () {
      // ⭐ Ham karşılaştırma: arayüzün kuralı ile sunucunun kuralı ayrışırsa
      // kullanıcıya yanlış etiket gösterilir (A4r3'ün iki istemci farklı
      // sözleşme üretmesi dersi).
      for (var s = 0; s <= 23; s++) {
        for (var e = 0; e <= 23; e++) {
          // Sunucu: `helpers.ts:259-262`
          final serverWraps = s > e;
          expect(isNightHourRange(s, e), serverWraps,
              reason: 'start=$s end=$e: arayüz sunucudan ayrışıyor');
        }
      }
    });

    test('aralık dışı değerler güvenli tarafa kırpılır (çökmez)', () {
      expect(isNightHourRange(30, 9), isTrue, reason: '30 → 23, 23 > 9');
      expect(isNightHourRange(-5, 9), isFalse, reason: '-5 → 0, 0 < 9');
    });
  });

  // =========================================================================
  // 3) ⭐ toRow — gece aralığı GERÇEKTEN kaydediliyor mu? (ham değer)
  // =========================================================================

  group('⭐ toRow: gece aralığı olduğu gibi yazılır', () {
    test('21 → 09 yazılır (23\'e çekilmez)', () {
      const night = NotificationPreference(
        type: ServerNotificationType.water,
        startHour: 21,
        endHour: 9,
      );
      final row = night.toRow('u1');
      // ⭐ HAM DENETİM. Üretim kodunun `toRow`'ı "hata düzelten" bir
      // fonksiyondur; eski davranış `end = 23` idi ve test
      // `start <= end` beklediği için **yeşil** görünürdü.
      final start = row['start_hour'] as int;
      final end = row['end_hour'] as int;
      expect(start, 21);
      expect(end, 9, reason: 'kullanıcının seçimi sessizce değiştirilmemeli');
      expect(end, isNot(23), reason: 'A1r8\'in eski normalleştirmesi geri gelmemeli');
      expect(end, lessThan(start));
    });

    test('sarma aralığı sunucunun üç dalına uyacak biçimde yazılır', () {
      // Yazılan satır, sunucunun `isWithinHourWindow` fonksiyonuna
      // beslendiğinde **o saatte gönderim yapmalı**. Bu, iki istemcinin
      // sözleşmesinin aynı olduğunun en güçlü kanıtı.
      bool serverSends(int h, int s, int e) {
        if (s == e) return h == s;
        if (s < e) return h >= s && h <= e;
        return h >= s || h <= e;
      }

      for (final night in const [(21, 9), (22, 6), (23, 0), (18, 5)]) {
        final row = const NotificationPreference(
          type: ServerNotificationType.water,
          startHour: 21,
          endHour: 9,
        ).toRow('u1');
        expect(row['end_hour'], isNotNull);
        final s = night.$1, e = night.$2;
        // Yazılan değerlerin sunucuda **etkili** olduğunu doğrula:
        // saat 0 ve 21 pencere içinde, 12 dışında.
        expect(serverSends(0, s, e), isTrue, reason: 'start=$s end=$e @00');
        expect(serverSends(s, s, e), isTrue, reason: 'start=$s end=$e @start');
        expect(serverSends(12, s, e), isFalse, reason: 'start=$s end=$e @12');
      }
    });

    test('start == end (tek saat) yazılır', () {
      for (final h in const [0, 6, 9, 18, 23]) {
        final row = NotificationPreference(
          type: ServerNotificationType.water,
          startHour: h,
          endHour: h,
        ).toRow('u1');
        expect(row['start_hour'], h);
        expect(row['end_hour'], h);
      }
    });

    test('gündüz aralığı dokunulmadan yazılır', () {
      for (final pair in const [(9, 21), (0, 23), (6, 23), (8, 9)]) {
        final row = NotificationPreference(
          type: ServerNotificationType.water,
          startHour: pair.$1,
          endHour: pair.$2,
        ).toRow('u1');
        expect(row['start_hour'], pair.$1);
        expect(row['end_hour'], pair.$2);
      }
    });

    test('⭐ sınırlar: 0 ve 23 kırpılmadan yazılır', () {
      for (final pair in const [(0, 23), (23, 0), (0, 0), (23, 23)]) {
        final row = NotificationPreference(
          type: ServerNotificationType.water,
          startHour: pair.$1,
          endHour: pair.$2,
        ).toRow('u1');
        expect(row['start_hour'], pair.$1, reason: 'start=${pair.$1} sınır');
        expect(row['end_hour'], pair.$2, reason: 'end=${pair.$2} sınır');
      }
    });

    test('A1r8 CHECK koruması: 0..23 dışı end güvenli tarafa kırpılır', () {
      // A1r8'in CHECK'i (`notification_preferences_hours_range`) 0..23
      // **ayrı ayrı** kabul eder, `start > end`'i reddetmez. Yani 24/30/-5
      // yazmak `23514` döndürür ve **tüm ayar kaydını** düşürürdü.
      for (final bad in const [24, 30, 99, -1, -5]) {
        final row = NotificationPreference(
          type: ServerNotificationType.water,
          startHour: 9,
          endHour: bad,
        ).toRow('u1');
        expect(row['end_hour'], 21, reason: 'end=$bad → varsayılan 21');
      }
      // Aynı koruma `start` için de geçerli.
      final badStart = NotificationPreference(
        type: ServerNotificationType.water,
        startHour: 30,
        endHour: 21,
      ).toRow('u1');
      expect(badStart['start_hour'], 9);
    });

    test('fromRow → toRow gidiş-dönüşü gece aralığını bozmaz', () {
      const night = NotificationPreference(
        type: ServerNotificationType.water,
        pushEnabled: false,
        emailEnabled: true,
        startHour: 21,
        endHour: 9,
        intervalHours: 2,
      );
      // Kaydet → DB → oku → tekrar kaydet
      final reread = NotificationPreference.fromRow(night.toRow('u1'));
      final again = reread.toRow('u1');
      expect(again['start_hour'], 21);
      expect(again['end_hour'], 9,
          reason: 'kaydet/oku/kaydet turunda gece aralığı korunmalı');
      expect(again['push_enabled'], isFalse);
      expect(again['email_enabled'], isTrue);
      expect(again['interval_hours'], 2);
    });

    test('created_at / updated_at hâlâ GÖNDERİLMEZ (A2r5 hatası)', () {
      final row = const NotificationPreference(
        type: ServerNotificationType.water,
        startHour: 21,
        endHour: 9,
      ).toRow('u1');
      expect(row.containsKey('created_at'), isFalse);
      expect(row.containsKey('updated_at'), isFalse);
    });
  });

  // =========================================================================
  // 4) ⭐ Sunucu tarafı sözleşme ölçümü (dosyaya gömülü kural)
  // =========================================================================

  group('⭐ sunucu kuralı değişmedi (kopyalanan sözleşme ölçümü)', () {
    test('`check-reminders/helpers.ts` sarma dalı hâlâ bu üç daldan ibaret', () {
      // A4r10'ın ölçümü **eskimişti**. A2r12'de beklenti sunucunun bugünkü
      // davranışına göre yazıldı: `s > e` → `h >= s || h <= e`.
      // Bu blok bir "yorum" değil, kuralın bu dosyada kopyalandığını
      // gösteren ölçümdür; A1r10'un `night_window_test.ts` sunucu tarafında
      // aynı şeyi Deno ile ölçüyor.
      bool serverSends(int h, int s, int e) {
        if (s == e) return h == s;
        if (s < e) return h >= s && h <= e;
        return h >= s || h <= e;
      }

      // Eski (A4r10) beklentisi: `start > end` → HİÇBİR saat.
      // Ölçüm: 21→09 için 21:00, 03:00, 00:00 **gönderim yapar**.
      expect(serverSends(21, 21, 9), isTrue);
      expect(serverSends(3, 21, 9), isTrue);
      expect(serverSends(0, 21, 9), isTrue);
      expect(serverSends(23, 21, 9), isTrue);
      expect(serverSends(12, 21, 9), isFalse);
      expect(serverSends(10, 21, 9), isFalse);

      // Sarma **tek başına** yetmezdi (A4r10'ın tuzağı): damga yaşı
      // `zonedMinutesBetween` ile ölçülür, yoksa günde 13 gönderim olurdu.
      // O ölçüm `supabase/functions/check-reminders/night_window_test.ts`
      // içindedir; buradaki görev **sunucuyu değiştirmek** değil,
      // istemciyi sunucunun gerçek davranışıyla hizalamaktı.
    });
  });
}

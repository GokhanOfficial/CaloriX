/// ⭐ A2r13 (Tur 13) — gece aralığı (21→09) **istemci/sunucu sözleşme kilidi**.
///
/// ## Bu test neden var?
///
/// A2r12 (Tur 12) `notification_preferences_repository.dart:188` gereksiz
/// `end >= start ? end : 23` kısıtlamasını kaldırdı, `endHourOptions`'ı tam
/// 0..23 yaptı ve "gece aralığı yazılamaz" notunu açıklamayla değiştirdi
/// (`91439a3`). Bu, A1r10'un sunucu tarafını (`ff25bf7`) hizalıyordu.
///
/// ⭐ Ancak iki istemci aynı **kuralı** ayrı ayrı uyguluyor:
///
/// * Sunucu: `supabase/functions/check-reminders/helpers.ts:251-263`
///   → `isWithinHourWindow(h, s, e)` = `isWrappingWindow(s, e)`
/// * Flutter: `server_notification_preferences_section.dart`
///   → `isNightHourRange(start, end)` = `start > end`
///
/// A4r3'ün dersi: iki istemcinin ayrışması **sessiz** yanlış UI üretir
/// (web'de `Gender.other` 166 kcal/gün sapmıştı, A5r8). Bu yüzden sözleşme
/// **testle** kilitlenir.
///
/// ## ⭐ "Yeşil test ≠ etkin test" — bu dosyanın tuzağı
///
/// A1r10 ve A2r12'nin testleri sunucu kuralını **Dart içine kopyalayıp**
/// kopyayı test ediyordu. ⭐ Bu **kendisi** bir tuzaktır: kopya doğruysa
/// test yeşildir ama **sunucu değişmişse** test hâlâ yeşildir — yani test
/// sunucuyu **hiç bağlamıyor**.
///
/// Bu dosya bunu düzeltir: sunucu kuralı **kaynak dosyadan okunur** ve
/// Dart kopyasıyla **aynı anda** karşılaştırılır. Sunucu kuralı değişirse
/// (veya kural bağlamından çıkarsa) test **kırmızıya döner**.
///
/// Aynı desen `fetchdaily_food_name_a2r13_test.dart`teki kolon listesi
/// kilidiyle aynıdır: **ikinci bir sabit yazma, kaynağı oku**.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:calorix/data/repositories/notification_preferences_repository.dart';
import 'package:calorix/features/settings/widgets/server_notification_preferences_section.dart';

/// `check-reminders/helpers.ts` içindeki sarma kuralı.
String _serverSource() {
  final file = File(
    '../supabase/functions/check-reminders/helpers.ts',
  );
  expect(file.existsSync(), isTrue,
      reason: 'sunucu kaynağı bulunamadı (yanlış çalışma dizini): '
          '${file.path}');
  return file.readAsStringSync();
}

/// Sunucudaki `isWithinHourWindow` gövdesinden **yalnız karar ağacını** çıkarır.
String _serverDecisionTree() {
  final src = _serverSource();
  final start = src.indexOf('export function isWithinHourWindow');
  expect(start == -1, isFalse,
      reason: 'isWithinHourWindow bulunamadı → sunucu sözleşmesi değişmiş');
  // Gövde: ilk `}` ile kapanır (yardımcı fonksiyon gövdesi sarmalanmaz).
  final body = src.substring(start, src.indexOf('\n}', start) + 2);
  // `safeHour(...)` sarmalayıcılarını soy → **karar** satırları kalsın.
  return body
      .replaceAll(RegExp(r'safeHour\((\w+)\)'), r'$1')
      .split('\n')
      .map((l) => l.trim())
      .where((l) =>
          l.startsWith('if (') || l.startsWith('return h') || l.contains('h >= s'))
      .join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // 1) ⭐ SUNUCU KAYNAĞI: kural gerçekten orada mı?
  // =========================================================================
  group('⭐ sunucu kuralı `isWithinHourWindow` üç daldan ibaret', () {
    test('kaynak dosyada üç dal + sarma **gerçekten** var', () {
      final tree = _serverDecisionTree();
      // Sunucunun karar ağacı (güncel hali, A1r10 `ff25bf7`):
      //   if (s === e) return h === s;         → tek saat
      //   if (s < e) return h >= s && h <= e;   → gündüz
      //   return h >= s || h <= e;              → gece (sarma)
      expect(tree, contains('if (s === e) return h === s;'),
          reason: 'sunucuda "tek saat" dalı kayboldu:\n$tree');
      expect(tree, contains('if (s < e) return h >= s && h <= e;'),
          reason: 'sunucuda "gündüz" dalı değişti:\n$tree');
      expect(tree, contains('return h >= s || h <= e;'),
          reason: '⭐ **sarma (gece aralığı) dalı kayboldu** → 21→09 artık '
              'sunucuda imkânsız:\n$tree');
    });

    test('gece yarısı tuzağı da sunucuda (damga yaşı, saat değil)', () {
      // A4r10'un tuzağı: sarma **tek başına** yetmez. Damga yaşı
      // `zonedMinutesBetween` ile **kullanıcının saat diliminde** ölçülmeli.
      final src = _serverSource();
      expect(src, contains('export function zonedMinutesBetween'),
          reason: 'gece yarısını geçen damga ölçümü kayboldu → gece '
              'aralığında günde ~13 gönderim + 90 art arda çift (ölçüldü)');
    });
  });

  // =========================================================================
  // 2) ⭐ DART ↔ SUNUCU PARİTESİ (24×24 saat çifti)
  // =========================================================================
  group('⭐ istemci kuralı sunucuyla **birebir** aynı', () {
    test('sarma tespiti 24×24 saat çiftinde ayrışmaz', () {
      // Sunucunun kararı: `isWrappingWindow(s, e)` = `safeHour(s) > safeHour(e)`.
      bool serverWraps(int s, int e) => s > e;

      for (var s = 0; s <= 23; s++) {
        for (var e = 0; e <= 23; e++) {
          expect(isNightHourRange(s, e), serverWraps(s, e),
              reason: 'start=$s end=$e → arayüz sunucudan ayrışıyor; '
                  'kullanıcıya yanlış "gece"/"gündüz" etiketi gösterilir');
        }
      }
    });

    test('⭐ **yazılan satır** sunucuda **etkili** gönderim yapar', () {
      // ⭐ En güçlü kanıt: kural iki yerde de doğru olabilir ama **yazılan
      // değer** yanlışsa kullanıcı hiçbir şey almaz. `toRow` çıktısı
      // sunucunun `isWithinHourWindow`'ına beslenir.
      bool serverSends(int h, int s, int e) {
        if (s == e) return h == s;
        if (s < e) return h >= s && h <= e;
        return h >= s || h <= e;
      }

      // A2r12'nin ölçtüğü kombinasyonlar + sınırlar.
      for (final pair in const [(21, 9), (22, 6), (23, 0), (18, 5), (0, 23)]) {
        // (a) Arayüz "gece" diyor mu? → `pair` gerçekten gece mi?
        expect(isNightHourRange(pair.$1, pair.$2), pair.$1 > pair.$2);

        // (b) Yazılan satır sunucunun kuralıyla **etkili** mi?
        final row = NotificationPreference(
          type: ServerNotificationType.water,
          startHour: pair.$1,
          endHour: pair.$2,
        ).toRow('u1');
        final s = row['start_hour'] as int;
        final e = row['end_hour'] as int;
        expect(s, pair.$1, reason: 'start $pair → yazılan $s');
        expect(e, pair.$2, reason: 'end $pair → yazılan $e');
        if (s > e) {
          // ⭐ A1r8/A4r8'in eski normalleştirmesi bir gece aralığını `23`'e
          // çekiyordu → kullanıcı 21→09 seçip 21→23 kaydediyordu.
          // Bu dal **yalnız** gece aralıklarında anlamlıdır: `(0,23)`'te
          // `end == 23` doğru değerdir (tüm gün).
          expect(e, isNot(23),
              reason: 'gece aralığı ($pair) 23\'e çekilmemeli — '
                  'A1r8\'in eski normalleştirmesi geri geldi');
        }

        // (c) Sunucu bu satırı **etkili** buluyor mu? 21/03/00/23 gönderir,
        //     12 göndermez.
        if (s > e) {
          expect(serverSends(s, s, e), isTrue, reason: 'start=$s gönderilir');
          // ⭐ Sarma iki dilime böler: `s..23` ∪ `0..e`. Pencerenin **dışında**
          // bir saat **arayarak** bulunur (formülle değil): geniş pencerelerde
          // (21→09, 13 saat) "karşı saat" (9) hâlâ **pencerede** olduğu için
          // `(s+12)%24` ölçümü yanlış negatif üretiyordu (ilk denemede kırmızı).
          // Bu, A4r3'ün "mantıklı görünen iddiayı test et" dersinin yeni
          // biçimi: **ölçümü veriden türet**, sabit formül yazma.
          final outside = [
            for (var h = 0; h <= 23; h++)
              if (!serverSends(h, s, e)) h,
          ];
          expect(outside, isNotEmpty,
              reason: 's=$s e=$e: sarma "tüm gün" sayılmamalı — 21→09 '
                  'penceresi 21..23 ∪ 0..9\'dur, 10..20 dışarıdadır');
          // Pencere 13 saatten geniş olamaz: `s..23` (24-s) + `0..e` (e+1).
          expect(outside, hasLength(24 - (24 - s) - (e + 1)),
              reason: 's=$s e=$e: pencere uzunluğu (24-s)+(e+1) olmalı');
        }
      }
      // (0,23) gündüz aralığı: 0..23 **tam** gün, sarma yok.
      final allDay = NotificationPreference(
        type: ServerNotificationType.water,
        startHour: 0,
        endHour: 23,
      ).toRow('u1');
      expect(allDay['start_hour'], 0);
      expect(allDay['end_hour'], 23);
      for (var h = 0; h <= 23; h++) {
        expect(serverSends(h, 0, 23), isTrue, reason: '0→23 saat $h');
      }
    });
  });

  // =========================================================================
  // 3) ⭐ ARAYÜZ SUNUCUNUN SUNABİLECEĞİ HER ARALIĞI SUNUYOR MU?
  // =========================================================================
  group('⭐ arayüz sunucunun desteklediği her aralığı **yazılabilir** kılar', () {
    test('bitiş saati **her saat** seçilebilir (0..23, 24 seçenek)', () {
      // ⭐ Regresyon kilidi: A4r10 `start..23` ile sınırlıydı ve 21→09
      // seçilemiyordu; sunucu ise destekliyor. `endHourOptions()` parametresiz
      // çağrıda tam liste vermeli.
      expect(endHourOptions(), hasLength(24));
      expect(endHourOptions().first, 0);
      expect(endHourOptions().last, 23);
      // Parametre geriye dönük uyum için duruyor ama **daraltmıyor**.
      for (var s = 0; s <= 23; s++) {
        expect(endHourOptions(s), endHourOptions(),
            reason: 'start=$s: liste `start`a bağlı OLMAMALI');
      }
      // ⭐ Gece aralığı **her** `start` için seçilebilir olmalı. `start = 0`
      // için `end < 0` **matematiksel olarak imkânsızdır** (0 zaten en küçük
      // saat) → o tek durumda gece aralığı yoktur ve **olmamalıdır**;
      // `start = 23` için `end = 0` vardır.
      for (var s = 1; s <= 23; s++) {
        expect(endHourOptions(s).any((e) => e < s), isTrue,
            reason: 'start=$s → gece aralığı (end < start) seçilemiyor');
      }
      expect(endHourOptions(0).any((e) => e < 0), isFalse,
          reason: 'start=0: `end < 0` imkânsız — 0→23 zaten tüm gündür '
              '(ve sunucuda da `s === e` değil, `s < e` dalı: 0..23 tam gün)');
      // 23→00 gerçekten yazılabilir mi? (sunucu `h >= 23 || h <= 0`)
      const wrap = NotificationPreference(
        type: ServerNotificationType.water,
        startHour: 23,
        endHour: 0,
      );
      final wrapRow = wrap.toRow('u1');
      expect(wrapRow['start_hour'], 23);
      expect(wrapRow['end_hour'], 0);
      expect(isNightHourRange(23, 0), isTrue);
    });

    test('"gece aralığı yazılamaz" notu **kaldırıldı**', () {
      // A4r10'un `settings.notifications.server.rangeNoNight` anahtarı artık
      // **kullanılmıyor** (kısıt kalktı). Anahtar 12 dilde **kalıyor**
      // (orphan = 0 kuralı gereği silinmiyor; A6'nın ratchet'i), ama kodda
      // **hiçbir yerde çağrılmamalı`.
      final dialog = File(
        'lib/features/settings/widgets/server_notification_preferences_section.dart',
      ).readAsStringSync();
      expect(dialog.contains('rangeNoNight'), isFalse,
          reason: '"gece aralığı yazılamaz" notu geri geldi — kullanıcıya '
              'yalnızca var olmayan bir kısıt anlatıyor');
      expect(dialog.contains('rangeNight'), isTrue,
          reason: 'gece aralığı **açıklaması** gösterilmeli');
      expect(dialog.contains('rangeDay'), isTrue,
          reason: 'gündüz aralığı da ne anlama geldiğini söylemeli');
    });
  });
}

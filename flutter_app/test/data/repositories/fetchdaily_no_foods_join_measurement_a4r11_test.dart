/// ⭐ A4r11 (Tur 12) — **TARİHSEL ÖLÇÜM — A2r13 (Tur 13) tarafından tersine
/// çevrildi**.
///
/// ## ⭐ Bu dosya neden "ölü" bir ölçüm olarak duruyor?
///
/// Bu dosya v1.2.0'dan beri var olan P1'i **kanıtlamak** için yazılmıştı:
/// `fetchDaily` `foods` JOIN'i yapmıyor → `displayName` = `custom_name` →
/// `food_id` dolu olsa bile dashboard "Bilinmeyen" gösteriyordu.
///
/// ⭐ A2r13 bu P1'i **kapattı** (`fetchDaily` artık `foods(name)` embed'i
/// istiyor + `MealEntry.foodName`), dolayısıyla bu test **kasıtlı olarak
/// kırmızıdır**. Silinmedi, çünkü:
///
/// 1. **Kanıt zinciri** bu dosyada başlıyor. Kim/ne zaman/nasıl ölçtü sorusu
///    "yeşil test" kaydından silinerek kaybolur; bir sonraki ajan aynı P1'i
///    yeniden keşfedip aynı işi yapmasın diye burada bırakıldı.
/// 2. Düz `select()`'e dönmek isteyen biri bu testi çalıştırdığında
///    **kırmızı** görür ve nedenini buradan okur.
///
/// ## ⭐ Kanıt: düzeltme bu testi kırmızıya döndürdü
///
/// ```text
/// $ flutter test test/data/repositories/fetchdaily_no_foods_join_measurement_a4r11_test.dart
///   Expected: '*'
///     Actual: 'id,user_id,…,deleted_at,foods(name)'
/// ```
///
/// Yani "yeşil test ≠ etkin test" bu sefer **ters yönde** kanıtlandı: bu test
/// ölçtüğü şeyi **gerçekten** ölçüyor (A4r11'in tuzağına düşmemiş).
///
/// Yeni (yeşil) sözleşme testi:
/// `test/data/repositories/fetchdaily_food_name_a2r13_test.dart`
///
/// ## Değişecek tek yer
///
/// A2r13'ün düzeltmesi **geri alınırsa** (gerekçeli bir kararla) buradaki
/// beklentiler `select` = `*` ve `foods(` embed'i **yok** olacak şekilde
/// eski hâline döndürülmelidir. Bu dosya o noktada **kullanılabilir hâle**
/// gelir; o ana kadar kırmızıdır ve `flutter test` paketini kırmaz mı
/// **kırar** — bilinçli: bu bir **ölçüm** dosyasıdır, sözleşme değil.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/data/repositories/diary_repository.dart';

/// PostgREST'e verilen **ham** istek gövdesi/sorgusu — `fetchDaily`'nin
/// `meal_entries` okumasında hangi kolonların istendiğini gösterir.
List<String> mealEntriesUrls = [];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ⭐ A2r13: bu ölçüm **bilinçli olarak kırmızıdır** (P1 kapatıldı).
  // Paketi düşürmemek için `skip` ile işaretli; açıklaması yukarıda.
  test(
    '⭐ fetchDaily meal_entries sorgusu `foods` join İSTEMİYOR '
    '(TARİHSEL ÖLÇÜM — A2r13 bu P1\'i kapattı, beklenti tersine döndü)',
    () async {
      final client = SupabaseClient(
        'https://probe.supabase.co',
        'anon-key',
        httpClient: _RecordingClient(),
      );
      final repo = DiaryRepository(client);

      try {
        await repo.fetchDaily('u1', DateTime(2026, 9, 28));
      } catch (_) {
        // Ağ yok: sorgu yine de **oluşturuldu**, `mealEntriesUrls` doludur.
        // (Bu test sorgu **şeklini** ölçer, yanıtı değil.)
      }

      expect(mealEntriesUrls, isNotEmpty,
          reason: 'ölçüm yapılamadı → test anlamsız');

      final mealUrl = mealEntriesUrls.firstWhere(
        (u) => u.contains('/rest/v1/meal_entries'),
        orElse: () => throw StateError('meal_entries sorgusu hiç atılmadı'),
      );

      // `foods(id,name,...)` embed'i **olmamalı** — join yoksa `MealEntry`
      // yalnız `meal_entries` kolonlarını görür ve `displayName` için
      // `custom_name`'e mahkûmdur.
      expect(
        RegExp(r'foods\(').hasMatch(mealUrl),
        isFalse,
        reason: 'SORGU foods join İÇERİYOR — bu dosyanın varsayımı yanlış, '
            'dashboard adı foods.name\'den okuyor olabilir (yeniden değerlendir)',
      );

      // `select` parametresi `*` (düz select, PostgREST'te `select=%2A`).
      final selectParam = Uri.parse(mealUrl).queryParameters['select'];
      expect(selectParam, '*',
          reason: 'düz `select()` → join yok → `displayName` = `custom_name`\n'
              'ölçülen: $mealUrl');
      expect(selectParam, isNot(contains('foods')),
          reason: 'embed yok (ölçülen: $selectParam)');
    },
    // ⭐ A2r13: beklenti artık **geçersiz**. Test yeşil sözleşmeyi değil
    // tarihsel ölçümü korur; paketi kırmadan açıklamayı da taşır.
    skip: 'A2r13 (Tur 13) fetchDaily\'e `foods(name)` embed\'i ekledi → bu '
        'ölçümün "join yok" beklentisi artık doğru değil. Yeni sözleşme '
        'testi: fetchdaily_food_name_a2r13_test.dart',
  );
}

/// Her isteği kaydeder, gövdeye boş tablo döner (ağ bağımsız).
class _RecordingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    mealEntriesUrls.add(request.url.toString());
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('[]')),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

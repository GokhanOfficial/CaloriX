/// ⭐ A4r11 — **ÖLÇÜM**: Gerçek `fetchDaily` sorgusu `foods` join'i yapıyor mu?
///
/// Bu dosya bir davranış **ölçümüdür**, düzeltme testi değil. Amacı,
/// `add_from_food_dialog`'ın `custom_name` P0'sunun **kapsamını** kesin
/// olarak belgelemek.
///
/// ## Ölçülen bulgu (brifteki varsayımdan DAHA AĞIR)
///
/// Görev brifi şunu diyordu:
/// > "Gıda silinince `custom_name` de NULL → dashboard'da 'Bilinmeyen'".
///
/// Gerçek tablo şu: **`custom_name` silinmeden önce de NULL'dır** ve
/// dashboard **zaten** o öğünü "Bilinmeyen" gösterir. Nedeni:
///
/// - `DiaryRepository.fetchDaily` (`diary_repository.dart:140-184`) sorgusu
///   düz `.select()` — `foods(...)` embed'i **yok** (ölçüm aşağıda).
/// - `MealEntry.displayName` (`meal_entry.dart:89`) yalnızca `customName`
///   okur: `customName ?? 'Bilinmeyen'`.
/// - Oysa `add_from_food_dialog` **silinemeyen** topluluk gıdalarında
///   `custom_name` **NULL** yazıyordu (eski kod) → `food_id` dolu olsa bile
///   `displayName` "Bilinmeyen" oluyordu.
///
/// ⭐ Yani "silinince" kaybolan bir ad **yok**: ad yazılmamıştı zaten.
/// Bu, `canDelete` koşulunu `custom_name`ye bağlamanın **doğru** olmasının
/// ek gerekçesidir: seçicilik, yalnız silinebilir gıdaları korurken
/// topluluk gıdalarını yine de "Bilinmeyen" bırakır; bu satır
/// **ayrı** bir bulgudur (bkz. raporun "Bulunurlar").
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

  test('⭐ fetchDaily meal_entries sorgusu `foods` join İSTEMİYOR', () async {
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
  });
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

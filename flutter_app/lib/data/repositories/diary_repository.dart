import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/observability/app_logger.dart';
import '../../core/utils/num_parsing.dart';
import '../models/meal_entry.dart';
import '../models/water_entry.dart';
import '../models/weight_entry.dart';
import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';

/// Tarihi web `format(date, 'yyyy-MM-dd')` ile aynı biçimde yazar.
///
/// Uygulama artık `core/utils/num_parsing.dart` → `formatDateOnly` içinde
/// (aynı mantık `ChatRepository.localDateOnly` içinde de vardı).
String formatEntryDate(DateTime date) => formatDateOnly(date);

/// Günün yemek toplamları — web `useDailyData.totals` karşılığı.
typedef DailyTotals = ({
  double calories,
  double protein,
  double carbs,
  double fat,
});

/// Seçili günün tüm günlük verisi (web `useDailyData` dönüş değeri).
class DailyData {
  const DailyData({
    required this.mealEntries,
    required this.waterEntries,
    this.latestWeight,
  });

  final List<MealEntry> mealEntries;
  final List<WaterEntry> waterEntries;

  /// Tarihten bağımsız en son kilo kaydı (web parity — gün filtresi YOK).
  final WeightEntry? latestWeight;

  /// Öğün tipine göre gruplandırma (web `mealsByType`).
  Map<MealType, List<MealEntry>> get mealsByType {
    final map = <MealType, List<MealEntry>>{};
    for (final entry in mealEntries) {
      final type = MealType.values.asNameMap()[entry.mealType];
      if (type == null) continue;
      map.putIfAbsent(type, () => []).add(entry);
    }
    return map;
  }

  /// Gün toplamları — web `totals` reduce'i ile aynı.
  DailyTotals get totals {
    var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0;
    for (final e in mealEntries) {
      calories += e.calculatedKcal;
      protein += e.calculatedProtein;
      carbs += e.calculatedCarbs;
      fat += e.calculatedFat;
    }
    return (calories: calories, protein: protein, carbs: carbs, fat: fat);
  }

  /// Toplam su (ml) — web `totalWater`.
  double get totalWater =>
      waterEntries.fold(0.0, (sum, e) => sum + e.amountMl);

  static const empty = DailyData(mealEntries: [], waterEntries: []);
}

/// Günlük (diary) CRUD — web `useDailyData.ts` karşılığı.
///
/// Tüm sorgular `entry_date = yyyy-MM-dd` + `deleted_at IS NULL`
/// filtreleriyle; silme soft-delete (`deleted_at = now()`).
class DiaryRepository {  DiaryRepository(this._client);

  final SupabaseClient _client;

  /// `timestamptz` kolonlarına yazılan damga daima **UTC** olmalı.
  ///
  /// `DateTime.now()` yerel saati (UTC kaydı) döndürür; `+03:00` ofseti olan
  /// bir istemcide bu, sunucu tarafında ~3 saat ileri bir zaman damgası
  /// olarak yorumlanır. Web `new Date().toISOString()` UTC ürettiği için
  /// burada da `.toUtc()` zorunlu.
  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// NaN / Infinity / negatif değerleri yazmadan reddeder.
  static void _requireFiniteNonNegative(String name, double v) {
    if (v.isNaN || v.isInfinite || v < 0) {
      throw ArgumentError.value(v, name, 'NaN, Infinity veya negatif olamaz');
    }
  }

  /// Miktar alanları için ayrıca `> 0` zorunlu (0'a bölme riski).
  static void _requireFinitePositive(String name, double v) {
    if (v.isNaN || v.isInfinite || v <= 0) {
      throw ArgumentError.value(v, name, 'NaN, Infinity veya sıfırdan küçük olamaz');
    }
  }

  /// `amount_g_ml` / `amount_ml` için **görünür** miktar doğrulaması.
  ///
  /// ## Neden ayrı bir yardımcı
  ///
  /// Miktar alanı iki ayrı katmanda, **farklı ölçütlerle** doğrulanıyordu:
  ///
  ///  * Veri katmanı: `NaN`/`≤0` → `ArgumentError` (DB'ye hiç yazılmaz),
  ///  * Arayüz (tanıma onayı): `r.amount <= 0` → **"Miktar gerekli"**
  ///    (`dialogs.amountRequired`). Kullanıcı 250 yazıp ondalık noktasını
  ///    unutmuşsa "girilmedi" mesajı alıyor, yani ekranda ne yaptığını
  ///    anlamıyor. Doğru mesaj `dialogs.invalidAmount` ("Geçerli bir miktar
  ///    girin") — 12 dilde **zaten var**, kod değişikliği 0 çeviri işidir.
  ///
  /// Bu metot tek doğruluk kaynağı olsun diye eklendi: arayüz
  /// `DiaryRepository.isUsableAmount` ile hem uyarı metnini hem de
  /// "kaydet" düğmesinin durumunu aynı anda yönetir, iki dal ayrışamaz.
  ///
  /// ## Neden üst sınır yok
  ///
  /// DB CHECK'i 10000 g/ml (`20260927120000_security_hardening_round1.sql:389`).
  /// Bu metot **kullanılabilirlik** içindir (`0 < miktar`), DB sözleşmesi
  /// zaten [_requireFinitePositive] + CHECK ile korunur.
  static bool isUsableAmount(double? amount) {
    if (amount == null) return false;
    if (amount.isNaN || amount.isInfinite) return false;
    return amount > 0;
  }

  /// Seçili günün tüm verisi: öğünler (created_at asc), su (entry_time asc)
  /// ve en son kilo kaydı (tarih filtresiz, entry_date desc limit 1).
  ///
  /// **Savunma-derinliği:** sorgular `deleted_at IS NULL` süzgecini sunucuya
  /// gönderir, ancak dönen satırlar istemcide de elenir
  /// ([_withoutDeleted]). RLS/süzgeç bir gün gevşerse ya da bir edge function
  /// filtresiz veri döndürürse, silinmiş bir öğün **gün toplamına girip**
  /// kullanıcıyı yanlış beslenme kararına yönlendiremezdi. Yumuşak silme
  /// üç tabloda da geçerli (`deleted_at` kolonu `supabase/migrations/…sql`
  /// 141/159/171) ve `DiaryRepository` **fiziksel silme yapmaz**; bu yüzden
  /// bu süzgeç kayıtların sessizce geri dönmesini de engeller.
  Future<DailyData> fetchDaily(String userId, DateTime date) async {
    final dateStr = formatEntryDate(date);

    final mealsFuture = _client
        .from('meal_entries')
        .select()
        .eq('user_id', userId)
        .eq('entry_date', dateStr)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true);

    final waterFuture = _client
        .from('water_entries')
        .select()
        .eq('user_id', userId)
        .eq('entry_date', dateStr)
        .isFilter('deleted_at', null)
        .order('entry_time', ascending: true);

    final weightFuture = _client
        .from('weight_entries')
        .select()
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('entry_date', ascending: false)
        .limit(1)
        .maybeSingle();

    final results =
        await Future.wait<dynamic>([mealsFuture, waterFuture, weightFuture]);

    // `select()` her zaman liste döndürdüğü için alttaki zorlama pratikte
    // güvenli; yine de tek bozuk/sürpriz yanıt tüm günlük ekranını
    // `TypeError` ile düşürmesin diye `List<dynamic>.from(...)` ile
    // savunuluyor (Tur 1 P3 kalıntısı).
    return DailyData(
      mealEntries:
          _withoutDeleted(_mapRows(results[0], MealEntry.fromJson)),
      waterEntries:
          _withoutDeleted(_mapRows(results[1], WaterEntry.fromJson)),
      latestWeight: results[2] == null
          ? null
          : _parseOrNull(WeightEntry.fromJson, results[2]),
    );
  }

  /// Yumuşak silinmiş (`deleted_at` dolu) kayıtları listeden çıkarır.
  ///
  /// Sorgu zaten `deleted_at IS NULL` süzgeci gönderiyor; bu ikinci katman
  /// yalnızca sunucunun süzgeci uygulamadığı (RLS gevşemesi, hatalı edge
  /// function sorgusu, sürpriz `null` değeri) durumlarda devreye girer.
  /// Yanlış toplam, yumuşak silmeden daha kötü bir sonuçtur: kullanıcı
  /// "ne yediğini" unutmuş bir kaydı hâlâ yerinde görür.
  static List<T> _withoutDeleted<T>(List<T> rows) => rows
      .where((e) => switch (e) {
            MealEntry() => e.deletedAt == null,
            WaterEntry() => e.deletedAt == null,
            _ => true,
          })
      .toList();

  /// Ham tek satırı modele çevirir; okunamazsa null döner (istisna yutmaz —
  /// `AppLog`'a gider, çağıran "veri yok" gösterir).
  static T? _parseOrNull<T>(
    T Function(Map<String, dynamic>) parse,
    Object? raw,
  ) {
    if (raw == null) return null;
    try {
      return parse(Map<String, dynamic>.from(raw as Map));
    } catch (e, s) {
      AppLog.w('Günlük satırı okunamadı, yok sayıldı', e, s);
      return null;
    }
  }

  /// Ham PostgREST satırlarını modele çevirir (satır başına try/catch).
  ///
  /// `json_serializable` `as` zorlamaları bozuk bir satırda istisna fırlatır;
  /// tek bir satırın tüm günü düşürmesi yerine atlanır ve `AppLog` ile
  /// raporlanır. Yine de **kısmi veri** arayüze gider — bu yüzden atlanan
  /// satırın yokluğu gün toplamlarını eksik tutar, fazla tutmaz.
  static List<T> _mapRows<T>(
    Object? raw,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (raw is! List) return <T>[];
    final out = <T>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final parsed = _parseOrNull(parse, row);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  /// Yemek girdisi ekle (web `addMealEntry` — payload alanları aynı).
  Future<MealEntry> addMealEntry(
    String userId, {
    required String mealType,
    required double amountGMl,
    required double calculatedKcal,
    required double calculatedProtein,
    required double calculatedCarbs,
    required double calculatedFat,
    required String entryDate,
    String source = 'manual',
    String? foodId,
    String? customName,
    String? note,
    String? photoUrl,
  }) async {
    // Yazma sınırı doğrulaması: `NaN`/`Infinity` Postgres'e JSON olarak
    // gider ve `numeric` kolonlarında hata/istisna üretir; negatif ya da
    // sıfır miktar ise 100g normalizasyonunu (`x/amount*100`) bozar ve
    // tüm gün toplamlarını yanlışlaştırır.
    _requireFinitePositive('amountGMl', amountGMl);
    _requireFiniteNonNegative('calculatedKcal', calculatedKcal);
    _requireFiniteNonNegative('calculatedProtein', calculatedProtein);
    _requireFiniteNonNegative('calculatedCarbs', calculatedCarbs);
    _requireFiniteNonNegative('calculatedFat', calculatedFat);

    final data = await _client
        .from('meal_entries')
        .insert({
          'user_id': userId,
          'food_id': foodId,
          'custom_name': customName,
          'meal_type': mealType,
          'amount_g_ml': amountGMl,
          'calculated_kcal': calculatedKcal,
          'calculated_protein': calculatedProtein,
          'calculated_carbs': calculatedCarbs,
          'calculated_fat': calculatedFat,
          'entry_date': entryDate,
          'note': note,
          'photo_url': photoUrl,
          'source': source,
        })
        .select()
        .single();
    return MealEntry.fromJson(data);
  }

  /// Yemek girdisi güncelle (web `updateMealEntry` — updated_at damgalı).
  ///
  /// [userId] hem `eq('id', ...)` hem de `eq('user_id', ...)` filtresine
  /// eklenir: RLS zaten `auth.uid() = user_id` ile koruyor, ama istemci
  /// tarafında ikinci filtre **kırık/eksik yetki** durumunda (örn. RLS
  /// politikası yanlışlıkla gevşetilirse) başkasının kaydının sessizce
  /// ezilmesini imkânsız kılar.
  ///
  /// ## Eşzamanlı düzenleme (kayıp güncelleme)
  ///
  /// [expectedUpdatedAt] verilirse **iyimser kilit** uygulanır: güncelleme
  /// yalnızca satırın `updated_at`'ı hâlâ verilen değere eşitse yazılır.
  ///
  /// Sorun: kullanıcı iki ekranda (telefon + tablet) aynı öğünü açtığında
  /// ikinci kaydetme, ilkinin değişikliklerini **sessizce** eziyordu. Kayıt
  /// "güncellendi" onayı veriyordu ama kullanıcı ilk düzenlemenin miktarını
  /// kaybetmişti ve hiçbir iz kalmıyordu. `updated_at` bu senaryoda yeterli
  /// bir sürüm damgasıdır: `update_updated_at_column` trigger'ı
  /// (`full_setup.sql:547`) her yazmada `now()` yazar, Postgres `now()` işlem
  /// başına sabit olduğu için iki yazma saniyelerce sonra bile farklı damga
  /// alır.
  ///
  /// Çağıran davranışı (A4 alanı): `entry.updatedAt` değerini geçirir;
  /// çakışma [MealEntryConflictError] ile bildirilir. Damga verilmeyen
  /// çağıranlar **son yazan kazanır** semantiğinde çalışır (geriye dönük
  /// uyum).
  Future<MealEntry> updateMealEntry(
    String userId,
    String id,
    Map<String, dynamic> updates, {
    String? expectedUpdatedAt,
  }) async {
    // Kısmi güncelleme: `updates` yalnızca verilen alanları içerir, diğer
    // alanlar (source/food_id/photo_url/entry_date) korunur. Yazılan sayısal
    // alanlar yine de doğrulanır — UI `_parse` boş metni 0'a çevirdiği
    // için 0 miktar buradan geçebilirdi.
    final amount = updates['amount_g_ml'];
    if (amount is double) _requireFinitePositive('amount_g_ml', amount);
    for (final key in const [
      'calculated_kcal',
      'calculated_protein',
      'calculated_carbs',
      'calculated_fat',
    ]) {
      final v = updates[key];
      if (v is double) _requireFiniteNonNegative(key, v);
    }

    final query = _client
        .from('meal_entries')
        .update({...updates, 'updated_at': _nowIso()})
        .eq('id', id)
        .eq('user_id', userId);
    final rows = await (expectedUpdatedAt == null
            ? query
            : query.eq('updated_at', expectedUpdatedAt))
        .select();

    if (rows.isNotEmpty) return MealEntry.fromJson(rows.first);

    // 0 satır: ya kayıt yok/silinmiş, ya da başka cihaz güncellemiş.
    // Kullanıcıya **doğru** mesaj için ayırt etmek şart — "bulunamadı" ile
    // "çakıştı" farklıdır.
    if (expectedUpdatedAt == null) {
      // Damga verilmediyse 0 satır = kayıt yok. Eski davranış (`.single()`
      // `PostgrestException` yerine anlaşılır `StateError`) korunur.
      throw StateError(
        'Güncellenecek öğün bulunamadı (id=$id) — başka cihazdan silinmiş olabilir',
      );
    }
    final current = await _client
        .from('meal_entries')
        .select('updated_at, deleted_at')
        .eq('id', id)
        .eq('user_id', userId)
        .maybeSingle();
    if (current == null) {
      throw StateError(
        'Güncellenecek öğün bulunamadı (id=$id) — başka cihazdan silinmiş olabilir',
      );
    }
    if (current['deleted_at'] != null) {
      throw StateError('Bu öğün başka bir cihazdan silinmiş (id=$id)');
    }
    throw MealEntryConflictError(
      entryId: id,
      expectedUpdatedAt: expectedUpdatedAt,
      actualUpdatedAt: current['updated_at'] as String?,
    );
  }

  /// Yemek girdisi sil — soft delete (web parity).
  ///
  /// [userId] kapsam filtresi — bkz. [updateMealEntry].
  Future<void> deleteMealEntry(String userId, String id) async {
    await _client
        .from('meal_entries')
        .update({'deleted_at': _nowIso()})
        .eq('id', id)
        .eq('user_id', userId);
  }

  /// Yemek girdisini geri al — `deleted_at = null` (soft-delete undo).
  /// Dashboard kaydır-sil sonrası "Geri Al" SnackBar aksiyonu.
  ///
  /// `.select().maybeSingle()` ile **etkilenen satır sayısı doğrulanır**:
  /// kayıt başka bir cihazda (ya da fiziksel olarak) silinmişse önceki
  /// sürüm sessizce hiçbir şey yapmadan "başarılı" dönüyordu — kullanıcı
  /// "Geri Al" düğmesine bastı, kayıt listede görünmedi, veri geri gelmedi.
  /// Artık [StateError] fırlatılır; çağıran (`meal_section.dart`) hatayı
  /// yakalayıp "silinemedi" mesajı gösteriyor.
  ///
  /// [userId] kapsam filtresi — bkz. [updateMealEntry].
  Future<void> restoreMealEntry(String userId, String id) async {
    final row = await _client
        .from('meal_entries')
        .update({'deleted_at': null, 'updated_at': _nowIso()})
        .eq('id', id)
        .eq('user_id', userId)
        .select('id, deleted_at')
        .maybeSingle();
    if (row == null) {
      throw StateError(
        'Geri alınacak kayıt bulunamadı (id=$id) — başka cihazdan silinmiş olabilir',
      );
    }
    if (row['deleted_at'] != null) {
      throw StateError(
        'Geri alma yazıldı ama kayıt hâlâ silinmiş görünüyor (id=$id)',
      );
    }
  }

  /// Su ekle (web `addWaterEntry` — entry_time DB default'una bırakılır).
  ///
  /// `water_entries.amount_ml` DB sütunu `integer`. Dart tarafı ml'yi
  /// `double` tutar (UI ilerleme çubuğu bölmesi için) ama PostgREST'e
  /// `250.0` gönderilirse Postgres integer ayrıştırıcısı ondalık noktayı
  /// reddeder → `22P02 invalid input syntax for type integer: "250.0"` →
  /// POST 400. Bu yüzden insert'te `int`'e dönüştürülür (su ml her zaman
  /// tam sayıdır; okuma yolu json_serializable'ın int→double zorlamasıyla
  /// zararsız çalışır).
  Future<WaterEntry> addWaterEntry(
    String userId, {
    required double amountMl,
    required String entryDate,
  }) async {
    if (amountMl.isNaN || amountMl.isInfinite || amountMl <= 0) {
      throw ArgumentError.value(
        amountMl,
        'amountMl',
        'Su miktarı NaN, Infinity veya sıfırdan küçük olamaz',
      );
    }
    final data = await _client
        .from('water_entries')
        .insert({
          'user_id': userId,
          'amount_ml': amountMl.round(),
          'entry_date': entryDate,
        })
        .select()
        .single();
    return WaterEntry.fromJson(data);
  }

  /// Su kaydı sil — soft delete (web'de yok ama tutarlılık için aynı desen).
  ///
  /// Etkilenen satır doğrulanmaz (`.select()` yok): bu metodun canlı bir
  /// geri-al yolu **yok** (dashboard'da su kaydı silme UI'ı bulunmuyor),
  /// dolayısıyla sessiz başarısızlık kullanıcıya yanlış bir onay göstermez.
  /// Yazıldığı zaman `deleted_at` UTC damgası alır.
  ///
  /// [userId] kapsam filtresi — bkz. [updateMealEntry].
  Future<void> deleteWaterEntry(String userId, String id) async {
    await _client
        .from('water_entries')
        .update({'deleted_at': _nowIso()})
        .eq('id', id)
        .eq('user_id', userId);
  }

  /// Kilo kaydı ekle (web `addWeightEntry`).
  Future<WeightEntry> addWeightEntry(
    String userId, {
    required double weightKg,
    required String entryDate,
    String? note,
  }) async {
    if (weightKg.isNaN || weightKg.isInfinite || weightKg <= 0) {
      // `weight_entries.weight_kg` NOT NULL + domain anlamı: 0/negatif
      // kayıt BMI ve tüm makro hedeflerini bozacağı için DB'ye hiç
      // gönderilmez. Çağıran (weight_card) zaten `weight <= 0` filtresi
      // uyguluyor; buradaki kontrol o filtrenin atlandığı her yol için
      // son savunmadır ve hatayı yüzeye taşır.
      throw ArgumentError.value(
        weightKg,
        'weightKg',
        'Kilo 0, negatif, NaN veya Infinity olamaz',
      );
    }

    final data = await _client
        .from('weight_entries')
        .insert({
          'user_id': userId,
          'weight_kg': weightKg,
          'entry_date': entryDate,
          'note': note,
        })
        .select()
        .single();
    return WeightEntry.fromJson(data);
  }
}

final diaryRepositoryProvider = Provider<DiaryRepository>((ref) {
  return DiaryRepository(ref.watch(supabaseClientProvider));
});

/// Dashboard'da seçili gün — sadece tarih kısmı anlamlı.
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Seçili günün tüm verisi (web `useDailyData(date)` karşılığı).
/// Ekleme/silme sonrası `ref.invalidate(dailyDataProvider)` ile tazelenir.
final dailyDataProvider = FutureProvider<DailyData>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return DailyData.empty;
  final date = ref.watch(selectedDateProvider);
  return ref.watch(diaryRepositoryProvider).fetchDaily(user.id, date);
});

/// Aynı öğün **eşzamanlı** iki ekranda düzenlendiğinde fırlatılır.
///
/// ## Anlamı
///
/// Kullanıcı telefonunda öğünü açtı, tablette de aynı öğünü düzenlemeye başladı.
/// Tablet'te "Kaydet" dediğinde `updated_at` filtresi artık eşleşmiyor, bu
/// yüzden yazma **yapılmaz** — aksi halde telefonun değişiklikleri sessizce
/// ezilirdi (kayıp güncelleme). Kullanıcıya "kayıt başka yerde değişti,
/// tekrar dene" demelidir.
///
/// ## Neden ayrı sınıf, neden `StateError` değil
///
/// * `StateError`'ın anlamı "program hatası / kayıt yok"; burada ise
///   **kullanıcının yapması gereken bir şey** var (tekrar denemek).
/// * Çağıran (`edit_meal_entry_dialog.dart`, **A4 alanı**) bu türü yakalayıp
///   farklı bir mesaj gösterecek; `catch (_)` bunu yutamaz.
class MealEntryConflictError implements Exception {
  const MealEntryConflictError({
    required this.entryId,
    required this.expectedUpdatedAt,
    this.actualUpdatedAt,
  });

  final String entryId;

  /// Arayüzün gönderdiği (ekranda gördüğü) damga.
  final String expectedUpdatedAt;

  /// DB'deki güncel damga — teşhis ve "yeniden yükle" akışı için.
  final String? actualUpdatedAt;

  /// Kullanıcıya gösterilebilecek tek satır. **Sunucu ayrıntısı taşımaz.**
  String get summary => 'Bu öğün başka bir cihazda değiştirilmiş.';

  @override
  String toString() => 'MealEntryConflictError(entryId: $entryId, '
      'expected: $expectedUpdatedAt, actual: $actualUpdatedAt)';
}

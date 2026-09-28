import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';

/// `profiles` tablosu CRUD — web `ProfileContext` karşılığı.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'profiles';

  // ------------------------------------------------------------------
  // Alan sınırları — DB CHECK kısıtlarının istemci karşılığı (A2r9)
  // ------------------------------------------------------------------
  //
  // ## Neden burada bir savunma gerekiyor?
  //
  // A1r8 (Tur 8) `profiles` tablosuna beş aralık CHECK'i ekledi
  // (`supabase/migrations/20260928400000_data_integrity_check_constraints.sql`):
  //
  //  | kolon                       | kısıt                          |
  //  |-----------------------------|--------------------------------|
  //  | `height_cm`                 | 100 – 250                      |
  //  | `current_weight_kg`         | 20 – 500                       |
  //  | `target_weight_kg`          | 20 – 500                       |
  //  | `daily_water_target_ml`     | 0 – 10000                      |
  //  | `weigh_in_frequency_days`   | 1 – 365                        |
  //
  // CHECK kısıtı **yazma anında** çalışır ve hata `23514` (check_violation)
  // olarak döner. Bu kötü bir durum **değildir** — ama kötü bir kullanıcı
  // deneyimidir:
  //
  //  * Arayüzün beş farklı yolu var (`onboarding_page.dart`,
  //    `personal_info_dialog.dart`, `goals_dialog.dart`, `weight_card.dart`,
  //    `notifications_dialog.dart`) ve **hepsi `catch (_)` ile yutuyor**
  //    → kullanıcı "Kaydedildi" yeşil mesajı görür ama **hiçbir şey
  //    yazılmamıştır**. "Ayarımı kaydettim ama hedefim değişmedi" — sessiz
  //    veri kaybı sınıfı.
  //  * `notifications_dialog.dart:146` `int.tryParse(...) ?? 7` kullanıyor:
  //    metin kutusuna `-5` yazılabiliyor → `check-reminders`'ın **her
  //    koşuda** tetiklenmesi (`frequencyDays` negatif olduğu için
  //    `daysSinceReminder >= frequencyDays` her zaman doğru).
  //
  // **Kural: DB CHECK'in reddedeceği bir değeri istemcide hiç göndermemek.**
  // Böylece (a) hatayı kullanıcının girdiği yerde yakalarız,
  // (b) "kaydedildi" yalanı söylemeyiz, (c) CHECK'in 5 ayrı yerde
  // yorumlanması yerine **tek bir sözleşme** oluşur.
  //
  // ## Aralık dışı değerde ne olur?
  //
  // Değer **sessizce düzeltilmez** (kullanıcının "7" yazdığı yere "30"
  // yazılmaz). Bunun yerine [ProfileFieldRangeError] fırlatılır; çağıran
  // zaten `catch (_)` ile genel bir hata mesajı gösteriyor, yani arayüz
  // değişmeden **doğru** davranış (kaydedilmedi + hata bildirimi) elde
  // edilir. Buna karşılık DB'ye yazılan **kapsayıcı** alanlar
  // (`updated_at` vb.) korunur.
  //
  // ## Neden `clamp` değil?
  //
  // `clamp` sessiz veri bozulmasıdır: kullanıcı 400 cm boy yazdı, kayıt 250
  // olarak kaydedildi ve kullanıcı **250 cm boylu** bir profil görüyor.
  // Kısıtı öğrenmek, aralığın ne olduğunu öğrenmekten iyidir; bu yüzden
  // hata mesajı aralığı da içerir.

  /// Bir alanın kabul ettiği aralık.
  static const Map<String, ({num? min, num? max})> fieldRanges =
      <String, ({num? min, num? max})>{
    // `NUMERIC(5,1)` teknik üst sınırı 9999.9 — fiziksel değil.
    'height_cm': (min: 100, max: 250),
    'current_weight_kg': (min: 20, max: 500),
    'target_weight_kg': (min: 20, max: 500),
    'daily_water_target_ml': (min: 0, max: 10000),
    'weigh_in_frequency_days': (min: 1, max: 365),
  };

  /// Alan adı → okunabilir aralık metni (hata mesajı için).
  static const Map<String, String> fieldRangeLabels = <String, String>{
    'height_cm': '100-250 cm',
    'current_weight_kg': '20-500 kg',
    'target_weight_kg': '20-500 kg',
    'daily_water_target_ml': '0-10000 ml',
    'weigh_in_frequency_days': '1-365 gün',
  };

  /// [fieldRanges]'da sınırlı alan mı?
  static bool hasRange(String field) => fieldRanges.containsKey(field);

  /// [value]'nin [field] için DB kabul aralığında olup olmadığını doğrular.
  ///
  /// **Saf fonksiyon** (ağ yok) — testte doğrulanabilir. `null` her zaman
  /// geçerlidir: CHECK'ler `IS NULL OR …` biçimindedir, yani kolon
  /// nullable'dır ve "bilinmiyor" ayarlanmış profil normaldir.
  ///
  /// Sonlu olmayan sayı (`NaN`/`Infinity`) **her zaman** reddedilir: JSON'a
  /// `NaN` yazmak PostgREST'te 400, `Infinity` ise Postgres `numeric`
  /// ayrıştırıcısında hata üretir.
  static void validateField(String field, Object? value) {
    final range = fieldRanges[field];
    if (range == null) return; // sınırsız alan → dokunulmaz
    if (value == null) return; // NULL serbest (CHECK `IS NULL OR …`)
    if (value is! num) {
      throw ProfileFieldRangeError(
        field: field,
        value: value,
        range: fieldRangeLabels[field],
        reason: 'sayı değil (${value.runtimeType})',
      );
    }
    final d = value.toDouble();
    if (!d.isFinite) {
      throw ProfileFieldRangeError(
        field: field,
        value: value,
        range: fieldRangeLabels[field],
        reason: 'sayı sonlu değil',
      );
    }
    final min = range.min;
    final max = range.max;
    if ((min != null && d < min) || (max != null && d > max)) {
      throw ProfileFieldRangeError(
        field: field,
        value: value,
        range: fieldRangeLabels[field],
        reason: 'aralık dışı',
      );
    }
  }

  /// Güncelleme gövdesindeki tüm sınırlı alanları doğrular.
  ///
  /// A2r9: `exportData` `select()` ile **tüm** kolonları çektiği için
  /// `profile` satırı bir yedeğin `profile` bölümüne girer. Web istemcisi
  /// `0` gövdeyle import ederse aynı CHECK ihlali orada da oluşurdu.
  static void validateUpdates(Map<String, dynamic> updates) {
    for (final field in fieldRanges.keys) {
      if (updates.containsKey(field)) {
        validateField(field, updates[field]);
      }
    }
  }

  /// Kullanıcının profilini getirir (yoksa null).
  Future<Profile?> fetch(String userId) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return Profile.fromJson(data);
  }

  /// Profil alanlarını günceller (updated_at otomatik tazelenir).
  ///
  /// ## Aralık doğrulaması (A2r9)
  ///
  /// [validateUpdates] **istemci tarafında** DB CHECK'lerinin kabul ettiği
  /// aralıkları uygular. Doğrulama **hiçbir istek atılmadan önce** çalışır:
  /// reddedilen bir alan için sunucuya giden `PATCH` yoktur, dolayısıyla
  /// yarım yazma da olmaz. Alan adları ve sınırlar
  /// [fieldRanges] içinde tanımlıdır (bkz. migration `:205-228`).
  Future<Profile?> update(String userId, Map<String, dynamic> updates) async {
    validateUpdates(updates);
    final payload = {
      ...updates,
      // `timestamptz` kolonu → UTC damga (yerel saat kaymasını önler).
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final data = await _client
        .from(_table)
        .update(payload)
        .eq('id', userId)
        .select()
        .maybeSingle();
    if (data == null) return null;
    return Profile.fromJson(data);
  }
}

/// `profiles` alanı DB CHECK aralığının dışında — [ProfileRepository.update]
/// tarafından, **hiçbir istek atılmadan** fırlatılır.
///
/// ## Neden ayrı bir tip (StateError değil)?
///
/// Çağıran ekranlar (`notifications_dialog.dart`, `goals_dialog.dart`,
/// `personal_info_dialog.dart`, `onboarding_page.dart`) `catch (_)` ile
/// genel bir "Kaydedilemedi" mesajı gösteriyor; bu yüzden sınıfın UI'ya
/// özel bir davranışı yok. Ama ayrı bir tip, (a) hatanın **bu uygulamanın
/// doğrulamasından** geldiğini testlerde ayırt edilmesini sağlar ve
/// (b) `catch (_)` dışında bir yerde (örn. onboarding'in hata ayrımı) özel
/// davranış istenirse yeri hazır olur.
class ProfileFieldRangeError implements Exception {
  const ProfileFieldRangeError({
    required this.field,
    required this.value,
    required this.range,
    required this.reason,
  });

  /// DB kolon adı (`weigh_in_frequency_days` gibi).
  final String field;

  /// Reddedilen değer.
  final Object? value;

  /// Okunabilir kabul aralığı (`1-365 gün` gibi).
  final String? range;

  /// Neden reddedildi (`aralık dışı`, `sayı sonlu değil`, …).
  final String reason;

  /// Kullanıcıya gösterilebilecek tek satır. **Sunucu ayrıntısı taşımaz.**
  String get summary => range == null
      ? 'Geçersiz profil alanı: $field'
      : '$field $range aralığında olmalı ($reason)';

  @override
  String toString() => 'ProfileFieldRangeError($field=$value, '
      'beklenen: $range, neden: $reason)';
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

/// Oturum açık kullanıcının profili.
///
/// Oturum yoksa `null` döner; oturum değişince otomatik yenilenir.
/// UI tarafında `ref.watch(profileProvider)` kullanılır; güncelleme
/// sonrası taze veri için `ref.invalidate(profileProvider)` çağrılır.
final profileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(profileRepositoryProvider).fetch(user.id);
});

import '../../core/constants/app_constants.dart';
import '../../core/observability/app_logger.dart';

/// `profiles.activity_level` (TEXT + CHECK) ile Flutter [ActivityLevel]
/// enum'u arasındaki **tek doğruluk kaynağı**.
///
/// ## Neden gerekli
///
/// DB CHECK kısıtı snake_case bekliyor, Dart enum adı camelCase:
///
/// ```sql
/// -- supabase/migrations/20260111041204_db829bb7-....sql:39
/// -- ve supabase/full_setup.sql:21
/// activity_level TEXT CHECK (activity_level IN
///   ('sedentary','light','moderate','active','very_active'))
/// ```
///
/// Aynı beş değer edge function'larda da sabitlendi:
/// `supabase/functions/calculate-macros/index.ts` (`ACTIVITY_LEVELS`) ve
/// `supabase/functions/ai-chat/index.ts` (gövde şeması + profil UPDATE).
///
/// `ActivityLevel.name` doğrudan gönderilirse (`veryActive`) CHECK ihlali →
/// `profiles` UPDATE'i başarısız → onboarding'de kullanıcı "Çok Aktif"
/// seçtiği halde hedefleri kaydedilemiyordu. Web tarafında aynı sözleşme
/// `src/lib/constants.ts` → `activityLevelToDb` / `activityLevelFromDb` ile
/// kuruldu (A5); buradaki karşılıkları birebir aynıdır.
abstract final class ActivityLevelMap {
  /// DB CHECK kısıtındaki beş değer (migration'dan okundu, elle uydurulmadı).
  static const List<String> dbValues = <String>[
    'sedentary',
    'light',
    'moderate',
    'active',
    'very_active',
  ];

  /// CHECK ihlali olmadan yazılabilecek değerler.
  ///
  /// [dbValues] kümesinin **birebir** aynısı olduğu birim testlerle
  /// doğrulanır; iki liste ayrışırsa DB yazımı sessizce kırılır.
  static const Set<String> dbValueSet = <String>{
    'sedentary',
    'light',
    'moderate',
    'active',
    'very_active',
  };

  /// Tanımsız/bozuk DB değeri karşısında seçilen güvenli varsayılan.
  ///
  /// Web (`activityLevelFromDb`) ve Flutter (`enum`'un ilk değeri olarak seçilen)
  /// aynı anda `moderate`'a düşüyor: orta seviye her iki uçtan da daha az
  /// agresif bir TDEE çarpanı (1.55) verir ve kullanıcıyı ne yanlış yönde
  /// aşırı beslenmeye ne de sınırsız calorie hedefine sürüklemez.
  static const ActivityLevel fallback = ActivityLevel.moderate;

  /// UI enum değeri → `profiles.activity_level` yazılacak dize.
  ///
  /// `exhaustive` switch sayesinde yeni bir enum değeri eklenirse derleme
  /// hatası verir ve buradaki eşleme güncellenmek zorunda kalır.
  static String toDb(ActivityLevel level) => switch (level) {
        ActivityLevel.sedentary => 'sedentary',
        ActivityLevel.light => 'light',
        ActivityLevel.moderate => 'moderate',
        ActivityLevel.active => 'active',
        ActivityLevel.veryActive => 'very_active',
      };

  /// `profiles.activity_level` → UI enum değeri.
  ///
  /// **Çökmez.** null/boş string, DB'de tanımsız bir değer (yeni sunucu
  /// sürümü, elle yazılmış veri, eski `veryActive` yazımı) veya yazım
  /// hatası durumunda [fallback] döner ve durum `AppLog` ile loglanır —
  /// profil ekranı yeni bir sunucu sürümü yüzünden düşmez.
  static ActivityLevel fromDb(Object? value) {
    final v = value?.toString().trim();
    if (v == null || v.isEmpty) {
      AppLog.w(
        'activity_level boş/null, varsayılana düşüldü',
        {'fallback': fallback.name},
      );
      return fallback;
    }
    final direct = _byName[v];
    if (direct != null) return direct;
    AppLog.w(
      'activity_level DB değeri tanınmıyor, varsayılana düşüldü',
      {'value': v, 'fallback': fallback.name},
    );
    return fallback;
  }

  static final Map<String, ActivityLevel> _byName = <String, ActivityLevel>{
    for (final l in ActivityLevel.values) toDb(l): l,
  };
}

/// `profiles.activity_level` yazılacak dize (web `activityLevelToDb` parity).
String activityLevelToDb(ActivityLevel level) => ActivityLevelMap.toDb(level);

/// `profiles.activity_level` okunduğunda UI enum değeri
/// (web `activityLevelFromDb` parity; çökmez, loglar).
ActivityLevel activityLevelFromDb(Object? value) =>
    ActivityLevelMap.fromDb(value);

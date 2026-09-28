import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../observability/app_logger.dart';

/// Uygulama yapılandırması.
///
/// Değerler öncelikle `--dart-define` ile, yoksa `.env` dosyasından okunur.
/// (CI / web build'de dart-define tercih edilir; .env asset olarak gömülür.)
///
/// ## GÜVENLİK — bu sınıf istemciye **gömülen** bir yapılandırmadır
///
/// `String.fromEnvironment` **şifreleme değildir**: verilen değer binary/JS
/// içine düz metin olarak yazılır ve `strings`/`grep` ile geri alınabilir.
/// Bu nedenle burada yalnızca zaten herkese açık olan değerler tutulmalıdır:
///
/// | Değişken | Gömülebilir mi? | Gerekçe |
/// |---|---|---|
/// | `SUPABASE_URL` | evet | Proje adresi zaten ağ trafiğinde görünür. |
/// | `SUPABASE_ANON_KEY` / `sb_publishable_…` | evet | Tasarım gereği public: RLS bu anahtarla da uygulanır. Sızıntısı kullanıcı verisini açmaz, yalnızca anon kotasını hedef alır (kalıcı rate limit A1'de tabloya taşındı). |
/// | `SENTRY_DSN` | evet | Gönderme yetkisi, okuma yetkisi değil. |
/// | `SUPABASE_SERVICE_ROLE_KEY` / `sb_secret_…` | **hayır** | RLS'i **tamamen atlar** — istemciye gömüldüğü anda veritabanı tüm satırları okuma/yazma yetkisine sahip olur. |
/// | `SUPABASE_DB_PASSWORD` | **hayır** | Doğrudan veritabanı erişimi. |
///
/// ## Derleme/build guard
///
/// A1 Tur 1 `_isSecretKey` ile **okuma** tarafını koruyordu (yanlışlıkla
/// service_role verilirse değer boşaltılır → RLS'siz çalışma yerine
/// "yapılandırılmamış" olur). Bu koruma **çalışma zamanında**dır ve
/// sessizdir. [assertSafeForClientBuild] bunu **derleme zamanında** yapar:
/// `assert` release modunda da etkin olduğu için
/// `flutter build apk --dart-define=SUPABASE_ANON_KEY=sb_secret_…` derlemeyi
/// **durdurur** (kırmızı build) — yanlış anahtarın binaryye sızması
/// mümkün olmaz.
///
/// ## `.env` neden hâlâ asset?
///
/// `pubspec.yaml`'daki `assets: - .env` kaldırılmadı: **üretim** yapılandırması
/// CI'da `--dart-define` ile veriliyor (bkz. `.github/workflows/flutter.yml`),
/// `.env` asset'i yalnızca **yerel geliştirme** kolaylığıdır. Kaldırma işlemi
/// pubspec + CI adımını birlikte değiştirmeyi gerektirir (A6 alanı) ve
/// `dotenv.load` yalnızca dosya **yoksa** sorun çıkardığı için düşük
/// getirili/yüksek risklidir. Not: `.env` `.gitignore`'da, CI'da
/// **placeholder** (`cp .env.example .env`) üretiliyor — gerçek sır binaryye
/// girmez.
class Env {
  Env._();

  /// İstemcide kullanılması güvenli olmayan anahtar önekleri.
  static const List<String> _forbiddenKeyPrefixes = [
    'sb_secret_',
    'service_role',
  ];

  /// Değer **içeriğinde** geçen yasaklı işaretler (öneğe ek olarak).
  /// `service_role` JWT'leri `{"role":"service_role"}` payload'ı taşır.
  static const List<String> _forbiddenValueMarkers = [
    'service_role',
    'sb_secret_',
  ];

  static const String _dartDefineUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String _dartDefineAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static const String _dartDefineSentryDsn =
      String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String _dartDefineServiceRole =
      String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY', defaultValue: '');

  static String get supabaseUrl => _dartDefineUrl.isNotEmpty
      ? _dartDefineUrl
      : (dotenv.env['SUPABASE_URL'] ?? '');

  static String get supabaseAnonKey {
    final value = _dartDefineAnonKey.isNotEmpty
        ? _dartDefineAnonKey
        : (dotenv.env['SUPABASE_ANON_KEY'] ?? '');
    // Yanlışlıkla service_role anahtarı tanımlanırsa uygulama sessizce
    // RLS'siz çalışmasına izin vermek yerine yapılandırılmamış sayılır.
    return isSecretKey(value) ? '' : value;
  }

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Sentry DSN — boşsa crash reporting devre dışı (yerel geliştirme).
  static String get sentryDsn => _dartDefineSentryDsn.isNotEmpty
      ? _dartDefineSentryDsn
      : (dotenv.env['SENTRY_DSN'] ?? '');

  /// Değer istemciye gömülemez mi? (A1 Tur 1'in kontrolü, burada paylaşıldı.)
  ///
  /// Hem **önek** hem **içerik** denetimi yapar: yeni Supabase anahtar
  /// biçimleri (`sb_secret_…`) eski JWT biçiminden (`eyJ…` ile başlayıp
  /// `"role":"service_role"` içeren) ayırt edilir. Gövde base64 olduğu için
  /// JWT içindeki `service_role` düz metin olarak görünmez — bu yüzden
  /// yalnızca ham/yapıştırılmış değerler yakalanır. Yeterli: gömülen değer
  /// **build girdisidir** ve insan tarafından yazılır.
  static bool isSecretKey(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (_forbiddenKeyPrefixes.any(normalized.startsWith)) return true;
    return _forbiddenValueMarkers.any(normalized.contains);
  }

  /// Derleme zamanı guard — istemci binary'sine sır gömülmesini engeller.
  ///
  /// `assert` hem `flutter test` hem `flutter build` (release dahil) sırasında
  /// değerlendirilir; ihlal derlemeyi durdurur. Testlerde doğrudan çağrılıp
  /// `AssertionError` fırlattığı doğrulanır.
  static void assertSafeForClientBuild({
    String? anonKey = _dartDefineAnonKey,
    String? serviceRoleKey = _dartDefineServiceRole,
    String? sentryDsn = _dartDefineSentryDsn,
    String? supabaseUrl = _dartDefineUrl,
  }) {
    assert(
      !isSecretKey(anonKey ?? ''),
      'GÜVENLİK: SUPABASE_ANON_KEY bir service_role/secret anahtarı içeriyor. '
      'Bu değer binaryye gömülemez (RLS atlanır). Publishable/anon anahtar '
      'kullanın (sb_publishable_… veya anon JWT).',
    );
    assert(
      (serviceRoleKey ?? '').trim().isEmpty,
      'GÜVENLİK: SUPABASE_SERVICE_ROLE_KEY istemci build\'inde tanımlanmış. '
      'Bu anahtar sunucu tarafında (edge function) kalmalı; mobil binaryye '
      'gömülürse RLS tamamen atlanır.',
    );
    assert(
      !isSecretKey(sentryDsn ?? ''),
      'GÜVENLİK: SENTRY_DSN bir service_role/secret değeri içeriyor.',
    );
    assert(
      (supabaseUrl ?? '').isEmpty || (supabaseUrl ?? '').startsWith('https://'),
      'GÜVENLİK: SUPABASE_URL https:// ile başlamalı.',
    );
  }

  static bool _loaded = false;

  /// Yapılandırmayı yükler.
  ///
  /// `.env` yoksa/bozuksa **sessizce** yutulmaz: `AppLog.w` ile raporlanır.
  /// Eksik alanlar `isConfigured` üzerinden görünür kalır — `initSupabase`
  /// bu durumda kullanıcıya "yapılandırma eksik" durumu gösterir
  /// (fail-fast değil ama görünür; A1'in `env.dart` alanına dokunulmadan).
  static Future<void> load() async {
    assertSafeForClientBuild();
    try {
      await dotenv.load(fileName: '.env');
      _loaded = true;
    } catch (e, s) {
      AppLog.w('.env yüklenemedi, --dart-define kullanılacak', e, s);
    }
    if (!isConfigured) {
      AppLog.w(
        'Supabase yapılandırması eksik '
        '(url=${supabaseUrl.isEmpty ? 'boş' : 'var'}, '
        'anonKey=${supabaseAnonKey.isEmpty ? 'boş' : 'var'})',
      );
    }
  }

  /// `.env` başarıyla yüklendi mi? (tanılama/test amaçlı)
  @visibleForTesting
  static bool get dotenvLoaded => _loaded;
}

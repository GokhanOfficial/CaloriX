import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Uygulama yapılandırması.
///
/// Değerler öncelikle `--dart-define` ile, yoksa `.env` dosyasından okunur.
/// (CI / web build'de dart-define tercih edilir; .env asset olarak gömülür.)
///
/// GÜVENLİK: Bu sınıf istemciye gömülen bir yapılandırmadır. Burada **yalnızca**
/// herkese açık anahtarlar (`anon`/`publishable`) bulunmalıdır. `service_role`
/// anahtarı istemciye gömülürse RLS tamamen atlanır; bu nedenle hiçbir ortam
/// değişkeni `SUPABASE_SERVICE_ROLE_KEY` adıyla okunmaz ve okunmamalıdır.
/// Supabase anahtarları `sb_publishable_`/`sb_secret_` önekleriyle ayırt edilir;
/// `secret` öneki taşıyan bir değer istemcide kullanılmaz.
class Env {
  Env._();

  /// İstemcide kullanılması güvenli olmayan anahtar önekleri.
  static const List<String> _forbiddenKeyPrefixes = [
    'sb_secret_',
    'service_role',
  ];

  static const String _dartDefineUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String _dartDefineAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static const String _dartDefineSentryDsn =
      String.fromEnvironment('SENTRY_DSN', defaultValue: '');

  static String get supabaseUrl =>
      _dartDefineUrl.isNotEmpty ? _dartDefineUrl : (dotenv.env['SUPABASE_URL'] ?? '');

  static String get supabaseAnonKey {
    final value = _dartDefineAnonKey.isNotEmpty
        ? _dartDefineAnonKey
        : (dotenv.env['SUPABASE_ANON_KEY'] ?? '');
    // Yanlışlıkla service_role anahtarı tanımlanırsa uygulama sessizce
    // RLS'siz çalışmasına izin vermek yerine yapılandırılmamış sayılır.
    return _isSecretKey(value) ? '' : value;
  }

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Sentry DSN — boşsa crash reporting devre dışı (yerel geliştirme).
  static String get sentryDsn =>
      _dartDefineSentryDsn.isNotEmpty ? _dartDefineSentryDsn : (dotenv.env['SENTRY_DSN'] ?? '');

  static bool _isSecretKey(String value) {
    final normalized = value.trim().toLowerCase();
    return _forbiddenKeyPrefixes.any(normalized.startsWith);
  }

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // .env yoksa dart-define ile çalışmaya devam et
    }
  }
}

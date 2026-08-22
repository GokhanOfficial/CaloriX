import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Uygulama yapılandırması.
///
/// Değerler öncelikle `--dart-define` ile, yoksa `.env` dosyasından okunur.
/// (CI / web build'de dart-define tercih edilir; .env asset olarak gömülür.)
class Env {
  Env._();

  static const String _dartDefineUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String _dartDefineAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static String get supabaseUrl =>
      _dartDefineUrl.isNotEmpty ? _dartDefineUrl : (dotenv.env['SUPABASE_URL'] ?? '');

  static String get supabaseAnonKey => _dartDefineAnonKey.isNotEmpty
      ? _dartDefineAnonKey
      : (dotenv.env['SUPABASE_ANON_KEY'] ?? '');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // .env yoksa dart-define ile çalışmaya devam et
    }
  }
}

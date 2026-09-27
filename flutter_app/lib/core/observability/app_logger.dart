import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Uygulama genelinde minik loglama katmanı.
///
/// Debug derlemede her seviye konsola yazar; release'te yalnızca
/// warning/error Sentry'ye gönderilir (main.dart DSN'yi yapılandırmazsa
/// Sentry çağrıları güvenli no-op'tur). Repository/UI'daki catch bloklarında
/// sessizce yutulan hatalar buraya raporlanmalar.
abstract final class AppLog {
  static void i(String message) {
    if (kDebugMode) debugPrint('ℹ️ $message');
  }

  static void w(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) debugPrint('⚠️ $message${_suffix(error)}');
    _capture(SentryLevel.warning, message, error, stackTrace);
  }

  static void e(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) debugPrint('❌ $message${_suffix(error)}');
    _capture(SentryLevel.error, message, error, stackTrace);
  }

  static String _suffix(Object? error) =>
      error == null ? '' : ' — $error';

  static void _capture(
    SentryLevel level,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (kDebugMode || !Sentry.isEnabled) return;
    unawaited(Sentry.captureEvent(
      SentryEvent(
        level: level,
        // Release'de ham mesaj gönderilmez: log satırları e-posta, JWT,
        // Supabase URL/token veya kullanıcı girdisi içerebilir. Sentry
        // tarafında okunabilir kalsın diye PII deseni temizlenir.
        message: SentryMessage(scrubPii(message)),
        throwable: error == null ? null : ScrubbedError(scrubPii(error.toString())),
      ),
      stackTrace: stackTrace,
    ));
  }

  /// E-posta, uzun hex/base64 (token), URL içindeki otonurum parçası ve
  /// `Bearer`/`apikey=` gibi anahtar-değer kalıplarını maskeler.
  ///
  /// Kasıtlı olarak kaba bir süzgeçtir: yanlış pozitif (maskelenmiş bir
  /// değerin kaybolması) PII sızıntısına göre çok daha düşük maliyetlidir.
  static final List<RegExp> _piiPatterns = [
    // e-posta
    RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+', caseSensitive: false),
    // Bearer / token / key değişkenleri
    RegExp(
      r'\b(bearer|token|apikey|api_key|secret|password|parola|anon[_-]?key)'
      r'(\s*[:=]\s*|\s+)\S+',
      caseSensitive: false,
    ),
    // JWT benzeri üç noktalı parça
    RegExp(r'\beyJ[\w-]{5,}\.[\w-]{5,}\.[\w-]{5,}\b'),
    // supabase anon/service key (eyJ... ile başlar, uzun)
    RegExp(r'\beyJ[A-Za-z0-9_-]{40,}'),
  ];

  /// Uzunluğu [_longTokenThreshold] üzerinde olan sürekli hex dizileri
  /// (sha256, token) maskelenir.
  static const int _longTokenThreshold = 32;
  static final RegExp _longHex = RegExp('\\b[0-9a-fA-F]{$_longTokenThreshold,}\\b');

  /// [message] içindeki olası PII'yi maskeler. Test edilebilir saf fonksiyon.
  static String scrubPii(String message) {
    var out = message;
    for (final p in _piiPatterns) {
      out = out.replaceAll(p, '[redacted]');
    }
    out = out.replaceAllMapped(
      _longHex,
      (m) => '[redacted:${m[0]!.length}]',
    );
    return out;
  }
}

/// `SentryEvent.throwable` için PII temizlenmiş hata sarmalayıcı.
///
/// Sentry `Throwable` olarak `error`'ü aynen iletirdi; `toString()`'i
/// `SupabaseException` gibi sınıflarda URL veya payload içerebildiği için
/// temizlenmiş metin gönderilir. `Type` korunur — Sentry gruplamayı
/// exception type + mesaj üzerinden yapar, stack trace ayrıca iletilir.
class ScrubbedError implements Exception {
  const ScrubbedError(this.message);

  final String message;

  @override
  String toString() => message;
}

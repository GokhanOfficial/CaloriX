import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'data/supabase/supabase_client_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Env.load();
  await initSupabase();
  // Analitik / tarih etiketleri için DateFormat locale verileri
  // (intl date_symbol_data_local — tüm desteklenen diller).
  await initializeDateFormatting();

  // DSN yapılandırılmamışsa init no-op'a düşer (yerel geliştirme etkilenmez).
  // `appRunner` SADECE Sentry başarılıysa kullanılır: `SentryFlutter.init`
  // bir hata fırlatırsa (bozuk DSN, ağ/native entegrasyon hatası) `runApp`
  // hiç çağrılmaz ve kullanıcı **beyaz ekranla** kalır. Bu yüzden
  // `runZonedGuarded` ile hem normal yol hem de hata yolu tek yerden
  // yürütülür; Sentry kurulamasa bile uygulama açılır (gözlemlenebilirlik
  // kaybı kabul edilir, kullanıcı kaybı değil).
  final appRoot = _AppRoot();

  await runZonedGuarded(
    () async {
      try {
        await SentryFlutter.init(
          (options) {
            options.dsn = Env.sentryDsn.isEmpty ? null : Env.sentryDsn;
            // PII gönderilmez; kullanıcı bağlamında yalnızca UUID taşınır
            // (sentry_user_context.dart).
            options.sendDefaultPii = false;
            options.tracesSampleRate = 0.1;
          },
          appRunner: appRoot.run,
        );
      } catch (e, s) {
        // Crash reporting kurulamadı — loglayıp uygulamayı yine başlat.
        debugPrint('Sentry başlatılamadı, uygulama yine açılıyor: $e\n$s');
        appRoot.run();
      }
    },
    (Object error, StackTrace stack) {
      // runZonedGuarded'ın üçüncü argümanı — Sentry kendi zone'unu kurduysa
      // buraya düşülmez, aksi halde son çare olarak konsola yaz.
      debugPrint('Uygulama zone hatası: $error\n$stack');
    },
  );
}

/// Uygulama ağacı — `runApp` çağrısını hem Sentry `appRunner` hem de
/// Sentry kurulamadığında kullanılan fallback yol için tek yerden üretir.
class _AppRoot {
  void run() {
    runApp(
      ProviderScope(
        child: EasyLocalization(
          supportedLocales: const [
            Locale('tr'),
            Locale('en'),
            Locale('de'),
            Locale('es'),
            Locale('fr'),
            Locale('it'),
            Locale('pt'),
            Locale('ru'),
            Locale('ar'),
            Locale('ja'),
            Locale('ko'),
            Locale('zh'),
          ],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('tr'),
          child: const CalorixApp(),
        ),
      ),
    );
  }
}

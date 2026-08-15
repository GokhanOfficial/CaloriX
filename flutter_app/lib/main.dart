import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

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

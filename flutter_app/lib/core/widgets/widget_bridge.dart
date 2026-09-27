import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/profile.dart';
import '../../data/repositories/diary_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../observability/app_logger.dart';
import 'widget_settings.dart';
import 'widget_snapshot.dart';
import 'widget_strings.dart';

/// Dart → native ana ekran widget veri köprüsü.
///
/// [buildDailySnapshot] / [buildWeeklySnapshot] / [buildStateSnapshot] çıktısını
/// `home_widget` üzerinden `flutter` adlı SharedPreferences dosyasına yazar ve
/// iki provider'a da tazeleme isteği gönderir. Native taraf
/// (bkz. `android/.../widget/WidgetData.kt`) yalnızca bu anahtarları okur ve
/// çizer — hesap yapmaz.
///
/// Tüm yazma işlemleri hata durumunda **sessizce yutulur**: widget güncellemesi
/// asla uygulamanın ana akışını düşürmemelidir. Hatalar `AppLog` ile loglanır.
class WidgetBridge {
  WidgetBridge._();

  /// `DailyWidgetProvider.ACTION_REFRESH` ile aynı olmalı.
  static const String refreshAction = 'com.calorix.app.action.WIDGET_REFRESH';

  /// Native provider sınıf adları — `home_widget` bunları manifest'te arar
  /// (`androidName` bir WidgetProvider sınıf adı olmalıdır).
  static const String _dailyProvider = 'DailyWidgetProvider';
  static const String _weeklyProvider = 'WeeklyWidgetProvider';

  /// Tüm anahtarları yazar, ardından widget'ları tazeler.
  static Future<void> publish(Map<String, Object?> snapshot) async {
    try {
      for (final entry in snapshot.entries) {
        final value = _jsonSafe(entry.value);
        if (value == null) continue;
        // home_widget yalnızca JSON-uyumlu temel tipleri kabul eder.
        if (value is bool) {
          await HomeWidgetSave.saveBool(entry.key, value);
        } else if (value is num) {
          await HomeWidgetSave.saveDouble(entry.key, value.toDouble());
        } else if (value is String) {
          await HomeWidgetSave.saveString(entry.key, value);
        } else {
          await HomeWidgetSave.saveString(entry.key, jsonEncode(value));
        }
      }
      await _refreshAll();
    } catch (e, s) {
      AppLog.w('WidgetBridge.publish başarısız', e, s);
    }
  }

  /// Her iki widget provider'ına da tazeleme isteği gönderir.
  static Future<void> _refreshAll() async {
    for (final name in [_dailyProvider, _weeklyProvider]) {
      await HomeWidgetSave.update(name);
    }
  }

  /// Günlük özet widget'ı için bugünün verisini yayınlar.
  static Future<void> publishDaily({
    required DailyData daily,
    required Profile? profile,
    required WidgetSettings settings,
    required WidgetStrings strings,
    required DateTime now,
    required String localeCode,
  }) {
    return publish(
      buildDailySnapshot(
        daily: daily,
        profile: profile,
        settings: settings,
        strings: strings,
        now: now,
        localeCode: localeCode,
      ),
    );
  }

  /// Çıkış yapıldığında widget'ı nötr duruma alır (eski kaloriler görünmesin).
  static Future<void> publishState({
    required String state,
    required WidgetStrings strings,
    required String localeCode,
  }) {
    return publish(
      buildStateSnapshot(
        state: state,
        strings: strings,
        now: DateTime.now(),
        localeCode: localeCode,
      ),
    );
  }

  /// NaN/Infinity yazılabilir değerleri temizler ve JSON-uyumlu tipe çevirir.
  static Object? _jsonSafe(Object? value) => switch (value) {
    null => null,
    // NaN/Infinity JSON'a yazılamaz; 0'a indir.
    final num n => (n.isNaN || n.isInfinite) ? 0 : n,
    final bool b => b,
    final String s => s,
    final List<Object?> l => l.map(_jsonSafe).whereType<Object>().toList(),
    final Map<String, Object?> m => m.map(
      (k, v) => MapEntry(k, _jsonSafe(v)),
    ),
    _ => value.toString(),
  };
}

/// `home_widget` sarmalayıcı — testlerde tek noktadan değiştirilebilsin diye
/// ayrıldı. (Platform kanalı widget testlerinde `MissingPluginException` verir.)
abstract final class HomeWidgetSave {
  static Future<bool?> Function(String, bool) saveBool =
      (k, v) => HomeWidget.saveWidgetData<bool>(k, v);
  static Future<bool?> Function(String, double) saveDouble =
      (k, v) => HomeWidget.saveWidgetData<double>(k, v);
  static Future<bool?> Function(String, String) saveString =
      (k, v) => HomeWidget.saveWidgetData<String>(k, v);
  static Future<String?> Function(String) readString =
      (k) => HomeWidget.getWidgetData<String>(k);
  static Future<bool?> Function(String) update =
      (name) => HomeWidget.updateWidget(
        androidName: name,
        iOSName: name,
        name: name,
      );

  /// Test sonrası orijinal implementasyonlara dön.
  static void reset() {
    saveBool = (k, v) => HomeWidget.saveWidgetData<bool>(k, v);
    saveDouble = (k, v) => HomeWidget.saveWidgetData<double>(k, v);
    saveString = (k, v) => HomeWidget.saveWidgetData<String>(k, v);
    readString = (k) => HomeWidget.getWidgetData<String>(k);
    update = (name) => HomeWidget.updateWidget(
      androidName: name,
      iOSName: name,
      name: name,
    );
  }
}

/// Widget köprüsünü uygulamanın veri akışına bağlar.
///
/// `MaterialApp.router` altına sarılır. Günlük veri her değiştiğinde
/// (öğün ekle/sil, su, kilo) ve ayar değiştiğinde native widget'lar tazelenir.
class WidgetBridgeScope extends ConsumerWidget {
  const WidgetBridgeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Günlük veri değiştikçe günlük widget'ı yeniden yayınla.
    ref.listen<AsyncValue<DailyData>>(dailyDataProvider, (previous, next) {
      final data = next.valueOrNull;
      if (data == null) return;
      unawaited(
        WidgetBridge.publishDaily(
          daily: data,
          profile: ref.read(profileProvider).valueOrNull,
          settings: ref.read(widgetSettingsProvider),
          strings: WidgetStrings.current(),
          now: DateTime.now(),
          localeCode: _localeCode(context),
        ),
      );
    });

    // Ayar değişiklikleri widget görünürlüğünü değiştirir → yeniden yayın.
    ref.listen<WidgetSettings>(widgetSettingsProvider, (previous, next) {
      if (previous == null || previous == next) return;
      unawaited(refreshVisibility(settings: next, localeCode: _localeCode(context)));
    });

    return child;
  }

  static String _localeCode(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale.isEmpty ? 'en' : locale;
  }
}

/// Ayar değiştiğinde yalnızca **görünürlük** anahtarlarını yeniden yazar.
///
/// Snapshot'ın kendisi `publishDaily` ile yazılır; kullanıcı makro/su/kilo
/// satırını gizlediyse veriyi silmek yerine bayrağı kapatmak doğru davranıştır
/// (gizleme kalıcı bir tercih, yeniden açınca veri hazır olmalıdır).
///
/// Not: `shared_preferences` **kullanılamaz** — `home_widget` veriyi
/// `HomeWidgetPreferences` dosyasına yazar, `shared_preferences` ise
/// `FlutterSharedPreferences` okur. Aşağıdaki `HomeWidgetSave` sarmalayıcısı
/// doğru kanalı kullanır.
Future<void> refreshVisibility({
  required WidgetSettings settings,
  required String localeCode,
}) async {
  try {
    final state = await HomeWidgetSave.readString(WidgetKeys.state);
    if (state == null) {
      // Hiç veri yazılmamış (ilk açılış / widget hiç kullanılmamış).
      return;
    }
    await WidgetBridge.publish({
      WidgetKeys.dShowMacros: settings.showMacros,
      WidgetKeys.dShowWater: settings.showWater,
      WidgetKeys.dShowWeight: settings.showWeight,
      WidgetKeys.wShowAvg: settings.weeklyShowAvg,
      WidgetKeys.wShowOnTarget: settings.weeklyShowDaysOnTarget,
    });
  } catch (e, s) {
    AppLog.w('WidgetBridge.refreshVisibility başarısız', e, s);
  }
}

/// Anahtar bu veri kanalına ait mi? (Dart tarafı ayarları `widget_*` önekli,
/// bu yüzden onlar yanlışlıkla süzülmez.)
bool isWidgetKey(String key) =>
    key.startsWith('widget.') ||
    key.startsWith('daily.') ||
    key.startsWith('weekly.') ||
    key.startsWith('str.');

/// Haftalık grafiği yayınlar (7 günlük sorgu gerektirir, ayrı akış).
Future<void> publishWeekly({
  required List<Map<String, dynamic>> mealRows,
  required Profile? profile,
  required WidgetSettings settings,
  required WidgetStrings strings,
  required String localeCode,
}) async {
  await WidgetBridge.publish(
    buildWeeklySnapshot(
      mealRows: mealRows,
      profile: profile,
      settings: settings,
      strings: strings,
      now: DateTime.now(),
      localeCode: localeCode,
    ),
  );
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
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

  /// `widget.state` anahtarının değerleri — `buildStateSnapshot` ile aynı
  /// sözleşme. `WidgetData.kt` yalnızca bu üç değeri tanır (`STATE_NO_CONFIG`
  /// dahil), başka bir değer görürse nötr duruma düşer.
  static const String stateReady = 'ready';
  static const String stateSignedOut = 'signedOut';
  static const String stateNoConfig = 'noConfig';

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
/// (öğün ekle/sil, su, kilo), oturum değiştiğinde ve ayar değiştiğinde
/// native widget'lar tazelenir.
class WidgetBridgeScope extends ConsumerStatefulWidget {
  const WidgetBridgeScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WidgetBridgeScope> createState() => _WidgetBridgeScopeState();
}

class _WidgetBridgeScopeState extends ConsumerState<WidgetBridgeScope> {
  /// Yayınlanan son günün veri imzası.
  ///
  /// `AsyncValue` referans eşitliği güvenilir değil: `AsyncLoading` →
  /// `AsyncData` → `AsyncData(yeni veri)` geçişlerinde provider her seferinde
  /// yeni bir `AsyncData` üretir ama `==` ile karşılaştırılabilir. Aynı veri
  /// için **tekrar yayın yapmamak**, kullanıcı ayar değiştirdiğinde widget'ın
  /// gereksiz yere yeniden çizilmesini (ve `home_widget` platform çağrısını)
  /// engeller.
  DailyData? _lastPublishedDaily;

  /// Oturum durumu yayınlandı mı? (nötr duruma geçiş yalnızca bir kez)
  String? _lastPublishedState;

  /// Günlük veri yayınlandı mı? (aynı örnek için tekrar yayın yapılmaz)
  ///
  /// NOT: `WidgetRef.listen` ilk değeri **tetiklemez** (aşağıdaki blokta
  /// gerekçesi var); bu bayrak "0) ilk değer" bloğunun yalnızca bir kez
  /// çalıştığını garanti eder.
  bool _dailyPublished = false;

  @override
  Widget build(BuildContext context) {
    final localeCode = _localeCode(context);

    // --- 0) İlk değer yayını (P0 düzeltmesi, 2026-09-28).
    //
    // `WidgetRef.listen` **ilk değeri tetiklemez.** Kaynak bunu açıkça
    // belirtiyor (flutter_riverpod-2.6.1/lib/src/consumer.dart:604):
    //   "We can't implement a fireImmediately flag because we wouldn't know
    //    which listen call was preserved between widget rebuild…"
    // Yani `build` içindeki `ref.listen` yalnızca **sonraki** değişikliklerde
    // çalışır.
    //
    // Gerçek etki: uygulama açıldığında widget'ın `HomeWidgetPreferences`
    // deposunda veri **yoksa** hiçbir şey yazılmıyordu — ana ekran
    // widget'ları "veri yok" durumunda kalıyor, günlük veri geldiğinde
    // `AsyncLoading` → `AsyncData` geçişi ise *muhakkak* bir değişiklik
    // sayıldığı için yakalanıyordu. Sorun, verinin **zaten önbellekte
    // hazır** olduğu (ya da oturumdan hiç okunmadan `ref.read` ile
    // senkron değer döndüğü) durumdu: `published` boş kalıyordu.
    //
    // Aşağıdaki blok `build` sırasında `ref.read` ile **mevcut** değeri
    // alıp aynı yayın yolundan geçirir. Böylece "provider HENÜZ okunmamışken
    // de ilk yayın yapılır" sözleşmesi gerçekten sağlanır; sonraki
    // değişiklikler `ref.listen` ile gelir ve `_lastPublished*` sayaçları
    // çift yayını engeller.
    if (!_dailyPublished) {
      final initial = ref.read(dailyDataProvider);
      final data = initial.valueOrNull;
      if (data != null) {
        _publishDaily(data, localeCode);
      }
    }
    if (_lastPublishedState == null) {
      // `currentUserProvider` zinciri `authRepositoryProvider` →
      // `Supabase.instance` üzerinden geçiyor; **exceptionsız** okunmalı
      // (`ref.read` aksi hâlde widget'ın build'ini patlatıyor — Supabase
      // başlatılmamışsa assertion fırlatıyor). Oturum durumu zaten 1)
      // bloğundaki `ref.listen` ile gelir; bu satır yalnızca "abone
      // olduğumuz provider'ın değeri hâlihazırda hazırsa" ilk yayını
      // tetikler.
      User? initialUser;
      try {
        initialUser = ref.read(currentUserProvider);
      } catch (_) {
        initialUser = null;
      }
      _publishState(initialUser == null, localeCode);
    }

    // --- 1) Günlük veri: her değiştiğinde günlük widget'ı yeniden yayınla.
    ref.listen<AsyncValue<DailyData>>(dailyDataProvider, (previous, next) {
      final data = next.valueOrNull;
      if (data == null) return;
      _publishDaily(data, localeCode);
    });

    // --- 2) Oturum durumu: çıkışta widget'ı nötr duruma al.
    //
    // `dailyDataProvider` `currentUserProvider`'a bağlı; kullanıcı çıkış
    // yapınca `DailyData.empty` döner ve **eski kaloriler widget'ta kalırdı**
    // (`publishState` hiç çağrılmıyordu → şifreli ekranda başkasının
    // kalori görünür). Burada durum değişimi nötr snapshot'a çevrilir.
    ref.listen<User?>(currentUserProvider, (previous, next) {
      _publishState(next == null, localeCode);
    });

    // --- 3) Ayar değişiklikleri yalnızca görünürlük anahtarlarını etkiler.
    ref.listen<WidgetSettings>(widgetSettingsProvider, (previous, next) {
      if (previous == null || previous == next) return;
      unawaited(
        refreshVisibility(settings: next, localeCode: localeCode),
      );
    });

    return widget.child;
  }

  /// Günlük snapshot'ı yayınlar. Aynı `DailyData` örneği için tekrar
  /// yayın yapmaz (`ref.invalidate` sonrası özdeş veri geldiğinde gereksiz
  /// `home_widget` platform çağrısı olmasın).
  void _publishDaily(DailyData data, String localeCode) {
    if (_dailyPublished && identical(_lastPublishedDaily, data)) return;
    _dailyPublished = true;
    _lastPublishedDaily = data;
    unawaited(
      WidgetBridge.publishDaily(
        daily: data,
        profile: ref.read(profileProvider).valueOrNull,
        settings: ref.read(widgetSettingsProvider),
        strings: WidgetStrings.current(),
        now: DateTime.now(),
        localeCode: localeCode,
      ),
    );
  }

  /// Oturum durumunu (nötr ya da hazır) yayınlar; aynı durum için tekrar
  /// yayın yapmaz.
  void _publishState(bool signedOut, String localeCode) {
    final state =
        signedOut ? WidgetBridge.stateSignedOut : WidgetBridge.stateReady;
    if (_lastPublishedState == state) return;
    _lastPublishedState = state;
    unawaited(
      WidgetBridge.publishState(
        state: state,
        strings: WidgetStrings.current(),
        localeCode: localeCode,
      ),
    );
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

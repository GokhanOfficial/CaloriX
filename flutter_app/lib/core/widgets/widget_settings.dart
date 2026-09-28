import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ana ekran widget'ı ayarları — cihaza lokal (SharedPreferences),
/// `ReminderSettings` deseniyle uyumlu. Supabase'e yazılmaz.
class WidgetSettings {
  const WidgetSettings({
    this.showMacros = true,
    this.showWater = true,
    this.showWeight = false,
    this.weeklyShowAvg = true,
    this.weeklyShowDaysOnTarget = true,
    this.encouragementEnabled = true,
    this.nudgeEnabled = false,
    this.nudgeHour = 20,
    this.nudgeMinute = 0,
  });

  /// Günlük widget'ta makro kartları gösterilsin mi?
  final bool showMacros;

  /// Günlük widget'ta su satırı gösterilsin mi?
  final bool showWater;

  /// Günlük widget'ta kilo satırı gösterilsin mi?
  final bool showWeight;

  /// Haftalık widget'ta ortalama etiketi gösterilsin mi?
  final bool weeklyShowAvg;

  /// Haftalık widget'ta "gün hedefte" etiketi gösterilsin mi?
  final bool weeklyShowDaysOnTarget;

  /// Gün içi teşvik metni (encouragement) açık mı?
  final bool encouragementEnabled;

  /// "Bugün hiç öğün yok" anlık bildirimi (nudge) açık mı?
  final bool nudgeEnabled;

  /// Nudge bildiriminin saat bileşeni (0-23).
  final int nudgeHour;

  /// Nudge bildiriminin dakika bileşeni (0-59).
  final int nudgeMinute;

  WidgetSettings copyWith({
    bool? showMacros,
    bool? showWater,
    bool? showWeight,
    bool? weeklyShowAvg,
    bool? weeklyShowDaysOnTarget,
    bool? encouragementEnabled,
    bool? nudgeEnabled,
    int? nudgeHour,
    int? nudgeMinute,
  }) {
    return WidgetSettings(
      showMacros: showMacros ?? this.showMacros,
      showWater: showWater ?? this.showWater,
      showWeight: showWeight ?? this.showWeight,
      weeklyShowAvg: weeklyShowAvg ?? this.weeklyShowAvg,
      weeklyShowDaysOnTarget:
          weeklyShowDaysOnTarget ?? this.weeklyShowDaysOnTarget,
      encouragementEnabled: encouragementEnabled ?? this.encouragementEnabled,
      nudgeEnabled: nudgeEnabled ?? this.nudgeEnabled,
      nudgeHour: nudgeHour ?? this.nudgeHour,
      nudgeMinute: nudgeMinute ?? this.nudgeMinute,
    );
  }
}

/// SharedPreferences kalıcı anahtarları — Dart↔native sözleşmesinin parçası
/// değil, yalnızca Dart tarafının okuma/yazma anahtarları.
abstract final class WidgetSettingsKeys {
  static const showMacros = 'widget_show_macros';
  static const showWater = 'widget_show_water';
  static const showWeight = 'widget_show_weight';
  static const weeklyAvg = 'widget_weekly_avg';
  static const weeklyDaysOnTarget = 'widget_weekly_target_days';
  static const encouragement = 'widget_encouragement';
  static const nudgeEnabled = 'widget_nudge_enabled';
  static const nudgeHour = 'widget_nudge_hour';
  static const nudgeMinute = 'widget_nudge_minute';
}

class WidgetSettingsNotifier extends Notifier<WidgetSettings> {
  @override
  WidgetSettings build() {
    _load();
    return const WidgetSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = WidgetSettings(
      showMacros: prefs.getBool(WidgetSettingsKeys.showMacros) ?? true,
      showWater: prefs.getBool(WidgetSettingsKeys.showWater) ?? true,
      showWeight: prefs.getBool(WidgetSettingsKeys.showWeight) ?? false,
      weeklyShowAvg: prefs.getBool(WidgetSettingsKeys.weeklyAvg) ?? true,
      weeklyShowDaysOnTarget:
          prefs.getBool(WidgetSettingsKeys.weeklyDaysOnTarget) ?? true,
      encouragementEnabled:
          prefs.getBool(WidgetSettingsKeys.encouragement) ?? true,
      nudgeEnabled: prefs.getBool(WidgetSettingsKeys.nudgeEnabled) ?? false,
      // Saat bileşenleri kırpılır: bozuk kalıcı değer (99) `DateTime`'in
      // ertesi güne normalize edilmesine ve `shouldSendNudge`'un her gün
      // true dönmesine yol açıyordu (P3, Tur 1). `reminder_settings.dart`
      // ile aynı savunma.
      nudgeHour: _clampHour(prefs.getInt(WidgetSettingsKeys.nudgeHour) ?? 20),
      nudgeMinute:
          _clampMinute(prefs.getInt(WidgetSettingsKeys.nudgeMinute) ?? 0),
    );
  }

  static int _clampHour(int hour) => hour < 0 ? 0 : (hour > 23 ? 23 : hour);

  static int _clampMinute(int minute) =>
      minute < 0 ? 0 : (minute > 59 ? 59 : minute);

  /// Ayarları uygular ve tüm alanları kalıcıya yazar — widget yeniden
  /// çizimi arka plan görevi bu anahtarları okuyarak ayağa kalkar.
  ///
  /// Saat bileşenleri yazılmadan **önce** kırpılır: bozuk bir değer kalıcıya
  /// yazılırsa her uygulama açılışında yeniden kırpılır ama native taraf
  /// (Kotlin) kalıcı değeri doğrudan okuyup normalize edilmemiş saati
  /// kullanabilirdi.
  Future<void> update(WidgetSettings settings) async {
    final sanitized = settings.copyWith(
      nudgeHour: _clampHour(settings.nudgeHour),
      nudgeMinute: _clampMinute(settings.nudgeMinute),
    );
    state = sanitized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(WidgetSettingsKeys.showMacros, sanitized.showMacros);
    await prefs.setBool(WidgetSettingsKeys.showWater, sanitized.showWater);
    await prefs.setBool(WidgetSettingsKeys.showWeight, sanitized.showWeight);
    await prefs.setBool(WidgetSettingsKeys.weeklyAvg, sanitized.weeklyShowAvg);
    await prefs.setBool(
      WidgetSettingsKeys.weeklyDaysOnTarget,
      sanitized.weeklyShowDaysOnTarget,
    );
    await prefs.setBool(
      WidgetSettingsKeys.encouragement,
      sanitized.encouragementEnabled,
    );
    await prefs.setBool(
        WidgetSettingsKeys.nudgeEnabled, sanitized.nudgeEnabled);
    await prefs.setInt(WidgetSettingsKeys.nudgeHour, sanitized.nudgeHour);
    await prefs.setInt(WidgetSettingsKeys.nudgeMinute, sanitized.nudgeMinute);
  }
}

final widgetSettingsProvider =
    NotifierProvider<WidgetSettingsNotifier, WidgetSettings>(
      WidgetSettingsNotifier.new,
    );

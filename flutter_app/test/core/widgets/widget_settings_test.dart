import 'package:calorix/core/widgets/widget_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget ayarları: varsayılanlar, update ile kalıcılık ve kalıcıdan
/// yeniden yükleme.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Notifier'ı build() ile başlatır, asenkron _load tamamlanana dek bekler.
  Future<WidgetSettings> loadSettings(ProviderContainer container) async {
    container.read(widgetSettingsProvider.notifier);
    await pumpEventQueue();
    return container.read(widgetSettingsProvider);
  }

  test(
    'varsayılanlar: makro+su+teşvik açık, kilo+nudge kapalı, nudge 20:00',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final settings = await loadSettings(container);

      expect(settings.showMacros, isTrue);
      expect(settings.showWater, isTrue);
      expect(settings.showWeight, isFalse);
      expect(settings.weeklyShowAvg, isTrue);
      expect(settings.weeklyShowDaysOnTarget, isTrue);
      expect(settings.encouragementEnabled, isTrue);
      expect(settings.nudgeEnabled, isFalse);
      expect((settings.nudgeHour, settings.nudgeMinute), (20, 0));
    },
  );

  test('update tüm alanları kalıcıya yazar', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(widgetSettingsProvider.notifier);
    await pumpEventQueue();

    await notifier.update(
      const WidgetSettings(
        showMacros: false,
        showWater: false,
        showWeight: true,
        weeklyShowAvg: false,
        weeklyShowDaysOnTarget: false,
        encouragementEnabled: false,
        nudgeEnabled: true,
        nudgeHour: 9,
        nudgeMinute: 30,
      ),
    );

    // State anında güncellenir.
    final state = container.read(widgetSettingsProvider);
    expect(state.showMacros, isFalse);
    expect(state.showWeight, isTrue);
    expect(state.nudgeHour, 9);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('widget_show_macros'), isFalse);
    expect(prefs.getBool('widget_show_water'), isFalse);
    expect(prefs.getBool('widget_show_weight'), isTrue);
    expect(prefs.getBool('widget_weekly_avg'), isFalse);
    expect(prefs.getBool('widget_weekly_target_days'), isFalse);
    expect(prefs.getBool('widget_encouragement'), isFalse);
    expect(prefs.getBool('widget_nudge_enabled'), isTrue);
    expect(prefs.getInt('widget_nudge_hour'), 9);
    expect(prefs.getInt('widget_nudge_minute'), 30);
  });

  test('yeni provider kalıcı değerlerden ayağa kalkar (reload)', () async {
    SharedPreferences.setMockInitialValues({
      'widget_show_macros': false,
      'widget_show_weight': true,
      'widget_weekly_avg': false,
      'widget_nudge_enabled': true,
      'widget_nudge_hour': 8,
      'widget_nudge_minute': 45,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = await loadSettings(container);

    expect(settings.showMacros, isFalse);
    expect(settings.showWater, isTrue); // yazılmayan anahtar → varsayılan
    expect(settings.showWeight, isTrue);
    expect(settings.weeklyShowAvg, isFalse);
    expect(settings.weeklyShowDaysOnTarget, isTrue);
    expect(settings.nudgeEnabled, isTrue);
    expect((settings.nudgeHour, settings.nudgeMinute), (8, 45));
  });

  test('copyWith yalnızca verilen alanları değiştirir', () {
    const base = WidgetSettings();
    final updated = base.copyWith(showWeight: true, nudgeHour: 7);
    expect(updated.showWeight, isTrue);
    expect(updated.nudgeHour, 7);
    expect(updated.showMacros, base.showMacros);
    expect(updated.nudgeMinute, base.nudgeMinute);
  });
}

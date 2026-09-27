import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/widget_settings.dart';

/// `DailyWidgetProvider.ACTION_REFRESH` ile aynı değer olmalıdır
/// (`android/app/src/main/kotlin/.../widget/DailyWidgetProvider.kt`).
const String kDailyWidgetRefreshAction = 'com.calorix.app.action.WIDGET_REFRESH';

/// Ana ekran widget ayarları diyaloğu.
///
/// Bildirim diyaloğunun aksine tamamen cihaza lokaldir (SharedPreferences);
/// Supabase'e hiçbir şey yazılmaz. Her anahtar değişir değişmez kalıcıya
/// alınır — ayrı bir "Kaydet" akışı yoktur. Widget metinleri (teşvik, nudge)
/// native taraf tarafından aynı SharedPreferences anahtarlarından okunur.
class WidgetSettingsDialog extends ConsumerWidget {
  const WidgetSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: const WidgetSettingsDialog(),
      ),
    );
  }

  /// Deep link (`calorix://widget/settings`) ile gelindiğinde diyaloğu açar.
  ///
  /// Ana ekran widget'ındaki ayarlar düğmesi bu yolu kullanır; kullanıcı
  /// uygulamayı açmadan görünürlük ayarlarına ulaşır. [navigatorKey] GoRouter
  /// üzerinden ayarlar sayfasına gider, oradan diyalog açılır.
  static Future<void> openFromDeepLink(WidgetRef ref) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return; // Router henüz hazır değil.
    // Widget ayarları ayarlar sayfasındaki bir kart; önce oraya git, sonra
    // diyaloğu aç (kullanıcı arka planında değil, uygulama içinde).
    ref.read(appRouterProvider).go(AppRoutes.settings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) unawaited(show(ctx));
    });
  }

  /// Değişikliği anında kalıcıya al — provider durumu günceller, ardından
  /// native widget'lara `HomeWidget.updateWidget` ile tazeleme yayını yapılır
  /// (Ayar değişimi bir sonraki 30 dk'lık periyodu beklemeden yansısın).
  void _update(WidgetRef ref, WidgetSettings settings) {
    final notifier = ref.read(widgetSettingsProvider.notifier);
    // Yazma tamamlanmadan yayın yapılırsa native taraf eski değerleri okuyabilir;
    // bu yüzden önce `update` bitir, sonra tazeleme yayını gönder.
    unawaited(
      notifier.update(settings).then(
            (_) => HomeWidget.updateWidget(
              name: 'CaloriXWidgetRefresh',
              iOSName: 'CaloriXWidgetRefresh',
              androidName: kDailyWidgetRefreshAction,
            ),
          ),
    );
  }

  /// HH:mm — baştaki sıfırlarla (örn. 20:05).
  String _formatTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(BuildContext context, WidgetRef ref) async {
    final current = ref.read(widgetSettingsProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: current.nudgeHour, minute: current.nudgeMinute),
    );
    // Saat seçici `await` sırasında kapatılabilir; `WidgetRef` dispose
    // olmuşsa kullanımı "Bad state: Cannot use ref after the widget was
    // disposed" fırlatır (ekran çöker).
    if (picked == null || !context.mounted) return;
    _update(
      ref,
      current.copyWith(nudgeHour: picked.hour, nudgeMinute: picked.minute),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(widgetSettingsProvider);
    final bodySmall = Theme.of(context).textTheme.bodySmall;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.widgets.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('settings.widgets.desc'.tr(), style: bodySmall),
          const SizedBox(height: 16),

          // ---- Günlük widget satırları ----
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.widgets.showMacros'.tr()),
            value: settings.showMacros,
            onChanged: (v) =>
                _update(ref, settings.copyWith(showMacros: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.widgets.showWater'.tr()),
            value: settings.showWater,
            onChanged: (v) =>
                _update(ref, settings.copyWith(showWater: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.widgets.showWeight'.tr()),
            value: settings.showWeight,
            onChanged: (v) =>
                _update(ref, settings.copyWith(showWeight: v)),
          ),
          const Divider(height: 32),

          // ---- Haftalık widget ----
          Text('settings.widgets.weeklyTitle'.tr(),
              style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.widgets.showAvg'.tr()),
            value: settings.weeklyShowAvg,
            onChanged: (v) =>
                _update(ref, settings.copyWith(weeklyShowAvg: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.widgets.showOnTarget'.tr()),
            value: settings.weeklyShowDaysOnTarget,
            onChanged: (v) =>
                _update(ref, settings.copyWith(weeklyShowDaysOnTarget: v)),
          ),
          const Divider(height: 32),

          // ---- Teşvik: kayıt yokken widget'ta mesaj göster ----
          Text('settings.widgets.encouragementTitle'.tr(),
              style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.widgets.encouragement'.tr()),
            value: settings.encouragementEnabled,
            onChanged: (v) =>
                _update(ref, settings.copyWith(encouragementEnabled: v)),
          ),
          const Divider(height: 32),

          // ---- Günlük kayıt hatırlatıcısı (nudge) ----
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.widgets.nudgeTitle'.tr()),
            value: settings.nudgeEnabled,
            onChanged: (v) =>
                _update(ref, settings.copyWith(nudgeEnabled: v)),
          ),
          if (settings.nudgeEnabled) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('settings.widgets.nudgeTime'.tr()),
              trailing: Text(
                _formatTime(settings.nudgeHour, settings.nudgeMinute),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              onTap: () => _pickTime(context, ref),
            ),
            Text('settings.widgets.nudgeDesc'.tr(), style: bodySmall),
          ],
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }
}

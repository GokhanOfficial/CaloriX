/// Bildirim ayarları ekranındaki **sunucu tarafı** (`notification_preferences`)
/// tercihler bölümü (A4r7, ürün kararı 2-A).
///
/// ## Kapsam ve öncelik
///
/// Bu bölüm **push/e-posta kanallarını** ve bunların **saat/aralık**
/// ayarlarını yönetir — yani `check-reminders` cron'unun üretip
/// `send-notification`'ın gönderdiği kanalları. Öğün hatırlatıcıları
/// **cihazda** (`ReminderSettings`) kalır ve burada yer almaz; bu, aynı
/// ayar ekranında iki kaynağın **birbirini tamamlaması** (biri push/e-posta,
/// diğeri yerel zamanlama) prensibidir.
///
/// ## Sunucu tarafı "sessizce kapalı" davranışının giderilmesi
///
/// `check-reminders` (`water`/`daily_log`/`weekly_summary`) yalnızca
/// **tercih satırı varsa ve push/e-posta açıksa** gönderir. Tablo boşken bu
/// üç tip sessizce kapanır. Bu ekran, satırı **ilk açılışta varsayılanlarla
/// doldurup** kaydeder, böylece "hangi tip istiyorum" ayrımı kullanıcıya
/// verilir ve varsayılan "push açık" davranışı geri kazanılır.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../data/repositories/notification_preferences_repository.dart';

/// Sunucu hatırlatıcıları bölümü — [prefs] durum, [onChanged] güncelleme.
///
/// Dört tip listelenir: `water`, `daily_log`, `weekly_summary`,
/// `goal_achieved`. `weigh_in` **burada gösterilmez** — onun kaynağı profil
/// sıklığıdır (`profiles.weigh_in_frequency_days`) ve `check-reminders`
/// profil varsayılanını kullanır; iki yerde ayrı ayrı ayar çift
/// doğruluk kaynağı olurdu (A4r3'ün dersi).
class ServerNotificationPreferencesSection extends StatelessWidget {
  const ServerNotificationPreferencesSection({
    super.key,
    required this.prefs,
    required this.onChanged,
  });

  final Map<ServerNotificationType, NotificationPreference> prefs;
  final void Function(
    ServerNotificationType type,
    NotificationPreference Function(NotificationPreference) update,
  )
  onChanged;

  /// Görünecek tipler ve çeviri anahtarları.
  static const _visible = <ServerNotificationType, String>{
    ServerNotificationType.water: 'settings.notifications.server.water',
    ServerNotificationType.dailyLog: 'settings.notifications.server.dailyLog',
    ServerNotificationType.weeklySummary:
        'settings.notifications.server.weeklySummary',
    ServerNotificationType.goalAchieved:
        'settings.notifications.server.goalAchieved',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in _visible.entries) ...[
          _PreferenceCard(
            title: entry.value.tr(),
            pref: prefs[entry.key] ?? defaultServerPreference(entry.key),
            onChanged: (update) => onChanged(entry.key, update),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Bir sunucu tercihini **tek alanlı** kopyalar — Dart'ın `copyWith`'inden
/// farklı olarak hepsi `non-null` (varsayılan `?? p.x`).
NotificationPreference copyPreference(
  NotificationPreference p, {
  bool? pushEnabled,
  bool? emailEnabled,
  int? startHour,
  int? endHour,
  int? intervalHours,
  int? summaryDay,
  int? summaryHour,
}) => NotificationPreference(
  type: p.type,
  pushEnabled: pushEnabled ?? p.pushEnabled,
  emailEnabled: emailEnabled ?? p.emailEnabled,
  startHour: startHour ?? p.startHour,
  endHour: endHour ?? p.endHour,
  intervalHours: intervalHours ?? p.intervalHours,
  summaryDay: summaryDay ?? p.summaryDay,
  summaryHour: summaryHour ?? p.summaryHour,
);

/// Tek sunucu tercihi kartı — push/e-posta anahtarı + tip-özgü zamanlama.
class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.title,
    required this.pref,
    required this.onChanged,
  });

  final String title;
  final NotificationPreference pref;
  final void Function(NotificationPreference Function(NotificationPreference))
  onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                _ChannelChip(
                  label: 'notificationTypes.push'.tr(),
                  value: pref.pushEnabled,
                  onChanged: (v) =>
                      onChanged((p) => copyPreference(p, pushEnabled: v)),
                ),
                const SizedBox(width: 8),
                _ChannelChip(
                  label: 'notificationTypes.email'.tr(),
                  value: pref.emailEnabled,
                  onChanged: (v) =>
                      onChanged((p) => copyPreference(p, emailEnabled: v)),
                ),
              ],
            ),
            // `goal_achieved` sunucuda zamanlamasız gönderilir
            // (`check-reminders` saat kontrolü yapmaz), `daily_log` ise
            // **sabit 18:00**'de gider (`:414 normalizedHour === 18`) —
            // ikisine de saat alanı göstermek yanlış bir vaat olurdu.
            if (pref.type == ServerNotificationType.water)
              _HourRangeFields(pref: pref, onChanged: onChanged),
            if (pref.type == ServerNotificationType.weeklySummary)
              _SummaryFields(pref: pref, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Kanal anahtarı (push/e-posta) — kompakt `FilterChip`.
class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: Theme.of(context).textTheme.bodySmall),
      selected: value,
      onSelected: onChanged,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// 0..23 saat seçenekleri — `water`/`weekly_summary` alanlarında ortak.
List<DropdownMenuItem<int>> _hourItems(TextStyle? style) => [
  for (var h = 0; h < 24; h++)
    DropdownMenuItem(
      value: h,
      child: Text(h.toString().padLeft(2, '0'), style: style),
    ),
];

/// `water` — saat aralığı (`start_hour`/`end_hour`) + aralık saati
/// (`interval_hours`, DB CHECK 1..24).
class _HourRangeFields extends StatelessWidget {
  const _HourRangeFields({required this.pref, required this.onChanged});

  final NotificationPreference pref;
  final void Function(NotificationPreference Function(NotificationPreference))
  onChanged;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: pref.startHour,
                decoration: InputDecoration(
                  labelText: 'settings.notifications.server.startHour'.tr(),
                  isDense: true,
                ),
                items: _hourItems(style),
                onChanged: (v) {
                  if (v == null) return;
                  onChanged((p) => copyPreference(p, startHour: v));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: pref.endHour,
                decoration: InputDecoration(
                  labelText: 'settings.notifications.server.endHour'.tr(),
                  isDense: true,
                ),
                items: _hourItems(style),
                onChanged: (v) {
                  if (v == null) return;
                  onChanged((p) => copyPreference(p, endHour: v));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: pref.intervalHours,
                decoration: InputDecoration(
                  labelText: 'settings.notifications.server.intervalHours'.tr(),
                  isDense: true,
                ),
                items: [
                  for (final h in const [1, 2, 3, 4, 6, 8, 12, 24])
                    DropdownMenuItem(
                      value: h,
                      child: Text('$h', style: style),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  onChanged((p) => copyPreference(p, intervalHours: v));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// `weekly_summary` — gün (`summary_day`, 0=Pazar..6=Cumartesi) + saat
/// (`summary_hour`). Sunucudaki `weekday` diziniyle birebir aynıdır
/// (`check-reminders/helpers.ts:70-78` `WEEKDAY_INDEX`).
class _SummaryFields extends StatelessWidget {
  /// Haftanın **Pazartesi** günü olan sabit tarih (`weekday == 1`).
  ///
  /// Etiketler `DateFormat.E` ile **yerelleştirilmiş** gün adı üretmek için
  /// gerçek bir `DateTime` gerekir. A4r7'in kullandığı `2024-01-07`
  /// **Pazar**dır (`DateTime(2024, 1, 7).weekday == 7`) ve tüm liste bir gün
  /// kaymış gösteriyordu (`Cmt → Paz`).
  ///
  /// ⚠️ **Referans tarihi gözle seçmeyin, ölçün.** Ölçüm (A4r7b,
  /// 2026-09-28, 12 dil): `2024-01-08` **Pazartesi**'dir ve `DateFormat.E`
  /// bütün dillerde doğru kısaltmayı verir:
  ///
  /// ```text
  /// tr Pzt · en Mon · de Mo · fr lun. · es lun · ar الاثنين
  /// zh 周一 · ja 月 · ko 월 · pt seg. · it lun · ru пн
  /// ```
  ///
  /// `2024-01-14` de "pazartesi gibi" görünüyor ama ölçümde **Pazar**
  /// (`en Sun`, `tr Paz`) çıktı — yani ilk denemede liste ters kaydı.
  /// `2024-01-01` de Pazartesi'dir (`tr Pzt`, `en Mon`) ve bir hafta daha
  /// eski olduğu için daha az kafa karıştırıcıdır; her ikisi de `weekday == 1`.
  static final _monday = DateTime(2024, 1, 8);

  const _SummaryFields({required this.pref, required this.onChanged});

  final NotificationPreference pref;
  final void Function(NotificationPreference Function(NotificationPreference))
  onChanged;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: pref.summaryDay,
                decoration: InputDecoration(
                  labelText: 'settings.notifications.server.summaryDay'.tr(),
                  isDense: true,
                ),
                // Sunucu `0 = Pazar` diye **kendi** dizinini kullanıyor
                // (`check-reminders/helpers.ts:70-78` `WEEKDAY_INDEX`:
                // `{Sun:0, Mon:1, …, Sat:6}`). Dart'ın `DateTime.weekday`
                // dizini ise `1 = Pazartesi, 7 = Pazar` → **ters yönde**.
                //
                // ⭐ Ölçülmüş hata (A4r7b, 2026-09-28): A4r7 burada
                // `DateTime(2024, 1, 7)` referansını kullanıyordu ve bu tarih
                // **Pazar**dır (`weekday == 7`). Sonuç: liste `Cmt → Paz`
                // sırasını gösteriyordu ve `value` doğru olsa bile **etiket
                // yanlış güne** işaret ediyordu → kullanıcı ekranda "Pzt"
                // gördüğü halde `summary_day = 0` yazılıyor, sunucu özeti
                // **Pazar** gününe gönderiyordu (ve tersi).
                //
                // Doğru: `_monday = 2024-01-08` (Pazartesi, 12 dilde ölçüldü) ve
                // `value = (i + 1) % 7` — Pzt=1 … Cmt=6, Paz=0.
                items: [
                  for (var i = 0; i < 7; i++)
                    DropdownMenuItem(
                      // `i = 0` Pazartesi → sunucuda 1 … `i = 5` Cumartesi → 6,
                      // `i = 6` Pazar → **0** (`(6 + 1) % 7`). Sıralama listede
                      // Pzt'den Paz'a doğrudur (takvim alışkanlığı), değerler
                      // `WEEKDAY_INDEX` dizinindedir.
                      value: (i + 1) % 7,
                      child: Text(
                        DateFormat.E(context.locale.languageCode)
                            .format(_monday.add(Duration(days: i))),
                        style: style,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  onChanged((p) => copyPreference(p, summaryDay: v));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: pref.summaryHour,
                decoration: InputDecoration(
                  labelText: 'settings.notifications.server.summaryHour'.tr(),
                  isDense: true,
                ),
                items: _hourItems(style),
                onChanged: (v) {
                  if (v == null) return;
                  onChanged((p) => copyPreference(p, summaryHour: v));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

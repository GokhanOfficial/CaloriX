import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/notifications/meal_reminder.dart';
import '../../../core/notifications/reminder_settings.dart';
import '../../../data/models/profile.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/profile_repository.dart';

/// Bildirim ayarları diyaloğu — web `saveNotifications` parity.
///
/// Profil seviyesi anahtarlar yazılır: push/email master, tartılma sıklığı,
/// makro otomatik yeniden hesap. Tür bazlı `notification_preferences`
/// tablosu Faz 5'te (bildirim zamanlayıcı) ele alınır.
class NotificationsDialog extends ConsumerStatefulWidget {
  const NotificationsDialog({super.key, this.profile});

  final Profile? profile;

  static Future<void> show(
      BuildContext context, WidgetRef ref, Profile? profile) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: NotificationsDialog(profile: profile),
      ),
    );
  }

  @override
  ConsumerState<NotificationsDialog> createState() =>
      _NotificationsDialogState();
}

class _NotificationsDialogState extends ConsumerState<NotificationsDialog> {
  late bool _push = widget.profile?.pushNotificationsEnabled ?? true;
  late bool _email = widget.profile?.emailNotificationsEnabled ?? true;
  late final TextEditingController _frequency = TextEditingController(
      text: (widget.profile?.weighInFrequencyDays ?? 7).toString());
  late bool _autoRecalc = widget.profile?.autoRecalculateMacros ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _frequency.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileRepositoryProvider).update(user.id, {
        'push_notifications_enabled': _push,
        'email_notifications_enabled': _email,
        'weigh_in_frequency_days':
            int.tryParse(_frequency.text.trim()) ?? 7,
        'auto_recalculate_macros': _autoRecalc,
      });
      ref.invalidate(profileProvider);
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.settingsSaved'.tr())),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.error'.tr())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(MealType meal) async {
    final reminder = ref.read(reminderSettingsProvider).meals[meal]!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminder.hour, minute: reminder.minute),
    );
    if (picked == null) return;
    await ref
        .read(reminderSettingsProvider.notifier)
        .setTime(meal, picked.hour, picked.minute);
  }

  String _formatTime(MealReminder reminder) =>
      '${reminder.hour.toString().padLeft(2, '0')}:'
      '${reminder.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final reminder = ref.watch(reminderSettingsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.notifications.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('settings.notifications.desc'.tr(),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.notifications.push'.tr()),
            value: _push,
            onChanged: (v) => setState(() => _push = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.notifications.email'.tr()),
            value: _email,
            onChanged: (v) => setState(() => _email = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _frequency,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'settings.notifications.weighInFrequency'.tr(),
              suffixText: 'settings.notifications.days'.tr(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.notifications.autoRecalculate'.tr()),
            value: _autoRecalc,
            onChanged: (v) => setState(() => _autoRecalc = v),
          ),
          const Divider(height: 32),
          Text('settings.notifications.reminderTitle'.tr(),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            kIsWeb
                ? 'settings.notifications.webOnlyInApp'.tr()
                : 'settings.notifications.reminderDesc'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final meal in reminderMeals)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(meal.emoji,
                  style: Theme.of(context).textTheme.titleMedium),
              title: Text('meals.${meal.name}'.tr()),
              subtitle: Text(
                _formatTime(reminder.meals[meal]!),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              trailing: Switch(
                value: reminder.meals[meal]!.enabled,
                onChanged: (v) =>
                    ref.read(reminderSettingsProvider.notifier).setEnabled(meal, v),
              ),
              onTap: () => _pickTime(meal),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text('common.close'.tr()),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('common.save'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

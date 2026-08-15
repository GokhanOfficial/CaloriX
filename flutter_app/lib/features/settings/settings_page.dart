import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/camera_preference.dart';
import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/profile_repository.dart';
import 'widgets/goals_dialog.dart';
import 'widgets/notifications_dialog.dart';
import 'widgets/password_dialog.dart';
import 'widgets/personal_info_dialog.dart';
import 'widgets/transfer_dialogs.dart';

/// Ayarlar — web `SettingsPage.tsx` karşılığı.
///
/// Bölümler: Profil / Uygulama / Veri / Hesap / Hakkında.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.valueOrNull;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Görünüm: tema (web: ayrı kart) ----
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: Text('settings.darkTheme'.tr()),
              value: themeMode == AppThemeMode.dark,
              onChanged: (dark) => ref
                  .read(themeModeProvider.notifier)
                  .setMode(dark ? AppThemeMode.dark : AppThemeMode.light),
            ),
          ),
          const SizedBox(height: 20),

          // ---- Profil ----
          _SectionHeader('settings.sections.profile'.tr()),
          Card(
            child: Column(
              children: [
                _Tile(
                  icon: Icons.person_outline,
                  title: 'settings.items.personalInfo'.tr(),
                  subtitle: _personalInfoDesc(profile),
                  onTap: () => PersonalInfoDialog.show(context, ref, profile),
                ),
                const Divider(height: 1),
                _Tile(
                  icon: Icons.track_changes_outlined,
                  title: 'settings.items.goals'.tr(),
                  subtitle: _goalsDesc(profile),
                  onTap: () => GoalsDialog.show(context, ref, profile),
                ),
                const Divider(height: 1),
                _Tile(
                  icon: Icons.notifications_outlined,
                  title: 'settings.items.notifications'.tr(),
                  subtitle: _notificationsDesc(context, profile),
                  onTap: () => NotificationsDialog.show(context, ref, profile),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---- Uygulama ----
          _SectionHeader('settings.sections.app'.tr()),
          Card(
            child: Column(
              children: [
                const _LanguageTile(),
                const Divider(height: 1),
                const _CameraTile(),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---- Veri ----
          _SectionHeader('settings.sections.data'.tr()),
          Card(
            child: Column(
              children: [
                _Tile(
                  icon: Icons.upload_outlined,
                  title: 'settings.items.exportData'.tr(),
                  subtitle: 'settings.items.exportDesc'.tr(),
                  onTap: () => TransferDialogs.export(context, ref),
                ),
                const Divider(height: 1),
                _Tile(
                  icon: Icons.download_outlined,
                  title: 'settings.items.importData'.tr(),
                  subtitle: 'settings.items.importDesc'.tr(),
                  onTap: () => TransferDialogs.import(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---- Hesap ----
          _SectionHeader('settings.sections.account'.tr()),
          Card(
            child: Column(
              children: [
                _Tile(
                  icon: Icons.lock_outline,
                  title: 'settings.items.changePassword'.tr(),
                  subtitle: 'settings.items.changePasswordDesc'.tr(),
                  onTap: () => PasswordDialog.show(context, ref),
                ),
                const Divider(height: 1),
                _Tile(
                  icon: Icons.logout,
                  title: 'settings.items.signOut'.tr(),
                  subtitle: 'settings.items.signOutDesc'.tr(),
                  iconColor: AppColors.destructive,
                  onTap: () => _signOut(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---- Hakkında ----
          _SectionHeader('settings.sections.about'.tr()),
          Card(
            child: _Tile(
              icon: Icons.info_outline,
              title: 'settings.items.aboutApp'.tr(),
              subtitle:
                  '${'common.version'.tr()} ${AppConstants.appVersion}',
              onTap: () => context.push(AppRoutes.about),
            ),
          ),
          const SizedBox(height: 20),

          // ---- Sağlık uyarısı (web: warning-tinted kart) ----
          Card(
            color: AppColors.warning.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'common.healthDisclaimer'.tr(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Web: `{display_name||noName} • {height_cm||-} cm • {current_weight_kg||-} kg`
  String _personalInfoDesc(Profile? p) {
    final name = (p?.displayName?.isNotEmpty ?? false)
        ? p!.displayName!
        : (p?.email ?? '-');
    final h = p?.heightCm?.toStringAsFixed(0) ?? '-';
    final w = p?.currentWeightKg?.toStringAsFixed(1) ?? '-';
    return '$name • $h cm • $w kg';
  }

  // Web: `{cal||-} kcal • P:..g K:..g Y:..g`
  String _goalsDesc(Profile? p) {
    final cal = p?.dailyCalorieTarget?.toStringAsFixed(0) ?? '-';
    final pr = p?.proteinTargetG?.toStringAsFixed(0) ?? '-';
    final cb = p?.carbsTargetG?.toStringAsFixed(0) ?? '-';
    final ft = p?.fatTargetG?.toStringAsFixed(0) ?? '-';
    return '$cal kcal • P:${pr}g K:${cb}g Y:${ft}g';
  }

  // Web: `{push?active:inactive} • {email?active:inactive}`
  String _notificationsDesc(BuildContext context, Profile? p) {
    final active = 'settings.active'.tr();
    final inactive = 'settings.inactive'.tr();
    final push = (p?.pushNotificationsEnabled ?? false) ? active : inactive;
    final email = (p?.emailNotificationsEnabled ?? false) ? active : inactive;
    return '$push • $email';
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authRepositoryProvider).signOut();
    // Router redirect (authState) /auth'a yönlendirir.
  }
}

/// Bölüm başlığı (web: muted küçük başlık).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

/// ListTile + chevron satırı (web: section item row).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Dil seçici — easy_localization `setLocale` (12 dil).
class _LanguageTile extends ConsumerWidget {
  const _LanguageTile();

  static const _names = <String, String>{
    'tr': 'Türkçe',
    'en': 'English',
    'de': 'Deutsch',
    'es': 'Español',
    'fr': 'Français',
    'it': 'Italiano',
    'pt': 'Português',
    'ru': 'Русский',
    'ar': 'العربية',
    'ja': '日本語',
    'ko': '한국어',
    'zh': '中文',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = context.locale.languageCode;
    return ListTile(
      leading: const Icon(Icons.language_outlined),
      title: Text('settings.language'.tr()),
      subtitle: Text(_names[current] ?? current),
      trailing: DropdownButton<String>(
        value: _names.containsKey(current) ? current : 'en',
        underline: const SizedBox.shrink(),
        onChanged: (code) {
          if (code != null) context.setLocale(Locale(code));
        },
        items: [
          for (final e in _names.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
      ),
      onTap: () {},
    );
  }
}

/// Varsayılan kamera tercihi (Faz 4'te tüketilir).
class _CameraTile extends ConsumerWidget {
  const _CameraTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pref = ref.watch(cameraPreferenceProvider);
    return ListTile(
      leading: const Icon(Icons.photo_camera_outlined),
      title: Text('settings.camera.title'.tr()),
      subtitle: Text(pref == CameraPreference.inApp
          ? 'settings.camera.inApp'.tr()
          : 'settings.camera.native'.tr()),
      trailing: SegmentedButton<CameraPreference>(
        segments: [
          ButtonSegment(
            value: CameraPreference.inApp,
            label: Text('settings.camera.inApp'.tr()),
          ),
          ButtonSegment(
            value: CameraPreference.native,
            label: Text('settings.camera.native'.tr()),
          ),
        ],
        selected: {pref},
        onSelectionChanged: (s) => ref
            .read(cameraPreferenceProvider.notifier)
            .setPreference(s.first),
      ),
    );
  }
}

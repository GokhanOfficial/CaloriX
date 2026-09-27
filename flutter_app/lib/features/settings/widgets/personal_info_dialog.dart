import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/calculations.dart';
import '../../../data/models/profile.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/macro_calculator.dart';
import '../../../data/repositories/profile_repository.dart';

/// Kişisel bilgiler diyaloğu — web `SettingsPage` personalInfo diyaloğu parity.
///
/// Kayıtta `autoRecalculateMacros && kilo değiştiyse && birthDate varsa`
/// `calculate-macros` (previous_macros ile) yeniden çağrılır ve hedefler
/// profille birlikte güncellenir.
class PersonalInfoDialog extends ConsumerStatefulWidget {
  const PersonalInfoDialog({super.key, this.profile});

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
        child: PersonalInfoDialog(profile: profile),
      ),
    );
  }

  @override
  ConsumerState<PersonalInfoDialog> createState() =>
      _PersonalInfoDialogState();
}

class _PersonalInfoDialogState extends ConsumerState<PersonalInfoDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile?.displayName ?? '');
  late final TextEditingController _height = TextEditingController(
      text: (widget.profile?.heightCm ?? 170).toStringAsFixed(0));
  late final TextEditingController _weight = TextEditingController(
      text: (widget.profile?.currentWeightKg ?? 70).toStringAsFixed(1));
  late final TextEditingController _target = TextEditingController(
      text: (widget.profile?.targetWeightKg ?? 70).toStringAsFixed(1));

  late Gender _gender =
      Gender.values.asNameMap()[widget.profile?.gender] ?? Gender.other;
  DateTime? _birthDate;
  bool _saving = false;

  static double _parse(String t, double fallback) =>
      double.tryParse(t.trim().replaceAll(',', '.')) ?? fallback;

  /// Fiziksel olarak anlamlı aralıklar — 0/negatif boy kilo BMR, VKİ ve
  /// makro hedeflerini bozuyordu (kilo 0 → BMR negatif, hedef 1200'e düşer).
  static const double _minHeightCm = 50;
  static const double _maxHeightCm = 250;
  static const double _minWeightKg = 20;
  static const double _maxWeightKg = 400;

  static double _clamp(double v, double min, double max) =>
      v.isNaN ? min : v.clamp(min, max);

  double _heightCm() =>
      _clamp(_parse(_height.text, 170), _minHeightCm, _maxHeightCm);

  double _weightKg() =>
      _clamp(_parse(_weight.text, 70), _minWeightKg, _maxWeightKg);

  double _targetWeightKg() =>
      _clamp(_parse(_target.text, 70), _minWeightKg, _maxWeightKg);

  /// Kaydet butonu için aralık kontrolü (sınırsız değer DB'ye yazılmasın).
  bool get _valid {
    final h = _parse(_height.text, double.nan);
    final w = _parse(_weight.text, double.nan);
    final t = _parse(_target.text, double.nan);
    return h >= _minHeightCm &&
        h <= _maxHeightCm &&
        w >= _minWeightKg &&
        w <= _maxWeightKg &&
        t >= _minWeightKg &&
        t <= _maxWeightKg;
  }

  @override
  void initState() {
    super.initState();
    final bd = widget.profile?.birthDate;
    if (bd != null) _birthDate = DateTime.tryParse(bd);
  }

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    _weight.dispose();
    _target.dispose();
    super.dispose();
  }

  double get _bmi => Calculations.bmi(_weightKg(), _heightCm());

  Color _bmiColor(String color) => switch (color) {
        'success' => AppColors.success,
        'warning' => AppColors.warning,
        'destructive' => AppColors.destructive,
        _ => AppColors.info,
      };

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final p = widget.profile;
    if (!_valid) return;
    final newWeight = _weightKg();
    final heightCm = _heightCm();
    final targetWeightKg = _targetWeightKg();

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updates = <String, dynamic>{
        'display_name': _name.text.trim(),
        'birth_date': _birthDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_birthDate!),
        'gender': _gender.name,
        'height_cm': heightCm,
        'current_weight_kg': newWeight,
        'target_weight_kg': targetWeightKg,
      };

      // Otomatik makro yeniden hesaplama (web savePersonalInfo parity).
      final autoRecalc = p?.autoRecalculateMacros ?? false;
      final weightChanged =
          p != null && p.currentWeightKg != newWeight;
      if (autoRecalc && weightChanged && _birthDate != null) {
        try {
          final goals = await ref.read(macroCalculatorProvider).calculate(
                age: Calculations.age(_birthDate!),
                gender: _gender,
                heightCm: heightCm,
                currentWeightKg: newWeight,
                targetWeightKg: targetWeightKg,
                activityLevel:
                    ActivityLevel.values.asNameMap()[p.activityLevel] ??
                        ActivityLevel.moderate,
                goal: Goal.values.asNameMap()[p.goal] ?? Goal.maintain,
                previousMacros: p.dailyCalorieTarget != null
                    ? {
                        'daily_calorie_target': p.dailyCalorieTarget,
                        'protein_target_g': p.proteinTargetG ?? 0,
                        'carbs_target_g': p.carbsTargetG ?? 0,
                        'fat_target_g': p.fatTargetG ?? 0,
                      }
                    : null,
                previousWeightKg: p.currentWeightKg,
              );
          updates.addAll({
            'bmr': goals.bmr,
            'tdee': goals.tdee,
            'daily_calorie_target': goals.calories,
            'protein_target_g': goals.protein,
            'carbs_target_g': goals.carbs,
            'fat_target_g': goals.fat,
          });
        } catch (_) {
          // Hesaplama başarısızsa kişisel bilgiler yine de kaydedilir.
        }
      }

      await ref.read(profileRepositoryProvider).update(user.id, updates);
      ref.invalidate(profileProvider);
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.personalInfoSaved'.tr())),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.error'.tr())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = Calculations.bmiCategory(_bmi);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.personalInfo.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('settings.personalInfo.desc'.tr(),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: 'auth.name'.tr()),
          ),
          const SizedBox(height: 12),
          // Doğum tarihi
          InkWell(
            onTap: _pickBirthDate,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'settings.personalInfo.birthDate'.tr(),
                border: const OutlineInputBorder(),
              ),
              child: Text(
                _birthDate == null
                    ? '-'
                    : DateFormat.yMMMd(context.locale.languageCode)
                        .format(_birthDate!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Cinsiyet
          Text('settings.personalInfo.gender'.tr(),
              style: Theme.of(context).textTheme.labelLarge),
          RadioGroup<Gender>(
            groupValue: _gender,
            onChanged: (g) => setState(() => _gender = g ?? Gender.other),
            child: Row(
              children: [
                for (final g in Gender.values)
                  Expanded(
                    child: RadioListTile<Gender>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(g.labelKey.tr(),
                          style: Theme.of(context).textTheme.bodySmall),
                      value: g,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                  ],
                  decoration: InputDecoration(
                      labelText: 'settings.personalInfo.height'.tr()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                  ],
                  decoration: InputDecoration(
                      labelText: 'settings.personalInfo.weight'.tr()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            decoration: InputDecoration(
                labelText: 'settings.personalInfo.targetWeight'.tr()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          // Canlı VKİ göstergesi (web parity).
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bmiColor(cat.color).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text('settings.personalInfo.bmi'.tr(),
                    style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text(
                  '${_bmi.toStringAsFixed(1)} • ${cat.labelKey.tr()}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: _bmiColor(cat.color),
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text('common.cancel'.tr()),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving || !_valid ? null : _save,
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

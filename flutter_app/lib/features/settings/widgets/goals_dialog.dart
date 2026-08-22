import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/calculations.dart';
import '../../../data/models/profile.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/macro_calculator.dart';
import '../../../data/repositories/profile_repository.dart';

/// Hedefler diyaloğu — web `SettingsPage` goals diyaloğu parity.
///
/// Aktivite/hedef radyo listeleri + AI hesapla butonu (5 alanı doldurur) +
/// 5 sayısal hedef girişi.
class GoalsDialog extends ConsumerStatefulWidget {
  const GoalsDialog({super.key, this.profile});

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
        child: GoalsDialog(profile: profile),
      ),
    );
  }

  @override
  ConsumerState<GoalsDialog> createState() => _GoalsDialogState();
}

class _GoalsDialogState extends ConsumerState<GoalsDialog> {
  late final TextEditingController _calories = TextEditingController(
      text: (widget.profile?.dailyCalorieTarget ??
              AppConstants.defaultCalories)
          .toStringAsFixed(0));
  late final TextEditingController _water = TextEditingController(
      text: (widget.profile?.dailyWaterTargetMl ?? AppConstants.defaultWater)
          .toStringAsFixed(0));
  late final TextEditingController _protein = TextEditingController(
      text: (widget.profile?.proteinTargetG ?? AppConstants.defaultProtein)
          .toStringAsFixed(0));
  late final TextEditingController _carbs = TextEditingController(
      text: (widget.profile?.carbsTargetG ?? AppConstants.defaultCarbs)
          .toStringAsFixed(0));
  late final TextEditingController _fat = TextEditingController(
      text: (widget.profile?.fatTargetG ?? AppConstants.defaultFat)
          .toStringAsFixed(0));

  late ActivityLevel _activity =
      ActivityLevel.values.asNameMap()[widget.profile?.activityLevel] ??
          ActivityLevel.moderate;
  late Goal _goal =
      Goal.values.asNameMap()[widget.profile?.goal] ?? Goal.maintain;

  bool _aiLoading = false;
  bool _saving = false;

  // DB sütunları (daily_calorie_target, *_target_g, daily_water_target_ml)
  // INTEGER — double gönderince Postgres `22P02 invalid input syntax for type
  // integer: "2500.0"` → 400. Bu yüzden int (round) döndür.
  static int _parse(String t, num fallback) =>
      (double.tryParse(t.trim().replaceAll(',', '.')) ?? fallback.toDouble())
          .round();

  @override
  void dispose() {
    _calories.dispose();
    _water.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  /// Web: calculate-macros çağırıp 5 alanı doldurur.
  Future<void> _aiCalculate() async {
    final p = widget.profile;
    setState(() => _aiLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final birthDate =
          p?.birthDate != null ? DateTime.tryParse(p!.birthDate!) : null;
      final goals = await ref.read(macroCalculatorProvider).calculate(
            age: birthDate != null ? Calculations.age(birthDate) : 30,
            gender:
                Gender.values.asNameMap()[p?.gender] ?? Gender.other,
            heightCm: p?.heightCm ?? 170,
            currentWeightKg: p?.currentWeightKg ?? 70,
            targetWeightKg: p?.targetWeightKg ?? 70,
            activityLevel: _activity,
            goal: _goal,
          );
      setState(() {
        _calories.text = goals.calories.toString();
        _water.text = goals.waterTarget.toString();
        _protein.text = goals.protein.toString();
        _carbs.text = goals.carbs.toString();
        _fat.text = goals.fat.toString();
      });
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.aiSuccess'.tr())),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.error'.tr())),
      );
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileRepositoryProvider).update(user.id, {
        'activity_level': _activity.name,
        'goal': _goal.name,
        'daily_calorie_target':
            _parse(_calories.text, AppConstants.defaultCalories),
        'protein_target_g':
            _parse(_protein.text, AppConstants.defaultProtein),
        'carbs_target_g': _parse(_carbs.text, AppConstants.defaultCarbs),
        'fat_target_g': _parse(_fat.text, AppConstants.defaultFat),
        'daily_water_target_ml':
            _parse(_water.text, AppConstants.defaultWater),
      });
      ref.invalidate(profileProvider);
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.goalsSaved'.tr())),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.goals.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('settings.goals.desc'.tr(),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),

          // Aktivite seviyesi
          Text('settings.goals.activityLevel'.tr(),
              style: Theme.of(context).textTheme.labelLarge),
          RadioGroup<ActivityLevel>(
            groupValue: _activity,
            onChanged: (a) =>
                setState(() => _activity = a ?? ActivityLevel.moderate),
            child: Column(
              children: [
                for (final a in ActivityLevel.values)
                  RadioListTile<ActivityLevel>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.labelKey.tr()),
                    value: a,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Hedef
          Text('settings.goals.goalType'.tr(),
              style: Theme.of(context).textTheme.labelLarge),
          RadioGroup<Goal>(
            groupValue: _goal,
            onChanged: (g) => setState(() => _goal = g ?? Goal.maintain),
            child: Column(
              children: [
                for (final g in Goal.values)
                  RadioListTile<Goal>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(g.labelKey.tr()),
                    value: g,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // AI hesapla
          OutlinedButton.icon(
            onPressed: _aiLoading ? null : _aiCalculate,
            icon: _aiLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_aiLoading
                ? 'settings.goals.calculating'.tr()
                : 'settings.goals.aiCalculate'.tr()),
          ),
          const SizedBox(height: 16),

          _numField(_calories, 'settings.goals.calories'.tr()),
          const SizedBox(height: 12),
          _numField(_water, 'settings.goals.water'.tr(), step: true),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _numField(_protein, 'settings.goals.protein'.tr())),
              const SizedBox(width: 12),
              Expanded(child: _numField(_carbs, 'settings.goals.carbs'.tr())),
              const SizedBox(width: 12),
              Expanded(child: _numField(_fat, 'settings.goals.fat'.tr())),
            ],
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

  Widget _numField(TextEditingController c, String label, {bool step = false}) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label),
    );
  }
}

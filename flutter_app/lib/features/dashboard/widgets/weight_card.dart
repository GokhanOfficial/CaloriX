import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/observability/app_logger.dart';
import '../../../data/models/profile.dart';
import '../../../data/models/weight_entry.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/macro_calculator.dart';
import '../../../data/repositories/profile_repository.dart';

/// Kilo kartı — son kayıt + hızlı giriş dialogu (web `Index.tsx` +
/// `AddWeightDialog` karşılığı).
///
/// `auto_recalculate_macros` açıksa ve kilo değiştiyse `calculate-macros`
/// Edge Function ile hedefleri günceller (web `handleWeightSubmit` parity).
class WeightCard extends ConsumerWidget {
  const WeightCard({super.key, this.latestWeight, this.profile});

  final WeightEntry? latestWeight;
  final Profile? profile;

  Future<void> _logWeight(BuildContext context, WidgetRef ref) async {
    // Dialog kendi `State`'i içinde controller'ı yönetir; dışarıda yaratılan
    // controller `dispose` edilmediği için bellek sızıyordu.
    final weight = await showDialog<double>(
      context: context,
      builder: (context) => const _WeightInputDialog(),
    );
    if (weight == null || weight <= 0 || weight > 500 || !context.mounted) {
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final date = ref.read(selectedDateProvider);

    try {
      await ref.read(diaryRepositoryProvider).addWeightEntry(
            user.id,
            weightKg: weight,
            entryDate: formatEntryDate(date),
          );
    } catch (e, s) {
      AppLog.e('Kilo kaydı eklenemedi ($weight kg)', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text('dashboard.errorWeight'.tr())),
      );
      return;
    }

    // Otomatik makro yeniden hesaplama (web handleWeightSubmit parity)
    final p = profile;
    var description = 'dashboard.savedAs'
        .tr(namedArgs: {'weight': weight.toStringAsFixed(1)});
    if (p != null &&
        (p.autoRecalculateMacros ?? false) &&
        weight != p.currentWeightKg &&
        context.mounted) {
      try {
        final goals = await ref.read(macroCalculatorProvider).calculate(
              age: _ageFrom(p.birthDate),
              gender: Gender.values.asNameMap()[p.gender] ?? Gender.other,
              heightCm: p.heightCm ?? 170,
              currentWeightKg: weight,
              targetWeightKg: p.targetWeightKg ?? weight,
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

        await ref.read(profileRepositoryProvider).update(user.id, {
          'current_weight_kg': weight,
          'daily_calorie_target': goals.calories,
          'protein_target_g': goals.protein,
          'carbs_target_g': goals.carbs,
          'fat_target_g': goals.fat,
          'bmr': goals.bmr,
          'tdee': goals.tdee,
        });
        if (goals.explanation != null && goals.explanation!.isNotEmpty) {
          description = goals.explanation!;
        }
      } catch (e, s) {
        // Yeniden hesaplama başarısızsa kilo kaydı yine de geçerli
        // (web parity — catch'te sadece console.error var).
        AppLog.w('Makro otomatik yeniden hesaplanamadı', e, s);
      }
    }

    // Await zinciri (kilo kaydı → makro yeniden hesap → profil güncelle)
    // boyunca widget dispose olabilir. `ref` dispose sonrası kullanılamaz
    // ("Bad state: Cannot use "ref" after the widget was disposed") —
    // invalidate'i atla; `messenger` await öncesi yakalandığı için snackbar
    // yine de güvenle gösterilir.
    if (context.mounted) {
      ref.invalidate(dailyDataProvider);
      ref.invalidate(profileProvider);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('${'dashboard.weightSaved'.tr()} — $description'),
      ),
    );
  }

  /// Web parity: `Math.floor((now - birthDate) / 365.25gün)`, yoksa 30.
  static int _ageFrom(String? birthDate) {
    if (birthDate == null) return 30;
    final parsed = DateTime.tryParse(birthDate);
    if (parsed == null) return 30;
    final days = DateTime.now().difference(parsed).inDays;
    return (days / 365.25).floor();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = latestWeight;

    String subtitle = 'dashboard.recordWeight'.tr();
    if (latest != null) {
      final date = DateTime.tryParse(latest.entryDate);
      if (date != null) {
        final days = DateTime.now().difference(date).inDays;
        // JSON `dashboard.lastWeight` named placeholder `{days}` kullanır;
        // `.tr(args:)` positional `{}` bekler → değiştirme olmaz, literal
        // `{days}` gösterilirdi. `namedArgs` ile doğru substitute edilir.
        subtitle = 'dashboard.lastWeight'.tr(namedArgs: {'days': '$days'});
      }
    }

    return Card(
      child: ListTile(
        leading: const Text('⚖️', style: TextStyle(fontSize: 20)),
        title: Text('dashboard.logWeight'.tr()),
        subtitle: Text(
          latest == null
              ? subtitle
              : '${latest.weightKg.toStringAsFixed(1)} kg — $subtitle',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'dashboard.logWeight'.tr(),
          onPressed: () => _logWeight(context, ref),
        ),
        onTap: () => _logWeight(context, ref),
      ),
    );
  }
}

/// Kilo giriş dialogu — `TextEditingController`'ı kendi `State`'inde tutar
/// (dışarıda yaratılıp bırakılan controller bellek sızdırıyordu).
class _WeightInputDialog extends StatefulWidget {
  const _WeightInputDialog();

  @override
  State<_WeightInputDialog> createState() => _WeightInputDialogState();
}

class _WeightInputDialogState extends State<_WeightInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('dashboard.logWeight'.tr()),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
        ],
        decoration: const InputDecoration(suffixText: 'kg'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            double.tryParse(_controller.text.replaceAll(',', '.')),
          ),
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}

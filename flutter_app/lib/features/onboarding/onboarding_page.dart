import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/calculations.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/macro_calculator.dart';
import '../../data/repositories/profile_repository.dart';

/// Web `OnboardingPage.tsx` karşılığı — 5 adımlı sihirbaz:
/// 1) Kişisel bilgiler  2) Boy/kilo  3) Aktivite  4) Hedef  5) Özet + AI hesaplama
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  static const int totalSteps = 5;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int _step = 1;
  bool _isSaving = false;
  bool _isCalculating = false;
  bool _hasCalculated = false;

  // Form state
  final _nameCtrl = TextEditingController();
  DateTime? _birthDate;
  Gender _gender = Gender.male;
  final _heightCtrl = TextEditingController(text: '170');
  final _weightCtrl = TextEditingController(text: '70');
  final _targetWeightCtrl = TextEditingController(text: '70');
  ActivityLevel _activity = ActivityLevel.moderate;
  Goal _goal = Goal.maintain;

  CalculatedGoals? _goals;
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _targetWeightCtrl.dispose();
    super.dispose();
  }

  double get _height => double.tryParse(_heightCtrl.text) ?? 0;
  double get _weight => double.tryParse(_weightCtrl.text) ?? 0;
  double get _targetWeight => double.tryParse(_targetWeightCtrl.text) ?? 0;

  // ---- doğrulama ---------------------------------------------------------

  bool _validateStep(int step) {
    _errors.clear();
    switch (step) {
      case 1:
        if (_nameCtrl.text.trim().length < 2) {
          _errors['name'] = 'İsim en az 2 karakter olmalı';
        }
        if (_birthDate == null) {
          _errors['birth'] = 'Doğum tarihi gerekli';
        } else {
          final age = Calculations.age(_birthDate!);
          if (age < 13 || age > 120) {
            _errors['birth'] = 'Yaş 13-120 arasında olmalı';
          }
        }
        break;
      case 2:
        if (_height < 50 || _height > 250) {
          _errors['height'] = 'Boy 100-250 cm arasında olmalı';
        }
        if (_weight < 20 || _weight > 400) {
          _errors['weight'] = 'Kilo 30-300 kg arasında olmalı';
        }
        if (_targetWeight < 20 || _targetWeight > 400) {
          _errors['targetWeight'] = 'Hedef kilo 30-300 kg arasında olmalı';
        }
        break;
    }
    setState(() {});
    return _errors.isEmpty;
  }

  // ---- akış --------------------------------------------------------------

  Future<void> _handleNext() async {
    if (!_validateStep(_step)) return;
    final next = _step + 1;
    if (next == OnboardingPage.totalSteps && !_hasCalculated) {
      setState(() => _step = next);
      await _calculate();
    } else {
      setState(() => _step = next.clamp(1, OnboardingPage.totalSteps));
    }
  }

  void _handleBack() {
    if (_step == OnboardingPage.totalSteps) {
      _hasCalculated = false;
      _goals = null;
    }
    setState(() => _step = (_step - 1).clamp(1, OnboardingPage.totalSteps));
  }

  Future<void> _calculate() async {
    if (_birthDate == null) return;
    setState(() {
      _isCalculating = true;
    });

    final calc = ref.read(macroCalculatorProvider);
    try {
      final result = await calc.calculate(
        age: Calculations.age(_birthDate!),
        gender: _gender,
        heightCm: _height,
        currentWeightKg: _weight,
        targetWeightKg: _targetWeight,
        activityLevel: _activity,
        goal: _goal,
      );
      if (!mounted) return;
      setState(() {
        _goals = result;
        _hasCalculated = true;
        _isCalculating = false;
      });
    } catch (_) {
      // Hesaplama başarısız: spinner sonsuza dek sürmesin, özet adımı
      // "Hesaplama Başarısız" durumunu göstersin ve kullanıcı geri
      // dönüp tekrar deneyebilsin.
      if (!mounted) return;
      setState(() {
        _goals = null;
        _hasCalculated = false;
        _isCalculating = false;
      });
    }
  }

  Future<void> _handleComplete() async {
    final user = ref.read(currentUserProvider);
    final goals = _goals;
    final birthDate = _birthDate;
    if (user == null || goals == null || birthDate == null) return;

    setState(() => _isSaving = true);
    final repo = ref.read(profileRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    Profile? updated;
    try {
      updated = await repo.update(user.id, {
        'display_name': _nameCtrl.text.trim(),
        'birth_date': birthDate.toIso8601String().split('T').first,
        'gender': _gender.name,
        'height_cm': _height,
        'current_weight_kg': _weight,
        'target_weight_kg': _targetWeight,
        'activity_level': _activity.name,
        'goal': _goal.name,
        'bmr': goals.bmr,
        'tdee': goals.tdee,
        'daily_calorie_target': goals.calories,
        'protein_target_g': goals.protein,
        'carbs_target_g': goals.carbs,
        'fat_target_g': goals.fat,
        'daily_water_target_ml': goals.waterTarget,
        'onboarding_completed': true,
      });
    } catch (_) {
      // Ağ/DB hatası: `_isSaving` sonsuza dek true kalıp butonu kilitlerdi.
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Profil kaydedilirken bir hata oluştu')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (updated == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Profil kaydedilirken bir hata oluştu')),
      );
      return;
    }

    // Profil provider'ını tazele ve dashboard'a git.
    ref.invalidate(profileProvider);
    context.go(AppRoutes.dashboard);
  }

  // ---- görünüm -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final progress = _step / OnboardingPage.totalSteps;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Text('common.appName'.tr(),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Adım $_step / ${OnboardingPage.totalSteps}',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text('${(progress * 100).round()}%',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _buildStep(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNavButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 1:
        return _stepPersonal();
      case 2:
        return _stepBody();
      case 3:
        return _stepActivity();
      case 4:
        return _stepGoal();
      case 5:
        return _stepSummary();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepHeader(IconData icon, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(subtitle,
              style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ]),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
      ],
    );
  }

  // Adım 1 — Kişisel bilgiler
  Widget _stepPersonal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(Icons.person_outline, 'Sizi Tanıyalım', 'Kişisel Bilgiler'),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: 'İsminiz',
            errorText: _errors['name'],
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickBirthDate,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'settings.personalInfo.birthDate'.tr(),
              errorText: _errors['birth'],
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            child: Text(
              _birthDate == null
                  ? 'Seçiniz'
                  : DateFormat.yMd(context.locale.languageCode)
                      .format(_birthDate!),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('settings.personalInfo.gender'.tr(),
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<Gender>(
          segments: Gender.values
              .map((g) => ButtonSegment(value: g, label: Text(g.labelKey.tr())))
              .toList(),
          selected: {_gender},
          onSelectionChanged: (s) => setState(() => _gender = s.first),
        ),
      ],
    );
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      locale: context.locale,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  // Adım 2 — Boy/kilo
  Widget _stepBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(Icons.straighten, 'Boy ve Kilo', 'Vücut Ölçüleri'),
        _numField(_heightCtrl, 'settings.personalInfo.height'.tr(), 'height'),
        const SizedBox(height: 16),
        _numField(_weightCtrl, 'settings.personalInfo.weight'.tr(), 'weight'),
        const SizedBox(height: 16),
        _numField(_targetWeightCtrl, 'settings.personalInfo.targetWeight'.tr(),
            'targetWeight'),
        if (_weight > 0 && _height > 0) ...[
          const SizedBox(height: 16),
          _bmiBadge(),
        ],
      ],
    );
  }

  Widget _numField(TextEditingController c, String label, String errKey) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      // `double.tryParse` "abc" ve "1e5" gibi girdilerde null döndürür ve
      // alan `0` kabul edilirdi; filtre yalnızca rakut/tek ayraç bırakır.
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, errorText: _errors[errKey]),
    );
  }

  Widget _bmiBadge() {
    final bmi = Calculations.bmi(_weight, _height);
    final cat = Calculations.bmiCategory(bmi);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${'settings.personalInfo.bmi'.tr()}: $bmi — ${cat.labelKey.tr()}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  // Adım 3 — Aktivite
  Widget _stepActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(Icons.directions_run, 'Ne Kadar Aktifsiniz?',
            'settings.goals.activityLevel'.tr()),
        ...ActivityLevel.values.map((lvl) => _radioCard<ActivityLevel>(
              value: lvl,
              group: _activity,
              label: lvl.labelKey.tr(),
              onChanged: (v) => setState(() => _activity = v),
            )),
      ],
    );
  }

  // Adım 4 — Hedef
  Widget _stepGoal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(Icons.flag_outlined, 'Hedefiniz Nedir?',
            'settings.goals.goalType'.tr()),
        ...Goal.values.map((g) => _radioCard<Goal>(
              value: g,
              group: _goal,
              label: g.labelKey.tr(),
              onChanged: (v) => setState(() => _goal = v),
            )),
      ],
    );
  }

  Widget _radioCard<T>({
    required T value,
    required T group,
    required String label,
    required ValueChanged<T> onChanged,
  }) {
    final selected = value == group;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? scheme.primary.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }

  // Adım 5 — Özet + AI
  Widget _stepSummary() {
    if (_isCalculating) {
      return Column(
        children: [
          _stepHeader(Icons.auto_awesome, 'Hedefleriniz Hesaplanıyor...',
              'settings.goals.calculating'.tr()),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: CircularProgressIndicator(),
          ),
        ],
      );
    }

    final goals = _goals;
    if (goals == null) {
      return Column(
        children: [
          _stepHeader(
              Icons.error_outline, 'Hesaplama Başarısız', 'common.error'.tr()),
          Text('Lütfen geri dönüp tekrar deneyin',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(Icons.auto_awesome, 'Hedefleriniz Hazır!',
            goals.usedAi ? 'settings.goals.aiCalculate'.tr() : 'Yerel Hesaplama'),
        if (goals.explanation != null) ...[
          Text(goals.explanation!,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
        ],
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: [
            _goalTile('${goals.calories}', 'settings.goals.calories'.tr()),
            _goalTile('${goals.protein}g', 'settings.goals.protein'.tr()),
            _goalTile('${goals.carbs}g', 'settings.goals.carbs'.tr()),
            _goalTile('${goals.fat}g', 'settings.goals.fat'.tr()),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _infoRow('BMR', '${goals.bmr} kcal'),
              _infoRow('TDEE', '${goals.tdee} kcal'),
              _infoRow('settings.goals.water'.tr(), '${goals.waterTarget} ml'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'common.healthDisclaimer'.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline),
        ),
      ],
    );
  }

  Widget _goalTile(String value, String label) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    final isLast = _step == OnboardingPage.totalSteps;
    return Row(
      children: [
        if (_step > 1)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _handleBack,
              icon: const Icon(Icons.chevron_left),
              label: Text('common.back'.tr()),
            ),
          ),
        if (_step > 1) const SizedBox(width: 12),
        Expanded(
          child: isLast
              ? FilledButton.icon(
                  onPressed:
                      (_isSaving || _isCalculating || _goals == null)
                          ? null
                          : _handleComplete,
                  icon: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text('common.save'.tr()),
                )
              : FilledButton.icon(
                  onPressed: _isCalculating ? null : _handleNext,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('İleri'),
                ),
        ),
      ],
    );
  }
}

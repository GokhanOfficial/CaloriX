import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/diary_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../shared/widgets/date_selector.dart';
import 'widgets/calorie_ring.dart';
import 'widgets/macro_cards.dart';
import 'widgets/meal_section.dart';
import 'widgets/water_tracker.dart';
import 'widgets/weight_card.dart';

/// Günlük özet — web `Index.tsx` karşılığı.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyAsync = ref.watch(dailyDataProvider);
    final profileAsync = ref.watch(profileProvider);

    final profile = profileAsync.valueOrNull;
    final targets = (
      calories:
          profile?.dailyCalorieTarget ?? AppConstants.defaultCalories.toDouble(),
      protein:
          profile?.proteinTargetG ?? AppConstants.defaultProtein.toDouble(),
      carbs: profile?.carbsTargetG ?? AppConstants.defaultCarbs.toDouble(),
      fat: profile?.fatTargetG ?? AppConstants.defaultFat.toDouble(),
      water: profile?.dailyWaterTargetMl ??
          AppConstants.defaultWater.toDouble(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('CaloriX'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'nav.settings'.tr(),
            onPressed: () => context.go(AppRoutes.settings),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dailyDataProvider);
          ref.invalidate(profileProvider);
          await ref.read(dailyDataProvider.future);
        },
        child: dailyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorBody(
            onRetry: () => ref.invalidate(dailyDataProvider),
          ),
          data: (daily) {
            final totals = daily.totals;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const DateSelector(),
                const SizedBox(height: 8),
                Center(
                  child: CalorieRing(
                    consumed: totals.calories,
                    target: targets.calories,
                  ),
                ),
                const SizedBox(height: 16),
                MacroCards(
                  protein: totals.protein,
                  carbs: totals.carbs,
                  fat: totals.fat,
                  proteinTarget: targets.protein,
                  carbsTarget: targets.carbs,
                  fatTarget: targets.fat,
                ),
                const SizedBox(height: 16),
                WaterTracker(
                  current: daily.totalWater,
                  target: targets.water,
                ),
                const SizedBox(height: 16),
                WeightCard(
                  latestWeight: daily.latestWeight,
                  profile: profile,
                ),
                const SizedBox(height: 16),
                MealSections(mealsByType: daily.mealsByType),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoutes.add),
        icon: const Icon(Icons.add),
        label: Text('dashboard.addFood'.tr()),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('common.error'.tr()),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text('common.resend'.tr()),
          ),
        ],
      ),
    );
  }
}

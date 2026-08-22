# Faz 3 — Tıklanabilir Halka/Makro + Per-Macro Analitik + Öğün Satırı Redesign

> Master: `flutter-redesign-master.md`
> Bağımlılık: bağımsız (Faz 1 tema cila ile uyumlu; `app_router.dart`,
> `analytics_page.dart`, dashboard widget'larına dokunur).

## 1. Hedef

- Kalori halkası tıklanabilir → `/analytics`.
- Her makro kartı (P/C/F) tıklanabilir → `/analytics?macro=protein|carbs|fat`.
- `AnalyticsPage` + `/analytics` rotası `focusedMacro` parametre alır;
  seçili makro için yeni per-macro grafik kartı gösterilir (backend
  değişikliği yok — `AnalyticsData.dailyStats` zaten P/C/F içeriyor,
  `analytics_repository.dart:12-34`).
- Öğün satırı kaydır-sil akışı redesign: `confirmDismiss` + undo
  SnackBar + düzenle + açık sil butonu.

## 2. `MacroFocus` Enum (yeni)

`lib/features/analytics/macro_focus.dart`:

```dart
enum MacroFocus {
  protein, carbs, fat;

  static MacroFocus? fromName(String? name) {
    if (name == null) return null;
    return values.firstWhere((m) => m.name == name, orElse: () => values.first);
  }

  String get labelKey => switch (this) {
    MacroFocus.protein => 'settings.goals.protein',
    MacroFocus.carbs => 'settings.goals.carbs',
    MacroFocus.fat => 'settings.goals.fat',
  };

  Color color(ThemeData theme) => switch (this) {
    MacroFocus.protein => AppColors.macroProtein,
    MacroFocus.carbs => AppColors.macroCarbs,
    MacroFocus.fat => AppColors.macroFat,
  };
}
```

## 3. `/analytics` Rotası + `AnalyticsPage` Parametre

### 3.1 Rota
`lib/core/router/app_router.dart:146-149`:
```dart
GoRoute(
  path: AppRoutes.analytics,
  builder: (context, state) {
    final macro = MacroFocus.fromName(state.uri.queryParameters['macro']);
    return AnalyticsPage(focusedMacro: macro);
  },
),
```
`const AnalyticsPage()` → `AnalyticsPage(focusedMacro: macro)` (const
kalkar). `import` `analytics/macro_focus.dart`.

### 3.2 `AnalyticsPage`
`lib/features/analytics/analytics_page.dart:18`:
`const AnalyticsPage({super.key, this.focusedMacro}); final MacroFocus? focusedMacro;`.

`build` ListView'una (`:67-83`) yeni `_FocusedMacroChartCard` ekle —
yalnızca `focusedMacro != null` iken; `_CaloriesChartCard` (`:299-446`)
gösterilmeye devam eder (hem kalori hem makro). Per-macro kartı calories
kartının üstüne konumlandır, `ScrollController` ile ona scroll (vurgu).

### 3.3 `_FocusedMacroChartCard` (yeni widget, analytics_page.dart içinde)

Mevcut `_CaloriesChartCard` (`:299-446`) `fl_chart` LineChart desenini
izle. Tek fark: veri seçici + renk + başlık.
- `spots`: `dailyStats[i]`'den `focusedMacro` seç (protein/carbs/fat) →
  **hedef yüzdesi** `(value / target * 100)`.
- `color`: `focus.color(theme)` (`AppColors.macroProtein/macroCarbs/macroFat`).
- Başlık: `focus.labelKey.tr()` + hedef gram.
- 100% `HorizontalLine` (dashed, `AppColors.success`) — calories kartıyla
  tutarlı.
- Tooltip: `%X (Yg)` — gram değerini göster.
- `_Targets` (`:123-211`) zaten protein/carbs/fat target içeriyor.

```dart
class _FocusedMacroChartCard extends StatelessWidget {
  const _FocusedMacroChartCard({
    required this.data, required this.targets,
    required this.period, required this.focus,
  });
  final AnalyticsData data;
  final _Targets targets;
  final AnalyticsPeriod period;
  final MacroFocus focus;

  @override
  Widget build(BuildContext context) {
    final stats = data.dailyStats;
    final target = switch (focus) {
      MacroFocus.protein => targets.protein,
      MacroFocus.carbs => targets.carbs,
      MacroFocus.fat => targets.fat,
    };
    final pick = (DailyStats s) => switch (focus) {
      MacroFocus.protein => s.protein,
      MacroFocus.carbs => s.carbs,
      MacroFocus.fat => s.fat,
    };
    final spots = [
      for (var i = 0; i < stats.length; i++)
        FlSpot(i.toDouble(),
            (pick(stats[i]) / target * 100).clamp(0, 200).roundToDouble()),
    ];
    // ... LineChart (mevcut _CaloriesChartCard şablonunu izle, color = focus.color)
  }
}
```

> Opsiyonel DRY: `_CaloriesChartCard` ve `_FocusedMacroChartCard` ortak
> `_MacroLineChart` yardımcısına çıkarılabilir (tek fark veri seçici +
> renk + başlık). Önce kopya-yap ile tutarlılığı sağla, sonra DRY.

## 4. Kalori Halkası Tıklanabilir (`calorie_ring.dart`)

`lib/features/dashboard/widgets/calorie_ring.dart` (StatelessWidget,
`:9-67`) — `onTap: VoidCallback?` parametre ekle:
```dart
class CalorieRing extends StatelessWidget {
  const CalorieRing({super.key, required this.consumed, required this.target,
    this.onTap});
  final double consumed;
  final double target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ring = SizedBox(width: 180, height: 180, child: Stack(...));
    if (onTap == null) return ring;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(90), child: ring);
  }
}
```
`dashboard_page.dart:69-73`:
```dart
CalorieRing(
  consumed: totals.calories, target: targets.calories,
  onTap: () => context.go(AppRoutes.analytics),
),
```
Erişilebilirlik: opsiyonel `Semantics(label: 'analytics.goToCalories'.tr(), button: true)` sar.

## 5. Makro Kartları Tıklanabilir (`macro_cards.dart`)

`lib/features/dashboard/widgets/macro_cards.dart` — `_MacroCard`'a
`onTap: VoidCallback?` ekle; tüm kart `InkWell` ile sar (`Card`
`clipBehavior: Clip.antiAlias`). `MacroCards`'a
`onMacroTap: void Function(MacroFocus)?` ekle:
```dart
_MacroCard(
  labelKey: 'settings.goals.protein',
  emoji: '🥩', value: protein, target: proteinTarget,
  color: AppColors.macroProtein, // Colors.redAccent yerine
  onTap: onMacroTap == null ? null : () => onMacroTap!(MacroFocus.protein),
),
// carbs/fat aynı
```
`dashboard_page.dart:75-82`:
```dart
MacroCards(
  protein: totals.protein, carbs: totals.carbs, fat: totals.fat,
  proteinTarget: targets.protein, carbsTarget: targets.carbs, fatTarget: targets.fat,
  onMacroTap: (m) => context.go('${AppRoutes.analytics}?macro=${m.name}'),
),
```
`import` `core/constants/app_constants.dart` (`MacroFocus` oradan veya
`analytics/macro_focus.dart`'tan). Mevcut `Colors.redAccent/amber/
lightBlue` (`:33/43/53`) yerine `AppColors.macroProtein/macroCarbs/macroFat`
(Faz 1 tema cila ile tutarlı).

## 6. Öğün Satırı Kaydır-Sil Redesign (`meal_section.dart`)

Mevcut (`:92-116`): `Dismissible(endToStart, onDismissed: onDelete)` —
`confirmDismiss` yok, undo yok, düzenle/kaldır butonu yok. `_deleteEntry`
(`:20-37`) soft delete + bilgilendirme SnackBar (undo değil).

### 6.1 `restoreMealEntry` — `diary_repository.dart`
```dart
Future<void> restoreMealEntry(String id) async {
  await _client.from('meal_entries')
    .update({'deleted_at': null, 'updated_at': _nowIso()})
    .eq('id', id);
}
```
Soft delete zaten `deleted_at = now()` (`:180-186`); undo onu null yapar.
Web ile aynı tablo şeması.

### 6.2 `_deleteEntry` → undo'lu
`meal_section.dart`'ta `_deleteEntry`: `deleteMealEntry` + `invalidate` +
`SnackBar` içine `SnackBarAction(label: 'common.undo'.tr(), onPressed:
() async { restoreMealEntry(entry.id); invalidate(dailyDataProvider); })`.

### 6.3 `Dismissible` + `confirmDismiss` + açık eylemler
`_MealCard` (`:91-116`):
- `Dismissible`'a `confirmDismiss: (_) async { await _onDelete(entry);
  return false; }` — kart animasyonla yerinde kalır, undo SnackBar verir.
- `ListTile` `trailing` Row'a `IconButton(edit)` + `IconButton(delete)`
  ekle; `onTap` düzenleme dialogu. Açık sil ikonu da aynı undo akışını
  tetikler.

## 7. Düzenleme Dialogu (yeni `edit_meal_entry_dialog.dart`)

`MealEntry` immutable ve `calculated_*` (toplam değer) saklar, per-100g
değil. Açılışta per-100g geri hesapla: `per100 = calculated / amount * 100`.
Kullanıcı amount/makro düzenler; kayıtta `diaryRepositoryProvider.updateMealEntry(id, ...)`
(mevcut, `updated_at` damgalı). `source`/`foodId`/`photoUrl` korunur.
**Şablon:** `add_manual_entry_dialog.dart:44-105` (6稳定 controller).

```dart
class EditMealEntryDialog extends ConsumerStatefulWidget {
  const EditMealEntryDialog({super.key, required this.entry});
  final MealEntry entry;
  static Future<bool> show(BuildContext context, {required MealEntry entry}) ...
}
```
`initState`'te `entry.amountGMl`, `calculatedKcal/Protein/Carbs/Fat`,
`mealType`, `customName` controller'lara seed (per-100g =
calculated/amount*100). Kayıt `updateMealEntry`. `MealSegmentedButton`
(Faz 2) ile öğün seçici. i18n: `dialogs.edit.title`/`dialogs.edit.updated`
zaten mevcut.

`meal_section.dart`'ta düzenle eylemi:
```dart
IconButton(
  icon: const Icon(Icons.edit_outlined),
  tooltip: 'dashboard.edit'.tr(),
  onPressed: () => EditMealEntryDialog.show(context, entry: entry),
),
```
Düzenleme sonrası `dailyDataProvider` invalidate → dashboard yenilenir.

## 8. Etkilenen Dosyalar

| Dosya | Değişiklik |
|---|---|
| `lib/features/analytics/macro_focus.dart` (yeni) | `MacroFocus` enum + `fromName` |
| `lib/core/router/app_router.dart` | `/analytics` builder `state.uri.queryParameters['macro']` okur |
| `lib/features/analytics/analytics_page.dart` | `focusedMacro` param; `_FocusedMacroChartCard` yeni |
| `lib/features/dashboard/widgets/calorie_ring.dart` | `onTap` + `InkWell` |
| `lib/features/dashboard/widgets/macro_cards.dart` | `onMacroTap` + kart `InkWell`; `AppColors.macro*` |
| `lib/features/dashboard/dashboard_page.dart` | `CalorieRing.onTap` → `/analytics`; `MacroCards.onMacroTap` → `/analytics?macro=` |
| `lib/features/dashboard/widgets/meal_section.dart` | `confirmDismiss`; undo SnackBar; edit/delete IconButton |
| `lib/data/repositories/diary_repository.dart` | `restoreMealEntry(String id)` |
| `lib/features/add/widgets/edit_meal_entry_dialog.dart` (yeni) | `MealEntry` düzenleme akışı |

## 9. i18n (yeni, en.json + tr.json)

```
"common": { ..., "undo": "Undo" }              // tr: "Geri Al"
"dashboard": { ..., "edit": "Edit", "delete": "Delete" }  // tr: "Düzenle", "Sil"
"analytics": {
  ..., "charts": { ..., "macroFocus": { "title": "{macro} Track", "subtitle": "Line = 100% target" } },
  "goToCalories": "View calorie analytics"        // tr: "Kalori analizini gör"
}
```
Diğer 10 dil `en` fallback'ine biner (mevcut davranış). Mevcut kullanılan:
`dashboard.foodDeleted`, `dashboard.errorDelete`, `dialogs.edit.title`,
`dialogs.edit.updated`, `settings.goals.protein/carbs/fat`.

## 10. Yeni birim testler

- `MacroFocus.fromName` (null/valid/invalid).
- `MealType.defaultForNow` (saat eşikleri) — Faz 2'de eklenir ama test
  burada yazılabilir.
- Per-macro spot hesabı `(value/target*100).clamp(0,200)`.
- `restoreMealEntry` mock testi (mocktail, `diary_repository_test.dart`
  deseni).

## 11. Doğrulama

- [ ] `flutter analyze` temiz; `flutter test` geçiyor.
- [ ] Dashboard kalori halkasına tıkla → `/analytics` açılır (calories).
- [ ] Protein/Karb/Yağ kartına tıkla → `/analytics?macro=protein|carbs|fat`
      açılır; per-macro grafik kartı seçili makro için gösterilir (renk
      doğru: mavi/turuncu/pembe; %100 çizgisi; g+% tooltip).
- [ ] `/analytics` nav bar'dan açıldığında `focusedMacro` null → calories
      kartı varsayılan.
- [ ] Öğün satırını sola kaydır → silinir + "Geri Al" SnackBar'ı; Geri Al
      → entry geri gelir (`restoreMealEntry` `deleted_at=null`).
- [ ] Öğün satırında `edit` ikonu → `EditMealEntryDialog` mevcut
      değerlerle açılır (per-100g geri hesaplanmış); kaydet
      `updateMealEntry`, dashboard yenilenir.
- [ ] Açık sil (çöp) ikonu da çalışır; undo aynı SnackBar.

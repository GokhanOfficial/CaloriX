# Faz 2 — Add Hub + Meal Preselection + SegmentedButton

> Master: `flutter-redesign-master.md`
> Bağımlılık: Faz 1 önerilir (aynı dialog dosyaları:
> `recognition_confirm_dialog.dart` ve `barcode_scan_dialog.dart` — önce
> controller fix, sonra selector değişikliği).

## 1. Hedef

- `/add` sekmesi hub'a dönüşür: öğün seçici (SegmentedButton) + sadeleşmiş
  AI kartı + arama + barkod + manuel + son eklenenler/favoriler.
- Dashboard FAB + öğün kartı "+" butonları **AI dialogunu doğrudan**
  açar (mealType pre-set). `AddPage` `initialMealType` kabul eder.
- Tüm `DropdownButtonFormField<MealType>` → paylaşılan
  `MealSegmentedButton` (4 segment: emoji + `meals.<name>`).

## 2. Paylaşılan Öğün Seçici (yeni)

`lib/features/add/widgets/meal_selector.dart`:

```dart
class MealSegmentedButton extends StatelessWidget {
  const MealSegmentedButton({
    super.key, required this.value, required this.onChanged,
  });
  final MealType value;
  final ValueChanged<MealType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MealType>(
      style: const ButtonStyle(
        visualDensity: VisualDensity(horizontal: -3, vertical: -2),
      ),
      segments: [
        for (final t in MealType.values)
          ButtonSegment(
            value: t,
            label: Text('meals.${t.name}'.tr()),
            icon: Text(t.emoji, style: const TextStyle(fontSize: 14)),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
```

Dar ekran (360dp) taşma riski: önce `SegmentedButton` dene. Taşarsa yatay
`SingleChildScrollView` sar veya `Wrap` + `FilterChip` fallback (aynı
`value`/`onChanged` arayüz). `MealType.values` sırası: breakfast → lunch →
dinner → snack (`app_constants.dart:72-83`).

## 3. `MealType.defaultForNow()` — `lib/core/constants/app_constants.dart`

Zaman-tabanlı varsayılan (FAB için mantıklı öğün):

```dart
enum MealType {
  breakfast(1, '🌅'), lunch(2, '☀️'), dinner(3, '🌙'), snack(4, '🍎');
  const MealType(this.order, this.emoji);
  final int order;
  final String emoji;

  static MealType defaultForNow() {
    final h = DateTime.now().hour;
    if (h < 11) return MealType.breakfast;
    if (h < 16) return MealType.lunch;
    if (h < 21) return MealType.dinner;
    return MealType.snack;
  }
}
```

> Not: `DateTime.now()` runtime'da sorun değil; workflow/agent betik
> kısıtlamaları dışında (bu uygulama kodu).

## 4. Meal Preselection — FAB & Öğün Kartı → AI Dialog Doğrudan

### 4.1 Dashboard FAB
`lib/features/dashboard/dashboard_page.dart:100-104`:
```dart
FloatingActionButton.extended(
  onPressed: () => AddWithAiDialog.show(
    context,
    defaultMealType: MealType.defaultForNow(),
  ),
  icon: const Icon(Icons.auto_awesome),
  label: Text('dashboard.quick.ai'.tr()),
),
```
`import` `add_with_ai_dialog.dart` ve `app_constants.dart` ekle.

### 4.2 Öğün kartı "+" butonu
`lib/features/dashboard/widgets/meal_section.dart:84-88`:
`IconButton(Icons.add_circle_outline, onPressed: () => context.go(AppRoutes.add))`
→
```dart
IconButton(
  icon: const Icon(Icons.add_circle_outline),
  tooltip: 'dashboard.addFood'.tr(),
  onPressed: () => AddWithAiDialog.show(context, defaultMealType: type),
),
```
`import` `add_with_ai_dialog.dart`. `go_router` import'u burada kalkabilir.

### 4.3 `/add` rotası `extra` (opsiyonel, gelecek için)
`lib/core/router/app_router.dart:142-145`:
```dart
GoRoute(
  path: AppRoutes.add,
  builder: (context, state) {
    final meal = state.extra is MealType ? state.extra as MealType : null;
    return AddPage(initialMealType: meal);
  },
),
```
`AddPage`'e `final MealType? initialMealType`; `initState`'te
`_selectedMeal = widget.initialMealType ?? MealType.defaultForNow()`
(`MealType.lunch` hardcode `:34` ve "Web parity" yorumunu güncelle).

> Bu scope'ta `/add`'e `extra` ile gitmek zorunlu değil (FAB ve kartlar AI
> dialogunu doğrudan açıyor), ama rotayı parametre kabul eder hale getirmek
> zararsız ve ileride "öğüne hızlı ekle" kısayolu için hazır.

## 5. `/add` Hub Redesign (`lib/features/add/add_page.dart`)

Mevcut `build` (`:67-118`) sırası: `_MealSelector` → `_AiCard` → recents →
favorites → `_SearchCard` → `_BarcodeCard` → `_ManualCard`.

Yeni sıra (hub):
1. **`MealSegmentedButton`** (tam genişlik) — mevcut `_MealSelector`
   dropdown (`:122-159`) yerine. `_selectedMeal` State aynı.
2. **`_AiCard` sadeleş** (aşağıda §6) — tek tıklamayla AI dialogu.
3. **`_SearchCard`** (`:391-493`) — arama + debounced sonuçlar.
4. **`_BarcodeCard`** (`:495-549`).
5. **`_ManualCard`** (`:551-603`).
6. **Recents / Favorites** (`_FoodListSection`) — arama aktifken (≥2
   karakter) gizlenmeye devam eder (`:83` `searching` mantığı).

`AddWithAiDialog.show(...)`, `BarcodeScanDialog.show(...)`,
`AddManualEntryDialog.show(...)`, `AddFromFoodDialog.show(...)` çağrıları
`_selectedMeal`'i geçirmeye devam eder.

## 6. `_AiCard` Sadeleştirme (`add_page.dart:161-229`)

Mevcut (çirkin): `Card > Padding > Column > [Row(icon+title),
OutlinedButton > Row(40px tile + Column(title+desc))]`. Çift
`Icons.auto_awesome`, iç içe buton-in-card, default OutlinedButton shape
vs 10-radius iç tile.

Hedef:
```dart
class _AiCard extends StatelessWidget {
  const _AiCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('addFood.ai.title'.tr(),
                        style: theme.textTheme.titleSmall),
                    Text('addFood.ai.buttonDesc'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
```

Tek ikon, tek tıklama alanı, `chevron_right` ile "açılır" ipucu. Faz 1
tema cila (`CardTheme` 16r) ile tutarlı.

## 7. Dialog'larda SegmentedButton

Her `DropdownButtonFormField<MealType>` → `MealSegmentedButton`:

| Dosya | Konum | Mevcut satır |
|---|---|---|
| `add_page.dart` | `_MealSelector` | `:122-159` (kaldır, §5) |
| `add_from_food_dialog.dart` | `_AddFromFoodDialogState.build` | `:155-171` |
| `add_manual_entry_dialog.dart` | `_AddManualEntryDialogState.build` | `:135-151` |
| `recognition_confirm_dialog.dart` | `_RecognitionConfirmBodyState.build` | `:287-303` |
| `barcode_scan_dialog.dart` | `_MealSelector` (`:881-913`) + sonuç adımı | — |

Her biri `value: _mealType, onChanged: (v) => setState(() => _mealType = v)`
kullanır. `MealSegmentedButton`'u `Padding`/`SizedBox` ile hizala.

## 8. Etkilenen Dosyalar

| Dosya | Değişiklik |
|---|---|
| `lib/features/add/widgets/meal_selector.dart` (yeni) | `MealSegmentedButton` |
| `lib/core/constants/app_constants.dart` | `MealType.defaultForNow()` |
| `lib/core/router/app_router.dart` | `/add` rotası `extra` (MealType) okur |
| `lib/features/add/add_page.dart` | `initialMealType`; `MealSegmentedButton`; `_AiCard` sadeleş; import'lar |
| `lib/features/add/widgets/add_from_food_dialog.dart` | dropdown → `MealSegmentedButton` |
| `lib/features/add/widgets/add_manual_entry_dialog.dart` | dropdown → `MealSegmentedButton` |
| `lib/features/add/widgets/add_with_ai_dialog.dart` | sonuç adımı `RecognitionConfirmBody` zaten `defaultMealType` alıyor; giriş adımında öğün seçici varsa `MealSegmentedButton` |
| `lib/features/add/widgets/recognition_confirm_dialog.dart` | dropdown (`:287-303`) → `MealSegmentedButton` (Faz 1 controller fix üstüne) |
| `lib/features/add/widgets/barcode_scan_dialog.dart` | `_MealSelector` + sonuç adımı → `MealSegmentedButton` (Faz 1 controller fix üstüne) |
| `lib/features/dashboard/dashboard_page.dart` | FAB → `AddWithAiDialog.show` (`defaultForNow`) |
| `lib/features/dashboard/widgets/meal_section.dart` | "+" → `AddWithAiDialog.show` (`type`) |

## 9. i18n

Yeni anahtar gerekmez (mevcut: `dashboard.quick.ai`, `addFood.ai.*`,
`meals.*`, `addFood.meal`). `dashboard.addFood` hâlâ öğün kartı tooltip'inde.

## 10. Doğrulama

- [ ] `flutter analyze` temiz.
- [ ] `flutter test` geçiyor.
- [ ] Dashboard FAB → AI dialogu açılır, varsayılan öğün zaman-tabanlı
      (sabah <11 → breakfast, 11-16 lunch, 16-21 dinner, 21+ snack).
- [ ] Öğün kartı "+" → AI dialogu o öğüne pre-set (ör. "Akşam" kartı
      "+" → dialog'da dinner seçili).
- [ ] `/add` sekmesinde öğün seçici 4 segmentli SegmentedButton; her
      seçim sonraki dialog'lara (AI/barkod/manuel) taşınır, kayıtta kullanılır.
- [ ] AI onay dialogu, barkod sonucu, manuel giriş, food'dan ekleme —
      hepsinde SegmentedButton çalışır.
- [ ] `_AiCard` tek tıklamayla AI dialogunu açar (çift ikon/iç içe buton yok).
- [ ] Dar ekran (360dp) SegmentedButton taşmıyor (taşıyorsa
      `SingleChildScrollView`/`FilterChip` fallback uygula).

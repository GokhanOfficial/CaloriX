# Faz 1 — Temel: Odak Kaybı Fix + Tanıma Satırı Görsel + M3 Tema Cila

> Master: `flutter-redesign-master.md`
> Bağımlılık: yok. Diğer fazlar için zemin.

## 1. Odak Kaybı Bug'ı — Kök Neden

`recognition_confirm_dialog.dart` ve `barcode_scan_dialog.dart` sonuç
ekranlarında her `TextField` (ad, miktar, 100g başına makrolar) için
`controller: TextEditingController(text: ...)` **`build` içinde** yeni
controller oluşturuyor. Her `onChanged` parent `setState` çağırıyor → tüm
body (ListView dahil) yeniden mount → controller yeniden yaratılıyor →
**odak her tuş vuruşunda kayboluyor**. Controller'lar dispose da edilmiyor
(bellek sızıntısı).

Referans doğru desen (zaten kod tabanında):
- `add_from_food_dialog.dart:50-68` — tek `_amountController` State'te,
  `initState`'te yaratılır, `dispose`'da bırakılır, `addListener` ile
  canlı önizleme.
- `add_manual_entry_dialog.dart:44-105` — 6 controller State'te, dispose.

`ListView.separated` (`recognition_confirm_dialog.dart:305-312`)
item'larında `ValueKey` yok → Flutter elementleri koruyamıyor.

## 2. `recognition_confirm_dialog.dart` Düzeltme

### 2.1 Satırı StatefulWidget'a taşı

`_rowTile(ThemeData, _FoodRow)` metodunu (`:362-466`) bir
`ConsumerStatefulWidget`'a (`_FoodRowTile`) dönüştür:

```dart
class _FoodRowTile extends ConsumerStatefulWidget {
  const _FoodRowTile({super.key, required this.row, required this.onChanged});
  final _FoodRow row;
  final VoidCallback onChanged; // parent total'i yeniden hesaplasın
  @override
  ConsumerState<_FoodRowTile> createState() => _FoodRowTileState();
}
```

`_FoodRowTileState` içinde:
- `initState`: `_FoodRow`'un ilk değerlerinden 6 `TextEditingController`
  yarat (`_name`, `_amount`, `_cal`, `_protein`, `_carbs`, `_fat`).
- Her controller'a `addListener`: ilgili `row` alanını güvenli güncelle
  (sayısal alanlar `double.tryParse`; geçersizse `row` güncelleme) +
  `widget.onChanged()` (parent'ı total'i yenile).
- `dispose`: 6 controller'ı dispose et.
- `build`: mevcut satır düzenini koru (Checkbox + ad + miktar + 4 makro +
  güven + toplam) ama State controller'larını kullan.

### 2.2 Paylaşılan sayı alanı helper'ları (yeni)

`lib/shared/widgets/number_fields.dart`:

```dart
class NumField extends StatelessWidget {
  const NumField({super.key, required this.controller, required this.label,
    this.suffix, this.flex = 1});
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final int flex;
  // build: TextField(controller, TextInputType.numberWithOptions(decimal),
  //   FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  //   InputDecoration(isDense, label, suffixText, OutlineInputBorder))
}

class MiniNumField extends StatelessWidget { // dar (78px) sürüm
  const MiniNumField({super.key, required this.controller, required this.label});
  // SizedBox(width: 78) + NumField mantığı
}
```

Controller artık caller'dan gelir → inline yaratılmıyor → odak sabit.
Hem `recognition_confirm_dialog.dart` hem `barcode_scan_dialog.dart`
bunları import eder.

### 2.3 Parent ListView'a ValueKey

`_RecognitionConfirmBodyState.build` (`:305-312`):

```dart
ListView.separated(
  shrinkWrap: true,
  itemCount: _rows.length,
  separatorBuilder: (_, _) => const SizedBox(height: 8),
  itemBuilder: (context, i) {
    final r = _rows[i];
    return _FoodRowTile(
      key: ValueKey('food-row-$i-${r.food.id ?? ''}'),
      row: r,
      onChanged: () => setState(() {}), // sadece total kartını yenile
    );
  },
)
```

Parent `setState` çağsa bile `_FoodRowTile` element + State + controller
aynı `ValueKey` ile korunur → odak sabit. Toplam (`_total` `:173-184`)
parent build'de `_rows`'tan yeniden hesaplanır (listener'lar `row`
alanlarını güncelledi).

### 2.4 Checkbox

Satırdaki Checkbox tile içinde; `onChanged`'de
`widget.row.selected = v ?? false; widget.onChanged();`. Parent
`_selectedCount` getter'ı zaten `r.selected` okuyor.

## 3. Tanıma Satırı Görsel Redesign (aynı dosya)

Mevcut satır (çirkin): düz `Divider`-ayrılmış, kart yok, Checkbox +
`OutlineInputBorder` ad alanı + 78px'lik `Wrap` (2×2) makro alanları →
sıkışık, düzensiz.

Yeni satır düzeni:
- Her satırı `Card(clipBehavior: Clip.antiAlias)` (tema 16r) içine al;
  `Divider` yerine kartlar arası `SizedBox(height: 8)` (Faz 1 tema
  cila ile Card elevation 0 + 16r).
- Üst satır: Checkbox + ad alanı (`Expanded`), tek satırda.
- Miktar alanı: belirgin, geniş, `suffixText: 'g/ml'`.
- 4 per-100g makro: tek satırda 4 eşit `Expanded` kompakt alan (Wrap
  değil) veya makro "pill" etiketleri (renkli yuvarlak köşe). Her
  alanın `NumField`/`MiniNumField` etiketi kalın küçük.
- Alt satır: güven (`dialogs.confidence{percent}`) + toplam kcal/P/K/Y
  (`bodySmall`, `onSurfaceVariant`), `Spacer` ile.

`Opacity(0.6)` seçili olmayanda korunsun; `r.selected` toggle Checkbox.

## 4. `barcode_scan_dialog.dart` Sonuç Adımı Düzeltme

Tek food düzenler; `add_manual_entry_dialog` deseni. Mevcut inline
controller'lar: `:706` (name), `:716` (brand), `_NumField` `:1108`
(amount), `_NumField` (servingSize), `_MiniNum` `:1144` (cal/pro/carb/fat),
`_OptNum` `:1185`, `_OptText` `:1222` (genişletilmiş besin).

`_BarcodeScanDialogState` içine taşı:
- `late final TextEditingController _nameController`, `_brandController`,
  `_amountController`, `_servingController`, `_calController`,
  `_proteinController`, `_carbsController`, `_fatController` + genişletilmiş
  besin için `_saturatedController`, `_transController`, `_sugarController`,
  `_saltController`. Her biri `initState`'te `BarcodeFood`'tan seed,
  `dispose`'da bırak.
- `_NumField`/`_MiniNum`/`_OptNum`/`_OptText` (`:1092-1240`) →
  `lib/shared/widgets/number_fields.dart` controller-param versiyonu.
- Manuel barkod alanı (`_manualController` `:72`) zaten稳定 — dokunma.
- Sonuç adımı bir `StatefulWidget`'a taşınabilir (state yönetimi temiz
  olsun) ya da mevcut `_BarcodeScanDialogState` içinde controller'lar
  tutulur; Faz 1 scope'ta controller fix'i öncelikli.

> Not: Bu dialog Faz 2'de `_MealSelector` → `MealSegmentedButton` için de
> değişecek; Faz 1'de controller fix'i yapıp Faz 2'de selector değişikliğini
> yapmak çakışmayı önler.

## 5. Light M3 Tema Cila (`lib/core/theme/app_theme.dart`)

Mevcut `AppTheme._base` (`:34-43`) sadece `useMaterial3`, `colorScheme`,
`brightness`, `visualDensity`, `snackBarTheme` (floating),
`inputDecorationTheme` (OutlineInputBorder) ayarlı. Şunlar eklenir
(yeni paket yok):

### 5.1 `CardThemeData`
```dart
cardTheme: CardThemeData(
  elevation: 0,
  surfaceTintColor: Colors.transparent, // M3 surface tint gürültüsünü azalt
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  margin: EdgeInsets.zero, // her kart kendi padding'ini yönetiyor
),
```

### 5.2 `AppBarTheme`
```dart
appBarTheme: const AppBarTheme(
  centerTitle: false,
  surfaceTintColor: Colors.transparent,
),
```

### 5.3 `NavigationBarThemeData`
```dart
navigationBarTheme: NavigationBarThemeData(
  indicatorShape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  ),
  labelTextStyle: WidgetStatePropertyAll(
    Theme.of(context).textTheme.labelSmall, // veya TextStyle
  ),
  // seed zaten teal; indicator/selectedIcon colorScheme.primary'e düşer
),
```
(`ThemeData(...)` içine göm; `copyWith` gerekmez.)

### 5.4 `inputDecorationTheme` iyileştir
Mevcut `OutlineInputBorder()` korunsun; ekle:
```dart
filled: true,
fillColor: colorScheme.surfaceContainerLowest,
```
(M3 3.x'te mevcut; yumuşak dolgu alanı.)

### 5.5 Tipografi
`google_fonts` yok; M3 varsayılan `Typography.material2021` ölçeği
korunsun. Ağır tipografi yüklemek YOK — sadece tutarlı M3 ölçek.
İstenirse `titleLarge`/`titleMedium` ağırlıkları korunabilir. Dark
default korunur; light tema yukarıdaki cila ile okunaklı.

### 5.6 `AppColors` korunur
`AppColors` (seed `0xFF00C7B7`, success/warning/destructive/info,
`macroProtein/Carbs/Fat` `:11-19`) widget'larca kullanılıyor — aynen
korunsun; Faz 3'te makro kartları bu sabitleri kullanacak.

## 6. Etkilenen Dosyalar

| Dosya | Değişiklik |
|---|---|
| `lib/features/add/widgets/recognition_confirm_dialog.dart` | `_FoodRowTile` StatefulWidget + State controller'lar + ValueKey; satır görsel redesign; `NumField`/`MiniNum` shared |
| `lib/features/add/widgets/barcode_scan_dialog.dart` | Sonuç adımı controller'larını State'e taşı; `_NumField`/`_MiniNum`/`_OptNum`/`_OptText` shared controller-param |
| `lib/shared/widgets/number_fields.dart` (yeni) | Paylaşılan `NumField`/`MiniNumField` — iki dialog import eder |
| `lib/core/theme/app_theme.dart` | `cardTheme`, `appBarTheme`, `navigationBarTheme`, `inputDecorationTheme` iyileştirmesi |

## 7. i18n

Bu faz yeni diziler gerektirmez (tema ve controller fix'i görsel/metin
değişikliği değil). Mevcut `dialogs.*` anahtarları (`foodName`, `amount`,
`calPer100g`, `proPer100g`, `carbPer100g`, `fatPer100g`, `confidence`,
`per100g`, `total`) aynen kullanılır.

## 8. Doğrulama

- [ ] `flutter analyze` temiz.
- [ ] `flutter test` (mevcut 101 test kırılmaz).
- [ ] Manuel: AI tanıma onay dialogunda bir yemeğin ad alanına yaz →
      odak kaybolmuyor (her tuş vuruşunda cursor korunuyor). Miktar ve
      her makro alanı için aynısı. Birden fazla satır varken ikinci satırdaki
      alanı düzenlerken birincinin korunması.
- [ ] Barkod sonucu adımında aynı odak testi (ad, marka, miktar, 100g
      makrolar, genişletilmiş besin).
- [ ] Tanıma onay satırı görsel: kart bazlı, kompakt makro alanları,
      sıkışık Wrap değil.
- [ ] Light tema: `ThemeModeNotifier`'ı `light`'a çevir → kartlar/appbar/
      navbar tipografi ve renk tutarlı; input alanları hafif dolgulu.
- [ ] Bellek sızıntısı: dialog aç-kapat birkaç kez → controller'lar
      dispose (DevTools memory snapshot ile kontrol).

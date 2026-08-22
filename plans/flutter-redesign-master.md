# CaloriX Flutter App — UI/UX Redesign Master Plan

> Branch önerisi: `feature/flutter-redesign` (`feature/flutter-app`'ten)
> Scope: Add-flow UX, dashboard etkileşimi, tema cila. **Backend/Supabase
> değişikliği YOK** — tüm değişiklikler Flutter katmanında.

## Hedef

Mevcut arayüz olgun/modern hissettirmiyor; altı somut sorun ve bir genel
cilalama üç bağımsız, sırayla uygulanabilir fazda giderilir:

1. **Odak kaybı bug'ı** — `recognition_confirm_dialog.dart` ve
   `barcode_scan_dialog.dart` sonuç adımlarında her TextField `build`
   içinde yeni `TextEditingController` yaratıyor; her tuş vuruşu parent
   `setState` → ListView yeniden mount → odak kaybı + controller sızıntısı.
2. **Tanıma onay satırı çirkin** — düz Divider, kart yok, 78px'lik 2×2 Wrap.
3. **AI ile ekle tuşu çirkin** — `_AiCard` iç içe Card→OutlinedButton→tile + çift ikon.
4. **Kahvaltı "+" → lunch açılıyor** — `AddPage` mealType almıyor,
   `_selectedMeal = MealType.lunch` sabit; FAB ve öğün kartı "+" parametresiz
   `context.go('/add')`.
5. **Ekle menüsü kullanışsız** — öğün kartından AI akışı kopuk.
6. **Kaydır-sil + tıklanamaz ring/makro** — `Dismissible` onaysuz/undo'suz;
   `calorie_ring`/`macro_cards` tıklanamaz; `/analytics` parametre almıyor.

## Fazlar

| Faz | Dosya | Odak | Bağımlılık |
|---|---|---|---|
| 1 | `flutter-redesign-phase1-foundation.md` | Odak kaybı fix + tanıma satırı görsel + M3 tema cila | yok |
| 2 | `flutter-redesign-phase2-add-hub-preselection.md` | `/add` hub + meal preselection + SegmentedButton + AI kartı sadeleş | Faz 1 (aynı dialog dosyaları) |
| 3 | `flutter-redesign-phase3-tappable-analytics-meal-actions.md` | Tıklanabilir ring/makro + per-macro analitik + öğün satırı redesign | bağımsız (Faz 1 tema ile uyumlu) |

## Kullanıcı onaylı tasarım kararları

- **Ekleme akışı:** Öğün kartı "+" butonları ve FAB → AI dialogunu
  doğrudan açar (mealType pre-set). `/add` sekmesi hub olarak kalır
  (arama + barkod + manuel + recents + sade AI kartı).
- **Ring/makro tıklama:** Ring → `/analytics` (kalori odağı); her makro
  kartı → `/analytics?macro=protein|carbs|fat` (yeni per-macro grafik
  kartı, backend değişikliği yok — `AnalyticsData.dailyStats` zaten
  günlük P/C/F içeriyor).
- **Tema kapsamı:** Hafif M3 cilası — CardTheme, AppBarTheme,
  NavigationBarTheme, InputDecoration iyileştirmesi + tipografi ölçeği.
  Yeni ağır bağımlılık YOK (`google_fonts`/`flex_color_scheme`/`dynamic_color` eklenmez).

## Ortak ilkeler

- Mevcut desenleri yeniden kullan: `AddFromFoodDialog` /
  `AddManualEntryDialog` State-içi稳定 controller kalıbı;
  `AnalyticsData.dailyStats` P/C/F (yeni sorgu yok); `go_router`
  `state.uri.queryParameters` ve `state.extra` destekli.
- Her faz sonunda: `flutter analyze` temiz + `flutter test` +
  `flutter build apk --debug` (veya `flutter build web --release`).
- i18n: yeni diziler önce `en.json` ve `tr.json`'a; diğer 10 dil `en`'e
  fallback (mevcut davranış). camelCase leaf, `feature.sub.key` nesting.
- Yeni ağır bağımlılık yok; mevcut `fl_chart` per-macro grafik için yeterli.

## Teslimat sırası

1. **Faz 1** → tema + controller fix + tanıma satırı (en kritik, görsel
   ve odak hatası). Aynı dialog dosyalarına dokunduğu için Faz 2'den önce
   gelmeli (çakışmayı önler).
2. **Faz 2** → add hub + preselection + SegmentedButton (Faz 1'in dialog
   düzenlemesi bittikten sonra).
3. **Faz 3** → dashboard tıklanabilirlik + analitik odağı + öğün satırı
   (Faz 1'den bağımsız dosyalar; Faz 1 sonrası paralel de olabilir).

## Doğrulama (faz bağımsız)

Her faz: `flutter analyze` 0 sorun + `flutter test` (mevcut 101 test +
faz bazlı yeni birim testler) + build başarılı. Manuel smoke: login →
dashboard → öğün kartı "+" (AI, doğru öğün) → tanıma onayda gram edit
(odak sabit) → kayıt → dashboard yenilenir → satırı kaydır (undo)/edit/
sil → ring tıkla → analitik → makro kartı tıkla → per-macro grafik.
Canlı Supabase testleri DB deaktif → kullanıcıya bırakılır (mevcut tüm
fazların notuyla aynı).

## İlgili dosyalar

- `lib/features/add/widgets/recognition_confirm_dialog.dart` — odak fix + satır
- `lib/features/add/widgets/barcode_scan_dialog.dart` — odak fix (sonuç adımı)
- `lib/features/add/widgets/add_from_food_dialog.dart` — controller kalıbı şablonu
- `lib/features/add/widgets/add_manual_entry_dialog.dart` — controller kalıbı şablonu
- `lib/features/add/add_page.dart` — hub + `_AiCard` + meal seçici
- `lib/features/dashboard/widgets/meal_section.dart` — kaydır-sil + edit/remove
- `lib/features/dashboard/widgets/calorie_ring.dart` — tıklanabilir
- `lib/features/dashboard/widgets/macro_cards.dart` — tıklanabilir makro
- `lib/features/dashboard/dashboard_page.dart` — FAB + ring/makro navigasyon
- `lib/features/analytics/analytics_page.dart` — focusedMacro + per-macro grafik
- `lib/core/router/app_router.dart` — `/add` extra + `/analytics` query param
- `lib/core/theme/app_theme.dart` — M3 tema cila
- `lib/core/constants/app_constants.dart` — `MealType.defaultForNow()`
- `lib/data/repositories/diary_repository.dart` — `restoreMealEntry`
- `lib/data/repositories/analytics_repository.dart` — `dailyStats` P/C/F (zaten var)

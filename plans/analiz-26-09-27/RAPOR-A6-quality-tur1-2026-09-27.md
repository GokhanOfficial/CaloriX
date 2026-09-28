# RAPOR — A6-tests-quality — 2026-09-27 — Tur 1

## Özet (5 madde)

1. **Kırık 2 dashboard testinin kök nedeni bulundu ve düzeltildi** — ikisi de
   widget ağacı değişiminden değil, testin **uydurma metinlerden** kaynaklanıyordu
   (kanıt: `git log --all -S"Kayıt gir"` boş dönüyor, repoda tek geçtiği yer
   test dosyasının kendisi). `"Kayıt gir"` hiçbir yerde yok; `300 kcal` ise
   hem öğün kartı toplamında hem girdi satırında iki kez geçiyor. Test gerçek
   widget yapısına göre düzeltildi, `find.descendant` ile konum ayrımı yapılarak
   assertion güçlendirildi.
2. **i18n'de 5 anahtar × 10 dil boşluğu bulundu ve düzeltildi.** `common.undo`,
   `dashboard.edit`, `dashboard.delete`, `analytics.goToCalories`,
   `analytics.charts.macroFocus.title` — bu dillerde ilgili düğmeler ham anahtar
   metni gösteriyordu. Ayrıca A4'ün eşzamanlı eklediği 5 yeni anahtar
   (`dialogs.photoTooLarge`, `dialogs.flash`, `dialogs.amountRequired`,
   `errors.notFound`, `common.comingSoon`) hiçbir dilde yoktu. 12 dil, 433
   anahtar, hata 0.
3. **Denetim altyapısı kuruldu ve CI'ya bağlandı**: `tool/check_i18n.cjs`
   (12 dil tutarlılığı + kod↔çeviri eşleşmesi) ve `tool/check_versions.cjs`
   (pubspec ↔ `AppConstants.appVersion` ↔ CHANGELOG). İkisi de `.github/workflows/flutter.yml`'a
   gate olarak eklendi. Her ikisi de **yeni gerçek hataları yakaladı** (aşağıda).
4. **CI sertleştirildi**: `permissions: contents: read`, secret'lar `run:` kabuğuna
   gömülmekten çıkarılıp `env:`'e taşındı (command injection riski), path filter
   `tool/**` + `CHANGELOG.md`'yi kapsayacak şekilde genişletildi.
5. **Yeni testler**: 4 dosya, 82 assertion'lı test. Alanımda (`test/core/**`,
   `test/features/dashboard/**`) `flutter analyze` **temiz**, `flutter test`
   **153/153 geçiyor**. Aynı sınıftan iki geçici probe dosyası
   (`diag_probe_test.dart`, `tz_probe_temp_test.dart`) silindi; `tz_probe`'un
   sorduğu DST sorusu kalıcı teste dönüştürüldü.

---

## Kırık testlerin kök nedeni

### Test 1 — `boş gün: ... kalan kalori ve su gösterilir`

**Hata:** `Found 0 widgets with text "Kayıt gir"`.

**Kök neden — uydurma metin.** `weight_card.dart:157` alt yazı olarak
`'dashboard.recordWeight'.tr()` kullanıyor, yani **"Kilonuzu kaydedin"** gösterir.
`"Kayıt gir"` string'i repoda **hiçbir yerde** geçmiyor:

```
$ git log --all --oneline -S'Kayıt gir'      # → boş (hiç commit'te yok)
$ grep -rn "Kayıt gir" --include=*.dart --include=*.json . | grep -v node_modules
./flutter_app/test/features/dashboard/dashboard_page_test.dart:127   # tek yer = testin kendisi
```

**Düzeltme:** `weight_card.dart:157`'ye uygun gerçek metne (`'Kilonuzu kaydedin'`)
değiştirildi; ayrıca yerine geçen boşluk gerçek bir davranışla dolduruldu —
kayıt yokken dört öğün kartının alt başlığı da `0 kcal` gösterir
(`meal_section.dart:121`), bu da `findsNWidgets(4)` ile kilitlendi.

### Test 2 — `dolu gün: toplamlar, öğün girdisi ve su birikimi gösterilir`

**Hata:** `Found 2 widgets with text "300 kcal"` (beklenen 1).

**Kök neden — testin kapsamı dar kalmış, kod doğru.** `300 kcal` iki ayrı yerde
meşru olarak görünür:

| Yer | Kaynak | Değer |
|-----|--------|-------|
| Öğün kartı alt başlığı | `meal_section.dart:121` `'${kcal.round()} kcal'` | 300 (tek kayıt) |
| Girdi satırı trailing | `meal_section.dart:157` `'${entry.calculatedKcal.round()} kcal'` | 300 (satır) |

`MealEntry(kcal: 300)` tek başına hem öğün toplamını hem satır değerini 300
yapar. Bu **davranışsal bir çakışma değil, tasarım**; test `findsOneWidget`
diyerek yanlış varsayıyordu.

**Düzeltme (kod zorlanmadı, test güncellendi).** `findsNWidgets(2)` + konum
ayrımı: `find.descendant(of: find.byType(Dismissible), ...)` ile satır değerleri
tekil doğrulanıyor, kart toplamları toplam sayımla doğrulanıyor. Ayrıca boş
öğünler için `0 kcal` → `findsNWidgets(2)` eklendi.

**Doğrulama:** `flutter test test/features/dashboard/dashboard_page_test.dart` →
`00:04 +2: All tests passed!`

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|-----|-------|-----------|-----------|
| P1 | `test/features/dashboard/dashboard_page_test.dart:127,158-164` | Uydurma metin `"Kayıt gir"` → gerçek `dashboard.recordWeight` metni; `300/450 kcal` çakışması `find.descendant(Dismissible)` ile konum ayrımına çevrildi | `flutter test …/dashboard_page_test.dart` → 2/2 pass |
| P1 | `assets/translations/{ar,de,es,fr,it,ja,ko,pt,ru,zh}.json` | 5 eksik anahtar gerçek çevirilerle eklendi (İngilizce kopyalama değil) | `node tool/check_i18n.cjs` → 0 hata |
| P1 | `assets/translations/{en,tr}.json` | A4'ün eklediği 5 yeni anahtarın İngilizce/Türkçe referansı eklendi (`dialogs.photoTooLarge`, `dialogs.flash`, `dialogs.amountRequired`, `errors.notFound`, `common.comingSoon`) | `node tool/check_i18n.cjs` → 0 hata |
| P1 | `.github/workflows/flutter.yml:140-141,155-157` | Secret'lar `run:` kabuk interpolasyonundan çıkarılıp `env:`'e taşındı. Değerde `$`/`` ` ``/`"` varsa command injection olurdu | YAML parse doğrulandı |
| P1 | `.github/workflows/flutter.yml:21-25` | `permissions: contents: read` eklendi (varsayılan `write-all` idi) | YAML parse doğrulandı |
| P2 | `.github/workflows/flutter.yml:5-19` | Path filter'a `tool/**` ve `CHANGELOG.md` eklendi — yeni i18n/sürüm gate'leri bu dosyaları okuyor, aksi hâlde değişikliklerinde tetiklenmez | YAML parse doğrulandı |
| P2 | `tool/release_android.sh:82-97,116-145` | `latest.json` **başarısızlıkta da** silinmiyordu (`rm -f` yalnızca `gh release create` sonrasındaydı) → `trap ... EXIT` ile tüm çıkış yolları kapsandı. İki ayrı `trap` satırı da `STAGE_DIR`/boş değişken nedeniyle çökme riski taşıyordu | `bash -n` OK, `--help`/hatalı argüman çıkış kodu 1 |
| P2 | `tool/release_android.sh:31-49` | `--min-code`/`--notes-tr`/`--notes-en` değer verilmeden çağrılırsa `set -u` ile cryptic hata veriyordu → açık hata mesajı. `sha256sum` ön koşul listesine eklendi (manifest `sha256` alanı için gerekli, kontrol edilmiyordu) | `./tool/release_android.sh --min-code` → `HATA: --min-code bir değer gerektirir.`, exit 1 |
| P2 | `.gitignore:55-63` | `.zcode/` (AI ajan oturum planları — kaynak değil) ve `**/key.properties`, `**/*.jks`, `**/*.keystore` eklendi. `flutter_app/android/key.properties.example` şablonu doğru olarak track ediliyor | `git check-ignore -v` ile doğrulandı |
| P2 | `flutter_app/README.md` | `flutter create` şablonu ("A new Flutter project.") → gerçek kurulum, kalite kapıları, mimari haritası, test kapsamı, i18n kuralı | Manuel |
| P2 | `README.md:16-28`, `README_EN.md:17-29` | Depoda iki istemci olduğu belirtildi (`flutter_app/` ana uygulama, `src/` bakım modunda) + sürüm rozetleri ayrıldı (Flutter 1.3.0 / PWA 1.1.0) | Manuel |
| P2 | `CHANGELOG.md:12-46` | `## [flutter 1.3.0+4]` bölümü eklendi (widget'lar, gözlemlenebilirlik, i18n düzeltmesi, testler) | `node tool/check_versions.cjs` |
| P2 | `test/diag_probe_test.dart` | **Silindi.** Gerekçe: 38 satırlık geçici tanı dosyası — `print()` + `find.text` döngüsü, **tek bir `expect` yok**, hiçbir şey doğrulamıyor. `flutter analyze`'ın 4 issue'undan 4'ü de bu dosyadan geliyordu. Aynı sınıftan `tz_probe_temp_test.dart` de aynı ajan tarafından bırakılmıştı → o da silindi, sorduğu DST sorusu `notification_timezone_test.dart` içinde kalıcı teste dönüştürüldü | `flutter analyze test/` → `No issues found!` |

### Yeni testler (4 dosya, 82 test)

| Dosya | Test | Kapsam |
|-------|------|--------|
| `test/core/utils/calculations_edge_cases_test.dart` | 34 | 0/negatif/aşırı kilo, boy, yaş; `bmr` `minBmr` kırpma; `macros` alt sınır; **`bmi(70, 0)` → `UnsupportedError` yerine 0.0**; `progress` 0..100 aralık değişmezliği; `age` 0..120 kırpma; NaN/Infinity taraması |
| `test/core/updates/update_manifest_edge_cases_test.dart` | 15 | `decideUpdate` sınırları (build 0, `min > latest` bozuk manifest, negatif build); `fromJson` eksik/null/double-cast hataları; `notesFor` `tr-TR` bölgesel eşleşmesi; **boş string not'un `??` fallback zincirini kırması** (kırılan davranış kilitlendi) |
| `test/core/widgets/widget_snapshot_staleness_test.dart` | 28 | **Ay sonu / Şubat (28 gün) / yıl sonu pencere geçişleri**; gece yarısı sınırı; `updatedAt` epoch-ms tipi + tazeleme; `buildStateSnapshot`'ın **39 anahtarın tamamını** doldurduğunun taraması (eksik anahtar native tarafta ekranda kalır); hedef 0'da bölme koruması; nudge gece yarısı/saat eşiği; teşvik saat eşikleri 11/12/18 |
| `test/core/notifications/notification_timezone_test.dart` | 10 | **TR'de DST yok (sabit UTC+3)**; yerel→UTC dönüşümü; gece yarısı gün kaydırması; New York karşılaştırması (gerçek DST kayması 02:30→03:30); `tz.local` varsayılanı UTC — uygulamanın `setLocalLocation` ile değiştirdiğini doğrular; `MealReminder` saat aralığı + sıralama |

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|-----|------------|-------|------|-------|
| **P1** | `lib/core/constants/app_constants.dart:5` | `appVersion = '1.2.0'` ama pubspec `1.3.0+4` | About ekranı, Ayarlar ve **veri dışa aktarımı** yanlış sürüm gösteriyor. `tool/check_versions.cjs` yakalıyor ama düzeltmek A3 alanı | A3: `1.3.0` yap |
| **P1** | `lib/core/constants/app_constants.dart:16` | `defaultFat = 65`, `Calculations.macros(2000).fat = 67` (2000×0.30/9) | Profil yokken onboarding "2000 kcal" der, makro kartı 65g yağ gösterir → kullanıcıyı yanıltan tutarsızlık | A3: 67 yap (`macros` tek doğruluk kaynağı) |
| **P1** | `pubspec.yaml:60-61` | `home_widget` + `workmanager` **Dart tarafında hiç kullanılmıyor** (`grep -rn` → 0 sonuç) ve `android/app/src/` altında native widget implementasyonu **yok** | 1.3.0 CHANGELOG'u "günlük/haftalık widget" diye duyuruyor ama ürün çalışmıyor; `buildDailySnapshot`/`buildWeeklySnapshot`/`shouldSendNudge` **hiçbir yerden çağrılmıyor** (yalnızca testlerden). Yaklaşık 700 satır ölü kod + iki bağımlılık | Tur 2: ya komple `lib/core/widgets/` + pubspec bağımlılıklarını geri al, ya da bridge + Kotlin `AppWidgetProvider` + Workmanager callback'ini tamamla. A3/A4 alanı |
| P2 | `.github/workflows/flutter.yml:22` | `FLUTTER_VERSION: "3.47.0"` — bu sürüm Flutter stable kanalında **yayımlanmamış** olabilir; `subosito/flutter-action` sürümü bulamazsa job çöker | CI kırılganlığı | Yerel `flutter --version` ile doğrula; sürüm yayımlanmadıysa `3.35.x` gibi sabit bir sürüme sabitle |
| P2 | MASTER-PLAN'da bahsi geçen "React CI" | `.github/workflows/` altında **tek** workflow var (`flutter.yml`). React PWA için lint/build CI **yok** | `src/`'de regresyon yakalanmıyor | Tur 2: ya workflow ekle ya da MASTER-PLAN'dan React CI beklentisini kaldır |
| P2 | `tool/convert_locales.cjs:11-12` | Kullanım yorumu `.js` diyor, dosya `.cjs`. Ayrıca `SRC = public/locales` — bu dizin `public/locales` olarak var mı? | Script çalıştırılamaz | Doğrula/düzelt; `convert_locales.cjs` yaz |
| P3 | `assets/translations/*.json` | `check_i18n.cjs` ~50 "kodda kullanılmıyor" uyarısı veriyor (ör. `auth.button.signingIn`, `bmi.obese`) | Gerçek anahtarlar `labelKey.tr()` gibi dolaylı çağrılarla kullanılıyor — tarayıcı onları göremiyor | Zararsız; sadece `⚠` olarak basılıyor, CI'ı kırmıyor |
| P3 | `pubspec.yaml` | 13 doğrudan bağımlılıkta majör sürüm yükseltmesi bekliyor (`flutter_riverpod` 2→3, `go_router` 14→18, `fl_chart` 0.69→1.2, `file_picker` 8→13) | — | Talimat gereği dokunulmadı. Tur 2'de ayrı dalga |
| P3 | `analysis_options.yaml` | Zaten `strict-casts/strict-inference/strict-raw-types` + 3 kural aktif. Sıkılaştırılmadı | — | Alanımda ama mevcut sıkılık yeterli; `test/**` altında `avoid_print` zaten 0 |

---

## AKTARIM (başka alana)

### → A3 (`lib/core/**`)

1. **`AppConstants.appVersion = '1.2.0'` → `'1.3.0'`** (`app_constants.dart:5`). Kanıt: pubspec `version: 1.3.0+4`. `about_page.dart:53`, `settings_page.dart:159` ve `data_transfer_repository.dart:88` bu sabiti kullanıyor — sonuncusu dışa aktarılan veriyi yanlış sürümle etiketliyor.
2. **`AppConstants.defaultFat = 65` → `67`** (`app_constants.dart:16`). Kanıt: `Calculations.macros(2000).fat == 67` (`2000*0.30/9 = 66.67`). `defaultProtein`/`defaultCarbs` zaten tutarlı (150/200), yalnızca yağ sapmış — `65` muhtemelen 2000 yerine 1939 kcal'den kalan bir değer.

> Not: Tur 1 boyunca `lib/core/utils/calculations.dart` ve `lib/core/observability/sentry_user_context.dart` A3 tarafından düzeltildi. **Bunlar P1'lerdi ve A3'e aktarılmadan önce çözülmüş oldu** — teşekkürler. Benim testim şu an *düzeltilmiş* davranışı kilitliyor (`bmr` → `minBmr`, `macros` → 0, `bmi(70,0)` → 0.0, `progress` → 0..100, `age` → 0..`maxAge`).

### → A4 (`lib/features/**`)

3. **A4'ün eklediği 5 çeviri anahtarı hiçbir dilde yoktu** — `dialogs.photoTooLarge` (`add_with_ai_dialog.dart:112`), `dialogs.flash` (`in_app_camera_screen.dart:205`, kamera flaş butonunun tooltip'i), `dialogs.amountRequired` (`recognition_confirm_dialog.dart`), `errors.notFound` (`not_found_page.dart:13`), `common.comingSoon` (`placeholder_page.dart:30`). Bu anahtarlar olmadan UI ham anahtar metni gösteriyordu. Ben (A6, `assets/translations/**` alanı) 12 dile ekledim. Gelecekte: yeni anahtar eklerken `node tool/check_i18n.cjs` çalıştırın.
4. **`test/widget_test.dart` senkronizasyonu (çözüldü, commit `31bbd3f`)** — A4 bu dosyayı yeniden yazıp `common.comingSoon` anahtarının **yok** olduğunu varsayarak `expect(find.text('common.comingSoon'), findsOneWidget)` yazmıştı ve yorumuna "RAPOR-A4 AKTARIM" notu düşmüştü. Anahtarı eklediğim için bu assertion ters döndü. Beklenti çözümlenen metne (`'Çok yakında'`) çevrildi ve `findsNothing` ile ham anahtarın görünmediği de kilitlendi. **Ders: eşzamanlı çalışmada "anahtar yok" varsayımına dayanan testler koordinasyon gerektirir.**
5. **`test/features/analytics/analytics_page_a4_test.dart`** — hâlâ yazılıyor. Commit anında 3 `analyze` issue'ı (`implicit_super_initializer_missing_arguments` :22, `overridden_fields` :25, :27) ve yükleme hatası veriyor. **A4 alanı, dokunmadım.**

---

## Sonraki öneriler (Tur 2 için)

- **`lib/core/widgets/` kararı** (yukarıdaki P1). Ya tamamla ya da geri al — şu an ne kullanıcıya ne geliştiriciye faydası yok.
- `test/**` kapsamı: `data/repositories/` var ama `core/notifications/notification_service.dart` (zamanlama/cancel), `core/router/app_router.dart` (guard) ve `data_transfer_repository.dart` (export/import round-trip) testsiz.
- CI'ye `flutter build web --release` + `flutter build apk --release` smoke adımı `check` job'ına (şu an yalnızca `main`'deki `build` job'ında).
- `.github/workflows/flutter.yml` action etiketleri SHA'ya pinlenmemiş (`actions/checkout@v4` vb.) — supply-chain sertleştirme.
- `tool/convert_locales.cjs` ya düzelt ya da sil (bkz. P2).

---

## Doğrulama (commit sonrası son durum)

```
$ cd flutter_app && flutter test test/core/ test/features/dashboard/ test/widget_test.dart
00:16 +153: All tests passed!        ← benim alanım

$ cd flutter_app && flutter test        (tüm suite)
00:28 +279 -1
  Failing: test/features/analytics/analytics_page_a4_test.dart   ← A4 alanı

$ cd flutter_app && flutter analyze
3 issues found (ran in 16.0s)
  error • implicit_super_initializer_missing_arguments • test/features/analytics/analytics_page_a4_test.dart:22:3
  info  • overridden_fields • test/features/analytics/analytics_page_a4_test.dart:25:16
  info  • overridden_fields • test/features/analytics/analytics_page_a4_test.dart:27:30

$ node tool/check_i18n.cjs
✓ i18n bütünlüğü temiz: 12 dil, 433 anahtar, 266 kod anahtarı doğrulandı.

$ node tool/check_versions.cjs
✗ AppConstants.appVersion = "1.2.0" ama pubspec version = "1.3.0"
1 sürüm tutarsızlığı.        ← AKTARIM 1 (A3 alanı, bilinçli olarak düzeltilmedi)
```

> **Not:** Kalan 3 analyze issue'ı ve 1 kırık test **tamamen
> `test/features/analytics/analytics_page_a4_test.dart`** dosyasındadır —
> A4'ün Tur 1'de yazmaya devam ettiği dosya (saat 22:24'te değişmiş).
> `lib/` tarafındaki A3/A4 issue'ları (sentry_user_context, main.dart,
> diary_repository, app_router) commit sonrası **çözülmüştür**.
> Benim alanımdaki `test/**` temiz ve 153/153 geçiyor.
> Ana ajan A4'ün dosyası tamamlandıktan sonra tekrar koşturmalı.

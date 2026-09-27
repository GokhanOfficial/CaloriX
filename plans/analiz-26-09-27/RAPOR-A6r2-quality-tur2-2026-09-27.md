# RAPOR — A6r2-tests-quality — 2026-09-27 — Tur 2

## Özet (5 madde)

1. **React tarafında CI yoktu; eklendi.** `.github/workflows/react.yml`
   (`npm ci` → `tsc -p tsconfig.app.json --noEmit` → `npm run lint` →
   `npm run build`). A5'ın bulduğu `TS5103` (derlemenin hiç çalışmadığı)
   ancak böyle yakalanabilirdi. `permissions: contents: read`, sabit Node
   major'ı, `cache: npm`. İki workflow da `yaml.safe_load` ile doğrulandı.
2. **163 orphan anahtarı silinmedi — silmek PWA'yı kırdı.** Doğrulama iki
   aşamalı çıktı: (a) Tur 1'in `.tr()` regex'i **20 anahtarı yanlışlıkla**
   orphan sayıyordu (çok satırlı zincirleme çağrı + dolaylı anahtarlar);
   (b) düzeltilmiş sınıflandırmada gerçekten ölü olan 63 anahtarın **61'i
   `public/locales` altındaki React çeviri dosyalarında hâlâ canlı**.
   Görevin kabul ettiği ikinci yol seçildi: ratchet (baseline = 63).
3. **A4r2'nin 24 yeni çeviri anahtarı 12 dile de eklendi.** `onboarding.*`
   (15), `auth.changePassword.*` (6), `dialogs.invalidAmount*` (2),
   `chat.errors.assistant`, `chat.loadEarlier`, `updates.unsafeUrl`.
   Bu anahtarlar koddan `.tr()` ile çağrılıyordu ama hiçbir dilde yoktu.
4. **Android widget tarafı CI'da hiç doğrulanmıyordu; doğrulandı.**
   `flutter build apk --debug` `check` işine eklendi. Ölçüm: APK build
   **33 sn**, `:app:compileDebugKotlin` **62 sn ve BAŞARISIZ** → APK build
   seçildi. Ayrıca `@string/*` referans doğrulama adımı eklendi.
5. **`FLUTTER_VERSION 3.47.0` yayımlanmış** (stable, 2026-08-12) — CI'ı
   kırmıyordu ama 5 patch gerideydi → `3.47.5`'e (güncel stable) sabitlendi.
   `check_versions.cjs`'e `defaultFat/Protein/Carbs` ↔ `macros()` kapısı
   eklendi: `defaultFat = 65` sapması ancak böyle yakalanabiliyordu.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|-----|-------|-----------|-----------|
| **P1** | `.github/workflows/react.yml` *(yeni)* | React PWA için tam CI işi: `setup-node@v4` (Node 20, `cache: npm`) → `npm ci` → `npx tsc -p tsconfig.app.json --noEmit` → `npm run lint -- --max-warnings 25` → `npm run build`. `permissions: contents: read`, `concurrency` ile eski çalışma iptali, 12 satırlık `paths` filtresi (`src/**`, `index.html`, `vite.config.ts`, `tsconfig*.json`, `package.json`, `package-lock.json`, `eslint.config.js`, `components.json`, `postcss.config.js`, `tailwind.config.ts`, `public/locales/**`, workflow'ın kendisi) | `yaml.safe_load` OK; `tsc` exit 0; lint 9 uyarı / 0 hata; `npm run build` başarılı |
| **P2** | `.github/workflows/flutter.yml:22` | `FLUTTER_VERSION 3.47.0 → 3.47.5`. Doğrulama: `releases_linux.json` → 3.47.0 (2026-08-12) **yayımlanmış**, güncel stable 3.47.5 (2026-09-18, Dart 3.13.4). Patch farkı `dart analyze` çıktısını değiştirebileceğinden tam sürüm sabit tutuldu | Uzak manifest doğrulandı |
| **P2** | `.github/workflows/flutter.yml` (`check` işi) | `flutter build apk --debug` adımı. Gerekçe: `analyze`/`test` yalnızca Dart'a bakar; `ec681c3` commit'indeki `widget/*.kt` + `res/layout/widget_*.xml` hiç doğrulanmıyordu | Yerelde 33 sn'de `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| **P2** | `.github/workflows/flutter.yml` (`check` işi) | `@string/*` referans doğrulama adımı: tüm `res/**/*.xml` içindeki `@string/x` referanslarının `res/values/strings.xml`'de tanımlı olduğunu kontrol eder (aapt2'den erken, okunabilir hata) | Yerelde `missing=0` |
| **P2** | `.github/workflows/flutter.yml:84` | `flutter analyze` → `flutter analyze --fatal-infos --fatal-warnings`. `analysis_options.yaml` strict-casts/strict-inference/strict-raw-types + 3 lint açık; mevcut taban "No issues found!" olduğu için uyarıları da kapıya almak maliyetsiz | `No issues found!`, exit 0 |
| **P2** | `tool/check_i18n.cjs` | **Regex düzeltmesi (yanlış negatif).** Eski `'a.b.c'\.tr\s*\(` regex'i çok satırlı zincirleme çağrıları (`'k'\n  .tr()`) ve backtick'li iç interpolasyonu kaçırıyordu → 20 anahtar (bmi.*, settings.goals.activity.*, about.version, analytics.charts.macroFocus.title, dashboard.savedAs/waterAdded, chat.newThread) yanlışlıkla "orphan" sayılıyordu. Tırnak+anahtar+tırnak+`.tr(` tek regex'te eşleştirildi | `--report-orphans` çıktısı: 457 anahtar, 294 Flutter + 276 React anahtarı |
| **P2** | `tool/check_i18n.cjs` | **Orphan raporu 4 sınıfa ayrıldı:** `ölü` (iki istemcide de yok), `react` (`src/**` içinde canlı → **silinmez**), `dinamik` (interpolasyonlu kalıp → silinmez), `dolaylı` (literal geçiyor, `.tr()` değil → silinmez). `--report-orphans` bayrağı + kategori bazlı özet | 63 ölü / 67 react / 17 dinamik / 16 dolaylı |
| **P2** | `tool/check_i18n.cjs` | **Ratchet:** `ORPHAN_BASELINE = 63`; üstü hata (exit 1). Dil dosyası sayısı kapısı (`EXPECTED_LANGS = 12`). CI'a uygun `✓`/`✗` özet satırı | `node tool/check_i18n.cjs` → exit 0, yeşil |
| **P1** | `tool/check_versions.cjs` | **Eksik kapı eklendi:** `AppConstants.defaultFat/Protein/Carbs` ile `Calculations.macros(defaultCalories)` çıktısı karşılaştırılıyor. `defaultFat = 65` vs `macros(2000).fat = 67` sapması **hiçbir araçla yakalanmıyordu**. `warnings()` yardımcısı kaldırıldı (CHANGELOG başlığı yoksa artık hata) | Doğru çalışıyor: `✗ AppConstants.defaultFat = 65 ama ... = 67` (A3 bekleniyor) |
| **P1** | `flutter_app/assets/translations/{ar,de,en,es,fr,it,ja,ko,pt,ru,tr,zh}.json` | 24 yeni anahtar eklendi (A4r2 `501cfb1`): 15 `onboarding.*`, 6 `auth.changePassword.*`, `dialogs.invalidAmount`, `dialogs.invalidAmountPartial`, `chat.errors.assistant`, `chat.loadEarlier`, `updates.unsafeUrl`. Kaynak tablo `tool/new_keys_tur2.json`, uygulayıcı `tool/apply_tur2_keys.cjs` | `check_i18n.cjs` → 12 dil / 457 anahtar / 0 eksik; placeholder tutarlılığı ayrıca doğrulandı |
| **P2** | `tool/convert_locales.cjs:11-12` | Yorum `.js` → `.cjs`. Ayrıca **yıkıcı uyarı** eklendi: script `flutter_app/assets/translations/*.json` üzerine yazıyor, kaynak 360 anahtar vs hedef 457 → çalıştırılırsa 97 Flutter-only anahtar sessizce silinir | `node --check` OK |
| **P2** | `README.md:200-212`, `README_EN.md:204-216` | "Frontend | React 18" satırı iki-istemci tablosuyla çelişiyordu. Teknoloji tablosu iki sütuna ayrıldı, Flutter birincil işaretlendi, her istemci için CI dosyası adı verildi | Manuel |
| **P2** | `README.md:186`, `README_EN.md:187` | Yayınlama talimatındaki bayat `version: 1.2.0+3` → `1.3.0+4` + `check_versions.cjs` kapısına atıf | `check_versions.cjs` sürüm satırı yeşil |
| **P2** | `CHANGELOG.md` | `## [flutter 1.3.0+4]` altına React CI, Android derleme doğrulaması, analyze sıkılaştırması, i18n ratchet'i, 24 yeni anahtar ve orphan kararının gerekçesi yazıldı | `check_versions.cjs` sürüm satırı yeşil |

---

## Orphan anahtarı kararı — **silinmedi, gerekçelendi**

Görev "163 orphan anahtarını sil" idi. Silmedim. Ölçüm:

| Aşama | Bulgu |
|-------|-------|
| 1 — araç düzeltmesi | Eski regex **20 anahtarı yanlışlıkla** orphan sayıyordu: `bmi.{4}`, `settings.goals.activity.{5}`, `settings.goals.goal.{3}`, `settings.personalInfo.{3}`, `meals.{4}`, `notifications.{14}`, `about.version`, `analytics.charts.macroFocus.title`, `dashboard.savedAs`, `dashboard.waterAdded`, `chat.newThread`, `settings.goals.{protein,carbs,fat}`. Sebep: (a) `dart format` `.tr(`'i yeni satıra taşıyor, `\s*` yetmiyor; (b) `Calculations.bmiCategory` → `(labelKey: 'bmi.normal')` gibi dolaylı anahtarlar `.tr()` yapmıyor. |
| 2 — React çapraz kontrolü | `flutter_app/assets/translations/*.json` **iki istemciye** hizmet ediyor: Flutter easy_localization **ve** React i18next (`public/locales`, `tool/convert_locales.cjs` ile üretilir, sonra elle genişletilmiş: kaynak 360 anahtar, hedef 457). `src/**` tarandı → adayların **66'sı React'te literal olarak geçiyor.** |
| 3 — sınıflandırma | 457 anahtar → 294 doğrudan `.tr()` + 17 dinamik (`meals.*`, `notifications.*`) + 16 dolaylı + 67 React canlı + **63 ölü**. |
| 4 — bağımsız doğrulama | 63 ölü anahtar `flutter_app/lib`, `test`, `android/app/src`, `supabase`, `src` altında tam anahtar olarak arandı: **0 gerçek eşleşme** (2'si alt-kelime çakışması: `auth.resetPassword` ⊂ `auth.resetPasswordTitle`, `chat.tool` ⊂ `chat.toolUse`). |
| 5 — nihai karar | 63 ölünün **61'i `public/locales/*/translation.json` içinde hâlâ var.** Bunlar React PWA'nın çalışma zamanı kaynağı; PWA `t('chat.emptyTitle')` gibi çağrılar yapıyor. Ortak anahtar uzayı paylaşıldığı için Flutter varlıklarından silmek 10 dilde PWA'yı kırardı. Kalan 2 (`dialogs.fiberG`, `settings.widgets.androidOnly`) bile React'te yok ama 1.3.0'ın widget özellikleri için saklanıyor. |

**Sonuç:** Görevin kabul ettiği ikinci seçenek uygulandı — `ORPHAN_BASELINE = 63` ratchet'i. Yeni anahtar iki istemcide de kullanılmadan eklenirse CI kırar; temizlik yapılırsa baseline düşürülür. Gerekçe `tool/check_i18n.cjs:46-77`'de kayıtlı.

---

## CI süre ölçümü (Android)

| Komut | Süre | Sonuç | Not |
|-------|------|-------|-----|
| `flutter build apk --debug` | **33 sn** (warm Gradle cache) | ✓ başarılı | Kotlin + XML + resource merge + manifest birleşimi |
| `./gradlew :app:compileDebugKotlin` | **62 sn** | ✗ **BAŞARISIZ** | `:app:compileFlutterBuildDebug` bağımlı olduğu için Dart asset paketlemesini de tetikliyor; ayrı hedef avantaj sağlamıyor, üstelik Dart hatasını maskeliyor |
| Soğuk CI tahmini | 8–15 dk | — | `subosito/flutter-action` `cache: true` Gradle/pub cache'ini geri yükler |

**Karar:** `flutter build apk --debug`. Görevin "~15 dakika" öncüsü soğuk-cache içindir; warm cache'te 33 sn. `compileDebugKotlin` hem daha yavaş hem başarısız olduğu için elendi. Ek olarak `--fatal-infos`'un maliyeti ~0 (2 sn).

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|-----|------------|-------|------|-------|
| **P1** | `flutter_app/lib/core/constants/app_constants.dart:20` | `defaultFat = 65`, `Calculations.macros(2000).fat = 67` (2000×0.30/9 = 66.67) | Profil yokken onboarding "2000 kcal" der, makro kartı 65 g yağ gösterir → iki ekranda farklı sayı. **A3r2 alanı; henüz commit atmadı** | A3r2: `67`. `node tool/check_versions.cjs` artık kırmızı — düzeltince yeşile döner |
| P2 | `.github/workflows/*.yml` | Üçüncü parti action'lar (`actions/checkout@v4`, `setup-node@v4`, `setup-java@v4`, `subosito/flutter-action@v2`, `upload-artifact@v4`) SHA'ya pinlenmemiş | Tag yeniden yönlendirilirse CI ele geçirilebilir | Tur 3: commit SHA'sına pinle (`@v4` + `# <40-char sha>` yorumu) |
| P2 | `.github/workflows/react.yml` | `npm run lint -- --max-warnings 25`; repo tabanı 9 uyarı (`react-refresh/only-export-components`) | shadcn/ui + context dosyaları nedeniyle eşik keyfi; yeni uyarılar 25'e kadar sessiz kalır | A5 alanı: 9 uyarıyı temizle, eşiği `0` yap |
| P2 | `flutter_app/lib/core/updates/` | `update_manifest.dart` `sha256` alanını hiç doğrulamıyor | İndirilen APK bütünlüğü teyit edilmiyor | **A3r2 alanı** (transfer defteri 1. satır) |
| P3 | `flutter_app/pubspec.yaml` | 13 doğrudan bağımlılıkta majör sürüm bekliyor (`flutter_riverpod` 2→3, `go_router` 14→18, `fl_chart` 0.69→1.2, `file_picker` 8→13) | Gerçek hata yok | Tur 3 dalga |
| P3 | `flutter_app/android/app/src/main/res/values/strings.xml` | Widget etiketleri yalnızca Türkçe (`widget_daily_label` = "Günlük Özet"); 11 dilde launcher etiketi Türkçe görünür | i18n tutarsızlığı, P3 | `values-XX/strings.xml` eklensin (A3 mimari kararı sonrası) |

---

## AKTARIM

### → A3 (`lib/core/**`)
1. **`defaultFat = 65` → `67`** (`app_constants.dart:20`). Artık CI kapısı var: `tool/check_versions.cjs` `macros(defaultCalories)` çıktısıyla karşılaştırıyor ve **şu an kırmızı**. Sabit düzeltilince `node tool/check_versions.cjs` yeşile döner.

### → A4 (`lib/features/**`, `shared/**`)
2. **24 yeni anahtar 12 dile eklendi** (`501cfb1` commit'inden sonra `check_i18n.cjs` 24 eksik anahtar bildirdi, hepsi karşılandı). Doğrulama notu: `onboarding.step` `{step}/{total}`, `onboarding.errAgeRange` `{min}/{max}`, `dialogs.invalidAmountPartial` `{count}` placeholder'ları `en` ile birebir eşleşiyor.
3. **`auth.changePassword.*` ile `auth.updatePassword`/`auth.newPassword` çakışması yok** — değişiklik parolası dialog'unda 5 yeni anahtar kullanılıyor, kayıt/şifre sıfırlama akışı eski `auth.updatePassword` anahtarlarını kullanmaya devam ediyor. İkisi de doğru.

### → Ana ajan
4. **`lib/core/widgets/**` ölü kod kararı kapandı** — `ec681c3` widget'ları gerçekleştirdi, `check_i18n.cjs` `dashboard.quickAdd` artık dolaylı olarak kullanılıyor. `home_widget`/`workmanager` bağımlılıkları artık gerçekten kullanılıyor.
5. **Docker doğrulaması hâlâ yapılmadı** (T1'den kalan). Bu ortamda docker yok; `curl /settings` → 200 ve `/healthz` → `ok` testi yapılmalı.

---

## Yeni testler

Test dosyası eklenmedi. `flutter test` **379/379 geçiyor** (göreve başlarken 322; artan 57 A2r2/A4r2'nin testleri). Bu turda bulgu **test eksikliği** değil, **CI boşluğuydu** — boşluğu kapatan iş CI işleri ve araç geliştirmesi oldu.

---

## Doğrulama (commit öncesi son durum)

```
$ cd flutter_app && flutter analyze --fatal-infos --fatal-warnings
No issues found! (ran in 2.1s)

$ cd flutter_app && flutter test
00:07 +379: All tests passed!

$ node tool/check_i18n.cjs
✓ i18n bütünlüğü temiz: 12 dil, 457 anahtar, 294 Flutter kod anahtarı,
  2 dinamik kalıp, 276 React i18next anahtarı doğrulandı.
  orphan → ölü: 63/63 · react canlı: 67 · dinamik: 17 · dolaylı: 16

$ node tool/check_versions.cjs
✗ AppConstants.defaultFat = 65 ama Calculations.macros(2000).fat = 67
1 sürüm tutarsızlığı.          ← AKTARIM 1, A3r2 bekleniyor

$ npx tsc -p tsconfig.app.json --noEmit
tsc exit=0                       (öncesi TS5103)

$ npm run lint
✖ 9 problems (0 errors, 9 warnings)

$ npm run build
✓ built

$ python3 -c "import yaml; yaml.safe_load(open('.github/workflows/react.yml'))"
.github/workflows/react.yml OK jobs: ['check']
.github/workflows/flutter.yml OK jobs: ['check', 'build']

$ cd flutter_app && flutter build apk --debug
✓ Built build/app/outputs/flutter-apk/app-debug.apk   (33 sn)
```

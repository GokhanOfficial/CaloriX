# Changelog

All notable changes to CaloriX are documented in this file.

---

# Flutter App

The Flutter app (`flutter_app/`) carries its own version independent of the
React web app. Versions below track `pubspec.yaml` version only.

## [flutter 1.2.1+3] - 2026-08-22

### Changed — Öğün bazlı hatırlatıcılar
- Tekil "sabah hatırlatıcısı" yerine her ana öğün (kahvaltı / öğle / akşam)
  için ayrı açılıp kapanabilen hatırlatıcı ve saat (varsayılan 08:30 /
  12:30 / 19:00). Mevcut kullanıcıların sabah ayarı göçle kesintisiz
  kahvaltı slotuna taşınır.
- Android bildirimleri ve web in-app banner'ı öğün bazlı; "1 saat ertele" /
  "öğünü atla" aksiyonları tıklanan öğünün bildirimi üzerinde çalışır
  (bildirim ID'leri 1001–1003, erteleme 1101–1103).
- Fixed: bildirimler var olmayan `notif.*` çeviri anahtarlarını kullanıyordu
  (ham anahtar metni gösteriliyordu) — `notifications.*` anahtarlarına
  düzeltildi.
- Translations: `notifications.lunch*/dinner*` anahtarları ve güncellenen
  `settings.notifications.reminder*` metinleri 12 dilde.

## [flutter 1.2.0+2] - 2026-08-22

### Added — Zamanlanmış hatırlatıcılar
- Android: günlük sabah kalori/kahvaltı hatırlatıcısı — aç/kapa + saat
  ayarı (Bildirim Ayarları diyaloğu), bildirim aksiyon tuşları
  ("Kahvaltı yapmayacağım", "1 saat ertele"), reboot sonrası plan korunumu.
- Web: uygulama açıkken gösterilen in-app hatırlatma banner'ı (aynı ayarlar).

### Removed — Barkod özelliği tamamen kaldırıldı
- Flutter ve React uygulamalarından tarayıcı/barkod akışı, `mobile_scanner`
  ve `@zxing/library` bağımlılıkları çıkarıldı; `foods.barcode` kolonu ve
  `food_source` enum'undaki 'barcode' değeri düşürüldü
  (`20260822000000_remove_barcode.sql` — mevcut satırlar 'manual'a taşındı).

### Added — Android zorunlu güncelleme mekanizması
- Launch-time update check against the GitHub Releases manifest
  (`releases/latest/download/latest.json`): builds below
  `minSupportedVersionCode` are blocked with a full-screen "Update Required"
  page (browser APK download); older-but-supported builds get a dismissible
  optional-update dialog; offline check falls back to the cached manifest and
  finally opens with a one-time warning.
- `tool/release_android.sh`: builds the release APK, generates `latest.json`
  (versionName/versionCode/minSupportedVersionCode/apkUrl/sha256/notes) and
  publishes both to GitHub Releases; `--min-code` sets the forced-update
  cutoff for breaking changes (e.g. DB migrations).
- Translations: `updates.*` keys in all 12 locales.

## [flutter 1.0.0+1] - 2026-08-16

### Added — Phase foundation (Faz 0–1)
- Flutter project scaffold on `feature/flutter-app` (supabase_flutter PKCE,
  flutter_riverpod, go_router, easy_localization for 12 locales).
- AuthRepository (signUp/signIn/signOut/resetPassword/resend/updatePassword),
  router auth redirect incl. PASSWORD_RECOVERY + onboarding gate.
- AuthPage (auth / forgot / pendingVerification / reset), OnboardingPage
  (5-step wizard, live BMI, Mifflin-St Jeor fallback for calculate-macros).
- Calculations (BMR/TDEE/macros/BMI/water parity with web).

### Added — Daily tracking (Faz 2)
- Food/FoodNutrition, MealEntry, WaterEntry, WeightEntry, FoodItem
  (100g-normalized, forAmount parity) models.
- FoodRepository (search / favorites / recent), DiaryRepository
  (fetchDaily + meal/water/weight CRUD, soft delete).
- Dashboard (DateSelector, CalorieRing, MacroCards, WaterTracker,
  WeightCard, MealSections), AddPage (300ms debounce search), AppShell.

### Added — Analytics + Settings (Faz 3)
- AnalyticsRepository + analytics_page (period selector, stat cards,
  fl_chart calorie/macro charts, weight trend).
- Settings (theme, 5 sections, 12-language picker, camera preference,
  health disclaimer), 4 dialogs (personal info / goals / notifications /
  password), JSON export/import via DataTransferRepository.

### Added — AI + Camera + Barcode (Faz 4)
- AI Chat (ChatMessage, ChatRepository, ChatPage with markdown).
- In-app camera (barcode-scanner style) + native camera + gallery via
  `camera_preference` (in_app|native, default in_app).
- RecognizedFood + RecognitionRepository (photo + text), AddWithAiDialog,
  RecognitionConfirmDialog (web handleSave parity).
- BarcodeFood + BarcodeRepository + BarcodeScanDialog (4-step scan flow;
  uses DB `sugar_g` singular — web `sugars_g` latent bug NOT inherited).
- mobile_scanner 5.2.3 with `kIsWeb` guard (manual entry on web).

### Added — Release pipeline (Faz 5)
- GitHub Actions CI (`flutter.yml`): path-filtered on `flutter_app/**`;
  pub get → build_runner → analyze → test; on main merge build web + AAB.
  Synthesizes a placeholder `.env` so the gitignored asset bundles.
- Android release signing: `key.properties`-driven signingConfig with
  debug-key fallback; R8 minify+shrink with proguard-rules.pro keep rules
  (models / supabase / riverpod / Play Core dontwarn).
- App icon + native splash config (flutter_launcher_icons,
  flutter_native_splash; CaloriX teal #00C7B7). Generators run manually.
- `applicationId com.calorix.app`; pubspec version `1.0.0+1`.

### Notes
- No live Supabase / Edge Function testing was performed (DB deactivated);
  the user will run end-to-end tests after all phases. Validation was
  `flutter analyze` (0 issues), `flutter test` (101/101), web build, and
  `flutter build appbundle --release` (R8 on, 70.9MB).
- Web `BarcodeScanDialog.tsx` inserts `sugars_g` (plural) into
  `food_nutrition`, but the DB column is `sugar_g` (singular) — that column
  silently drops on web. The Flutter app uses the correct singular name.

---

## [1.1.0] - 2026-05-18

### Added
- Added AI Chat nutrition assistant for conversational support around daily food logs, goals, and nutrition decisions.
- Added Supabase Edge Function support for AI chat responses.
- Added database migration support for storing AI chat conversations and messages.

### Changed
- Updated documentation to describe the AI Chat feature and the 1.1.0 release.
- Updated package metadata from 0.0.0 to 1.1.0.

### Removed
- Removed the offline sync feature because it was buggy and caused reliability/data consistency issues.
- Removed offline sync database artifacts via migration.

---

# Değişiklik Günlüğü

CaloriX için dikkat çeken tüm değişiklikler bu dosyada belgelenir.

---

# Flutter Uygulaması

Flutter uygulaması (`flutter_app/`) React web uygulamasından bağımsız kendi
sürümünü taşır. Aşağıdaki sürümler yalnızca `pubspec.yaml` sürümünü izler.

## [flutter 1.0.0+1] - 2026-08-16

### Eklendi — Faz altyapısı (Faz 0–1)
- `feature/flutter-app` branch'inde Flutter projesi iskeleti
  (supabase_flutter PKCE, flutter_riverpod, go_router, 12 dil için
  easy_localization).
- AuthRepository (signUp/signIn/signOut/resetPassword/resend/updatePassword),
  router auth yönlendirmesi (PASSWORD_RECOVERY + onboarding geçidi dahil).
- AuthPage (auth / forgot / pendingVerification / reset), OnboardingPage
  (5 adımlı sihirbaz, canlı BMI, calculate-macros için Mifflin-St Jeor
  fallback'i).
- Calculations (BMR/TDEE/makro/BMI/su — web parity).

### Eklendi — Günlük takip (Faz 2)
- Food/FoodNutrition, MealEntry, WaterEntry, WeightEntry, FoodItem
  (100g-normalize, forAmount parity) modelleri.
- FoodRepository (arama / favoriler / son yenilenler), DiaryRepository
  (fetchDaily + meal/water/weight CRUD, soft delete).
- Dashboard (DateSelector, CalorieRing, MacroCards, WaterTracker,
  WeightCard, MealSections), AddPage (300ms debounce arama), AppShell.

### Eklendi — Analitik + Ayarlar (Faz 3)
- AnalyticsRepository + analytics_page (dönem seçici, istatistik kartları,
  fl_chart kalori/makro grafikleri, kilo trendi).
- Ayarlar (tema, 5 bölüm, 12 dil seçici, kamera tercihi, sağlık reddi),
  4 diyalog (kişisel bilgi / hedefler / bildirimler / şifre), JSON
  export/import (DataTransferRepository).

### Eklendi — AI + Kamera + Barkod (Faz 4)
- AI Chat (ChatMessage, ChatRepository, markdown destekli ChatPage).
- Ekran içi kamera (barkod-tarayıcı stili) + yerel kamera + galeri
  (`camera_preference`: in_app|native, varsayılan in_app).
- RecognizedFood + RecognitionRepository (foto + metin), AddWithAiDialog,
  RecognitionConfirmDialog (web handleSave parity).
- BarcodeFood + BarcodeRepository + BarcodeScanDialog (4 adımlı tarama;
  DB `sugar_g` tekil kullanılır — web `sugars_g` latent bug'u MİRAS
  ALINMADI).
- mobile_scanner 5.2.3, `kIsWeb` guard'ı ile (web'de manuel giriş).

### Eklendi — Yayın pipeline'ı (Faz 5)
- GitHub Actions CI (`flutter.yml`): `flutter_app/**` path filter'lı;
  pub get → build_runner → analyze → test; main merge'de web + AAB build.
  Asset paketlemesi için placeholder `.env` sentezler.
- Android release imzalama: `key.properties` odaklı signingConfig (debug
  fallback'li); R8 minify+shrink + proguard-rules.pro keep kuralları
  (modeller / supabase / riverpod / Play Core dontwarn).
- Uygulama ikonu + açılış ekranı yapılandırması (flutter_launcher_icons,
  flutter_native_splash; CaloriX teal #00C7B7). Üretim elle çalıştırılır.
- `applicationId com.calorix.app`; pubspec sürüm `1.0.0+1`.

### Notlar
- Canlı Supabase / Edge Function testi yapılmadı (DB deaktif); kullanıcı
  tüm fazlar bitince uçtan uca test edecek. Doğrulama `flutter analyze`
  (0 sorun), `flutter test` (101/101), web build ve `flutter build
  appbundle --release` (R8 açık, 70.9MB) ile yapıldı.
- Web `BarcodeScanDialog.tsx` kaydı sırasında `food_nutrition`'a
  `sugars_g` (çoğul) insert ediyor, ancak DB sütunu `sugar_g` (tekil) —
  web'de bu sütun sessizce düşer. Flutter uygulaması doğru tekil adı
  kullanır.

---

## [1.1.0] - 2026-05-18

### Eklendi
- Günlük yemek kayıtları, hedefler ve beslenme kararları hakkında sohbet ederek destek almayı sağlayan AI Chat beslenme asistanı eklendi.
- AI chat yanıtları için Supabase Edge Function desteği eklendi.
- AI chat konuşmaları ve mesajlarını saklamak için veritabanı migration desteği eklendi.

### Değiştirildi
- Dokümantasyon AI Chat özelliği ve 1.1.0 sürümüyle güncellendi.
- Paket metadata sürümü 0.0.0 değerinden 1.1.0 değerine yükseltildi.

### Kaldırıldı
- Hatalı çalıştığı ve güvenilirlik/veri tutarlılığı sorunlarına neden olduğu için offline sync özelliği kaldırıldı.
- Offline sync veritabanı kalıntıları migration ile kaldırıldı.

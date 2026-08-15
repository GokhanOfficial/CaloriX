# CaloriX Flutter — İlerleme Takibi

> Master plan: `flutter-plan-master.md`
> **Not:** Supabase veritabanı şu an deaktif — canlı backend testleri tüm fazlar bittikten sonra kullanıcı tarafından yapılacak.

---

## ✅ Faz 0 — İskelet & Altyapı (tamamlandı: 2026-08-15)

### Yapıldı
- [x] `flutter create --org com.calorix --project-name calorix --platforms=android,web,linux flutter_app`
- [x] `pubspec.yaml` — tüm bağımlılıklar (supabase_flutter, riverpod, go_router, easy_localization, fl_chart, mobile_scanner, **camera**, image_picker, flutter_dotenv, flutter_markdown, share_plus, flutter_local_notifications...)
- [x] `.env.example` şablonu + `.env` gitignore'a eklendi (gerçek değerler test aşamasında kullanıcı tarafından girilecek)
- [x] `lib/core/config/env.dart` — dart-define > .env öncelikli okuma
- [x] `lib/data/supabase/supabase_client_provider.dart` — `initSupabase()` (env eksikse sessizce atlar, uygulama yine açılır)
- [x] `lib/core/theme/app_theme.dart` — Material 3, **dark varsayılan**, `shared_preferences` kalıcılığı (`theme` anahtarı — web ile aynı), `ThemeModeNotifier`
- [x] `lib/core/router/app_router.dart` — 9 route (web path'leriyle birebir), placeholder sayfalar; auth redirect TODO (Faz 1)
- [x] `lib/app.dart` + `lib/main.dart` — EasyLocalization + ProviderScope + MaterialApp.router
- [x] **i18n:** `tool/convert_locales.cjs` — i18next `{{var}}` → easy_localization `{var}` dönüştürücü; **12 dilin tamamı** `assets/translations/` altında (Faz 3'ten öne çekildi)
- [x] `assets/images/logo.png` web'den kopyalandı
- [x] Android: `applicationId com.calorix.app`, `minSdk 23`, manifest izinleri (INTERNET, CAMERA, POST_NOTIFICATIONS), `android:label="CaloriX"`
- [x] Android build düzeltmeleri:
  - `isCoreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.1.4` (flutter_local_notifications)
  - `android/build.gradle.kts` subprojects hook: `camera_android_camerax`'e `androidx.concurrent:concurrent-futures:1.2.0` (CameraX 1.5.3 jspecify derleme hatası çözümü)

### Doğrulama sonuçları
- [x] `flutter analyze` — **0 sorun**
- [x] `flutter test` — **1/1 geçti** (PlaceholderPage widget testi)
- [x] `flutter build web --release` — **✓ Built build/web**
- [x] `flutter build apk --debug` — **✓ Built app-debug.apk**

### Kalan / notlar
- Emulator'de görsel smoke test yapılmadı (gerek yok — placeholder sayfalar)
- Chrome yok → web sadece build edildi, tarayıcı testi yapılmadı
- `proguard-rules.pro` placeholder olarak eklendi (Faz 5'te doldurulacak)
- Flutter doctor: adb çoğaltması uyarısı var (zararsız), Chrome eksik (web run için `CHROME_EXECUTABLE` ayarlanabilir)

---

## ✅ Faz 1 — Auth + Onboarding + Profil (tamamlandı: 2026-08-15)

**Plan:** `flutter-plan-phase1-auth.md`

### Yapıldı
- [x] `AuthRepository` (signUp/signIn/signOut/resetPassword/resendVerificationEmail/updatePassword) — hata biçimi web ile aynı: nullable `AuthException?`; e-posta redirect'leri platforma göre (web: `Uri.base.origin`, mobil: `io.supabase.calorix://reset-callback`)
- [x] Router auth redirect — `_routeDecisionProvider` (sealed: loading/ready): oturum yok→`/auth`, PASSWORD_RECOVERY→`/auth`, profil hatası veya `onboarding_completed=false`→`/onboarding`; `refreshListenable` ile otomatik yeniden yönlendirme
- [x] AuthPage UI — 4 görünüm: auth (Giriş/Kayıt TabBar), forgotPassword, pendingVerification (yeniden gönder + farklı hesap), resetPassword; PASSWORD_RECOVERY eventi otomatik reset görünümüne geçirir; hata mesajları web ile aynı string eşleşmeleri
- [x] Deep link: `io.supabase.calorix://reset-callback` intent-filter AndroidManifest'e eklendi
- [x] OnboardingPage — 5 adımlı sihirbaz (kişisel → boy/kilo [canlı BMI rozeti] → aktivite → hedef → özet); son adımda `MacroCalculator` (önce `calculate-macros` Edge Function, hata/eksikte yerel Mifflin-St Jeor fallback); kayıt `ProfileRepository.update` + `profileProvider` invalidate
- [x] `Profile` modeli (json_serializable, `isOnboardingComplete` getter) + `ProfileRepository` (fetch `.maybeSingle()`, update `updated_at` damgalı) + `profileProvider`
- [x] `UserSetting` modeli + `UserSettingsRepository` (fetchAll→Map, upsert `onConflict: 'user_id,key'`) + `userSettingsProvider`
- [x] `AppConstants` + enum'lar: ActivityLevel (çarpanlar), Goal (kalori modifikatörleri), Gender, MealType (Faz 2 için)
- [x] `Calculations` — BMR/TDEE/hedef kalori/makro (30/40/30)/BMI/su (kg×33)/yaş/ilerleme; web `calculations.ts` parity
- [x] Unit testler (mocktail): **34 test, tamamı geçiyor**
  - `test/data/repositories/auth_repository_test.dart` — 12 test (tüm metotlar + redirect URL + display_name fallback)
  - `test/data/repositories/macro_calculator_test.dart` — 6 test (AI başarı / fallback 3 senaryo / istek gövdesi parity)
  - `test/core/utils/calculations_test.dart` — web parity hesap testleri

### Doğrulama sonuçları
- [x] `flutter analyze` — **0 sorun**
- [x] `flutter test` — **34/34 geçti**
- [x] `flutter build web --release` — **✓ Built build/web**
- [x] `flutter build apk --debug` — **✓ Built app-debug.apk**

### Kalan / notlar
- `json_annotation` ^4.12.0'a yükseltildi (build_runner uyarısı)
- Canlı Supabase testi yapılmadı (DB deaktif) — kullanıcı tüm fazlar bitince test edecek
- iOS deep link yapılandırması yapılmadı (proje android+web+linux hedefli; gerekirse Faz 5'te)

---

## ⏳ Faz 2 — Günlük + Yemek Ekleme (sıradaki)

**Plan:** `flutter-plan-phase2-diary.md`

---

## Faz 2-5 — Beklemede
Planlar hazır: `flutter-plan-phase2-diary.md`, `flutter-plan-phase3-analytics-settings.md`, `flutter-plan-phase4-ai.md`, `flutter-plan-phase5-release.md`

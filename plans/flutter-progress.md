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

## ⏳ Faz 1 — Auth + Onboarding + Profil (sıradaki)

**Plan:** `flutter-plan-phase1-auth.md`

### Yapılacaklar
- [ ] `AuthRepository` (signUp/signIn/signOut/resetPassword/resendVerification)
- [ ] Router auth redirect mantığı (oturum + onboarding durumu)
- [ ] AuthPage UI (giriş/kayıt/şifre sıfırlama sekmeleri)
- [ ] Deep link: `io.supabase.calorix://reset-callback` intent-filter
- [ ] OnboardingPage (çok adımlı form) + `calculate-macros` entegrasyonu
- [ ] `Profile` modeli + `ProfileRepository` + `profileProvider`
- [ ] `UserSettings` modeli + repository
- [ ] Unit testler (mocktail)

---

## Faz 2-5 — Beklemede
Planlar hazır: `flutter-plan-phase2-diary.md`, `flutter-plan-phase3-analytics-settings.md`, `flutter-plan-phase4-ai.md`, `flutter-plan-phase5-release.md`

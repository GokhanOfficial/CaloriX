# Faz 5 — Web Build, CI/CD ve Yayınlama

> Master plan: `flutter-plan-master.md`

## 1. Web build
- `flutter build web --release --web-renderer canvaskit` (grafik/kamera performansı için canvaskit önerilir)
- Env değerleri CI'da `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` ile (web'de dotenv dosyası asset olarak gömüldüğünden CI'da dart-define tercih edilir)
- Barındırma seçenekleri: mevcut Vercel deploy'unun yanına ayrı path/subdomain (`app.yediginibil...`) veya ayrı Vercel projesi — karar yayınlama aşamasında
- Auth redirect URL'leri Supabase Dashboard'a eklenmeli (Site URL + Redirect URLs: Flutter web URL'i)

## 2. Android release
- `key.properties` + upload keystore (Play Console için)
- `flutter build appbundle --release`
- `android/app/build.gradle`: `applicationId com.calorix.app`, imzalama config
- ProGuard/R8: `minifyEnabled true` + keep rules (supabase/riverpod için gerekirse)
- App ikonu + splash: `flutter_launcher_icons` + `flutter_native_splash` (mevcut `public/logo.png` kaynak alınır)

## 3. CI (GitHub Actions önerisi — `.github/workflows/flutter.yml`)
- Tetikleyici: `flutter_app/**` altında değişiklik (path filter — web CI'ından bağımsız)
- Adımlar: flutter setup → `flutter pub get` → `build_runner` (codegen) → `flutter analyze` → `flutter test` → (main'e merge'de) `flutter build web` + `flutter build appbundle`

## 4. Supabase Dashboard yapılandırması (elle, bir kez)
- Authentication → URL Configuration:
  - Redirect URLs'e ekle: `io.supabase.calorix://reset-callback` (Android), Flutter web URL'i
- Edge Function'lar aynı projede — ek değişiklik YOK
- Aynı anon key kullanılır (RLS koruyor)

## 5. Sürüm stratejisi
- Flutter app kendi `pubspec.yaml` version'unu taşır (`1.0.0+1` ile başla; web `1.1.0`'dan bağımsız)
- CHANGELOG.md'e ayrı "Flutter App" bölümü

## 6. Yayın öncesi kontrol listesi
- [ ] Android: login→onboarding→öğün→foto tanıma→chat uçtan uca release build'de test edildi
- [ ] Web build: aynı akış Chrome'da test edildi
- [ ] Aynı hesapla web + Flutter yan yana veri tutarlılığı son kez doğrulandı
- [ ] `flutter analyze` + `flutter test` CI'da yeşil
- [ ] Play Store listeleme metinleri/görselleri (Türkçe + İngilizce)

## Açık sorular (yayın aşamasında karar)
- Flutter web, React web'in yerini alacak mı yoksa paralel mi kalacak? (Varsayılan: paralel, React app korunur)
- iOS hedefi var mı? (Kod tabanı hazır ama Apple Developer hesabı + macOS build ortamı gerekir)

# Faz 0 — Flutter İskeleti & Altyapı

> Master plan: `flutter-plan-master.md`

## Amaç
Boş ama çalışan, Supabase'e bağlanabilen, tema/i18n/router altyapısı hazır bir Flutter projesi.

## Adımlar

1. **Proje oluşturma**
   ```bash
   cd /home/lancebishop/Development/Projects/CaloriX-v2
   flutter create --org com.calorix --project-name calorix flutter_app
   cd flutter_app
   ```

2. **Bağımlılıklar** (`pubspec.yaml`)
   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     supabase_flutter: ^2.8.0
     flutter_riverpod: ^2.5.1
     go_router: ^14.0.0
     easy_localization: ^3.0.7
     shared_preferences: ^2.3.0
     json_annotation: ^4.9.0
     fl_chart: ^0.69.0
     mobile_scanner: ^5.2.0
     camera: ^0.11.0          # in-app kamera (foto çekimi)
     image_picker: ^1.1.2     # galeri + native kamera fallback
     flutter_dotenv: ^5.1.0
     intl: any
   dev_dependencies:
     build_runner: ^2.4.0
     json_serializable: ^6.8.0
     flutter_test:
       sdk: flutter
     mocktail: ^1.0.4
   ```

3. **Env yapılandırması**
   - `flutter_app/.env` (gitignore'a ekle):
     ```
     SUPABASE_URL=...
     SUPABASE_ANON_KEY=...
     ```
   - Değerler web'in `VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY` ile aynı.
   - Alternatif: `--dart-define` (CI için).

4. **Çekirdek dosyalar**
   - `lib/core/config/env.dart` — dotenv okuma
   - `lib/data/supabase/supabase_client_provider.dart` — `Supabase.initialize(...)` + Riverpod provider
   - `lib/core/theme/app_theme.dart` — Material 3 light/dark; web'deki gibi **dark varsayılan**, tercih `shared_preferences`'ta (`theme: dark|light|system`)
   - `lib/core/router/app_router.dart` — tüm route'ların boş placeholder sayfaları + auth redirect iskeleti
   - `lib/app.dart` — `MaterialApp.router` + `EasyLocalization`
   - `lib/main.dart` — `WidgetsFlutterBinding.ensureInitialized()` → dotenv → Supabase init → `ProviderScope` → runApp

5. **i18n iskeleti**
   - `public/locales/en/translation.json` ve `tr/translation.json`'ı `assets/translations/en.json` / `tr.json`'a dönüştüren `tool/convert_locales.js` (Node, repo kökünde, i18next `{{var}}` → `{var}`).
   - Diğer 10 dil Faz 3'te.

6. **Android yapılandırması** (`android/app/build.gradle`, `AndroidManifest.xml`)
   - `minSdkVersion 23`, `targetSdk 34`
   - İzinler: `INTERNET`, `CAMERA` (Faz 4'te kullanılacak ama manifeste şimdi)
   - Deep link (şifre sıfırlama) — Faz 1'de intent-filter eklenecek

7. **Placeholder sayfalar** — her route için basit `Scaffold(appBar: ..., body: Center(Text('...')))`.

## Teslim kriterleri
- [ ] `flutter run` (Android emulator) açılıyor, boş dashboard placeholder görünüyor
- [ ] Supabase init hatasız (console'da bağlantı logu)
- [ ] Tema dark varsayılan, toggle çalışıyor ve kalıcı
- [ ] TR/EN dil değişimi çalışıyor
- [ ] `flutter analyze` temiz

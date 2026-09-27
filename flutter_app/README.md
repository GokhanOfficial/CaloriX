# CaloriX — Flutter Uygulaması

Kalori, makro, su ve kilo takibi yapan Flutter istemcisi. React PWA (`src/`)
bakım modundadır; **bu uygulama ana üründür**.

## Gereksinimler

| Araç | Sürüm | Not |
|------|-------|-----|
| Flutter SDK | 3.24+ (CI: `stable` / `3.47.0`) | `flutter --version` |
| Dart SDK | `^3.13.0` | `pubspec.yaml` → `environment.sdk` |
| JDK | 17 | Android build (`compileOptions.VERSION_17`) |

## Kurulum

```bash
cd flutter_app

# 1) Ortam değişkenleri — .env gitignore'dadır ama pubspec'te asset olarak
#    paketlendiği için dosyanın var olması ZORUNLUDUR.
cp .env.example .env
# .env içindeki SUPABASE_URL / SUPABASE_ANON_KEY değerlerini doldurun.

# 2) Bağımlılıklar
flutter pub get

# 3) Codegen (json_serializable) — .g.dart dosyaları repoda committed,
#    üretimi doğrulamak/üretmek için:
dart run build_runner build --delete-conflicting-outputs

# 4) Çalıştır
flutter run
```

`--dart-define` ile geçici olarak değer geçilebilir; `Env` dart-define'a öncelik
verir (release pipeline'ı bu yolu kullanır):

```bash
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=eyJ...
```

## Kalite kapıları

```bash
flutter analyze     # uyarı/hata sıfır olmalı
flutter test        # tüm testler geçmeli
```

Ek denetimler (repo kökünden, Node 18+ gerekir):

```bash
node tool/check_i18n.cjs      # 12 dilde anahtar bütünlüğü + kod/çeviri eşleşmesi
node tool/check_versions.cjs  # pubspec / AppConstants / CHANGELOG sürüm tutarlılığı
```

## Mimari

```
lib/
  app.dart                 uygulama iskeleti + yönlendirme (GoRouter)
  main.dart                giriş noktası, Sentry, locale/env başlatma
  core/
    config/env.dart        SUPABASE_URL / SUPABASE_ANON_KEY okuma
    constants/             enum'lar ve varsayılan hedefler
    notifications/         öğün bazlı hatırlatıcılar, zamanlama
    observability/         AppLog (Sentry köprüsü)
    router/                rotalar + guard'lar
    theme/                 renk/tema sabitleri
    updates/               GitHub Releases manifesti, zorunlu güncelleme
    utils/                 hesaplamalar (BMI/BMR/TDEE/makro)
    widgets/               ana ekran widget'ı veri sözleşmesi
  data/
    models/                immutable modeller (json_serializable)
    repositories/          Supabase veri erişimi (tek doğruluk kaynağı)
  features/                ekranlar (auth, onboarding, dashboard, add,
                           analytics, chat, settings, about, updates)
  shared/widgets/          ekranlar arası paylaşılan widget'lar
```

**Katman kuralı:** `features/` yalnızca `data/` repository'leri ve `core/`
yardımcıları üzerinden veri okur. Widget'lar Supabase istemcisini doğrudan
 çağırmaz.

## Testler

`test/` altındaki testler saf çekirdek mantığı hedefler; Supabase'e ve
platform kanallarına bağlanmaz.

| Yol | Kapsam |
|-----|--------|
| `test/core/utils/` | BMI/BMR/TDEE/makro hesapları + kenar durumlar |
| `test/core/updates/` | Sürüm manifesti karar mantığı, JSON sözleşmesi |
| `test/core/notifications/` | Öğün hatırlatıcısı varsayılanları ve v1.2 göçü |
| `test/core/widgets/` | Widget snapshot sözleşmesi, pencere/bayatlama |
| `test/core/constants/` | Öğün tipi saat eşikleri |
| `test/data/` | Model JSON, repository, makro hesaplayıcı |
| `test/features/` | Ekran render + saf yardımcı mantık |

## Android sürüm yayınlama

```bash
# Sürümü pubspec.yaml'da yükseltin: version: 1.3.0+4
tool/release_android.sh --notes-tr "..." --notes-en "..."
# Kırıcı DB değişikliğinde:
tool/release_android.sh --min-code 5
```

Script release APK'yı derler, `latest.json` manifestini üretir ve GitHub
Releases'a yükler. Uygulama açılışta bu manifesti kontrol eder; ayrıntı için
[README.md](../README.md#-android-sürüm-yayınlama-ve-zorunlu-güncelleme).

## Çeviriler

`assets/translations/<lang>.json` — 12 dil (`tr`, `en`, `de`, `fr`, `es`,
`it`, `pt`, `ru`, `ja`, `ko`, `zh`, `ar`). `en.json` referans kabul edilir.

Yeni bir çeviri anahtarı eklerken:

1. `lib/` içinde `'anahtar.adi'.tr()` biçiminde kullan.
2. **12 dilin tamamına** anahtarı ekle.
3. `node tool/check_i18n.cjs` ile doğrula — eksik anahtar CI'ı kırar.

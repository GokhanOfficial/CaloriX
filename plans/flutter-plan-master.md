# CaloriX Flutter Uygulaması — Master Plan

> **Branch:** `feature/flutter-app`
> **Hedef:** React (web) frontend'ine paralel, Supabase backend'ini paylaşan Flutter uygulaması
> **Platformlar:** Android (öncelik 1) + Web (öncelik 2); iOS/Desktop tek kod tabanından mümkün
> **Backend:** Değişmiyor — mevcut Supabase projesi, tablolar, RLS ve Edge Function'lar kullanılacak

---

## 1. Bağlam

CaloriX şu anda React + TS + Vite + shadcn/ui ile yazılmış bir PWA. Supabase üzerinde:

- **16 tablo:** `profiles`, `user_roles`, `foods`, `food_nutrition`, `meal_entries`, `water_entries`, `weight_entries`, `notifications`, `notification_preferences`, `user_settings`, `favorite_foods`, `recent_foods`, `push_subscriptions`, `chat_threads`, `chat_messages` (+ kaldırılan `sync_log`)
- **6 Edge Function:** `ai-chat`, `calculate-macros`, `recognize-food` (fotoğraf), `recognize-food-text`, `check-reminders`, `send-notification`
- **Auth:** E-posta/şifre + e-posta doğrulama + şifre sıfırlama (deep link: `/auth?verified=true`, PASSWORD_RECOVERY eventi)

Web uygulaması aynen yerinde kalacak; Flutter uygulaması **aynı Supabase projesine** bağlanacak.

## 2. Teknoloji Kararları

| Konu | Karar | Gerekçe |
|---|---|---|
| Dil/SDK | Flutter 3.x (stable), Dart | Android+Web+iOS tek kod tabanı |
| Supabase | `supabase_flutter` ^2.x | Auth + DB + Functions + Storage hepsi dahili |
| State / DI | `flutter_riverpod` ^2.x | React'teki Context+hooks yapısına en yakın, test edilebilir |
| Navigasyon | `go_router` ^14.x | Declarative route + auth redirect (React Router karşılığı) |
| i18n | `easy_localization` ^3.x | Mevcut 12 dilin JSON çevirileri taşınabilir (public/locales/{ar,de,en,es,fr,it,ja,ko,pt,ru,tr,zh}) |
| Tema | Material 3 `ThemeData`, dark default | Web'deki dark-default davranışıyla uyum |
| Grafikler | `fl_chart` | recharts karşılığı |
| Barkod | `mobile_scanner` (Android/iOS) + `flutter_zxing` veya ML Kit alternatifi (Web) | @zxing/library karşılığı; web'de kamera sınırlı → web'de manuel giriş fallback |
| Kamera (yemek fotoğrafı) | `camera` (in-app çekim) + `image_picker` (native kamera + galeri) | Kullanıcı tercihi: Ayarlar'dan "varsayılan kamera" (uygulama içi / telefon kamerası) seçilir; galeri her zaman ayrı seçenek. Detay: Faz 4 |
| Yerel depolama | `shared_preferences` | localStorage karşılığı (tema, dil, kamera tercihi) |
| HTTP (yedek) | `dio` veya supabase client'ın kendisi | Edge Function çağrıları `supabase.functions.invoke` ile |
| Env/config | `flutter_dotenv` + `--dart-define` | VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY karşılığı |

## 3. Dizin Yapısı

```
CaloriX-v2/
├── src/                  # React web (dokunulmuyor)
├── supabase/             # Backend (dokunulmuyor)
└── flutter_app/          # YENİ Flutter projesi
    ├── lib/
    │   ├── main.dart
    │   ├── app.dart                  # MaterialApp.router, tema, locale
    │   ├── core/
    │   │   ├── config/               # env, constants (SUPABASE_URL, ANON_KEY)
    │   │   ├── router/               # go_router tanımları + auth redirect
    │   │   ├── theme/                # light/dark ThemeData, renkler (web tailwind paletine yakın)
    │   │   ├── localization/         # easy_localization setup
    │   │   └── utils/
    │   ├── data/
    │   │   ├── models/               # Profile, Food, FoodNutrition, MealEntry, WaterEntry,
    │   │   │                         #   WeightEntry, UserSettings, ChatThread, ChatMessage...
    │   │   │                         #   (freezed/json_serializable ile fromJson/toJson)
    │   │   ├── repositories/         # AuthRepository, FoodRepository, DiaryRepository,
    │   │   │                         #   AnalyticsRepository, ChatRepository, SettingsRepository
    │   │   └── supabase/             # client wrapper
    │   ├── features/
    │   │   ├── auth/                 # giriş/kayıt/şifre sıfırlama (AuthPage karşılığı)
    │   │   ├── onboarding/           # OnboardingPage karşılığı
    │   │   ├── dashboard/            # Index — günlük özet, kalori halkası, makrolar
    │   │   ├── add/                  # AddPage — arama, favoriler, son yenilenler, barkod, AI foto/metin
    │   │   ├── analytics/            # AnalyticsPage — fl_chart grafikler
    │   │   ├── chat/                 # ChatPage — AI sohbet (chat_threads/messages + ai-chat fn)
    │   │   ├── settings/             # SettingsPage — profil, hedefler, dil, tema, bildirimler
    │   │   └── about/                # AboutPage karşılığı
    │   └── shared/
    │       ├── widgets/              # ortak UI parçaları
    │       └── providers/            # Riverpod provider'ları (authState, profile, settings)
    ├── assets/
    │   ├── translations/             # tr.json, en.json, ... (public/locales'ten dönüştürülen)
    │   └── images/                   # logo.png vb.
    ├── android/                      # minSdk 23+, INTERNET + CAMERA izinleri
    ├── web/                          # flutter build web
    └── test/
```

## 4. Mevcut Web ↔ Flutter Sayfa Eşlemesi

| React Route | Flutter Route | Not |
|---|---|---|
| `/auth` | `/auth` | signUp/signIn/resetPassword/resendVerification |
| `/onboarding` | `/onboarding` | ilk kurulum (profil + hedefler) |
| `/` | `/` (dashboard) | günlük özet |
| `/add` | `/add` | yemek ekleme akışı |
| `/analytics` | `/analytics` | grafikler |
| `/settings` | `/settings` | ayarlar |
| `/chat` | `/chat` | AI sohbet |
| `/about` | `/about` | hakkında |
| `*` | 404 sayfası | NotFound |

**Auth akışı:** `supabase_flutter` `onAuthStateChange` stream'i dinlenir → go_router `redirect` içinde: oturum yoksa `/auth`, onboarding tamamlanmamışsa `/onboarding`, aksi halde `/`. Şifre sıfırlama için Android deep link + web URL yapılandırması gerekir (`io.supabase.calorix://reset-callback` ve `https://<host>/#/auth`).

## 5. Veri Katmanı

- **Modeller:** `supabase/types.ts` içindeki şemaya birebir denk gelen Dart sınıfları. `json_serializable` (+ opsiyonel `freezed`) ile codegen. Alan adları snake_case ↔ camelCase eşlemesi `@JsonKey` ile.
- **Repository'ler:** Her feature kendi repository'sini kullanır; tümü tek `SupabaseClient` instance'ını paylaşır. Edge Function çağrıları:
  ```dart
  await supabase.functions.invoke('recognize-food', body: {'image': base64, ...});
  await supabase.functions.invoke('ai-chat', body: {...});
  ```
- **RLS:** Web ile aynı — client tarafında ekstra güvenlik mantığı yazılmaz, RLS'e güvenilir.

## 6. i18n Stratejisi

`public/locales/<lang>/translation.json` dosyaları namespace'li (nested) i18next formatında. İki seçenek:

1. **(Önerilen)** Bir dönüştürme scripti (`tool/convert_locales.sh` veya Node) ile nested JSON'ları easy_localization formatına (nested destekler, sadece dosya adı/yapı uyumu) çevirip `flutter_app/assets/translations/` altına koymak. i18next'in `{{var}}` interpolasyonu easy_localization'da `{}` veya `{var}` — script bunu da dönüştürür.
2. Elle başlangıçta sadece `tr.json` + `en.json`, diğerleri kademeli.

## 7. Platform Farkları

| Özellik | Android | Web |
|---|---|---|
| Barkod tarama | `mobile_scanner` (kamera) | Kamera kısıtlı → manuel barkod girişi |
| Foto ile yemek tanıma | In-app kamera (`camera`) / native kamera + galeri (`image_picker`) — ayarla seçilir | `image_picker` (dosya seçici) varsayılan; `camera` web'de getUserMedia ile kısıtlı destek |
| Bildirimler | Yerel bildirim (`flutter_local_notifications`) | Web push yok (kapsam dışı, web uygulaması zaten var) |
| Oturum kalıcılığı | Secure local storage (varsayılan) | localStorage (varsayılan) |
| Deep link | `app_links` / supabase auth | URL hash |

## 8. Fazlar (ayrı dosyalarda detaylandı)

1. **Faz 0 — İskelet & Altyapı** → `flutter-plan-phase0-setup.md`
2. **Faz 1 — Auth + Onboarding + Profil** → `flutter-plan-phase1-auth.md`
3. **Faz 2 — Dashboard + Yemek Ekleme (günlük takip çekirdeği)** → `flutter-plan-phase2-diary.md`
4. **Faz 3 — Analitik + Ayarlar + i18n genişletme** → `flutter-plan-phase3-analytics-settings.md`
5. **Faz 4 — AI Özellikleri (Chat, foto/metin tanıma, barkod)** → `flutter-plan-phase4-ai.md`
6. **Faz 5 — Web build, CI/CD, yayınlama** → `flutter-plan-phase5-release.md`

Her faz, tek başına çalışan (derlenebilir + demo edilebilir) bir artış teslim eder.

## 9. Doğrulama (her fazın sonunda)

- `flutter analyze` temiz
- `flutter test` (model + repository unit testleri, mock Supabase ile)
- Android emulator'de manuel akış testi (login → onboarding → öğün ekle → dashboard'da gör)
- Web: `flutter build web` + `firebase serve`/`python -m http.server` ile smoke test
- Aynı Supabase projesinde web ve Flutter'dan aynı kullanıcıyla veri tutarlılığı kontrolü

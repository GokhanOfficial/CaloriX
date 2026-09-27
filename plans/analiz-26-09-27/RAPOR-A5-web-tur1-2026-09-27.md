# RAPOR — A5-web-legacy — 2026-09-27 — Tur 1

## Özet (5 madde)

1. **React PWA ölü kod değil, çalışıyor.** Kanıt: `index.html:25` → `/src/main.tsx` → `App.tsx:10-18` dokuz route (`/auth`, `/onboarding`, `/`, `/add`, `/analytics`, `/settings`, `/chat`, `/about`, `*`) render ediyor. `vite.config.ts:15-19` `@` alias'ı tanımlı, `components.json` alias'ları eşleşiyor. `npm run build` **başarılı** (3502 modül, ~1.41 MB / 396 KB gzip). Yani `src/` silinebilir bir artık değil, bakım altında yaşayan ikinci istemci.
2. **README iddiaları doğru ve tutarlı.** `README.md:20-28` ve `README_EN.md` "Bu depoda iki istemci var" tablosunu açıkça söylüyor: `flutter_app/` ana uygulama, `src/` React PWA bakım modunda. Ancak teknikteki "Frontend | React 18, TypeScript, Vite" satırı (`README.md:191`, `README_EN.md:193`) tek istemci izlenimi veriyor — **A6'ya aktarıldı**.
3. **En büyük bulgu: `activity_level` enum/snake-case uyuşmazlığı (P1).** UI `veryActive` (camelCase) gönderiyor, DB CHECK constraint `very_active` (snake_case) bekliyor → "Çok Aktif" seçilince `profiles` UPDATE'i başarısız oluyor, hedefler kaydedilmiyordu. 5 yazma/okuma noktası `activityLevelToDb`/`activityLevelFromDb` ile düzeltildi. **Aynı hata Flutter tarafında da var** (enum `.name` = `veryActive`) → **AKTARIM A3/A2**.
4. **`useDataExport` import akışı toplu olarak bozuktu (P1):** var olmayan `recorded_at` kolonu, boş sonuçta `.single()` (PGRST116) ile sessiz import düşürme, `toISOString().split('T')[0]` UTC kayması, kontrolsüz `...food` yayılımı, geçersiz `source` enum değeri. Hepsi düzeltildi; beyaz listeli kolon kopyalama ile de sertleştirildi.
5. **Docker prod hattı güvensizdi (P1):** `Dockerfile.prod` root çalışıyordu, nginx yoktu (SPA fallback yok → her derin link 404), healthcheck yoktu, `docker-compose.prod.yml` var olmayan `.env.prod`'yi zorunlu yüklüyordu. nginx + non-root + `HEALTHCHECK` + CSP/güvenlik başlıkları + read-only FS eklendi.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|-----|-------|-----------|----------|
| P1 | `tsconfig.app.json:3` | `"ignoreDeprecations": "6.0"` kaldırıldı. Bu değer yalnızca TS 6.x'te geçerli; TS 5.8.3 (package.json:83) `TS5103: Invalid value for '--ignoreDeprecations'` veriyordu ve **tsc hiç derleme yapamıyordu**. Kullanılan seçeneklerin hiçbiri TS 5.8'de deprecated olmadığı için seçenek gereksiz; neden dosyada yorum olarak belgelendi. | `npx tsc -p tsconfig.app.json --noEmit` → **exit 0** (öncesi: TS5103) |
| P2 | `tsconfig.json` | Kök dosyadaki **etkisiz** `compilerOptions` bloğu silindi. `files: []` + `references` içeren bir solution-style config'te kök `compilerOptions` alt projelere uygulanmıyor; ayrıca `strictNullChecks: false` yazılıydı ama `tsconfig.app.json`'in `strict: false` kararı zaten geçerliydi — **kapsam dışı kararlar değiştirilmedi**. | `npx tsc -p tsconfig.app.json --noEmit` → exit 0 |
| **P1** | `src/lib/constants.ts:34-64` | `activityLevelToDb()` / `activityLevelFromDb()` eşleyicileri eklendi + gerekçe yorumu. | `tsc` exit 0 |
| **P1** | `src/pages/OnboardingPage.tsx:127,153,303` | `activity_level` okuma → `activityLevelFromDb`; iki yazma (edge fn `calculate-macros` çağrısı + `profiles` UPDATE) → `activityLevelToDb`. | `tsc` exit 0, `npm run build` ✓ |
| **P1** | `src/pages/SettingsPage.tsx:38,88,113,151,207,252` | Aynı eşleyici 3 okuma + 2 yazma noktasına uygulandı. | `tsc` exit 0, build ✓ |
| **P1** | `src/pages/Index.tsx:15,115` | `calculate-macros` edge fn çağrısına `activityLevelToDb` eklendi. | `tsc` exit 0, build ✓ |
| **P1** | `src/hooks/useDataExport.ts` | (a) `localDateFromIso()` eklendi; `toISOString().split('T')[0]` UTC kayması 3 yerde düzeltildi. (b) `weight_entries.recorded_at` **kolonu tabloda yok** (migration `20260111041204_...sql:178-190`) → `created_at` üzerinden türetildi, geçersizse `continue`. (c) `water_entries` ve `foods` varlık kontrolleri `.single()` → `.maybeSingle()` (0 satırda `.single()` PGRST116 hatası veriyor, import sessizce düşüyordu). (d) `foods`/`food_nutrition` insert'leri beyaz listeli kolonlarla yapıldı — kullanıcı kontrollü yedek dosyasından `created_by`/`verified`/`popularity_count`/`id` değiştirilemiyor. (e) `source` enum'u (`barcode`, `photo`, `text`, `manual`; `barcode` migration `20260822000000` ile kaldırıldı) doğrulanıyor, geçersizse `'manual'`. (f) Yedeğin `foods` filtresi `select('*, food_nutrition(*)')` idi ama tablo `source food_source NOT NULL DEFAULT 'manual'` — `barcode` gönderilirse CHECK ihlali. | `tsc` exit 0, `npm run build` ✓ |
| P2 | `src/hooks/useNotifications.ts:77` | **Lint uyarısı 1 giderildi.** `requestPushPermission`, tanımlanmasından önce kullandığı `subscribeToPush`'a `useCallback`'le bağlıydı → daima ilk render'daki closure'ı (ESLint de bağımlılığı raporluyordu). `subscribeToPushRef` + senkronlayan `useEffect` ile fonksiyonel geri çağrım referansı haline getirildi; `toast` bağımlılığı eklendi. | `npm run lint`: 11 → **9 warning, 0 error** |
| P2 | `src/pages/AuthPage.tsx:56` | **Lint uyarısı 2 giderildi.** `useEffect` bağımlılığına `t` eklendi. | `npm run lint`: **9 warning** |
| P2 | `src/hooks/useNotifications.ts:113` | `console.log('Push subscription saved')` kaldırıldı (üretim log gürültüsü; PII değil ama gereksiz). `console.warn`/`console.error` korundu. | `npm run lint` ✓ |
| P2 | `src/hooks/useNotifications.ts:221-261` | `markAsRead` ve `deleteNotification` yalnızca `id` ile filtreliyordu — kullanıcı kapsamı RLS'e bırakılmıştı (RLS policy mevcut: migration `20260111041204:403-411`). Savunma katmanı olarak `.eq('user_id', user.id)` eklendi ve artık `user` yoksa erken dönüş yapılıyor. | `tsc` exit 0 |
| P2 | `src/hooks/useDailyData.ts:79-89` | Yorum eklendi: `.limit(1)` + `.maybeSingle()` doğru birleşim (`.single()` 0/1'de hata verirdi). Davranış değiştirilmedi — **kontrol edildi, hata bulunmadı**. | `tsc` exit 0 |
| P1 | `src/pages/ChatPage.tsx:309-321` | `clearVisibleChat` `error`'ı yok sayıyordu → RLS reddi olsa bile UI sohbeti siliyor, kullanıcı verinin arşivlendiğini sanıyordu. Artık `if (error) throw error`. | `tsc` exit 0, build ✓ |
| P2 | `src/pages/ChatPage.tsx:38-42,250-256` | `MAX_ATTACHMENT_BYTES` (10 MB) + `ALLOWED_ATTACHMENT_TYPES` eklendi; yükleme öncesi boyut ve MIME kontrolü. `<input accept>` yalnızca MIME önerir, uygulamıyordu. | `tsc` exit 0, build ✓ |
| P2 | `src/vite-env.d.ts` | `ImportMetaEnv` arayüzü: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_PROJECT_ID`, `VITE_VAPID_PUBLIC_KEY` tiplendi. Gizli anahtar kastedilmeyeceği yorumla belgelendi. | `tsc` exit 0 |
| **P1** | `Dockerfile.prod` (yeniden yazıldı) | `node:20-alpine` + `npm run preview` → **multi-stage `nginx:1.27-alpine`**. `USER nginx` (non-root), `HEALTHCHECK` (`/healthz`), `chown`/`chmod` ile okunabilirlik, `touch /var/run/nginx.pid` (read-only FS'te `nginx.pid` yazılamıyordu), `VITE_VAPID_PUBLIC_KEY` build arg'ı eklendi. | `docker build` **çalıştırılmadı** (bu ortamda Docker yok) — sözdizimi gözle doğrulandı |
| **P1** | `nginx.conf` (yeni dosya) | SPA fallback (`try_files $uri $uri/ /index.html`) — **önceden hiç yoktu**, `BrowserRouter` derin linkleri (`/settings` vb.) 404 dönerdi. `assets/` immutable cache, `locales/` kısa cache, gzip, `X-Content-Type-Options`/`X-Frame-Options`/`Referrer-Policy`/`Permissions-Policy`/`Content-Security-Policy` başlıkları, `/healthz` ucu. | Sözdizimi gözle doğrulandı |
| P2 | `docker-compose.prod.yml` | Var olmayan `.env.prod` zorunluluğu kaldırıldı. Healthcheck, `read_only: true` + `tmpfs` (`/tmp`, `/var/cache/nginx`, `/var/run`), `security_opt: no-new-privileges:true`, `VITE_VAPID_PUBLIC_KEY` build arg'ı. | `docker compose config` **çalıştırılmadı** (Docker yok) |
| P2 | `Dockerfile` (dev, yeniden yazıldı) | Root çalışıyordu → `addgroup/adduser calorix` + `USER calorix`. `--chown` eklendi. | Sözdizimi gözle doğrulandı |
| P2 | `.dockerignore` (yeniden yazıldı) | `flutter_app/`, `plans/`, `docs/`, `tool/`, `.zcode/`, `.github/` **build bağlamına giriyordu**. `**/*.pem/key/p12/jks/keystore`, `**/key.properties`, `**/.env*`, `.npmrc` eklendi. `docker-compose*.yml` ve `Dockerfile*` kapsam dışı bırakıldı. | `npm run build` hâlâ ✓ (bağlam değişikliği build'i etkilemiyor) |
| P2 | `.gitignore` | `*.pem/*.key/*.p12/*.pfx/*.jks/*.keystore`, `key.properties`, `**/key.properties`, `.npmrc`, `.htpasswd` eklendi (PROTOKOL §3 anahtar materyali); `!.flutter_app/.env.example` istisnası; `.zcode/` eklendi. | `git status` — gizli dosya sızdırmıyor |
| P2 | `docker-compose.yml` | `app` servisine healthcheck (`wget --spider http://127.0.0.1:8080/`, `start_period: 90s` — `npm ci` yavaş). | Sözdizimi gözle doğrulandı |
| P2 | `index.html` | `<html lang="en">` içinde bozuk girinti (satır 16-20), satırlar arasına sızan ham newline'lar, `<!-- TODO -->` yorumu, eksik `theme-color` (dark tema `#0f172a` ama `<html>` beyaz flaş yapıyordu), `referrer` meta, `viewport-fit=cover`. **CSP meta olarak EKLENMEDİ** — `style-src 'unsafe-inline'` gereksinimi nedeniyle HTTP header (nginx.conf) doğru yer; meta CSP `connect-src`'i Supabase host'una bağlamak zorunda kalırdı ve `VITE_SUPABASE_URL` build-time. | `npm run build` ✓, `dist/index.html` yeniden üretildi |

### Doğrulanan, **düzeltilmedi** (yanlış pozitif olduğu teyit edildi)

- **`dangerouslySetInnerHTML`**: tek kullanım `src/components/ui/chart.tsx:70`. Girdi **tamamen statik**: `ChartConfig` nesnesinden üretilen CSS değişkenleri (`--color-${key}`), `THEMES` sabiti üzerinden. Recharts/shadcn'in kanonik kalıbı, kullanıcı girdisi veya API yanıtı işlenmiyor. **XSS yok.**
- **`ChatPage.tsx`**: `dangerouslySetInnerHTML` **yok**. `renderInlineMarkdown` (satır 40-48) ve `renderAssistantContent` (satır 50-93) React text node üretiyor — AI yanıtı dahil güvenli.
- **API anahtarı gömme**: `src/` içinde sabit anahtar, JWT, `service_role`, `sb_secret` **yok** (`grep -rniE "eyJ…|sk-…|service_role|sb_secret" src/` → yalnızca `vite-env.d.ts` içindeki yorum). `client.ts:6` yalnızca `VITE_SUPABASE_PUBLISHABLE_KEY` kullanıyor — doğru anahtar. Repo `.env` içindeki `SUPABASE_DB_PASSWORD` **git'e izlenmiyor** (`git ls-files | grep env` → yalnızca 4 `.env.example` + `env.dart`).
- **`client.ts:11-17`**: `persistSession: true`, `autoRefreshToken: true`, `storage: localStorage` — Supabase varsayılanları ve doğru. Refresh token'ın `localStorage`'da tutulması XSS riskini artırır ama `sb_publishable_` anahtarı (eski `anon` JWT) RLS'e tabidir, `service_role` değil — etkilenmez.
- **`src/lib/calculations.ts` ↔ `flutter_app/lib/core/utils/calculations.dart`**: **birebir aynı.** BMR (Mifflin-St Jeor, `other`→male), TDEE çarpanları (1.2/1.375/1.55/1.725/1.9), 1200 kcal tabanı, makro 30/40/30, BMI 1 ondalık, BMI kategori eşikleri (18.5/25/30), `progress` 0-100 clamp. **Fark yok, düzeltme gerekmedi.** `src/lib/constants.ts` çarpan/modifikatörleri de `flutter_app/lib/core/constants/app_constants.dart:24-63` ile aynı.
- **Konsola PII loglama**: `src/` içinde `console.log` **yok** (kaldırılan tek örnek hariç). Kalanlar `console.error(error)` / `console.warn` — Supabase `PostgrestError` nesneleri (schema adı + kısıt adı, PII değil). Hiçbir yerde stack trace kullanıcıya gösterilmiyor; hatalar `t("common.error")` gibi sabit metinlere çevriliyor.
- **`useAnalyticsData.ts`**: tarih aralığı UTC kayması **yok** — `format(day, "yyyy-MM-dd")` yerel `Date` nesnesi üzerinde çalışıyor (`date-fns`), UTC'ye çevrim yok. `eachDayOfInterval` (satır 121) `Math.min(end, now)` ile gelecek günleri kapsıyor. `daysWithMeals`/`daysWithWater` ayrı ayrı sayılıyor (satır 167-172) — ortalama hesabı doğru.
- **RLS'e güvenip frontend filtrelemesi**: Tüm `user_id` filtreleri mevcut (`useDailyData`, `useAnalyticsData`, `useDataExport`, `ChatPage`). `markAsRead`/`deleteNotification` eksikti → düzeltildi. Kalan yerlerde çift filtreleme savunma katmanı, `user_id`'yi zaten JWT'den alıyor (kullanıcı değiştiremez).

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|-----|-------------|--------|------|-------|
| **P1** | `flutter_app/lib/data/repositories/macro_calculator.dart:67`, `flutter_app/lib/features/onboarding/onboarding_page.dart:150`, `flutter_app/lib/features/settings/widgets/goals_dialog.dart:129` | `activityLevel.name` → `"veryActive"` gönderiliyor; DB CHECK `'very_active'` bekliyor. **Ana Flutter uygulamasında "Çok Aktif" seçilemiyor / hedef kaydedilmiyor.** | Kullanıcı aktivite seviyesini kaydedemiyor | → **AKTARIM A3** |
| **P1** | `flutter_app/lib/data/models/profile.dart:68` | `activityLevel` okunurken `very_active` → enum'a eşlenmiyor (`.name` ile karşılaştırılırsa düşer). | Ayarlar sayfasında seçim kayboluyor | → AKTARIM A2 |
| P2 | `src/hooks/useNotifications.ts:29-43` | `NOTIFICATION_LABELS` ve toast metinleri **Türkçe hardcoded**, uygulama 12 dilde (`i18n.ts`, `public/locales/*`). | i18n tutarsızlığı | A4/tur 2: `notifications.*` çeviri anahtarlarına taşı |
| P2 | `src/hooks/useDataExport.ts:100-118` tüm toast'ları | Export/import toast metinleri de Türkçe hardcoded. | i18n tutarsızlığı | Tur 2 |
| P2 | `src/App.tsx:24-32` + `src/hooks/useTheme.ts` | Tema, React mount'tan sonra `useEffect` ile uygulanıyor. `index.html`'de `class="dark"` yok → ilk boyama beyaz flaş yapıyor. | Koyu temada FOUC (P2) | Tur 2: `index.html`'e `<script>` ile erken `class` uygulaması |
| P2 | `src/hooks/useAnalyticsData.ts:59-60,153-154` | Tüm tarif/hafta hesapları ve etiketler `locale: tr` sabit. | 12 dilde tarih İngilizce/yanlış | Tur 2 |
| P2 | `src/components/dialogs/**`, `src/components/dashboard/**` | 27 shadcn/ui bileşeni `main.tsx`'ten **ulaşılamaz** (statik import analizi, 104 dosyadan 78 erişilebilir): `accordion, alert, aspect-ratio, breadcrumb, calendar, carousel, chart, command, context-menu, drawer, form, hover-card, input-otp, menubar, navigation-menu, pagination, popover, resizable, sidebar, slider, table, toggle, toggle-group, use-toast, NavLink, use-mobile` + `i18n.ts` (side-effect import, çalışma zamanında yükleniyor) + `vite-env.d.ts` (tip). | Bundle ~1.41 MB (396 KB gzip) — `chart`/`carousel`/`sidebar`/`calendar` ağır | **Silme kararı bana ait değil** (PROTOKOL §3 "ölü kod silme kararı sende değilse raporla"). Not: Vite tree-shaking zaten kullanılmayanları bundle'a almıyor; `dist/assets/index-*.js` tek chunk çünkü `manualChunks` tanımlı değil. **Tur 2 önerisi:** `build.rollupOptions.output.manualChunks` ile vendor ayrımı. |
| P2 | `src/App.css` | Hiçbir yerden import edilmiyor (`grep -rn "App.css" src/` → yok). Vite scaffold kalıntısı (`#root { max-width: 1280px; padding: 2rem }` — PWA düzenini bozardı). | 42 satır ölü kod | Güvenli ama **kullanıcı dosyası** → dokunmadım, silme kararı ana ajana |
| P2 | `README.md:191`, `README_EN.md:193` | "Frontend \| React 18, TypeScript, Vite" satırı, iki istemci tablosuyla (`README.md:20-28`) çelişiyor. | Dokümantasyon yanlış yönlendirmesi | → **AKTARIM A6** (README benim alanımda ama A6 dokümantasyon sahibi; ayrı ajanlar düzenliyor) |
| P3 | `vite.config.ts:6` | `defineConfig(({ mode }) => ({...}))` — `mode` parametresi kullanılmıyor. | Ölü parametre | Tur 3 |
| P3 | `eslint.config.js:6` | `ignores: ["dist", "supabase/functions"]` — `node_modules` yok (ESLint varsayılanı atlıyor), `.zcode` yok. | Lint gürültüsü riski | Tur 3 |
| P3 | `Dockerfile.prod`, `docker-compose*.yml` | **Docker bu ortamda kurulu değil — `docker build` / `docker compose config` çalıştırılamadı.** Değişiklikler sözdizimsel olarak gözle doğrulandı, çalışma zamanı test edilmedi. | Doğrulanmamış | Tur 2'de Docker daemon'u olan bir ortamda `docker build -f Dockerfile.prod .` + `curl localhost:8080/settings` (SPA fallback) test edilmeli |
| P3 | `package-lock.json` | `package.json:83` `typescript: ^5.8.3` (caret). `tsc` çıktısına göre kurulu sürüm TS 5.8.3. `ignoreDeprecations` hatası **caret** yüzünden değil, tam sürüm uyumsuzluğundan. | Düşük | → AKTARIM A6 (pinned sürüm) |

---

## AKTARIM (başka alana)

**→ A3-flutter-core / A2-backend-data — `activity_level` enum/snake-case uyuşmazlığı (P1)**

Web tarafını düzelttim (`src/lib/constants.ts:activityLevelToDb/FromDb`). Flutter tarafı **aynı hatayı taşıyor**:

- `flutter_app/lib/core/constants/app_constants.dart:29` → `enum ActivityLevel { ... veryActive(1.9) }` → Dart `.name` = `"veryActive"`
- `flutter_app/lib/data/repositories/macro_calculator.dart:67` → `'activity_level': activityLevel.name`
- `flutter_app/lib/features/onboarding/onboarding_page.dart:150` → `'activity_level': _activity.name`
- `flutter_app/lib/features/settings/widgets/goals_dialog.dart:129` → `'activity_level': _activity.name`
- DB: `supabase/migrations/20260111041204_...sql:39` → `CHECK (activity_level IN ('sedentary','light','moderate','active','very_active'))`
- Edge fn: `supabase/functions/calculate-macros/index.ts:21` → `["sedentary","light","moderate","active","very_active"]`
- Edge fn `ai-chat` da aynı listeyi kullanıyor (`ai-chat/index.ts:242, 367`)

**Dokunmadım** (benim alanım değil). Öneri: enum değerlerini snake_case yapın (`very_active`) veya Serde/`@JsonValue` ile DB'ye snake_case map'leyin. Flutter `app_constants.dart:42`'deki `settings.goals.activity.very_active` **çeviri anahtarı** — enum adını değiştirmek çevirileri kırar, `@JsonValue`/`toDbValue` eşleyicisi tercih edilmeli (web tarafındaki çözümün aynısı).

**→ A1-security — `.env` içinde düz metin DB parolası (P0/P1, işaretleme)**

Repo kökünde `.env` **gitignore'da ve izlenmiyor**, ama içinde `SUPABASE_DB_PASSWORD="DGWgq2MYwgkw0Ked"` düz metin duruyor. Bu anahtar gerçek bir Supabase projesine ait (`bzfnncensolirkqdohpq`). Şunları teyit edin: (a) bu parolanın **rotate** edilmesi gerekiyor (dosya en az bir kez diskte düz metin olarak bulundu, shell history/log'a girmiş olabilir), (b) `SUPABASE_ACCESS_TOKEN` de aynı dosyada bekleniyor. Ben `.gitignore`'ı sıkılaştırdım ama **anahtarı silmedim/döndürmedim** — kullanıcı kararı gerektirir.

**→ A6-tests-quality — CI'da React tarafı doğrulanmıyor**

`.github/workflows/` altında **tek** dosya var: `flutter.yml`. `git log --all -- .github/workflows/` tek commit döndürüyor (`5767af2`) ve içeriği Flutter-only. PROTOKOL §0 "CI'da lint çalıştırılıyor" diyor — bu **doğru değil**: React PWA için `npm run lint` veya `tsc` çalıştıran bir job yok. Doğruladım: `.github/workflows/flutter.yml` `paths:` filtresi yalnızca `flutter_app/**` + kendisini tetikliyor. `src/`'deki bir regresyon (bu turda bulduğum `TS5103` dahil) CI'da yakalanamaz. **Öneri:** `web.yml` ekleyin (`npm ci` → `npm run lint` → `npx tsc -p tsconfig.app.json --noEmit` → `npm run build`).

**→ A6 — Dokümantasyon tutarsızlığı**

`README.md:191` / `README_EN.md:193` "Frontend | React 18, TypeScript, Vite" diyor; `README.md:20-28` iki istemci tablosunu doğru anlatıyor. `README.md:173` sürüm talimatı hâlâ `version: 1.2.0+3` diyor ama `pubspec.yaml` 1.3.0+4 (PROTOKOL §0). README'ler benim alanımda ama A6 dokümantasyon sahibi ve paralel çalışıyor — dokunmadım.

---

## Yeni testler

**Yok.** React PWA'da test altyapısı yok: `package.json:6-12` script'leri (`dev/build/build:dev/lint/preview`) içinde `test` yok, `package.json:69-86` devDependencies'te Jest/Vitest/Testing Library yok, `src/` altında `*.test.*`/`*.spec.*` dosyası yok. Test çatısı eklemek kapsam dışı bir refactor (PROTOKOL §3 "geniş kapsamlı refactor yapma") — **raporlandı, yapılmadı.**

Bunun yerine doğrulama komutlarının üçünü de temiz geçirdim (`build` ✓, `lint` 0 error, `tsc` exit 0) ve iki kritik hesabı Flutter eşdeğerleriyle **elle karşılaştırarak** kanıtladım (`calculations.ts` ↔ `calculations.dart`, `constants.ts` ↔ `app_constants.dart`).

---

## Sonraki öneriler (tur 2 için)

1. **P1 takibi (AKTARIM):** Flutter `activity_level` snake_case haritalaması — ana uygulama, kullanıcıya doğrudan etki ediyor.
2. **Docker runtime testi:** `docker build -f Dockerfile.prod .` + `docker compose -f docker-compose.prod.yml up` → `curl -I localhost:8080/settings` **200** dönmeli (SPA fallback), `curl localhost:8080/healthz` → `ok`, `docker inspect` → `User: nginx`. Bu ortamda Docker yok, doğrulanamadı.
3. **CI'ya React hattı** (AKTARIM A6) — `web.yml`. `tsc` şu an kırıkken bile kimse fark etmedi; bu P1'in CI'ya eklenmesinin gerekçesi.
4. **Bundle boyutu:** `vite.config.ts`'e `build.rollupOptions.output.manualChunks` (react/recharts/supabase/vendor ayrımı). 396 KB gzip tek chunk. React Router route bazlı `React.lazy` ile 9 sayfa da bölünebilir — 8 sayfa mount edilmeden indirilmiyor.
5. **Ölü kod kararı:** 26 shadcn bileşeni + `src/App.css` ulaşılamaz durumda. **Silme kararı bana ait değil** — ana ajan/ana ajan onayıyla temizlenmeli. Not: `NavLink`, `alert`, `breadcrumb`, `pagination` gibi 6'sı 1-2 satır; geri kalanı shadcn scaffold.
6. **i18n:** `useNotifications.ts` ve `useDataExport.ts` toast/label metinleri 12 dil sistemine taşınsın (A4 ile koordinasyon gerekir — ortak `translations/*.json` dosyalarına dokunuyor).
7. **FOUC:** `index.html`'e `class="dark"` + erken uygulama script'i.
8. **Test altyapısı:** en az `src/lib/calculations.ts` için Vitest + birkaç assertion (Mifflin/TDEE/BMI eşikleri). Flutter'da `calculations_test.dart` varsa aynı beklenen değerler web'e de uygulanabilir — tutarlılık kanıtı olur.

# ÖZET — Tur 1 (2026-09-27)

6 ajan eşzamanlı taradı. 4 ajan commit attı (2 ajan hâlâ çalışıyor: A2, A1b).

## Commit'ler (main branch, sırayla)

| Hash | Kapsam | Stat |
|---|---|---|
| `6653687` | `fix(security)` — A1: edge function auth/CORS/validation + RLS sertleştirme | 14 dosya, +1822/−582 |
| `0451ef2` | `fix(web)` — A5: P1 build/runtime/güvenlik + A5 raporu | 21 dosya, +541/−92 |
| `d886ff6` | `test(ci)` — A6: kırık testler + i18n/sürüm denetleyicileri | 21 dosya, +2426/−57 |
| `b92a036` | `docs(ci)` — A6: CI sertleştirme, dokümantasyon hizalama | 5 dosya, +221/−21 |
| `31bbd3f` | `test` — A6: widget_test çeviri beklentisi | 1 dosya |
| `f0bd012` | `chore` — A6: `.gitignore` tekrar kuralları | 1 dosya |
| `be8158a` | `fix(flutter-core)` — A3: hatırlatıcı kayması, APK URL süzgeci, hesap kenar durumları | 20 dosya, +1627/−74 |
| `e0ae053` | `fix(flutter-features)` — A4: bölme hataları, yaşam döngüsü, sınırsız girdi | 25 dosya, +792/−209 |
| `f603e98` | `docs(plans)` — A4 raporu | 1 dosya |

## En kritik bulgular (önem sırasıyla)

1. **`recognize-food` ve `recognize-food-text` edge function'ları hiç çalışmıyordu** — derleme hatası (çift `return new Response(`). AI beslenme tanıma özelliği sessizce ölüydü. → A1, yeniden yazdı.
2. **`check-reminders` anon ile tetiklenebiliyordu** → herhangi biri hatırlatıcıları tetikleyip tüm kullanıcılara bildirim yaptırabiliyordu. Artık internal token gerekiyor. → A1.
3. **`send-notification` BOLA açığı** — `userId` parametresiyle başka kullanıcıya bildirim gönderilebiliyordu. → A1, `requireUserContext` + `user_id` eşleşmesi.
4. **AI fonksiyonlarında timeout yoktu** — `ai-chat`/`recognize-food*` sonsuza kadar asılı kalabiliyor, maliyet sınırsız. → A1, `AbortSignal.timeout` + rate limit.
5. **RLS boşlukları** — 15 tabloda `anon` rolüne tam erişim; `chat_messages`/`chat_threads`/`foods` DELETE politikası yok; 5 `SECURITY DEFINER` fonksiyonda `search_path` sabitlenmemiş. → A1, yeni migration.
6. **Bildirimler sessizce UTC'de planlanıyordu** — `FlutterTimezone` hatası `catch (_)` ile yutuluyordu, `tz.local` UTC dönüyor. TR'de hatırlatıcılar **3 saat kaymış** çalışıyordu. → A3, probe testiyle kanıtlandı.
7. **Hatırlatıcılar ilk açılışta hiç planlanmıyordu** — `reschedule()` `!_initialized`'da isteği düşürüyordu; kalıcı ayarlar sessizce kayboluyordu. → A3.
8. **`tsc` hiç derlemiyordu** — `tsconfig.app.json`'daki `"ignoreDeprecations": "6.0"` TS 5.8.3'te `TS5103` veriyordu. → A5.
9. **`activity_level` enum uyuşmazlığı** — UI `veryActive` gönderiyor, DB `very_active` bekliyor → "Çok Aktif" seçilince hedefler kaydedilmiyordu (React + Flutter). → A5 (React), Flutter tarafı açık.
10. **Zorunlu güncelleme ekranı açık yönlendirme yüzeyi** — uzak `apkUrl` şema doğrulaması olmadan `url_launcher`'a gidiyordu (`javascript:`/`intent:`). → A3 süzgeci ekledi, ekran henüz kullanmıyor.
11. **Docker prod'da nginx yoktu** → SPA fallback yok, `/settings` 404; root çalışıyordu, healthcheck yoktu. → A5, nginx + non-root + CSP + HEALTHCHECK.
12. **Web push bildirimleri fiilen hiç gitmiyordu** — VAPID JWT imzası üretilmiyordu, sadece `t=<public>` konuyordu. → A1b (devam ediyor).
13. **Sentry init hatası beyaz ekran yapıyordu** — `SentryFlutter.init` fırlatırsa `runApp` hiç çağrılmıyordu. → A3.
14. **`Calculations.bmi` boy 0'da ekran düşürüyordu** — `Infinity.round()` → `UnsupportedError`, `MacroCalculator` bunu `try` dışında çağırıyordu. → A3.
15. **Miktar ≤ 0 kaydedilebiliyordu** (`edit_meal_entry`, `add_manual_entry`, `recognition_confirm`) → negatif kalori. → A4.
16. **Kamera ekranında `inactive/resume`'da crash** — nullable controller `!` ile zorlanıyordu. → A4.
17. **10 dilde 5 i18n anahtarı hiç yoktu**; toplam 15 eksik anahtar bulundu. → A6.
18. **163 orphan çeviri anahtarı** (kullanılmıyor). → açık.

## Yanlış pozitifler (araştırıldı, sorun değil)
- `dangerouslySetInnerHTML` yalnızca `src/components/ui/chart.tsx:70`'te, girdi tamamen statik → XSS yok.
- `src/lib/calculations.ts` ↔ `calculations.dart` birebir aynı → fark yok.
- Kırık 2 dashboard testi **testin kendisindeydi** (`"Kayıt gir"` diye bir metin hiç yok; `"300 kcal"` meşru olarak 2 yerde görünüyor). Kod doğruymuş.
- React PWA ölü kod değil: `npm run build` başarılı, 78/104 dosya `main.tsx`'ten erişilebilir.

## Doğrulama durumu
- `flutter analyze`: kendi alanlarında tüm ajanlar temil bildirdi (A2'nin in-flight dosyası hariç).
- `flutter test`: A6 alanında 153/153, A3 68/68, A4 hedef 7/7. A3'ün tam koşusu: `282 passed, 1 failed` (kalan hata A2'nin in-flight `data_write_safety_test.dart`).
- `npm run build` → ✓, `npm run lint` → 9 uyarı (0 hata, öncesi 11), `npx tsc` → exit 0 (öncesi TS5103).
- Migration gerçek Postgres 16'da 3× çalıştırıldı, 0 hata; canlı RLS izolasyon testleri geçti.
- `deno check` 6/6 edge function temiz.
- `node tool/check_i18n.cjs` → ✓ 12 dil, 433 anahtar, 266 kod anahtarı, 0 hata.
- `node tool/check_versions.cjs` → ✗ (`defaultFat` tutarsızlığı, A3 alanında bekliyor).

## Tur 2'ye kalan işler
1. `defaultFat` 65 → 67 (`app_constants.dart:16`).
2. `force_update_page.dart` `isApkUrlSafe` kullanmıyor.
3. `activity_level` enum Flutter tarafında (`macro_calculator.dart:67`, `onboarding_page.dart:150`, `goals_dialog.dart:129`).
4. `macro_calculator.dart:55` `bmi` çağrısı savunmasız.
5. `full_setup.sql` yeni migration'lardan geride → senkronla.
6. `ai-chat` `@ts-nocheck` kaldır, `supabase gen types` çalıştır.
7. `home_widget`/`workmanager` ölü kod kararı: uygula veya kaldır.
8. `sha256` manifest doğrulaması.
9. React CI job'ı (tsc + lint + build) ekle.
10. 163 orphan çeviri anahtarı temizliği + sabit Türkçe metinler.
11. Rate limit kalıcı sayaç tablosu (bellek içi → DB).
12. Docker değişikliklerini çalıştırarak doğrula.

# Transfer Defteri — Ana Ajan (2026-09-27)

Ajanlar arası aktarımların takip listesi. "Durum" alanı: `BEKLIYOR` | `AJAN ATAANDI` | `COZULDU`

## T1 — A5-web-legacy aktarımları

| Sev | Konu | Hedef alan | Dosya | Durum |
|---|---|---|---|---|
| **P1** | `activity_level` enum uyuşmazlığı: Flutter `ActivityLevel.name` = `"veryActive"` (camelCase) ama DB CHECK constraint'i ve edge function `very_active` (snake_case) bekliyor. "Çok Aktif" seçilince profil yazımı başarısız oluyor, hedefler kaydedilmiyor. | flutter data + features | `flutter_app/lib/data/repositories/macro_calculator.dart:67`, `flutter_app/lib/features/onboarding/onboarding_page.dart:150`, `flutter_app/lib/features/settings/widgets/goals_dialog.dart:129` | BEKLIYOR (A2/A4 turu biterken) |
| **P0 işaretleme** | `.env` içinde düz metin `SUPABASE_DB_PASSWORD`. Proje frozen olsa da credential sızıntısı riski. | operasyon | `.env` | BEKLIYOR (ana ajan notu) |
| **P1** | CI'da **React için hiç job yok**. `.github/workflows/` altında tek `flutter.yml` var (`paths: flutter_app/**`). Bu yüzden `TS5103` gibi derleme kırılmaları yakalanamıyor. | ci | `.github/workflows/` | BEKLIYOR (A6'ya iletilecek) |
| **P2** | `README.md:191` "Frontend | React 18" satırı, iki-istemci tablosuyla çelişiyor; sürüm talimatı bayat. | docs | `README.md` | BEKLIYOR (A6) |
| **P2** | `docker-compose.prod.yml` / `Dockerfile.prod` değişiklikleri **bu ortamda doğrulanamadı** (docker kurulu değil). Tur 2'de `curl /settings` → 200 ve `curl /healthz` → `ok` ile test edilmeli. | ops | docker | BEKLIYOR |
| P3 | 26 ulaşılamaz shadcn bileşeni + `src/App.css` (42 satır, hiç import edilmiyor) — ölü kod, silinmedi. | web | `src/components/ui/*`, `src/App.css` | BEKLIYOR (düşük öncelik) |

## T1 — A1-security aktarımları

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P1** | `check-reminders` artık `x-calorix-internal: 1` başlığını kabul etmiyor; mobil istemci hatırlatmayı doğrudan tetikleyemiyor. | flutter core | AJAN ATAANDI (A1b) — aslında bu bir **regresyon değil, bilinçli güvenlik kararı**; istemci tetikleme yapmıyorsa sorun yok, A3 doğrulayacak |
| **P1** | VAPID imzası üretilmiyor → web push bildirimleri fiilen hiç gitmiyor. | supabase | AJAN ATAANDI (A1b) |
| **P2** | `full_setup.sql` yeni migration'lardan geride (chat tabloları, GRANT'ler, `search_path=''`, DELETE politikaları yok) → yeni kurulumlar zayıf korumalı. | supabase | BEKLIYOR |
| **P2** | `ai-chat/index.ts` içinde `@ts-nocheck`; `supabase gen types` gerekiyor. | supabase | BEKLIYOR |
| **P3** | `profiles.timezone` kolonu hiç kullanılmıyor, `UTC+3` sabit kodlanmış. | supabase | BEKLIYOR |
| P2 | `test/tz_probe_temp_test.dart` geçici teşhis dosyası repoda kalmış olabilir → silinmeli. | test | BEKLIYOR (A6) |

## T1 — A6-tests-quality aktarımları

| Sev | Konu | Hedef | Dosya | Durum |
|---|---|---|---|---|
| ~~P1~~ | ~~`appVersion` 1.2.0 → 1.3.0~~ | flutter core | `app_constants.dart` | **COZULDU (A3, `be8158a`)** |
| **P1** | `defaultFat = 65` ama `macros(2000).fat = 67` → tutarsız makro kartı. | flutter core | `flutter_app/lib/core/constants/app_constants.dart:16` | BEKLIYOR (A3 kendisi çözmedi) |
| **P1** | `home_widget` + `workmanager` bağımlılıkları **hiç kullanılmıyor**; native widget dosyası yok. `buildDailySnapshot`/`buildWeeklySnapshot`/`shouldSendNudge` yalnızca testlerden çağrılıyor → ~700 satır ölü kod, 1.3.0 duyurusu gerçeği yansıtmıyor. **Karar:** ya widget'ı gerçekten uygula (native Android widget + `home_widget` bridge) ya bağımlılıkları ve kodu kaldır. | mimari | `flutter_app/pubspec.yaml:60-61`, `flutter_app/lib/core/widgets/**` | BEKLIYOR (ana ajan kararı — tur 2) |
| **P2** | `FLUTTER_VERSION: 3.47.0` CI'da sabit; stable'da yayımlanmamış olabilir → CI kırılabilir. Yerelde kurulu sürümle karşılaştır. | ci | `.github/workflows/flutter.yml:22` | BEKLIYOR |
| **P2** | `convert_locales.cjs:11` yorumu `.js` diyor, dosya `.cjs`. | ci | `tool/convert_locales.cjs` | BEKLIYOR (A6 tur 2) |
| **P3** | 13 Flutter bağımlılığında majör sürüm yükseltmesi bekliyor. Gerçek hata yok, dokunulmadı. | deps | `pubspec.yaml` | BEKLIYOR (tur 3) |

### A6 tarafından yapılanlar (doğrulandı)
- Kırık 2 dashboard testi: **testte uydurma metinler** (`"Kayıt gir"`, tekilleştirilmemiş `"300 kcal"`), kod doğruymuş.
- `tool/check_i18n.cjs` (12 dil / 433 anahtar / 0 hata) + `tool/check_versions.cjs` → CI'ya bağlandı.
- 10 dilde eksik 5 i18n anahtarı gerçek çevirilerle eklendi; A4'ün 5 yeni anahtarı da eklendi.
- CI sertleştirildi: `permissions: contents: read`, secret'lar `run:` → `env:`, path filter genişletildi.
- 82 yeni test, 2 assertion'sız probe dosyası silindi. A6 alanında analyze temiz, 153/153 pass.
- **A6'nın bildirdiği kalan tek kırık test:** `test/features/analytics/analytics_page_a4_test.dart` (A4'ün dosyası) — 3 analyze issue + yükleme hatası.

### A6'ya cevap gerekiyor (A5 aktarımı)
- CI'da **React için job yok** (`.github/workflows/` altında tek `flutter.yml`). `TS5103` sınıfı derleme kırılmaları yakalanmıyor → React `tsc`+`lint`+`build` job'ı eklenmeli.
- `README.md:191` "Frontend | React 18" satırı iki-istemci tablosuyla çelişiyor.

## T1 — A3-flutter-core aktarımları

| Sev | Konu | Hedef | Dosya | Durum |
|---|---|---|---|---|
| **P1** | Zorunlu güncelleme ekranı `apkUrl` güvenlik süzgecini **kullanmıyor** (`core/updates/update_gate.dart`'de `isApkUrlSafe` var, ekran `force_update_page.dart:19-26` kullanmıyor) → açık yönlendirme yüzeyi. A3 `update_gate`'i düzeltti ama ekranı kendi alanı dışı bıraktı. | features | `flutter_app/lib/features/update/force_update_page.dart:19-26` | BEKLIYOR (A4) |
| **P1** | `macro_calculator.dart:55` `bmi`'yi `try` **dışında** çağırıyordu. A3 `bmi`'yi 0'a bölme yerine 0.0 dönecek şekilde düzeltti, ancak çağrı yeri hâlâ korumasız. | data | `flutter_app/lib/data/repositories/macro_calculator.dart:55` | BEKLIYOR (A2) |
| **P1** | `lib/core/widgets/**` (446 satır) **hiçbir yere yazılmıyor**. `buildDailySnapshot`/`buildWeeklySnapshot`/`shouldSendNudge` yalnızca testlerden çağrılıyor; `MainActivity.kt` 5 satırlık boş `FlutterActivity`; `home_widget`+`workmanager` bağımlılık var, kullanılmıyor. A3 ve A6 bağımsız olarak aynı sonuca vardı. **Karar gerekli: gerçek widget'ı uygula (native Android `AppWidgetProvider` + `home_widget` bridge) ya da bağımlılık+kodu kaldır.** | mimari | `flutter_app/lib/core/widgets/**`, `pubspec.yaml:60-61` | BEKLIYOR (ana ajan, tur 2) |
| P2 | `sha256` manifest'te **hiç doğrulanmıyor** → indirilen APK bütünlüğü teyit edilmiyor. | core | `core/updates/update_manifest.dart` | BEKLIYOR (A3, tur 2) |
| P2 | `core/config/env.dart`: `String.fromEnvironment` değerleri build'e **gömüyor** (şifreleme değil) + `.env` asset olarak paketleniyor → sızdırılabilir. | core | `core/config/env.dart` | BEKLIYOR (A3/A1 tur 2) |
| P2 | Temasal kontrast: `destructive` rengi açık temada ~1.9:1 (WCAG AA gerekir). | core | `core/theme/app_theme.dart` | BEKLIYOR (A3, tur 2) |
| P3 | Exact-alarm izni geri çekilmemiş, iOS hedeflenmemiş, `shouldSendNudge` saat kırpması yok, release log görünürlüğü. | core | çeşitli | BEKLIYOR (tur 3) |

### A3'ün en değerli bulguları (doğrulandı, `be8158a`)
1. **Bildirimler sessizce UTC'de planlanıyordu**: `notification_service.dart:50-57` `FlutterTimezone` hatasını `catch (_)` ile yutuyordu; `tz.local` `initializeTimeZones()` sonrası UTC. TR'de hatırlatıcılar **3 saat kaymış** çalışıyordu. Probe testiyle kanıtlandı.
2. **Hatırlatıcılar ilk açılışta hiç planlanmıyordu**: `reschedule()` `!_initialized`'da isteği düşürüyordu, `ReminderSettingsNotifier.build()` asenkron init'ten önce çalışıp kalıcı ayarları sessizce kaybediyordu.
3. `update_gate.dart`: uzak `apkUrl` doğrudan `url_launcher`'a gidiyordu (`javascript:`/`intent:` şeması yüzeyi).
4. `Calculations.bmi` boy 0'da `Infinity.round()` → `UnsupportedError` → ekran düşüyordu.
5. `AppLog` release modunda PII sızdırıyordu (`scrubPii` eklendi).
6. `SentryFlutter.init` fırlatırsa `runApp` hiç çağrılmıyordu → **beyaz ekran** (`runZonedGuarded` + fallback).
7. DST: `add(Duration)` yerine `TZDateTime`; saat dilimi değişiminde yeniden planlama; web "ertele" ölü özelliği + sınırsız map.
8. Router: profil hatasında kullanıcı onboarding'e zorlanıyordu; `GoRouter` dispose edilmemişti.

## T1 — A4-flutter-features aktarımları

| Sev | Konu | Hedef | Dosya | Durum |
|---|---|---|---|---|
| **P1** | Zorunlu güncelleme ekranı `isApkUrlSafe` süzgecini kullanmıyor (A3 bunu `update_gate`'e ekledi, ekran hâlâ ham `apkUrl`'i `url_launcher`'a veriyor) → açık yönlendirme. | features | `features/update/force_update_page.dart:19-26` | BEKLIYOR (tur 2, A4) |
| **P1** | `macro_calculator.dart:55` `bmi` çağrısı `try` dışında (A3 `bmi`'yi güvenli yaptı, çağrı yeri hâlâ savunmasız) | data | `data/repositories/macro_calculator.dart:55` | BEKLIYOR (A2) |
| **P1** | `activity_level` enum uyuşmazlığı: `"veryActive"` vs DB'nin beklediği `"very_active"` → "Çok Aktif" kaydedilemiyor. (A5 buldu, hem React hem Flutter'ta.) | data+features | `macro_calculator.dart:67`, `features/onboarding/onboarding_page.dart:150`, `features/settings/widgets/goals_dialog.dart:129` | BEKLIYOR (A2/A4 tur 2) |
| P2 | `analytics_repository.dart:328` — oturum yoksa repository'ye gitmeden `empty` dönüyor; "veri yok" ile "oturum yok" ayırt edilemiyor. Kullanıcı giriş yapmamışken analitik ekranı "0 veri" gibi görünüyor. | data | `data/repositories/analytics_repository.dart:328` | BEKLIYOR (A2) |
| P2 | Sabit Türkçe metinler (çeviri anahtarı olmayan): `onboarding_page.dart` ~17 satır, `password_dialog.dart:96,99,122,131`, `analytics_page.dart:838` (`['Protein','Karbonhidrat','Yağ']`). | features | çeşitli | BEKLIYOR (tur 2/3) |
| P2 | **163 orphan çeviri anahtarı** (`dialogs` 34, `dashboard` 27, `chat` 18, `settings` 17, …) — 12 dil dosyalarında var ama kodda kullanılmıyor → ölü i18n yükü. | i18n | `assets/translations/*.json` | BEKLIYOR (A6, tur 2 — temizlik kararı gerekiyor) |
| P2 | `transfer_dialogs.dart:45` `'CaloriX backup'` sabit metin — marka mı çeviri mi? | features | `features/settings/widgets/transfer_dialogs.dart:45` | BEKLIYOR (karar) |
| P2 | Chat geçmişi sayfalamasız → uzun sohbetlerde tüm mesajlar bellekte | features | `features/chat/chat_page.dart` | BEKLIYOR (tur 3) |
| P3 | `analytics_page.dart:97` `onRefresh` yalnızca invalidate ediyor, "yenileniyor" geri bildirimi yok | features | — | BEKLIYOR (tur 3) |

### A6'ya A4'ten eksik çeviri anahtarları (A4 kodu `.tr()` ile çağırıyor, JSON'da yok)
`common.comingSoon` (`shared/widgets/placeholder_page.dart:30`), `errors.notFound` (`features/not_found/not_found_page.dart:13`), `dialogs.flash` (`features/add/widgets/in_app_camera_screen.dart:205`), `dialogs.photoTooLarge` (`features/add/widgets/add_with_ai_dialog.dart:112`), `dialogs.amountRequired` (`features/add/widgets/recognition_confirm_dialog.dart:521`).
Ayrıca `onboarding.*` ve `auth.changePassword.*` anahtar önerileri A4 raporunun AKTARIM bölümünde.

### A4'ün düzeltmeleri (doğrulandı, `e0ae053`, 25 dosya +792/−209)
- Sıfıra bölme: `analytics_page.dart` hedef 0/negatif profil → NaN/infinity (5 nokta), ortak `_percent()` guard + **retry butonu** eklendi.
- `RangeError`: 6 yerde sınırsız `stats[i]`/`trend[i]`.
- Yaşam döngüsü: `app.dart:42,66` iptal edilmeyen `StreamSubscription` + çift abonelik; `weight_card`/`water_tracker` inline `showDialog` + dispose edilmeyen controller; `in_in_app_camera_screen` `inactive/resume`'da `!` ile zorlanan nullable camera controller → crash.
- Veri bütünlüğü: `edit_meal_entry`, `add_manual_entry`, `recognition_confirm` **miktar ≤ 0 kaydedebiliyordu**.
- Yutulan hata: `settings_page._signOut`, `password_dialog` (pop sonrası SnackBar), `chat_page` yükleme hatası sessizce yutuluyordu → `_LoadErrorBody` + retry.
- `StateError`: `transfer_dialogs` `.single` → `.first`, 25 MB sınır.
- `onboarding_page` `_calculate` ve `_handleComplete` try/catch'sizdi → crash.
- Üst sınırlar: 500 kg / 5000 ml / 10 MB.

## TUR 2 — görevlendirmeler (2026-09-27 gece)

### A1 → A1r2 (`supabase/**`) — ✅ TAMAMLANDI (`ad5f219`, `385ad4b`)
1. ~~**P0 (A2'nin bulgusu):** UPDATE politikalarında `WITH CHECK` eksik.~~ → **COZULDI, ancak A2'nin P0 iddiası YANLIŞ çıktı.** A1r2 `pg_policies.with_check`yi sorguladı ve 4 tabloda (`workups`, `weight_logs`, `water_logs`, `goals`) zaten dolu olduğunu gördü. Ayrıca PostgreSQL'te `WITH CHECK` yoksa `USING`'i fallback olarak yeniden değerlendirir — yani hijack zaten engelleniyordu. Yine de 15 tablo için `USING` + `WITH CHECK` açıkça yazıldı (savunma-derinliği). Kanıt: `supabase/tests/rls_policies.sql`.
   **Ders: "politikada WITH CHECK yok" ≠ "açık var". Postgres fallback davranışını bil.**
2. **Gerçekten bulunan ve düzeltilen açıklar:** `chat_threads`/`chat_messages` politikaları `TO public` idi → `TO authenticated`; `foods`/`food_nutrition` UPDATE politikaları `USING`'sizdi; eksik DELETE politikaları; `anon`+`PUBLIC` için `REVOKE ALL`; 5 `SECURITY DEFINER` fonksiyonda `search_path=''`; `recent_foods.food_id` ve `chat_messages.thread_id` değiştirilebiliyordu (RLS `OLD`'a erişemez → `freeze_immutable_columns()` trigger ile çözüldü, `to_jsonb(NEW)/to_jsonb(OLD)`).
3. `full_setup.sql` migration yoluyla **parite**ye getirildi: 55 politika, 49/49 test iki tarafta da aynı.
4. Kalıcı rate limit: `rate_limits` tablosu + atomik `rate_limit_hit()`/`cleanup_rate_limits()` RPC, `search_path=''`, yalnız `service_role`. 10 paralel istek testi → tam olarak 5 izin.
5. `ai-chat` `@ts-nocheck` kaldırıldı; 2 gerçek tip hatası `requireEnum` + allow-list ile çözüldü (`as` cast kullanılmadı).
6. **Doğrulama:** `deno check` 14/14 · `deno test` 19 geçti · migration'lar 3× idempotent çalıştı.
7. **Kısıt:** `supabase db reset` mümkün değildi (CLI yok) → elle kurulan Postgres 16.15 Docker ile doğrulandı; PostgREST/JWT yok. Rate-limit'in PostgREST `rpc()` yolu deploy sonrası smoke test istiyor.

### A2 → A2r2 (`flutter_app/lib/data/**`) — ✅ TAMAMLANDI (`e5a9d44`)
1. ✅ `lib/data/activity_level_map.dart` → `activityLevelToDb(ActivityLevel)` / `activityLevelFromDb(Object?)`. DB değerleri migration CHECK'inden okundu; `exhaustive switch` (yeni enum değeri derleme hatası verir); round-trip 5/5; küme bütünlüğü her iki yönde birebir; 12 tolerans testi.
2. ✅ `macro_calculator.dart:68` — asıl hata: `ActivityLevel.name` (`veryActive`) edge function'a gidiyordu, `calculate-macros` yalnız snake_case kabul ediyor → **her onboarding AI isteği 400** alıyordu.
3. ✅ `analytics_repository.dart` — `AnalyticsAuthRequired` durumu eklendi (oturum yok ≠ veri yok). `features/**`'e dokunulmadı, UI hala `e is AnalyticsAuthRequired` ayrımını yapmıyor → **kalan iş**.
4. ✅ `bmi`/`bmr` çağrıları `_safeBmi`/`_safeBmr`/`_safeInt` ile savunuldu.
5. ✅ `lib/core/utils/num_parsing.dart` (`numOr`/`numOrNull`/`formatDateOnly`/`randomUuidV4`).
6. ✅ `chat_threads.title` artık çeviri anahtarı yazmıyor (NULL).
7. ✅ `randomUuidV4` — `Random.secure()` tabanlı, RFC 4122 v4/variant bitleri doğru, bağımlılık eklenmedi.

**Kalan (A4 alanı):** `weight_card.dart:72` ve `personal_info_dialog.dart:166` → `asNameMap()[p.activityLevel]` **her zaman `moderate`'a** düşüyor (DB snake_case döner) → `activityLevelFromDb(...)` kullanılmalı.

### A3 → A3r2 (`flutter_app/lib/core/**`) — 🔄 DEVAM EDİYOR (`ses_f1b2a4df3ffesEy0fpZMg3Rn0C`)
İlk deneme HTTP 404 ile öldü, yeniden başlatıldı.
1. `defaultFat` 65→67 (`check_versions.cjs` hâlâ kırmızı).
2. Manifest `sha256` doğrulaması.
3. `env.dart` gömülen sır değerlendirmesi.
4. Tema kontrastı (`destructive` ~1.9:1).
5. `num_parsing.dart`'i `core/` geneline benimseme.
6. Widget köprüsü incelemesi.

### A4 → A4r2 (`flutter_app/lib/features/**`, `app.dart`, `shared/**`) — ✅ TAMAMLANDI (`501cfb1`, `32248e8`)
1. ✅ `force_update_page.dart` — `isApkUrlSafe` kapısı; 13 test `launchUrl` **çağrılmadığını** kanıtlıyor.
2. ✅ `activity_level` 4 noktada (2 yazma + 2 okuma). A2'nin `lib/data/` sürümüne bağlandı, geçici kopya silindi.
3. ✅ `ChatException` + `ArgumentError` yakalandı; `recognition_confirm_dialog`'da kısmi kayıt için ayrı mesaj.
4. ✅ 35 yeni çeviri anahtarı (onboarding 24, auth.changePassword 6, dialogs.invalidAmount 2, chat 2, updates 1) — A6 12 dile uyguladı, placeholder'lar 0 uyuşmazlık.
5. ✅ Sohbet geçmişi 200 mesajlık pencere; `analytics_page onRefresh` artık bekliyor.
6. ⚠️ `analytics_page.dart:99` `error:` dalı `AnalyticsAuthRequired` ayrımı **yapılmadı** → A2'nin durumu UI'da karşılıksız, kullanıcı yine "veri yok" görüyor. **Tur 3.**

### A6 → A6r2 (`flutter_app/test/**`, CI, `tool/**`, çeviriler, dokümantasyon) — ✅ TAMAMLANDI (`8ebdad5`)
1. ✅ `.github/workflows/react.yml` eklendi (Node 20, `cache: npm`, `npm ci`, tsc + lint + build, `permissions: contents: read`, 12 satır `paths`).
2. ✅ **163 orphan anahtar silinmedi — silmek PWA'yı kırdı.** İki aşamalı doğrulama: Tur 1'in regex'i 20 anahtarı yanlışlıkla orphan sayıyordu (çok satırlı `.tr()`, dolaylı `bmi.*`/`meals.*`); düzeltilmiş sınıflandırmada gerçek ölü 63 anahtarın **61'i `public/locales`'te hâlâ canlı** (React i18next dosyaları Flutter dosyalarının üst kümesi). Çözüm: `ORPHAN_BASELINE = 63` ratchet'i (`check_i18n.cjs:46-77`).
3. ✅ A4'ün 24 çevirisi 12 dile uygulandı.
4. ✅ Android derleme kapısı: `flutter build apk --debug` **33 sn** vs `:app:compileDebugKotlin` **62 sn ve BAŞARISIZ** → APK build seçildi. Ayrıca `@string/*` referans doğrulama adımı. `analyze` artık `--fatal-infos --fatal-warnings`.
5. ✅ `FLUTTER_VERSION 3.47.0` yayımlanmış (2026-08-12) ama 5 patch geride → `3.47.5`. `check_versions.cjs`'e `defaultFat/Protein/Carbs` ↔ `macros()` kapısı eklendi.

**Kalan riskler (A6):** `check_versions.cjs` A3 commit'ini bekliyor · action etiketleri SHA'ya pinlenmemiş (Tur 3) · lint eşiği 25 keyfi (9 mevcut uyarı) · `strings.xml` widget etiketleri yalnızca Türkçe (P3) · Docker doğrulaması yapılamadı.

## T3 — A1r3 aktarımları (güvenlik, commit `13d87a5` + `689a46b`)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P0** | **Hesap silme UI'ı yok.** Edge function hazır (`delete-account`), ama kullanıcıya "Hesabımı Sil" girişi + **parola onay ekranı** yok. Mağaza/KVKK zorunluluğu ve ölü bir özellik. `POST {SUPABASE_URL}/functions/v1/delete-account` gövdesi `{"password":"..."}`, `Bearer <kullanıcı tokenı>`; 200 sabit / 401 `"Parola hatalı"` / 429 bekle. | features (A4 sonraki tur) | **AJAN ATAANDI (Tur 4)** |
| P1 | Silme sonrası `supabase.auth.signOut()` + yerel önbellek temizliği yapılmalı. | features | Tur 4 |
| P2 | Yeni **7 cihaz sınırı** var: push abonelik kaydı hatası sessizce yutulmamalı, kullanıcıya gösterilmeli. | data/features | Tur 4 |
| P2 | 256 KB gövde sınırı + **`Content-Type: application/json` zorunluluğu** (415). `supabase.functions.invoke()` sorunsuz; elle `fetch` eden yol varsa başlık eklenmeli. | data | Tur 4 (A2r3 kontrol ediyor) |
| P3 | `push_subscriptions` yeni 7 cihaz sınırı hatası tablo adı sızdırıyordu → düzeltildi. | — | ✅ |

### A1r3'ün **benim brifimdeki hatayı yakalaması** (davranışsal not)
Görev brifinde "iki HKDF adımı, `p256dh` gerekmez" demiştim. A1r3 bunu
**reddedip doğruladı**: RFC 8291 §3.3/§3.4 **üç** adım istiyor ve `p256dh`
**zorunlu** (ECDH peer key + `key_info`). `auth` yalnızca HKDF *salt* girdisi.
Brifi uygulayan bir ajan tarayıcının açamayacağı, sessizce kaybolan push
üretirdi. **Ders: ajanlara reçete yazma, davranışı tarif et — ajanlar
literatürü doğrulayabiliyor.**

### A1r3'ün yeni bulguları (doğrulandı)
1. **P1 `check-reminders` haftalık özeti günde ~12 kez gönderiyordu** — damga
   kolonu (`last_weekly_summary`) hiç yoktu. ISO hafta kontrolü ile düzeltildi.
2. **P1 `push_subscriptions` kullanıcı başına sınırsızdı** → 7 cihaz trigger'ı.
3. **P1 `readJsonBody` 1 MB varsayılan sınırdı** → 256 KB + `Content-Type` zorunluluğu (415).
4. Push gövdesi artık **gerçekten şifreleniyor** (RFC 8188+8291 `aes128gcm`),
   VAPID imzası bozulmadan. Testler modülün `ecdh_secret`/`PRK`/`CEK`/`NONCE`
   değerlerini **RFC 8291 Ek A'nın yayımlanmış değerleriyle** karşılaştırıyor
   (hepsi birebir) — bu düzeyde doğrulama iyi bir örnek.
5. Temiz çıkanlar: `TO public` politika yok, `search_path` kaçağı yok,
   SQL injection yok, `service_role` sızma yolu yok, hata mesajlarında şema sızıntısı yok.

### A1r3 doğrulama kanıtları
`deno check` 17/17 · `deno test` 54/0 · 15 migration sıfırdan 0 hata · yeni
migration 3× idempotent · RLS 98/98 (migration yolu **ve** `full_setup.sql` yolu).
Hesap silme **gerçek Postgres 16'da uçtan uca**: 14 tablo → 0, idempotent,
başka kullanıcının verisi korundu.

### Kalan riskler (A1r3)
`supabase db reset` çalışmıyor (CLI yok) → canlıda tekrar doğrulanmalı ·
edge function'lar **çalışır halde** denenmedi (gerçek push servisi/FCM'e istek
atılmadı) · hesap silmenin parola/`admin` yolu gerçek Supabase Auth'e karşı
 denenmedi · `check-reminders`'ta `profiles.update()` hatası hâlâ yutuluyor (P2) ·
`profiles.timezone` hâlâ kullanılmıyor (`UTC+3` sabit).

## T3 — A4r3 aktarımları (ekranlar, commit `489d6ea`+`85dae8c`+`0523740`+`cd4ea59`)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P0 (kendi geçmiş hatası)** | `chat_page.dart:408` — A4r2'ın pencerelemesi **her sohbeti çökertiyordu**: `itemBuilder` indeks ofseti `+` idi, `_hasMore` true iken `visible[i]` → `RangeError`. Test yazıp **kırmızı olduğunu kanıtladı**, düzeltti. | — | ✅ |
| **P1 (canlı hata, ölçüldü)** | **TDEE sapması %18,4 eksik.** `very_active` DB değeri `asNameMap()` ile okunamadığı için `moderate` (1.55) sayılıyordu; doğrusu `veryActive` (1.90). Somut: 30y/erkek/175cm/80kg → **2759 yerine 3382 kcal/gün**. `auto_recalculate_macros` açıksa kalıcı olarak hedefe yazılıyordu. | — | ✅ (A4r2'de düzelmişti, A4r2 etkisini ölçtü) |
| P2 | `dialogs.amountRequired` metni yanlış: koşul `r.amount <= 0` ama metin "Miktar gerekli". **A4r3'ün önerisi (a):** çeviri değiştirmek yerine kodda `dialogs.invalidAmount`'a geçir — o anahtar zaten 12 dilde var ve durumu doğru anlatıyor, **0 çeviri işi**. | data/features | **AJAN ATAANDI (Tur 4)** |
| P2 | `analytics_page.dart` **1239 satır**, `chat_page.dart` **969 satır** — bölme önerisi. | features | Tur 5 |
| P2 | `FilledButton.icon` ikonlarında `Semantics(label:)` yok (metin butonun kendisinden geliyor, yeterli ama tam değil). | features | Tur 5 |

### A4r3'ün kendi avı (yeni, düzeltilen)
| Sev | Dosya | Bulgu |
|---|---|---|
| P1 | `chat_page.dart:294` | `await archiveThread` sonrası `setState` (mounted yok) → dispose sonrası çökme; hata `catch`'e düşüp **başarılı arşivlemeyi "temizlenemedi" diye** gösteriyordu |
| P1 | `shared/widgets/date_selector.dart:40` | `await showDatePicker` sonrası `WidgetRef` → "Cannot use ref after dispose" |
| P1 | `settings/widgets/widget_settings_dialog.dart:85` | `await showTimePicker` sonrası aynı desen |
| P1 | `settings/widgets/goals_dialog.dart:111` | `await calculate` sonrası `setState`; `finally` koruması `setState`'ten sonra geliyordu |
| P1 latent | `add/widgets/recognition_confirm_dialog.dart:209` | `setState(_saving=true)` sonrası erken `return` → Kaydet butonu kalıcı kilit (**şu an erişilemez**, düzeltildi) |
| P2 | `auth/auth_page.dart:316` | Şifre göster/gizle ikon butonunda `tooltip` yok (WCAG 4.1.2) |

### ⛔ A4r3'ün **geri aldığı** bulgu (davranışsal not — çok değerli)
`recognition_confirm_dialog` önizlemesinde "`/10` = 10 kat şişirme" iddiası
**test yazınca yeşil kaldı**. Gerçek neden: `(x/10).round()/10 ≡ round(x/100*10)/10`
— matematiksel olarak **özdeş** (200.000 rastgele çiftle doğrulandı, 0 uyuşmazlık).
A4r3 değişikliği **geri aldı, testi sildi ve raporlamadı.**
**Ders: "mantıklı görünen" bir iddiayı test et; test yeşilse iddiayı bırak.**

### A4r3'ün kalan riskleri
- **`widget_bridge_scope_test.dart` 4 hata + 1 timeout** → tam `flutter test`
  paketi kırmızı. Bu dosya **A3r2'nin commit'lenmemiş** yeni dosyası.
- `showDatePicker`/`showTimePicker` `flutter_test`'te sürülemiyor → iki `mounted`
  düzeltmesi için **strict regresyon testi yazılamadı** (smoke-test seviyesinde).
  Gerçek riski: düzeltmeler mantıken doğru, kanıt zayıf.
- Erişilebilirlik tam audit yapılmadı.

## T4 — A1r4 aktarımları (güvenlik, commit `54b88d0` + `4181404`)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P1** | `delete-account` **kısmi silmede 200 "başarı"** dönüyordu. Tablo silme hatası `continue` ile yutuluyordu → KVKK gereği eksik silme başarı gibi görünüyordu. `{deleted, failed}` + `DELETION_PARTIAL_MESSAGE` + `retryRecommended` eklendi. | — | ✅ (A1r4) |
| **P1** | `delete-account` rate limit 5/saat → **2/saat**. Parola doğrulandığı için 5 gereksizdi (yıkıcı + geri alınamaz işlem). Anahtar kullanıcı bazlı (doğrulandı). | — | ✅ (A1r4) |
| **P1** | `MAX_PLAINTEXT_BYTES = 3993` **off-by-one**: başlık 21 + GCM 16 + delimiter 1 çıkarılmamış. `preparePushPayload` 4096 **karaktere** izin verdiği için **3993-4058 baytlık** pencerede uzun HTML'li `weekly_summary` **push'u sessizce kaybediyordu** (e-posta + DB kaydı yazıldığı için görünmüyor). `rs=32` + 40 bayt da RFC §4 ihlaliydi. | — | ✅ (A1r4) |
| **P1** | 4 edge function'da `ValidationError` mesajı istemciye sızıyordu. | — | ✅ (A1r4) |
| P1 | `profiles.timezone` artık okunuyor + migration ile IANA allow-list CHECK'i. **TR kullanıcıları için davranış değişmiyor** (kolonu kimse yazmıyordu → NULL → `Europe/Istanbul` normalize → eski sabit `+3` ile aynı). | — | ✅ (A1r4) |
| P2 | `deleteAuthUser` içindeki `includes("not found")` çok geniş eşleşme — **düzeltilmedi, raporlandı**. | supabase | Tur 5 |
| P2 | **`foods` silinmiyor** — `created_by` FK'si `ON DELETE SET NULL` (Postgres'te kanıtlandı) → gıda kalır. **Ürün kararı gerekiyor**: kullanıcının eklediği yiyecek topluluk verisiyle paylaşılıyor mu, yoksa silinmeli mi? | ürün kararı | **ANA AJAN → A4r5'e sorulacak** |
| P2 | `dbBypassUntil` 60 sn bypass (nedeni belgelenmeli). | supabase | Tur 5 |
| P3 | `deno.lock` repoda **takip edilmiyor** → CI'da `cache: true` ilk çalışmada faydasız. | ci/tool | Tur 5 |

### A1r4'ün doğrulama kanıtları
`deno check` 0 hata · `deno test` **100/0** (54→100) · 16 migration sıfırdan 0 hata
(`pg_cron`/`pg_net` satırları shim'lendi) · yeni migration 3× idempotent ·
RLS 49/49 iki yolda · `full_setup.sql` sıfırdan 0 hata, 55 politika ·
YAML geçerli (`jobs:['edge']`, `permissions: contents:read`, `timeout: 15`).

### A1r4'ün **kendi ekibinin kodunu denetlemesi** (davranışsal not)
A1r3'ün yazdığı `delete-account` ve push şifrelemesini bağımsız denetledi ve
**3 gerçek hata** buldu. Bu, turların kendi kodunu değişen ajanları geri çağırma
pratiğinin işe yaradığını gösteriyor. **Tur 5'te aynı pratiği sürdür.**

## T4 — A2r4 aktarımları (veri, commit `7f7cde0` + `befb5d9` + `20c4707`)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P0/P1** | **Kısmi import imkânsız hale getirildi.** Üç faz: önce doğrula (ağ yok) → varlık kontrolü (yalnız GET) → toplu + telafili yazma. Tek ölümcül ihlalde **hiçbir istek atılmaz**; yazma hatasında o turda yazılanlar `id` ile fiziksel olarak silinir; `counts` **her zaman** dolu. 42 test. | — | ✅ (A2r4) |
| **P1** | **Eski "güvenli" dönüştürmeler aslında ölümcüldü**: `amount_ml`/`weight_kg` geçersizde `0` yazılıyordu → DB CHECK 400 → **tüm import öğünler yazıldıktan sonra** düşüyordu. Besin satırında sayı olmayan zorunlu alan `0`'a çevriliyordu = **sessiz yanlış besin değeri**. İkisi de ön-uçu ölümcül oldu. | — | ✅ (A2r4) |
| **P1** | **2000 istek ölçüldü ve çözüldü**: 4506 → **37 istek** (POST 4480 → 9). `importBatchSize = 500` (Postgres parametre tavanı 65535'e karşı 7000 = %11). | — | ✅ (A2r4) |
| **P1** | Kayıp güncelleme (race) kapatıldı: `updateMealEntry(expectedUpdatedAt:)` + `MealEntryConflictError`. | features | **AJAN ATAANDI (Tur 5)** |
| P2 | `favorite_foods`/`recent_foods` **dışa aktarılıyor ama içe aktarılmıyor** → yedek→geri yüklemede favoriler kaybolur. | data | Tur 5 |
| P2 | `photo_url` yedeğe giriyor ama **bucket içeriği girmiyor** → geri yüklemede kırık görsel. 25 MB sınırı var, ürün kararı gerekiyor. | ürün kararı | Tur 5 |
| P2 | Web `useDataExport.ts` **aynı hataları taşıyor** (kısmi import, tarih kayması). | src | Tur 5 |
| P3 | `sanitizeFood` ölü kod · `MealEntry.updatedAt` nullable · `exportData` `select()` tüm kolonlar. | data | Tur 6 |

### A4r4'e / A4r5'e zorunlu (A2r4 yazdı, features kapsamı dışında bıraktı)
1. `transfer_dialogs.dart:97` `catch (_)` → iki ayrı kol:
   `ImportValidationError` (`.issues`/`.summary`) ve `ImportWriteError` (`.report`).
2. `recognition_confirm_dialog.dart:547` `amountRequired` → `invalidAmount` + `isUsableAmount`.
3. `edit_meal_entry_dialog.dart:132` `expectedUpdatedAt` + `on MealEntryConflictError`
   yakalama (başka cihazda güncellenmişse kullanıcıya bildir).
4. Telafi başarısız olursa `rolledBack=false` → "bazı kayıtlar eklendi" mesajı.

### A1r4'e (RPC aktarımı — **yapılmadı, raporlandı**)
`import_data(jsonb)` RPC'si (Seçenek A) atomiklik verirdi ama: migration +
`GRANT/REVOKE` + ~200 satır PL/pgSQL + **iki istemci** değişikliği gerektirir,
`meal_entries`'te dedup `UNIQUE` **yok** (`ON CONFLICT` çalışmaz, `WHERE NOT EXISTS`
gerekir) ve **bu ortamda Postgres çalıştırılamadığı** için "e2e doğrulandı"
denemez. Seçenek B (telafi) tercih edildi ve 42 testle kanıtlandı.
RPC istenirse: `SECURITY DEFINER` + `search_path=''` + `v_user := auth.uid()` görevli,
`pg_proc.proacl` doğrulaması ve hesap silme denetimine eklenmeli.

### A2r4'ün yeni avı
- Su dedup'u dize → **epoch mikrosaniye** (`+00:00` ↔ `Z` aynı kaydı iki kez ekliyordu)
- Yazılabilir satırda tarih çözümlenemiyorsa **atlanmıyor, ölümcül oluyor** (sessiz veri kaybı)
- `foods`: `verified`/`popularity_count` yazılmıyordu (popmod trigger'ı artırıyor)
- `created_at` toplu yazımda kayboluyordu → yedekten taşınıyor
- `exportData` **6 hassas tabloyu sorgulamıyordu** (testle sabitlendi)
- `Profile.activityLevel` → `ActivityLevel?` yapıldı; `json_serializable` bu alanda
  **kullanılamıyor** (`as ActivityLevel?` derlenmez) → `fromJson`/`toJson` elle,
  `profile.g.dart` silindi. `activityLevelFromDb` API'si bozulmadı.

## T5 — A2r5 aktarımları (veri, commit `850c63b` + `5a1c9f6`)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P1** | **Favoriler/son kullanılanlar geri yüklenmiyordu.** `exportData` `favorite_foods` + `recent_foods` + `notification_preferences` yazıyordu, `importData` **hiçbirisini okumuyordu** → yedek→geri yüklemede favoriler **sessizce** kayboluyordu. Üçü de içe aktarıma eklendi (`user_id` her kayıtta → RLS; `food_id` **ad** üzerinden → yeni id; eşleşmeyen kayıt **atla+raporla**, ölümcül değil). | — | ✅ (A2r5) |
| **P1** | **Uçtan uca round-trip testi yoktu.** `backup_round_trip_test.dart` (19 test): tam veri seti → export → import → ikinci export → alan alan karşılaştırma. Sahte DB `RETURNING id` + NOT NULL/FK/UNIQUE/CHECK + `timestamptz` biçimi + `foods!inner(name)` embed'ini taklit ediyor. | — | ✅ (A2r5) |
| **P1** | Test yazarken bulunan **veri bozulması**: `food_nutrition.nova_score` geçersizde `_count()`'un **sayaç değeri** (1, 2, 3…) yazılıyordu → sınıflandırılmamış gıda "1 = işlenmemiş" olurdu. 42 test kaçırmıştı. | — | ✅ (A2r5) |
| **P2** | `favorite_foods`/`recent_foods` için `created_at` sözleşmeye girmiyordu → toplu `insert` `StateError` ile **tüm import'u** düşürüyordu. | — | ✅ (A2r5) |
| **P2** | Tanıma sonucu bozuk elemanla çöküyordu: `numOr` NaN/Infinity filtrelemiyordu (`1e999` → `forAmount()` → `UnsupportedError`) ve `e as Map<String,dynamic>` tek bozuk elemanla tüm ekranı düşürüyordu. | — | ✅ (A2r5) |
| **P2** | `DiaryRepository.totals` **ham double**, `AnalyticsRepository.aggregateDaily` **yuvarlıyor** → aynı gün iki ekranda iki farklı sayı. Testle sabitlendi, kod değişmedi (ürün kararı). | ürün kararı | Tur 6 |
| P3 | `_rollback` DELETE **etkisini doğrulamıyor** (istek atmama durumu `rolledBack = true` sayılıyor). | data | Tur 6 |

### A6r5'e (web) — `src/**`

`src/hooks/useDataExport.ts:81-82` favorileri/son kullanılanları dışa
aktarıyor, `importData` **okumuyor** → web'de **aynı veri kaybı**. Dokunulmadı.

> Tur 5'te paralel çalışan `src/lib/import/backupImport.ts` + `backupRestore.ts`
> (commit `34fb23a`, 1119 + 424 satır) bu yolu **zaten uygulamış** görünüyor.
> **Karar tutarlı** — "eşleşmeyen `food_id` → atla + raporla, ölümcül değil"
> (`backupImport.ts:402-423`), Flutter ile aynı. Doğrularken üç noktaya bak:
>
> 1. **`user_id` her kayıtta yazılıyor mu?** Kolon gövdeden düşerse
>    (`defaultToNull: true`) RLS `WITH CHECK (auth.uid() = user_id)`
>    (`full_setup.sql:332/337`) → **tüm import** 400 düşer.
> 2. **`notification_preferences` web'de de eklenmeli mi?** Flutter'da
>    ekledim (`UNIQUE(user_id, notification_type)`, CHECK allow-list
>    `20260927120000_…:411-423`). Web'de aynı kayıp var. **Not:** Flutter UI'ı
>    tür bazlı tercihleri henüz yazmıyor (`notifications_dialog.dart:17`) →
>    tablo iki istemcide de pratikte hep boş.
> 3. **Telafi sırası:** `favorite_foods` FK'si `ON DELETE CASCADE` →
>    favoriler `foods`'tan **önce** silinmeli. Flutter'da
>    `importTables.reversed` veriyor; test `backup_round_trip_test.dart`
>    "telafi sırası" ile sabitliyor.

### A4r5'e (features) — `photo_url` kararı

Araştırma sonucu: **hiçbir istemci `photo_url` yazmıyor**
(`recognition_confirm_dialog.dart:238` açıkça `photoUrl: null`; web'de
yazan yok) → "kırık görsel" senaryosu **bugün mümkün değil**. Bu yüzden
**kod yazılmadı**, karar rapora bırakıldı.

> **Görev metnindeki "25 MB sınırı" YANLIŞ.** Gerçek sınır
> `chat-attachments` bucket'ında **10 MB** (`full_setup.sql:674`) ve o bucket
> **sohbet ekleri** için; ölçüm görselleri için **hiç bucket yok**.

| | Seçenek | Karar |
|---|---|---|
| A | Export'a base64 katmak | ❌ `exportData` `JsonEncoder.withIndent` **tüm yedeği bellekte** üretir (`:163`) → 10 MB × N görsel = **OOM**; `importBatchSize`/Postgres 65535 parametre tavanı patlar; ölçüm görseli **veri değil çıktı**; `chat-attachments` bucket'ı özel ekler için (`thread_id` klasörü `:303`) |
| B | Geri yüklerken "görseller dahil değil" de | ✅ **Önerilen** |
| C | Hiçbir şey yapma | ❌ "Yapılmış" sayılıp ileride özellik gelince **sessiz** bozulur |

**Önerilen uygulama:** (1) `data` alanında export gövdesine
`'media': {'included': false, 'reason': …, 'columns': ['meal_entries.photo_url', 'foods.image_url']}`
anahtarı; (2) `transfer_dialogs.dart`'da tek satır uyarı; (3) ileride
fotoğraf yükleme özelliği gelirse ayrı `meal-photos` bucket + **`photo_url`
değil `storage_path`** tutan tablo (imzalı URL yenileme deseni zaten var:
`chat_repository.dart:325-362`).

### A1'e (supabase)
Ölçüm görselleri için bucket **yok** (`full_setup.sql:665-695` yalnız
`chat-attachments`). Fotoğraf yükleme eklenirse ayrı bucket + politika bloğu;
migration **yeni dosya** olarak eklenmeli.

### ⭐ Ürün/A1 kararı bekleyen bulgu (Tur 6)
**`favorite_foods`/`recent_foods` tabloları hiçbir istemci tarafından
yazılmıyor.** İki istemci de favorileri `meal_entries`'ten **hesaplıyor**
(son 200/50 kayıt, `food_repository.dart:111-168` ↔ `useFavoriteFoods.ts:59`).
Sonuç: (a) geri yüklenen favoriler **bugün UI'da görünmez**; (b) iki tablo
DB'de gereksiz. Ya türetilmiş kalmalı (tablolar silinmeli), ya da gerçek tablo
olmalı. Şu an "hangi gerçek?" belirsiz.

## T6 — A3r6 aktarımları (çekirdek denetimi, commit `69a3a54`+`f1684b9`+`5e2422a`)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P0 (benim kodum)** | **Widget tazeleme hiç çalışmıyordu.** `HomeWidget.updateWidget(name: name, androidName: name)` çağrılıyordu; home_widget 0.10.0 sınıfı `qualifiedAndroidName ?: "$packageName.$className"` ile çözüyor → `applicationId` = `com.calorix.app` olduğu için `com.calorix.app.DailyWidgetProvider` arıyor → `ClassNotFoundException`. Yani öğün ekleme, ayar değişimi, "Güncelle" — **hiçbiri widget'a ulaşmıyordu**. Düzeltme: yalnız `androidName`. A6r3'ün "ilk değer yok" bulgusundan bağımsız. | — | ✅ (A3r6) |
| **P1** | Bildirimde 4 sessiz kayıp: (a) `zonedSchedule` bir öğünde patlayınca **diğerleri de** planlanmıyordu; (b) `_exactAllowed` yalnız init'te bir kez okunuyordu → kullanıcı tam alarm iznini kapatınca hatırlatıcılar **sessizce hiç gelmiyordu**; (c) `POST_NOTIFICATIONS` reddi hiçbir yerde görünmüyordu; (d) dilim çözülemezse UTC'ye düşülüyordu ama `AppLog` release'de DSN boşsa **tamamen kayboluyordu**. `NotificationScheduleOutcome` + her `reschedule`'te izin yeniden okuma. | — | ✅ (A3r6) |
| **P1** | `nextDailyOccurrence` sonucu `tz.local` ile kuruyordu → farklı dilimdeki `now` sessizce kayıyordu. Ayrıca **mevcut DST testleri hiçbir şey ölçmüyordu** (test ortamında `tz.local` = UTC) — yanlış güven. Artık `now.location`. | — | ✅ (A3r6) |
| **P1** | Hesap hataları: `bmi(70,-180) = 24.2` döndü (**kare pozitif** olduğu için imkânsız kayıt geçerli görünüyordu); `progress`/`waterTargetMl` NaN'da `UnsupportedError`; `tdee` alt sınırı açıktı. | — | ✅ (A3r6) |
| P2 | `ForceUpdatePage` hâlâ `sha256` atlıyor — engel kalktı, 4 satır. | features | **AJAN ATAANDI (A4r7'ye ilet)** |
| P2 | `isSafeApkUrl` **host kısıtı yok**, TLS pinning yok. | core | Tur 8 |
| P2 | `refreshTimeZone` bağlı değil → seyahat sonrası 1-2 gün yanlış saat. | features | Tur 8 |
| **P2 (ürün kararı)** | **Haftalık widget + nudge görünür ama işlevsiz.** `publishWeekly` (`lib/`'de 0 çağıran → haftalık widget hep boş), `shouldSendNudge` (ayar UI'da görünür, hiç bildirim gitmiyor). A3r6 silmedi, yorumla işaretledi. | mimari | **URUN-KARARLARI'na eklendi** |
| P2 | Web'de `Gender.other` **kadın** formülüne düşüyor (166 kcal fark), Flutter erkek formülünde. | src | Tur 8 |

### A3r6'nın doğruladığı "temiz" bulgular (kanıtlanmış)
- **Göç mantığı doğru ve artık testli**: `reminder_enabled → kahvaltı` **bir kez**
  çalışıyor; legacy anahtar siliniyor; yeni öğün anahtarları varsa dokunmuyor.
  Yeni test: legacy anahtar yeniden yazılsa bile kullanıcının 9:00 ayarı **ezilmiyor**.
- **Zamanlayıcı sızıntısı yok**: `reschedule` önce 4×2 ID'nin tamamını iptal ediyor.
- `update_gate`: sonsuz döngü riski yok (`_promptScheduled` bayrağı ikinci
  post-frame kaydını engelliyor, `dismissOptional` zorunluyu bastıramıyor).
- BMR formülü doğru (80/175/30 → 1749 = `800+1093.75-150+5`).

### ⭐ A3r6'nın **ölü kod** tespiti (silmedi, işaretledi — mantıklı)
- `downloadVerifyAndOpen` `_UpdateGateState` **içindeydi** → Dart'ta `State`
  gizli olduğu için `ForceUpdatePage` **çağıramıyordu**; "tek giriş noktası"
  yorumu fiilen imkânsızdı. Top-level'a taşındı.
- Kanıtlanmış ölü: `publishWeekly`, `shouldSendNudge`, `refreshTimeZone`,
  `workmanager` bağımlılığı (0 referans). Hepsi **eksik özellik**, ölü hata değil.

### Widget sözleşme testi (çok değerli)
`test/core/widgets/widget_key_contract_test.dart` (7 test) — `WidgetData.kt`'yi
**metin olarak okuyup** 40 sabiti `WidgetKeys` ile **her iki yönde** karşılaştırıyor;
ayrıca tip sözleşmesini (`putLong(rawLongBits)` + `home_widget.double.` bayrağı,
`Double.fromBits`), `ACTION_REFRESH == AndroidManifest` ve tazeleme yayınının
`androidName` ile yapıldığını (`name: name` **yokluğu**) kilitliyor.
**Ders: iki taraflı sözleşmeler metin karşılaştırmasıyla teste bağlanmalı.**

## T8 — A1r8 aktarımları (commit `2582dc0` + `b011f0c` + `3dc591f`)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P1 ⭐** | **"Proje frozen, veri yok" varsayımı DOĞRULANAMADI.** `.gitignore`lu `supabase/.temp/` içinde gerçek proje kanıtı var (ref `bzfnncensolirkqdohpq`, PG 17.6.1, GoTrue v2.185.0, eu-central-1) ve kök `.env`'de **düz metin DB parolası**. 3 turdur aynı gerekçeyle CHECK eklenemiyordu. | operasyon | **A1r8 doğru davranışı seçti: 13 CHECK'i satır değiştirmeyen/doğrulayan tasarımla ekledi** (ihlal varsa `RAISE EXCEPTION` + hangi `SELECT`'in çalıştırılacağı yazılı). Geri alınmadı. **Ama canlı veri doğrulanmadı** → aşağıya bak |
| **P1** | **`src/hooks/useNotifications.ts:29-33` `interval_hours: 0` yazıyor** → `notification_preferences_hours_range` **reddediyor** (canlı Postgres'te kanıtlandı). Web'de bildirim ayarı **kaydedilemiyor**. | src | **AJAN ATAANDI (A5r8'e iletildi)** |
| P1 | **`profiles_weigh_in_frequency_days_range` gerçek istemci hatası** (varsayım değil): `notifications_dialog.dart:146` `int.tryParse` ile aralık denetimi yapmıyor, `-5` yazılabiliyor, `check-reminders`'ta her koşuda tetikliyor. | features | **AJAN ATAANDI (Tur 9)** |
| P1 | `isAlreadyDeletedAuthError` genişliği: `{message:"", status:404, code:"session_not_found"}` idempotent *başarı* sayılıyordu — A1r4'ün kapattığı açık `code` alanından **yeniden açılmıştı**. Artık önce `code === "user_not_found"` (GoTrue `apierrors/errorcode.go`, mühürlü). `User already deleted` diye hata GoTrue'da **yok** (doğrulandı). | — | ✅ (A1r8) |
| P1 | `dbBypassUntil` tek global → kova bazlı yapıldı. Anahtar RPC'nin `p_bucket`'ıyla **birebir aynı** türetiliyor, çağrı yerlerinde sıfır değişiklik. Negatif ölçüm: kontrolü geri alınca **3 test kırmızı**. | — | ✅ (A1r8) |
| P1 | `full_setup.sql` artık **idempotent**: 2. çalıştırmada 105 hata → **0 gerçek hata** (1/2/3. kez). 3 tip, 15 tablo, 10 index, 59 politika, 13 trigger, 7 constraint. | — | ✅ (A1r8) |
| **P2** | **`cron.schedule` hiçbir yerde yok** → `check-reminders` elle tetikleniyor, **hatırlatıcılar hiç gitmiyor**. A1 Tur 1'den beri. | operasyon + supabase | Tur 9 (dashboard'da kurulmalı veya migration) |
| P2 | Storage: magic-byte (içerik imzası) doğrulaması yok (MIME başlığı kontrolü var). | supabase | Tur 9 |
| P2 | SQL testleri (`supabase/tests/*.sql`) **CI'a bağlı değil** — `supabase.yml` sadece `deno check`/`deno test` çalıştırıyor. | ci | Tur 9 |
| P3 | `full_setup.sql` `CREATE TYPE` idempotansı A1r8 tarafından çözüldü (yukarıda). | — | ✅ |

### Temiz çıkanlar (ölçülmüş)
- **Storage politikaları iyi**: `public=false`, 10 MB limit, 4 MIME tipi, 4 politika
  `TO authenticated`, hepsi `<user_id>/` önek zorunlu, `anon` erişimi yok.
- **SSRF**: 4 AI fonksiyonu `OPENAI_BASE_URL`'a istek atıyor ama bu **env**,
  kullanıcı girdisi değil. `subscription.endpoint` kullanıcı girdisi ama
  allow-list arkasında — 11 senaryo test edildi (`userinfo`, metadata IP,
  suffix sahteciliği dahil) **11/11 doğru**.
- Rate limit anahtarları kullanıcı bazlı, `rate_limit_hit` RPC parametreli, injection yok.
- Parite `diff` (migration vs full_setup): FK + CHECK + politika → **boş**.

### A1r8'in doğrulama kanıtları
`deno check` 0 hata · `deno test` **124/0** (115'ten) · 18 migration sıfırdan 0 hata ·
yeni migration 3× idempotent · `full_setup` 1/2/3. kez 0 gerçek hata ·
5 SQL testi iki yolda yeşil · **3 negatif ölçüm yapıldı** (kırmızı görüldü, geri kondu).

## T8 — A5r8 aktarımları (web, commit `1e49218`, 42 dosya +2866/−377)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P1** | `check_versions.cjs` **kendi denetimini yaparken gerçek bir Flutter hatası buldu**: "BMI ağırlık alt sınırı iki tarafta farklı" → `bmi(70, -180) = 24.2`. A3r6 boyu düzeltmiş ama **ağırlığı** düzeltmemiş. | core | **AJAN ATAANDI (Tur 9)** |
| P2 | 21/50 shadcn bileşeni ulaşılamaz; `chart.tsx` `dangerouslySetInnerHTML` içeriyor (statik, A5 doğrulamış) | src | Tur 10 |
| P3 | `@hookform/resolvers` ölü bağımlılık · `src/App.css` ölü dosya | src | Tur 10 |
| P3 | `OnboardingPage.loadProfile` hatası hâlâ yutuluyor | src | Tur 10 |
| — | Kilo penceresi 1 yıla sabitlendi — ürün kararı bekliyor | ürün | `URUN-KARARLARI` |

### A5r8'in kapatılan ayrışmaları
1. **`Gender.other` 166 kcal (toplam 257 kcal/gün) farkı.** Web `other`/`null`'ı
   **kadın** formülüne düşürüyordu, Flutter **erkek**'e. BMR 1583↔1749,
   TDEE 2454↔2711 — profil kalıcı yazılıyordu. Karar: **erkek (`+5`)**;
   Flutter sözleşmesi kaynak alındı. Gerekçe: Mifflin'in `−161`'i 60+ kadın
   grubundan, `+5` daha geniş kitleden; yüksek taraf güvenli (düşük taraf
   "hedefim 300 kcal arttı" yanılgısı üretir).
2. **Hesap katmanı 10 fark** — `bmi` negatif kilo, BMR clamp yok, TDEE negatif,
   makro negatif gram, `age` üst sınırı yok, **`progress` koruması 3 katman
   vardı ama HİÇ çağrılmıyordu**, su hedefi `NaN` yazabiliyordu, per-100g 3 kopya.
3. **UTC gün kaçıklığı: 4 gerçek desen / 8 çağrı noktası.**
   `toISOString().split("T")[0]` (TR'de onboarding `max` = **yarın**),
   `new Date("2000-01-15")` UTC gece yarısı (**yaş 1 gün önce** ×3),
   `Math.floor(/864e5)` (uyarı **1 gün geç**), `eachDayOfInterval` (DST + `RangeError`).
   Yeni `src/lib/dates.ts` tek kaynak; **27 test 4 saat diliminde** koşuyor.
4. **Veri katmanı**: `try/catch` **3 yerde hiç çalışmıyordu** — "eklendi" toast'u
   hiçbir kayıt yazılmadan; `addMealEntry`'de miktar sınırı yoktu; 3 yarış
   koşulu (kullanıcı B'nin ekranında A'nın verisi); "en son kilo" belirsiz
   sıralama; **sonsuz sayfalama döngüsü**; `clearVisibleChat`'te `user_id` yok;
   yarım yazma kalıcı artık; uzantı beyaz listesi yok; 4 yerde ham
   `error.message` **şema sızıntısı**.

### A5r8'in `check_versions.cjs` genişletmesi (çok değerli)
6 kapı eklendi: BMR sabitleri + **`genderForBmr` kuralı**, BMI negatif ağırlık,
su çarpanı, yaş sınırı + **uygulanıyor mu**, öğün miktarı + `isUsableAmount`,
**`calculateProgress` çağrılıyor mu**. 3'ü regresyon enjeksiyonuyla kırmızya
döndürüldü.
⭐ **Dürüst yöntem notu:** ilk denemeler **yanlış yeşil** verdi (yorum satırları
ve ölü import'lar "kullanım" sanılıyordu) → kapı artık yorum/import temizleyip
gerçek çağrı arıyor. 2 mevcut kapı kırıldı (sabitler taşındı) → güncellendi +
**"ölü sabit" kontrolü** eklendi.

### Doğrulama
build ✓ · lint 0 hata · tsc exit 0 · **test 40 → 113 pass** ·
`check_i18n` ✓ · `check_versions` ✓ (1 uyarı = Flutter borcu) · 27 tarih testi 4 TZ

### A5r8'in kalan riskleri
Testler **saf katman**la sınırlı (`requestIdRef`/telafi çalıştırılmadı, jsdom gerekir) ·
`.or()` keyset **URL düzeyinde** doğrulandı, gerçek PostgREST'e karşı koşulamadı ·
`TZ` değiştirme V8'e özgü.

## T10 — Kalan P1'ler (ürün kararları kapandıktan sonra)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P1** | **Web istemcisi sunucu bildirim tercihini kaydedemiyor.** `src/hooks/useNotifications.ts` `interval_hours: 0` yazıyor → `notification_preferences_hours_range` CHECK'i reddediyor (A1r8 canlı Postgres'te kanıtladı, A4r8 da teyit etti). Ayrıca **aynı master gölgelenmesi** web'de de var: `send-notification:423` `preference?.push_enabled ?? profile.push_notifications_enabled` — satır yazılınca profil master anahtarı ölüyor. | src | **AJAN ATAANDI (A5r10)** |
| **P1** | `weigh_in_frequency_days` aralık denetimi yok: `0` yazılırsa **CHECK reddi** tüm `_save`'i düşürüyor (profil + sunucu birlikte). A2r9 veri katmanına savunma koydu ama A4r7b "0 da reddedilmeli" diyor — **UI seviyesinde** de gerekli. | features | **AJAN ATAANDI (A4r10)** |
| P1 | `deleteFood`'ın **hiç UI çağıranı yok** — sözleşme yalnız veri katmanında ölçülüyor. Kullanıcı eklediği yizeceği silemiyor → tablo şişiyor. | features | Tur 11 |
| P2 | `goal_achieved` tipi **kimse göndermiyor**: `check-reminders` işlemiyor, `send-notification`'ı çağıran yok → ölü tercih tipi. | features | Tur 11 |
| P2 | Gece aralığı (21→09) desteklenmiyor. | features | Tur 11 |
| P2 | `std@0.168.0` kodda sabit (11 dosya) → CVE riski. | supabase | Tur 11 |
| P3 | `analysis_options.yaml` 25 Ağustos'tan beri commitlenmemişti | — | ✅ (`43e0f7c`) |
| P3 | Web PWA'da hesap silme giriş noktası yok (`src/**`). Android zorunluluğu karşılandı, web'de KVKK "sil" elle. | src | Tur 11 |

### A4r8'in bulduğu 2 **gerçek** hata (sunucu tercihleri)
1. **P1 — master anahtarlar ölmüştü.** `send-notification:423`
   `preference?.push_enabled ?? profile.push_notifications_enabled`;
   `??` yalnız NULL'a düşer. "Her tip için satır yaz" özelliği devreye girince
   `push_enabled` **dolu** oldu → **profil master anahtarı hiç okunmuyor**.
   Ölçülen: master `false`, varsayılan `true` → yazılan satır `true`.
   Düzeltme: `applyMasterSwitches` (AND mantığı).
2. **P1 — `start_hour > end_hour` sessizce hiç göndermiyordu.**
   `index.ts:356` koşulu hiçbir saatte sağlanmaz; DB CHECK'i iki saati de
   0..23 olduğu için **izin veriyor**. `toRow` artık `end`'i 23'e çekiyor.

### A4r7b'nin bulduğu tuzak (hafta günü etiketleri)
`DateTime(2024,1,7)` kullanılmıştı → `weekday == 7` = **Pazar**; liste
`Cmt→Paz` idi, kullanıcı "Pzt" görüp `summary_day=0` yazıyordu.
⚠️ **İlk düzeltmesi (`2024-01-14`) de yanlıştı** — test kırmızı döndü,
12 dilde ölçüp `2024-01-08` ile düzeltti. Tarih sabitleri gözle değil testle doğrulanmalı.

### A4r7b'nin **kendisinin neredeyse kaçırdığı** tuzak ⭐
`tester.tap('Kaydet')` **sessizce hiçbir şey yapıyordu**
(`Offset(713.7,1140) outside root Size(800,600)`) → 3 test **yeşil** görünürken
**hiçbir şey ölçmüyordu** (`verify` = 0). `tapSave` artık `drag` ile kaydırıyor.
**Ders: yeşil test ≠ etkin test. Etkileşimin gerçekten gerçekleştiğini doğrula.**

### A6r9'un düzelttiği tutarsızlık (deno.lock)
A6r5 kilidi **takip etme** kararı verdi ve kökteki `deno.lock`'u commit'ledi —
ama `supabase/deno.json` `"lock": "deno.lock"` diyor, Deno bunu çalışma
dizinine göre çözüyor → `supabase/deno.lock`, o **untrackted**. Yani karar
**fiilen uygulanmamıştı**. Ölçüldü: kök lock'u hiçbir `deno` komutu okumuyordu.
Düzeltme: `supabase/deno.lock` takipte (8382 → 4920 bayt, React'ın 70 npm
kaydı çıktı), CI'da **`--frozen=true`** kapısı eklendi. Negatif ölçüm:
`--frozen`'sız yeni uzak import kilidi **sessizce yeniliyordu** (görünmez kayıp).
`.gitignore`'daki `supabase/functions/*/deno.lock` glob'u o dosyayı asla
yakalamıyordu, "izlenmiyor" yanılsaması üretiyordu → silindi.

## T11 — A4r10 aktarımları (ekranlar, commit `1778cf8`+`207e38d`+`994d371`)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P0 ⭐ (daha önce 3 kez raporlandı)** | **`check-reminders` için `pg_cron` job'ı hâlâ yok.** Bu turdaki tüm sunucu bildirim düzeltmeleri kullanıcıya **görünmez** olmaya devam ediyor. | operasyon | **KULLANICIYA İLETİLDİ** (A1r10 da uyaracak) |
| P1 | Silme düğmesi **veritabanı/seed** gıdalarında da görünüyor (`created_by` NULL → `false` + toast). Veri kaybı yok ama **UX gürültüsü**. `food_repository.search()` `created_by`/`source` seçmiyor. | data | **AJAN ATAANDI (A2r11)** |
| P1 | Gece aralığı (21→09) sunucuda **desteklenmiyor** (`check-reminders:356` koşulu `start>end` için hiçbir saatte sağlanmaz). Gerçek destek iki koşul gerektiriyor: sarma + **gece yarısını geçen damganın günü** (aksi halde gece diliminde **her saat** gönderim). | supabase | **AJAN ATAANDI (A1r10)** |
| P2 | 4 ekranda `catch (_)` loglamıyor (`personal_info`, `goals`, `settings_page`, `recognition_confirm`). Alan doğrulaması tetiklemiyor ama log eksik. | features | Tur 12 |
| P3 | `goalAchieved` çeviri anahtarı Flutter'da silinmedi (React PWA kullanıyor) — A5'e aynı karar aktarıldı. | src | A5r10 |

### A4r10'un bulduğu **ikinci `tryParse` tuzağı** (A4r7b'den sonra ikinci kez)
Dart `int.tryParse('0x10')` → **16**, `int.tryParse('+7')` → **7** döner.
`tryParse` "rakam yazıldı" demek değil. Parser artık `^\d+$` ile biçimi de
doğruluyor. Testler: harf, ondalık, `1e3`, `0x10`, `+7`, boş, yalnız boşluk, `null`, `" 7 "`.

### A4r10'un **kendi kodundaki hatasını testin yakalaması** ⭐
`_save` erken çıkışı yanlışlıkla `_frequencyErrorOf` çağırıyordu →
"geçersiz değer bul" yerine "**her dolu metin geçersiz**" dönüyordu, yani
**geçerli** değerler de kaydedilemiyordu.
Ayrıca `hitTestOnBinding` düğmeye ulaşıldığını doğruluyordu ama `verify` 0 çağrı
buldu → **etkileşim gerçekleşmiyordu** (A4r7b'nin tuzağının 2. biçimi).
`_tapSave` artık kaydırma + `verifyNever` ile etkileşimi doğruluyor.

### Diğer kararlar
- **`goal_achieved` UI'dan gizlendi** ((b) seçildi). Gerekçe: `check-reminders`
  bu tipi hiç okumuyor; kullanıcı anahtar görüp hiçbir şey olmuyor.
  (a)'nın gerektirdiği: tetikleme koşulu **ürün kararı** + **idempotency**
  (`last_goal_achieved` damgası, aksi halde cron saatte bir "Tebrikler!"
  gönderir — A1r3'ün `weekly_summary` hatasının aynısı).
- **`deleteFood` arayüzü eklendi**: `shared/widgets/delete_food_button.dart`,
  `add_page`'in 4 bölümüne. Onay diyaloğu yemek adı + kullanım sayısı +
  favori uyarısı. `foods.deleted_at` **yok** → fiziksel silme.
  `meal_entries.food_id` `ON DELETE SET NULL` (öğünler korunur).
  `false` dönerse **"başarı" söylenmiyor** — RLS/FK nedeni kullanıcıya açıklanıyor.
- Negatif ölçüm: 4 düzeltme, hepsi kırmızı görüldü.

## T11 — A5r10 aktarımları (web, commit `6f411f9`, test 113 → 142)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P1 ⭐ kök neden** | **`SettingsPage.saveNotifications` ÖLÜ KODDU** — `grep` tek sonuç verdi: **tanımı**, hiç çağrılmıyordu. Yani web'de profil master anahtarları **hiç yazılmıyordu** ve "her tip için satır yaz" hiç tetiklenmiyordu → sessiz-kapalı `water`/`daily_log`/`weekly_summary` hiç satır kazanamıyordu. Diyaloga master anahtarları + "Kaydet" eklendi. | — | ✅ (A5r10) |
| **P1** | `interval_hours: 0` → CHECK reddi. Yeni saf katman `src/lib/notificationPreferences.ts`: `clampInt` ← Flutter `_clamp`, `normalizePreference`/`buildPreferenceRow` ← `toRow`, `_asInt` `Number()` ile kapatıldı. Varsayılan tablosu Flutter'ınkiyle **sayı sayı eşit**. `fetchPreferences` de normalize ediyor (kolonlar nullable). | — | ✅ (A5r10) |
| P2 | `send-notification:423-424` sunucu tarafında hâlâ `??` — ikinci savunma katmanı eklenecek. | supabase | Tur 12 |
| P2 | `useDataExport`/`backupRestore` tercihleri geri yüklerken **normalize katmanı kullanmıyor** → yedekte `interval_hours: 0` varsa aynı CHECK reddi oradan gelir. | src | Tur 12 |
| P3 | Hafta günü etiketleri Türkçe sabit (değer doğru, çeviri eksik). | src | Tur 12 |

### ⭐ A5r10'un **"yanlış yeşil"** bulgusu (3. kez, farklı biçim)
Varsayılan tablosu testi `buildPreferenceRow`'dan geçirip **sonucu** denetliyordu;
`0 → 3` çevrildiği için `interval_hours: 0` yazan tabloyla bile **yeşil** kalıyordu —
**test, hatanın kendisini gizleyen katmandan geçiriyordu.** Ham değer denetimine çevrildi.
Bu, A4r7b (`tap` sessizce başarısız → 3 test hiçbir şey ölçmüyor) ve A4r10
(`hitTest` ulaşılıyor ama tıklama gerçekleşmiyor) ile **aynı sınıf**.
⭐ **Ders: test, üretim kodunun aynı fonksiyonundan geçirilip çıktısı
denetleniyorsa, o fonksiyon bir hata düzeltiyorsa test o hatayı da gizler.**

### Diğer doğrulamalar
- `summary_day` 0=Pazar: web'de gün **üretilmiyor** (ölçtü), yalnız kullanıcı seçimi.
  `WEEKDAY_OPTIONS` ilk etiketi Pazar; `weekdayIndexFor` 7 gerçek tarihle
  sunucu dizinine karşı ölçülüyor.
- Hesap silme giriş noktası (P3) eklendi: saf `lib/accountDeletion.ts` +
  `useAccountDeletion` + iki aşamalı diyalog. Elle `fetch` **kullanımadı**
  (415 + token sızıntısı riski). Test: parola `String`/`JSON`/stack içinde
  **arandı**, bulunamadı.
- `convert_locales.cjs` **ters yönlü** çalışıp 152 anahtarı siliyormuş →
  kullanılmadı; bunun yerine `tool/sync_locales_once.cjs` (idempotent).

## T11 — A1r10 aktarımları (commit `1f936bf`+`2272411`+`08944c8`+`ff25bf7`, deno 124 → 164)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P0 ⭐ 4 turdur raporlanıyordu** | **`pg_cron` job'ı kuruldu** — `cron.schedule` repoda hiçbir yerde yoktu, `water`/`daily_log`/`weekly_summary`/`weigh_in` **hiç gönderilmiyordu**. 5 turdaki tüm sunucu bildirim düzeltmeleri görünmezdi. Sıklık `7-59 * * * *`: 5 dk = saatte 12 AI çağrısı + rate-limit kovası tükeniyor; saatte 1 = 09:00/18:00 bildirimleri **1/24 ihtimalle** kaçıyor (A1r3'ün `weekly_summary` sınıfı). Token **Vault**'ta; `Authorization` **reddedildi** (kaynak kod `x-calorix-internal-token` arıyor, `Authorization` service_role JWT yolu). | — | ✅ (A1r10) |
| **P1** | **Master anahtar gölgelenmesinin SUNUCU tarafı hâlâ açıktı** → `resolveChannelEnabled` (AND) ile kapatıldı. İstemci tek katmandı; **DB'de yazılı satırları** (yedek içe aktarım, elle SQL) engellemiyordu. | — | ✅ (A1r10) |
| **P1** | `check-reminders` **master anahtarları hiç okumuyordu** → kapalı kullanıcı için de **her koşuda HTTP çağrısı**. Kapı + `skippedByMaster` sayacı eklendi (sessiz değil). | — | ✅ (A1r10) |
| **P1** | Gece aralığı (21→09) **gerçekten** destekleniyor. A4r10'ın uyardığı tuzak **ölçüldü**: sarma tek başına → günde **13 gönderim** + 90 art arda çift. Neden: damga UTC'de saklanıyor (dün 23:50 TR = 20:50 UTC, bugün 00:10 TR = 21:10 UTC) → gün+saat mantığı "1 saat" diyordu. `zonedMinutesBetween` her iki zamanı da kullanıcının kendi gün/saat/dakika parçalarına çeviriyor → **20 dakika**. | — | ✅ (A1r10) |
| P1 ⭐ | A4r10'un "bonus tuzak"ı: **saat (0-23) tek başına yetmez** — 22:50→23:00 "1 saat" sanılıyor ama 10 dakika, yani **50 dk erken** gönderim. Karşılaştırma artık `>= intervalHours * 60`. | — | ✅ (A1r10) |
| P2 | `std 0.168.0`/`0.190.0` → **`0.224.0`** (registry'den teyitli). Transitif bağımlılık 11 → 2 modül. ⚠️ `deno cache`/`test` kilidi **kısmi** bırakıyor (A6r9 gözlemi teyit) → lock **elle** düzeltildi. | — | ✅ (`2272411`) |
| **P2** | Flutter tarafı artık **gereksiz** bir sınırlama yapıyor: `notification_preferences_repository.dart:188` `end >= start ? end : 23` → kullanıcının seçimini sessizce değiştiriyor. Sunucu artık desteklediği için `_clamp(endHour, 0, 23, 21)` yeterli. `endHourOptions`'ın `start..23` sınırlaması (A4r10) geri açılabilir, "gece aralığı yazılamaz" notu kaldırılabilir. **Ürün kararı.** | data/features | **AJAN ATAANDI (A2r12)** |
| P2 | `check-reminders` **N+1 sorgu** yapıyor | supabase | Tur 13 |
| P2 | SQL testleri (`supabase/tests/*.sql`) hâlâ **CI'da değil** | ci | Tur 13 |
| P2 | DST'de ±60 dk sapma (gece aralığında) | supabase | Tur 13 |
| P2 | `goal_achieved` hâlâ ölü tercih tipi (A4r10 gizledi) | — | Ürün kararı bekliyor |

### A1r10'un ⭐ 3 kez "yanlış yeşil" yaşaması ve düzeltmesi
Ajan, kendi testlerinin **3 kez yanlış yeşil** verdiğini itiraf edip düzeltti.
Bu, bu döngünün en önemli metodolojik gözlemi: **test, üretim kodunun hata
düzeltten fonksiyonundan geçirildiğinde hatayı da gizler.**
Bu turda toplam: A4r7b (`tap` gerçekleşmiyor), A4r10 (`hitTest` ama tıklama yok),
A5r10 (normalize katmanından geçirme), A1r10 (3 kez) = **5 vaka**.

### A1r10'un test sınırı (dürüst raporlama)
Shim yazdı (Supabase imzaları birebir). Doğrulanan: tanım + gövdenin SQL'i +
üretilen HTTP isteği (URL/başlık/timeout). **Doğrulanamayan:** `pg_cron`'un
gerçek zamanlayıcısı ve `pg_net`'in gerçek HTTP gönderimi → **operasyon adımı zorunlu**.
Migration 3× çalıştırıldı → **1 job** (ölçüldü). `CREATE EXTENSION` `EXCEPTION`'a
sarıldı → A1r8'in atlama zorunda kaldığı hata gitti, hangi ortamda da 0 gerçek hata.

### T12 — A4r11 (P0 düzeltmesi, `1b83c2c`)
Yemek silinince öğün **"Bilinmeyen"** oluyordu (A2r11'in bulduğu P0, A4r10'un
eklediği özelliğin verdiği zarar). `custom_name` yalnız `isCustom`'a bağlıydı;
kullanıcının **kendi gıdası** silinince `food_id` NULL + `custom_name` NULL →
dashboard'da adsız öğün. Düzeltildi.

## T12 — A4r11 aktarımları (P0 düzeltmesi, `1b83c2c`, 1067 → 1081 test)

| Sev | Konu | Hedef | Durum |
|---|---|---|---|
| **P1 ⭐ asıl kapsam daha geniş** | **"Bilinmeyen"in tamamı çözülmedi.** A4r11 brifimden **ağır** olduğunu kanıtladı: ad **hiç yazılmamıştı zaten** — `fetchDaily` `foods` join'i **yapmıyor**, `displayName` yalnız `custom_name` okuyor. `git show e99ba95` ile doğrulandı: **v1.2.0'dan beri** böyle. Yani **topluluk gıdası** öğünleri silinmeden "Bilinmeyen" görünüyor. Alternatif: `fetchDaily`'e `foods(name)` embed ekle. | data | **AJAN ATAANDI (A2r13)** |
| P2 | `EditMealEntryDialog` boş ad kilidi | features | Tur 13 |
| — | Web PWA'da aynı P0 **yok** (`AddFromFoodDialog.tsx:93` koşulsuz yazıyor) — doğrulandı | — | Temiz |

### A4r11'in ⭐ dürüst düzeltmesi (brif yanlıştı)
Görev brifim "gıda silinince kaybolan ad" diyordu. Gerçek: ad **hiç yazılmamıştı**,
`fetchDaily` join yapmıyor. Yani P0 hem A4r11'in sandığından **dar** (yalnız kendi
gıdası) hem de **eski** (v1.2.0'dan beri). Ajan her iki yönü de düzeltti ve
kalan kısmı aktardı.

### A4r11'in kararı: `canDelete` koşulu neden bu
`canDelete` = `created_by == auth.uid()` = `deleteFood`'in **RLS süzgeciyle
birebir aynı** koşul. Yani "adı yedekle" ile "gıda silinebilir" **aynı sorunun
iki yüzü**. Topluluk/seed gıdası öğünleri için `custom_name` yazmak
gereksiz tekrar (10k öğün ≈ 200 KB + index şişmesi) — bu yüzden yazılmadı.

Eski bozuk veri için **migration gerekmedi**, 3 kanıt: (a) proje frozen,
(b) eski kural `food_id`'yi **dolu** bırakıyordu yani `(NULL, NULL)`
kendiliğinden oluşamazdı, (c) 3 yazma yolu da böyle satır yazmıyor.
⚠️ Kanıt **statik** — A1r8'in bulduğu gerçek proje kanıtı nedeniyle sıfır
değil; envanter sorgusu rapora yazıldı.

### ⭐ A4r11'in "etkin test" doğrulaması (6. vaka, yeni biçim)
- Yazma testi `invocation.namedArguments[#customName]` ile **ham** değeri
  denetliyor (A5r10 tuzağı değil).
- `_tapAdd` + `expect(captured.calls, 1)` ile kaydın **gerçekten** oluştuğunu
  kanıtlıyor — bu olmasa altındaki denetimler `null` görüp yeşil kalırdı
  (A4r7b tuzağı).
- ⭐ **Yeni**: `'Ekle'` sabiti kırmızı oldu (gerçek: `Yiyecek Ekle`). Sabiti
  düzeltmek yerine **çeviri anahtarından türettirdi** + sözleşme testi ekledi.
- Ölçüm testi ilk denemede `select=*` yüzünden kırmızı oldu → **ölçümün
  gerçekten okuduğunun** kanıtı.

Negatif ölçüm 3 enjeksiyon, hepsi kırmızı. P0 geri alınınca **yalnız
`canDelete:true` olanlar** kırmızı oldu, manuel/tanıma/community yeşil kaldı
= düzeltmenin **seçici** olduğunun kanıtı.

## Operasyon (dashboard)

### ⭐ `pg_cron` canlı doğrulaması ZORUNLU
`pg_cron` job'ı kuruldu ama **gerçek zamanlayıcısı test edilmedi** (shim sınırı).
Supabase Dashboard'dan veya `psql` ile:
```sql
select jobname, schedule, command from cron.job;
```
Sonra `check-reminders`'ın **gerçekten HTTP çağrısı yaptığını** doğrula
(log'da istek, kullanıcıda bildirim). Vault secret'ının **tanımlı** olması
gerekiyor — `INTERNAL_FUNCTION_TOKEN`:
```sql
select name from vault.secrets;
```

### ⚠️ Canlı veri doğrulaması gerekiyor (A1r8'in eklediği CHECK'ler)
13 CHECK eklendi; ihlal varsa migration **`RAISE EXCEPTION` ile duruyor** ve
hangi `SELECT`'in çalıştırılacağını yazıyor. Migration dosyasındaki mesajı oku.
**Uygulamadan önce** o `SELECT`'leri çalıştır — veri temizse sorun yok.

### ⭐ `check-reminders` hiç tetiklenmiyor
`cron.schedule` tanımı **yok**. Sunucu tarafı hatırlatıcıları (`water`,
`daily_log`, `weekly_summary`, öğün hatırlatıcılarının push ayağı) **hiç gitmiyor**.
Dashboard'da `pg_cron` job'ı kurulmalı:
`Authorization: Bearer <INTERNAL_FUNCTION_TOKEN>` başlığıyla.

## Operasyon (eski kayıt)

Detay: `OPS-tur1-security.md`
- `INTERNAL_FUNCTION_TOKEN` secret tanımla
- `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` secret tanımla
- Auth → Site URL `https://calorix.app`
- `check-reminders` cron tanımı `Authorization: Bearer <INTERNAL_FUNCTION_TOKEN>` göndermeli
- `20260927120000_security_hardening_round1.sql` migration'ını uygula
- `.env` içindeki DB parolasını rotate et (frozen proje, düşük acil ama düzelt)

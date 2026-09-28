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

## Operasyon (dashboard)

Detay: `OPS-tur1-security.md`
- `INTERNAL_FUNCTION_TOKEN` secret tanımla
- `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` secret tanımla
- Auth → Site URL `https://calorix.app`
- `check-reminders` cron tanımı `Authorization: Bearer <INTERNAL_FUNCTION_TOKEN>` göndermeli
- `20260927120000_security_hardening_round1.sql` migration'ını uygula
- `.env` içindeki DB parolasını rotate et (frozen proje, düşük acil ama düzelt)

# RAPOR — A1r10-security — 2026-09-28 — Tur 11

> Kapsam: `supabase/**` (migration + edge function + lock + test).
> `flutter_app/**`, `src/**`, `tool/**`, `plans/**` **dokunulmadı**.
> Doğrulama: **Postgres 16.15** (Docker `a1r8-pg`, veritabanı `calorix`),
> **deno 2.9.7**, `pg_cron`/`pg_net`/`vault` **shim** ile.
> Testler `supabase/tests/` altında (kullanıcı kısıtı: `/tmp` dışında).

## Özet (5 madde)

1. **⭐ P0: `check-reminders` için `pg_cron` job'ı kuruldu** (4 turdur raporlanıyordu).
   `cron.schedule` repoda **hiçbir yerde yoktu**; `water`, `daily_log`,
   `weekly_summary`, `weigh_in` **hiç gönderilmiyordu**. Migration
   `20260929010000_check_reminders_cron_job.sql` + `full_setup.sql` paritesi.
   Sıklık `7-59 * * * *`, yetkilendirme `x-calorix-internal-token` başlığıyla,
   token **Vault**'tan. **13 kontrol 13 ok.**

2. **⭐ P1: Gece aralığı (21→09) gerçekten destekleniyor — ve tuzak ölçüldü.**
   A4r10'ın uyardığı tuzak **doğrulandı**: sarma tek başına uygulansaydı
   `interval_hours=1` ile **günde 13 gönderim** + aralık içi **art arda iki
   saatte** gönderim olurdu. İki koşul birlikte düzeltildi: sarma
   (`isWithinHourWindow`) **+ damga yaşının kullanıcının kendi gün/saat/dakika
   parçalarından ölçülmesi** (`zonedMinutesBetween`). **26 test** (124→150).

3. **⭐ P1 (Görev 4 bulgusu): Master anahtar gölgelenmesinin SUNUCU tarafı
   kapatıldı.** A4r8 bunu yalnız **istemcide** `applyMasterSwitches` ile
   düzeltmişti; `send-notification`'in `??` zinciri hatayı **hâlâ** taşıyordu
   ve DB'de zaten yazılmış satırları (yedek içe aktarım, eski istemci, elle
   SQL) engellemiyordu. İkinci gölgelenme yolu daha gizliydi:
   `check-reminders` master anahtarları **hiç okumuyordu**. **14 test** (150→164).

4. **P2: `std@0.168.0`/`0.190.0` → `0.224.0`** (güncel kararlı sürüm, resmi
   registry'den teyitli). `supabase/deno.lock` **elle düzeltildi ve
   commit'lendi**; A6r9'ın `--frozen` kapısı geçiyor. Yan fayda: `http/server.ts`
   transitif bağımlılığı **11 → 2 modüle** düştü.

5. **Metodoloji notu:** Bu turda **4 negatif ölçüm** yapıldı (hepsi kırmızı
   görüldü, geri kondu) ve **3 kez "yanlış yeşil"** yaşandı: (a) yorum
   satırlarını kullanım sanan kaynak taraması, (b) regex'in kısaltma
   (`{ minute }`) biçimini kaçırması, (c) `to_regprocedure` imzasının
   `pg_net`'in varsayılan parametreli imzasıyla eşleşmemesi. Üçü de düzeltildi.

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P0** | `migrations/20260929010000_check_reminders_cron_job.sql` (**yeni**, 298 satır) | `pg_cron` job'ı: `cron.schedule('check-reminders', '7-59 * * * *', net.http_post(...))`. Yetkilendirme `x-calorix-internal-token`, token `vault.decrypted_secrets`'ten. Çift kayıt koruması (adlandırılmış UPSERT + `cron.unschedule` döngüsü). `CREATE EXTENSION` `EXCEPTION` ile sarıldı → **hangi ortamda da 0 gerçek hata** | 3× üst üste **0 hata**, **1 job**; gövde çalıştırıldı → kuyrukta doğru URL/başlık/timeout |
| **P0** | `full_setup.sql` (§5 Cron Jobs, +78 satır) | Aynı job'ın parite kopyası. `CREATE EXTENSION IF NOT EXISTS`'in "not available" **hatası** da `EXCEPTION`'a çevrildi (A1r8 bu yüzden `20260111080533`'ü atlamak zorunda kalmıştı) | 1/2/3. çalıştırma **0 gerçek hata**, job sayısı 1 |
| **P0** | `tests/a1r10_cron_shim.sql` (**yeni**, 104 satır) | `pg_cron`/`pg_net`/`vault` minimal taklidi, **Supabase API imzalarıyla**. Vault kolonu `decrypted_secret` — dokümandan doğrulandı | shim olmadan migration da 0 hata veriyor |
| **P0** | `tests/cron_reminders_job.sql` (**yeni**, 292 satır) | 13 kontrol: çift kayıt · sıklık · başlık · Vault · **düz metin sır yok** · `Authorization` yok · URL · gövde işlevsel çalışması · **Vault boşken** davranış · timeout | **13 ok / 0 FAIL** |
| **P1** | `functions/check-reminders/helpers.ts` (+173) | `isWithinHourWindow` (sarma + `start==end`→tek saat) · `isWrappingWindow` · `zonedMinutesBetween` (gün+saat**dakika** farkı) · `ZonedParts.minute` alanı · `safeHour`/`safeMinute` | 26 yeni test |
| **P1** | `functions/check-reminders/index.ts` | Su bloğu: eski `normalizedHour >= startHour && <= endHour` **kaldırıldı**; damga yaşı `hoursBetween` yerine `zonedMinutesBetween`. Master anahtar kapısı + `skippedByMaster` sayacı | `night_window_test.ts` 26/26 · `channel_switch_test.ts` 14/14 |
| **P1** | `functions/_shared/http.ts` (+55) | `resolveChannelEnabled()` — kanal kararı **AND** mantığı, saf ve test edilebilir | 14 test |
| **P1** | `functions/send-notification/index.ts` | `preference?.push_enabled ?? profile.push_notifications_enabled ?? true` zinciri **kaldırıldı** → `resolveChannelEnabled` | negatif ölçüm #1 |
| **P2** | 7 × `functions/*/index.ts` + `deno.lock` | `std@0.168.0`/`0.190.0` → `0.224.0`; 23 stale lock kaydı çıkarıldı, 2 gerçek hash eklendi | `--frozen` × 2 geçti |

## ⭐ Görev 1: Gece aralığı — tuzak ölçümü

**Ölçülen tuzak (7 günlük simülasyon, `deno` ile):**

| Yaklaşım | 21→09, `interval_hours=1` | Art arda gönderim |
|---|---|---|
| Eski (`>= && <=`) | **0** (hiç gönderilmiyor — P1) | — |
| Sarma **tek başına** | **13/gün** | **90 çift** (aynı saatte iki kez) |
| Sarma + dakika farkı (düzeltme) | **13/24 saat = pencere saatleri** | **0** |

**Neden sarma tek başına yetmez:** damga yaşı `hoursBetween(stamp, now)` ile
**UTC** farkından ölçülüyordu; 21:00→22:00 arası gerçekten 1 saat geçtiği
için `>= interval(1)` sağlanıyor. Sarmalı pencere "gece dilimi hâlâ açık"
diye okunuyor ve içerideki **her saat** yeniden tetikleniyor.

**Gece yarısı tuzağı nasıl önlendi:** `last_water_reminder` bir
`timestamptz`'dir ve **UTC'de saklanır**. Damga dün 23:50 TR = 20:50 UTC,
kontrol bugün 00:10 TR = 21:10 UTC. **Gün + saat** mantığı
(`1*24 + (0-23)`) **1 saat** der → `>= 1 saat` sağlanır → 00:10'da **tekrar
gönderim**. `zonedMinutesBetween` her iki zamanı da kullanıcının kendi
gün/saat/dakika parçalarına çevirir → **20 dakika** verir. Bu, A1r3'ün
`weekly_summary` hatasının (günde ~12 kez) **aynı sınıfıdır**; tekrarlamadı.

**Ek tuzak (görev metninde yok, bulundu):** saat (0-23) tek başına
yetersiz — aynı gün 22:50→23:00 farkı "1 saat" sanılır ama gerçekte 10
dakikadır; `interval_hours=1` için **50 dakika erken** gönderim. Bu yüzden
karşılaştırma `>= intervalHours * 60` **dakika** cinsinden yapılır ve
`ZonedParts` `minute` alanı kazandı.

**Test kapsamı (26):** `start==end` · `start<end` (regresyon) · `start>end`
(sarma) · **gece yarısını geçen damga (23:50→00:10 = 20 dk)** · 24 saatlik
tam tur (gündüz **ve** gece) · 48/168 saatlik turlarda kaçak kontrolü ·
aralık dışı saatlerde güvenli düşüş.

## ⭐ Görev 2: `pg_cron` job'ı

| Soru | Cevap + gerekçe |
|---|---|
| **Sıklık** | `7-59 * * * *` (saatte 7 kez, :07…:56). **5 dk = saatte 12 AI çağrısı** (`daily_log` 18:00'de `generateMotivationalMessage` her koşuda çağrılır) + `checkRateLimit` 2/300 kovası yüzünden dakikada bir **her zaman** "atlandı" döner. **Saatte 1 = `weigh_in` (09:00) ve `daily_log` (18:00) 1/24 ihtimalle KAÇAR** (`normalizedHour === 9` bir sonraki koşuda artık sağlanmaz) — A1r3'ün `weekly_summary` hatasının aynı sınıfı. 7 kez/saat: 09:00/18:00 **garanti**, gecikme en fazla ~8 dk. |
| **Başlık** | `x-calorix-internal-token`. ⚠️ Görev metni `Authorization: Bearer <token>` diyordu; bu **daha zayıf**: `send-notification/isInternalCall` token'ı `x-calorix-internal-token` altında arıyor, `Authorization`'ı **service_role JWT** sanıyor. Kaynak koddan doğrulandı, test kilitledi. |
| **Token nerede** | **Vault** (`vault.decrypted_secrets`, ad `calorix_internal_function_token`). Vault yoksa job **kurulmaz** ve `WARNING` verir — token'ı migration'a düz yazmak repoya kalıcı sır giriyordu. **URL Vault'ta değil:** `config.toml`'daki `project_id` zaten repoda düz metin, yani kimlik sır değil. Karar: **sır → Vault, kimlik → düz metin.** |
| **İdempotans** | Adlandırılmış `cron.schedule(jobname, …)` **UPSERT** yapar (ölçüldü: 2× aynı ad → 1 satır) + migration her çalışmada aynı adlı işleri `cron.unschedule` ile düşürür (dashboard'dan elle eklenmiş eski tanım da temizlenir). Sonunda `NOTICE/WARNING` ile **job sayısı raporlanır** (0 iş → WARNING). |
| **`pg_net`/`pg_cron` yok** | `CREATE EXTENSION` **`DO $$ … EXCEPTION` ile sarıldı**: `IF NOT EXISTS` kurulu olsa bile "extension is not available" **hatası** verir. A1r8 bu yüzden `20260111080533`'ü **atlamak** zorunda kaldı (4 hata). Artık **hangi ortamda da 0 gerçek hata**; shim ile 0 hata, shimsiz 0 hata. |
| **Test ortamı sınırı** | Stock `postgres:16-alpine` imajında ikisi de yok. Bu yüzden **shim** yazıldı ve Supabase'ın belgelenen imzaları birebir taklit edildi. **Sınırlar:** (a) `pg_cron`'un gerçek Zamanlayıcı davranışı (job gerçekten tetiklenir) test edilemez — yalnız tanım + gövde doğrulanır; (b) `pg_net` HTTP'yi gerçekten göndermez, kuyruğa yazar; (c) `net._http_response` **asenkron** olduğu için pg_cron'da yanıt beklemek mümkün değil — `check-reminders` zaten `stampFailures` sayacını döndürüyor, `cron.job_run_details` koşuyu kaydediyor. |
| **Sürücü/timeout** | `timeout_milliseconds := 30000`. Varsayılan 2000 olsaydı `check-reminders`'ın AI çağrısı (20 sn) iptal edilirdi → **hiç gönderim olmazdı**. |

## P2: `std` sürüm güncellemesi + lock durumu

- **Kaynak:** `https://cdn.deno.land/std/meta/versions.json` → `{"latest":"0.224.0"}`.
  Ağ erişimi **vardı**; güncelleme yapıldı.
- **API uyumu:** `0.224.0/http/server.ts` kaynağı okundu — `serve(handler)`
  imzası **değişmemiş** (yalnız `ConnInfo`/`Handler`/`ServerInit` deprecated).
- **Ölçülen kazanç:** transitiv bağımlılık **11 → 2 modül**
  (`async/mod.ts` artık yeniden export edilmiyor; `abortable`, `deadline`,
  `debounce`, `deferred`, `mux_async_iterator`, `pool`, `retry`, `tee`,
  `_util/asserts` **düştü**).
- **Lock durumu:** `supabase/deno.lock` **elle** düzeltildi (23 stale kayıt
  çıkarıldı, `0.224.0` için 2 hash **Deno'nun kendi çözümlemesinden** alındı)
  ve **commit'lendi** (`2272411`). A6r9'ın `--frozen` kapısı **geçiyor** ve
  frozen koşusunda kilit **değişmiyor**.

⚠️ **Metodoloji notu (yeni gözlem):** `deno cache` + `deno test` kilidi
**kısmi** bırakıyor — A6r9'un ölçümü teyit edildi: 12822 → 1909 bayt, 25 std
kaydından 0'i kaldı. Deno 2.x `nodeModulesDir:"none"` ile **yalnız yeniden
çözümlenen** modülleri kilitler; `check`/`test` std'yi yeniden çözümlemiyor.
Bu yüzden lock elle düzeltildi ve `--frozen` ile doğrulandı.

## ⭐ Yeni güvenlik bulguları (Görev 4)

### P1 — Master anahtar gölgelenmesi, **sunucu tarafında hâlâ açık** (düzeltildi)

A4r8 bulgusunu **istemci tarafında** düzeltti; sunucu tarafı **aynen** hatalıydı:

```ts
const pushEnabled = preference?.push_enabled ?? profile.push_notifications_enabled ?? true;
```

`??` yalnız `NULL` üstüne düşer. `push_enabled` kolonu `BOOLEAN DEFAULT true`
ve **NOT NULL değil** → satır yazıldığı anda doludur. Flutter (A4r7) ve web
(A5r10) "her tip için satır yaz" yazan istemciler olduğu için **şart gerçekleşmiş**:
kullanıcı üstteki anahtarı kapatır, tip bazlı `true` satırları bildirimi
göndermeye devam eder. Ölçülen: `master=false, satır=true → true` (gönderilir).

**Neden P1:** istemci tabanlı bildirim tercihi bir güvenlik sınırı **değildir**.
A4r8'in `applyMasterSwitches`'ı **tek katmandır**; DB'de zaten yazılmış
satırları (yedek içe aktarım `data_transfer_import.dart`, eski istemci
sürümü, elle SQL) **engellemez**.

Düzeltme: saf `resolveChannelEnabled()` (AND mantığı, master kazanır) +
`send-notification` bunu kullanır.

### P1 — İkinci gölgelenme yolu: `check-reminders` master'ı hiç okumuyor

`pref?.push_enabled || pref?.email_enabled` ile tetikleniyor; profil master
anahtarları **hiç** okunmuyordu. Master `false` olan kullanıcı için de her
koşuda 4 blok değerlendirilip `send-notification`'a HTTP çağrısı yapılıyordu
→ gereksiz yük, `rate_limit_hit` sayımının tükenmesi, gereksiz
`notifications` INSERT'i. Artık iki master da açıkça `false` ise profil
**atlanır** (`NULL` = belirsiz → kapatılmış sayılmaz, geriye uyum korunur) ve
atlanan sayı `skippedByMaster` ile **görünür** (A1r3'ün sessizlik ilkesi).

### `notification_preferences`'a yazan istemci var mı? (sorunun cevabı)

**Evet.** `grep` sonucu: Flutter `server_notification_preferences_section.dart`
+ `notification_preferences_repository.dart` (A4r7/A4r8, "her tip için satır
yazar"), web `useNotifications.ts` + `notificationPreferences.ts` (A5r10 —
`buildPreferenceRow` ile normalize edilmiş, `interval_hours: 0` düzeltilmiş).
Yani **tablo artık boş değil** — ama yalnız **kullanıcı ayarlar ekranını bir kez
açıp kaydettikten sonra**. Kaydetmeyen kullanıcıda `check-reminders`'ın
"satır yoksa kapalı" davranışı geçerli (bu, A4r7'nin varlık nedeni).

### Temiz çıkanlar (ölçüldü)

| Alan | Sonuç |
|---|---|
| **Yeni hata sızıntısı** | Yok. `send-notification` push hata gövdesini `<redacted>` ile temizliyor; `check-reminders` istemciye sabit mesaj dönüyor. `resolveChannelEnabled` girdi **yok** dönüyor, yeni yüzey yok. |
| **Yeni yetki açığı** | Yok. `check-reminders` master kapısı **kısıtlaştırıyor** (gönderimi azaltır), genişletmez. `verify_jwt=false` olan iki fonksiyonun kendi yetkilendirmesi var. |
| **`pg_net`/`cron` yüzeyi** | `net.http_post` yalnız `cron.schedule` ile kurulan job gövdesinde çağrılıyor; `anon`/`authenticated` rolleleri `net`'e **bağlanamaz** (`NOLOGIN`) ve `net` Data API'de değil. |
| **`notification_preferences` RLS** | 4 politika `TO authenticated`, hepsi `auth.uid() = user_id` **INSERT/UPDATE `WITH CHECK` dahil** → başka kullanıcıya yazma reddedilir. |
| **Job gövdesi sır sızdırıyor mu** | Hayır — test, gerçek bir Vault token'ını gövdede arıyor ve bulamıyor (`FAIL` → düzeltildi). |

## Yeni testler (124 → 164 Deno + 2 SQL dosyası)

- `functions/check-reminders/night_window_test.ts` — **26** (yeni)
- `functions/_shared/channel_switch_test.ts` — **14** (yeni)
- `tests/cron_reminders_job.sql` — **13 kontrol** (yeni)
- `tests/a1r10_cron_shim.sql` — shim (yeni)

### Negatif ölçümler (kırmızı gördüm, geri koydum) — **4 adet**

1. **Sarma geri alındı** (`isWithinHourWindow` → `return false`) → **10 test kırmızı**
2. **Gün+dakika farkı atıldı**, sadece saat farkı kaldı → **9 test kırmızı**
   (gece yarısı tuzağı testi dahil)
3. **Token düz metne alındı + `Authorization`'a taşındı** → **4 kontrol FAIL**
   (başlık yok, Vault yok, `Authorization` var, başlık `NULL`)
4. **Sıklık `0 * * * *` yapıldı** → **2 kontrol FAIL** (09:00/18:00 kaçırma kapısı)
   — ek olarak `resolveChannelEnabled` eski `??` mantığına döndürüldü → **4 test kırmızı**;
   `check-reminders` master kapısı `if (false)` yapıldı → **2 test kırmızı**.

### ⭐ "Yanlış yeşil" — 3 kez yaşandı, hepsi düzeltildi

| Yaşanan | Nasıl yakalandı | Düzeltme |
|---|---|---|
| Kaynak taraması **yorumdaki** eski koşulu "kullanım" saydı | Test kırmızı ama sebebi yanlıştı | `stripComments()` yardımcısı (Deno testinde) + `regexp_replace` (SQL testinde) |
| Regex `minute:` aradı, kaynak **kısaltma** `{ minute }` yazıyordu | 1 test kırmızı | `\bminute\b` + `weekday` filtresi |
| `to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)')` shim'deki **4 argümanlı** imzayı görmedi → job **sessizce kurulmadı** | `WARNING: job YOK` | **3 imza** kabul ediliyor; aynı hata `full_setup.sql`'de de düzeltildi |
| Vault kolon adı: shim `secret` yapmıştı, gerçek **koltuğun** adı **`decrypted_secret`** | Gövde `column "decrypted_secret" does not exist` | Supabase Vault dokümanı okundu, sözleşme düzeltildi |

## Doğrulama kanıtları

| Komut | Sonuç |
|---|---|
| `cd supabase && deno check --frozen=true functions/` | **0 hata** |
| `cd supabase && deno test --frozen=true --allow-env --allow-read --allow-net functions/` | **164 passed / 0 failed / 1 ignored** (Tur 8'de 124) |
| Kilit frozen koşusunda değişiyor mu | **Hayır** (CI'da sessiz yenilenme yok) |
| `20260929010000` migration, `calorix` (tam şema), **3× üst üste** | **0 gerçek hata**, her seferinde `A1r10: TAMAM — 1 adet check-reminders job'ı` |
| Aynı migration, **shimsiz** ortam (eklenti yok), 3× | **0 gerçek hata** (`NOTICE` ile atlanır) |
| `full_setup.sql` **1/2/3.** kez | **0 gerçek hata**, job sayısı **1** |
| `tests/cron_reminders_job.sql` | **13 ok / 0 FAIL** |
| İşlevsel kanıt | Job gövdesi **çalıştırıldı** → `net.http_request_queue`'da `POST`, doğru URL, `x-calorix-internal-token: <Vault'taki değer>`, `timeout 30000` |
| Vault boşken | Başlık `NULL` (sessiz 401 akışı), istek yine kuyruğa yazıldı (hata **yok**) |
| Migration ad denetimi (CI komutu, birebir) | ✓ **19** migration geçerli ve kronolojik sıralı |
| Commit kapsamı | 4 commit'in **4'ünde de** `supabase/` dışı dosya **0** |

## AKTARIM (başka alan)

### → A2 / A4 (Flutter, `lib/data/**` + `lib/features/**`) — P1

`notification_preferences_repository.dart:188` içinde:

```dart
final end = endHour >= 0 && endHour <= 23 && endHour >= start ? endHour : 23;
```

Sunucu artık gece aralığını **gerçekten destekliyor** (`start > end` → 21..23 ∪
0..9), bu yüzden `end`'i 23'e çekme artık gereksiz ve kullanıcının seçimini
**sessizce değiştiriyor** (21→09 seçen kullanıcıya 21→23 yazılıyor).
Dosyanın `toRow` yorumu da artık geçersiz.

**İstenen değişiklik:** `end`'i yalnız `0..23` aralığına clamp'le, `>= start`
kısıtını kaldır:
```dart
final end = _clamp(endHour, 0, 23, 21);
```

Ek: `server_notification_preferences_section.dart` içindeki `endHourOptions`
(A4r10'un `start..23` ile sınırlayan düzeltmesi) artık **24 seçeneğe** geri
açılabilir ve "gece aralığı yazılamaz" notu kaldırılabilir. Bu **ürün kararı**
gerektirir; sunucu tarafı hazır.

### → Operasyon (dashboard) — P0, migration öncesi

1. `INTERNAL_FUNCTION_TOKEN` edge secret olarak tanımlı olmalı:
   `supabase secrets set INTERNAL_FUNCTION_TOKEN=$(openssl rand -hex 32)`
   (A1 Tur 1'den beri açık.)
2. Token'ı Vault'a yaz (migration `calorix_internal_function_token` adını
   arıyor):
   ```sql
   SELECT vault.create_secret('<token>', 'calorix_internal_function_token', 'INTERNAL_FUNCTION_TOKEN ile aynı');
   ```
3. `20260929010000` migration'ını uygula. `NOTICE`/`WARNING` çıktısını oku:
   `TAMAM — 1 adet job` beklenir, `job YOK` ise eklenti/vault kontrol edilmeli.
4. Doğrulama:
   ```sql
   SELECT jobid, schedule FROM cron.job WHERE jobname = 'check-reminders';
   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 5;
   SELECT status_code, error_msg FROM net._http_response ORDER BY created DESC LIMIT 5;
   ```
   Beklenen: `7-59 * * * *` ve `status_code = 200`.

### → Operasyon — P0, yeni

**Proje `frozen` değil.** A1r8'in ölçtüğü kanıt (`supabase/.temp/linked-project.json`
→ `bzfnncensolirkqdohpq`, PG 17.6.1, eu-central-1) hâlâ geçerli ve kök
`.env`'de düz metin DB parolası var. Tur 3/4/7'de CHECK eklemeyi engelleyen
"veri yok" varsayımı bu yüzden hâlâ bir varsayım. Yeni eklenen CHECK'ler bu
yüzden **veri doğrulayan** tasarlandı (ihlal → `RAISE EXCEPTION`).

## Kalan riskler (açıkça)

1. **Cron job'ı canlı projede denenmedi.** Shim, tanımın ve gövdenin SQL
   olarak doğru olduğunu kanıtlar; `pg_cron`'un gerçek zamanlayıcısı ve
   `pg_net`'in gerçek HTTP gönderimi test edilemedi. Operasyon adımı zorunlu.
2. **A1r8'in eklediği 13 CHECK'in canlı veri durumu hâlâ doğrulanmadı.**
   Onaymadan uygulanırsa migration **durdurur** (veri kaybı yok, `RAISE
   EXCEPTION` + hangi `SELECT` çalıştırılacak yazılı).
3. **`goal_achieved` tipi hâlâ ölü tercih.** `check-reminders` bu tipi
   **okumuyor**; `send-notification`'ı çağıran dört çağrı da dört tipi
   gönderiyor. A4r10 arayüzden gizledi (ürün kararı 2-B) — doğru karar,
   ama tablo CHECK'i hâlâ kabul ediyor.
4. **DST geçişlerinde ±60 dk sapma.** `zonedMinutesBetween` gezegensel saat
   farkını görmez (damga ve kontrol farklı UTC ofsetlerinde olabilir). Kabul
   edildi: hatırlatma zamanlamasında 1 saatlik sapma, sıfırlama/tekrar
   gönderim gibi bir hatadan **çok** daha küçük. Test edilmedi.
5. **`hour == 23 && minute == 59` sınırında** `dayDiff` yuvarlaması
   (`Math.round`) ±1 gün kayabilir. `Date.parse` orta-noktası UTC gece
   yarısına denk geldiği için pratikte doğru, ama tam sınır test edilmedi.
6. **`check-reminders` hâlâ kullanıcı başına N+1 sorgu yapıyor** (profil + tercih
   + su/öğün/kilo sorguları). Saatte 7 koşuda 1000 kullanıcıda ~35 bin
   sorgu/gün. Kabul edilebilir ama ölçülmedi.
7. **`deno.lock` elle düzeltildi.** `--frozen` geçiyor, ancak bir sonraki
   bağımlılık güncellemesinde `deno cache`/`deno test`'in kısmi bıraktığı
   tuzak (A6r9 + bu tur) tekrarlayabilir.
8. **SQL testleri CI'a bağlı değil** (`.github/workflows/supabase.yml` yalnız
   `deno check`/`deno test` çalıştırıyor). `supabase/tests/*.sql` Postgres
   gerektiriyor. A6 alanı — dokunmadım.

## Sonraki öneriler (Tur 12)

1. **Operasyon:** Vault + secret + migration + doğrulama sorguları
   (yukarıdaki 4 adım). Bu yapılmadan sunucu bildirimleri hâlâ **gidiyor**.
2. `check-reminders`'ın N+1 sorgusunu azalt (tercihleri tek `in` sorgusuyla
   çek) — saatte 7 koşuda ölçüm gerekiyor.
3. `goal_achieved` için **ürün kararı**: tetikleme koşulu + idempotency damgası
   (`last_goal_achieved`). A1r3'ün `weekly_summary` hatasının aynısı olur
   aksi halde — A4r10'un raporunda yazdığı gibi.
4. `supabase/tests/*.sql` dosyalarını CI'a bağla (A6 alanı) — 5 SQL testi
   artık 7 oldu.
5. `deno.json`'a bir `"tasks"` bloğu ekleyip `deno lock` yenilemesini tek
   komuta bağla (kısmi kilit tuzağını kapatır).

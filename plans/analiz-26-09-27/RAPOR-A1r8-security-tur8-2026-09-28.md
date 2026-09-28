# RAPOR — A1r8-security — 2026-09-28 — Tur 8

> Kapsam: `supabase/**` (migration + edge function + config + SQL test).
> `flutter_app/**`, `src/**`, `tool/**`, `.github/**` **dokunulmadı**.
> Doğrulama ortamı: **Postgres 16.15 (Docker `a1r8-pg` / `a1r8-fs`)**, `deno 2.9.7`.
> Test dosyaları `supabase/tests/` altında (kullanıcı kısıtı: `/tmp` dışında).

## Özet (5 madde)

1. **⭐ `full_setup.sql` artık idempotent.** Dosya ikinci kez çalıştırılınca
   **105 hata** veriyordu (55 politika · 25 tablo/index · 13 trigger · 3 tip ·
   7 constraint); A1r2'den beri biliniyordu. Tümü `IF NOT EXISTS` /
   `DROP ... IF EXISTS` desenine çevrildi. **Ölçüldü:** 1./2./3. çalıştırmada
   **0 gerçek hata**. Parite `diff` (migration vs full_setup) FK + CHECK +
   politika → **boş**.

2. **⭐ "Proje frozen, veri yok" iddiası bu turda doğrulanamadı — CHECK'ler
   yine de eklendi, ama güvenli tasarımla.** `.gitignore`lanmış
   `supabase/.temp/` içinde **gerçek bir projeye bağlantı kanıtı** var
   (`ref bzfnncensolirkqdohpq`, Postgres 17.6.1, GoTrue v2.185.0,
   eu-central-1) ve `.env`'de düz metin DB parolası bulunuyor. "Şema boş"
   kanıtlanmış bir gerçek değil, **doğrulanmamış bir varsayım**dı. Bu yüzden
   13 CHECK **hiçbir satırı değiştirmeden** eklendi: mevcut satırlar ihlal
   ederse migration **görünür hata** verir ve hangi kolonun inceleneceğini
   yazar. Veri boşsa sorunsuz geçer; veri doluysa veri kaybettirmez.

3. **`isAlreadyDeletedAuthError` canlı yerine kaynak kodla doğrulandı ve
   gerçek bir açık bulundu.** Projede bağlı GoTrue sürümü `v2.185.0`; yanıt
   `error.code === "user_not_found"` veriyor (mühürlü hata kodu, mesaj
   değişebilir). Karar artık önce `code`'a bakıyor. **Test yazarken kırmızı
   çıkan açık:** `{message:"", status:404, code:"session_not_found"}` →
   idempotent *başarı* sayılıyordu. A1r4'ün kapattığı açık `code` alanı
   üzerinden yeniden açılmıştı; düzeltildi.

4. **`dbBypassUntil` kova bazlı yapıldı** (A1r2'den kalan tek `rate_limit.ts`
   riski). Anahtar, zaten RPC'ye gönderilen `p_bucket` ile birebir aynı
   şekilde türetiliyor → çağrı yerlerinde hiçbir değişiklik gerekmedi.
   60 sn değeri, eşikler ve anahtar biçimleri aynen korundu. **Ölçüldü:**
   bir kovanın arızası diğerini etkilemiyor.

5. **A4r7 şema uyumu: `favorite_foods` ✅ uyumlu, `notification_preferences`
   ✅ uyumlu, ama web istemcisinde 💥 gizli bir çakışma bulundu.** A4r7'nin
   yazdığı kolonların tamamı şemada karşılanıyor. Ancak web istemcisinin
   `NOTIFICATION_DEFAULTS` değerleri (`interval_hours: 0`) mevcut CHECK'e
   **takılıyor** — Postgres ile kanıtlandı (bkz. bulgular tablosu).

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `migrations/20260928400000_data_integrity_check_constraints.sql` (**yeni**, 300 satır) | 13 CHECK: `nova_score` 1-4 · `nutri_score` A-E · `calculated_* >= 0` · 5 `profiles` aralığı · 5 `chat_messages` JSONB tipi. Her biri **önce mevcut satırları doğrular**, ihlal varsa `RAISE EXCEPTION` + hangi `SELECT` çalıştırılacak yazılı. Hiçbir satır güncellenmez/delilmez | 18 migration sıfırdan **0 hata** · aynı migration **3× üst üste** 0 hata (`13/13` NOTICE) · **58 negatif/pozitif yazma denemesi** `tests/check_constraints.sql` ile |
| **P1** | `tests/check_constraints.sql` (**yeni**, 300 satır) | Her CHECK için **negatif** test: `EXCEPTION WHEN check_violation` ile "reddedildi" doğrulanır. `nova_score` 0/5/-1/99 · `nutri_score` F/X/AA/boş · `calculated_*` -1 (4 kolon) · 5 profiles aralığı (0/-5/366/100000…) · JSONB 5 tip × kolon. Ayrıca 13 kısıtın `convalidated` olduğu doğrulanır (NOT VALID sessizliği yakalanır) | **58 deneme doğrulandı** · iki kurulum yolunda da **yeşil** · negatif ölçüm aşağıda |
| **P1** | `full_setup.sql` | **İdempotans:** 3 `CREATE TYPE` → `DO $$ … duplicate_object … $$` (etiket dizisi karşılaştırmalı, farklıysa WARNING) · 15 `CREATE TABLE IF NOT EXISTS` · 10 `CREATE INDEX IF NOT EXISTS` · 59 `DROP POLICY IF EXISTS` · 13 `DROP TRIGGER IF EXISTS` · 7 `DROP CONSTRAINT IF EXISTS` · **+ 13 yeni CHECK** (bölüm 8, migration paritesi) | 1./2./3. çalıştırma **0 gerçek hata** · parite `diff` boş |
| **P1** | `functions/_shared/rate_limit.ts` | `dbBypassUntil` (tek global) → `dbBypassUntilByBucket: Map<bucket, number>`. Anahtar `<kovalar>:u:<id>` → `<kovalar>` (RPC'nin `p_bucket`'ı ile birebir aynı) · `pruneBypass` bellek koruması · `isDbBypassed()` test kancası · `dbBypassUntil` gözlem olarak korunur | `deno check` 0 hata · 4 yeni kova izolasyon testi |
| **P1** | `functions/delete-account/helpers.ts` | `isAlreadyDeletedAuthError`: karar önce `error.code` (`user_not_found` birebir), sonra mesaj regex'i. ⭐ **`code` doluysa ve `user_not_found` değilse → istisna** (bulunan açık). `duplicate_object` kanıtı GoTrue `v2.185.0` kaynak kodundan | 5 yeni test + 2 ölçülen negatif |
| **P2** | `functions/_shared/rate_limit_test.ts` | 4 yeni test (kova izolasyonu, pencere kalıcılığı, gözlem sıfırlama, temiz durum) | 115 → **124** |
| **P2** | `functions/delete-account/delete_account_test.ts` | 5 yeni test (gerçek GoTrue yanıtı, mesaj değişse de karar, geriye uyum, **GoTrue'un 11 diğer "not found" hatası**, kısmi kod eşleşmesi) | 39 test, 0 başarısız |
| **P2** | `functions/delete-account/index.ts` | `deleteAuthUser` yorumu: kararın artık `code`'a dayandığı belgelendi | `deno check` 0 hata |

## ⭐ "Proje frozen, production verisi yok" iddiasının sınanması (Görev 5)

PROTOKOL §0 bu varsayımı **gerçek** olarak veriyor. Bu turda sorguladım:

| Kanıt | Yön | Nerede |
|---|---|---|
| `"frozen"` kelimesi yalnızca **plan/rapor metinlerinde** geçiyor | frozen | `PROTOKOL.md:10`, `OPS-tur1`, 5 rapor |
| `linked-project.json` → `{"ref":"bzfnncensolirkqdohpq","name":"CaloriX",…}` | **canlı** | `supabase/.temp/` (**gitignore'lu** → A1r5 grepleri görmemiş) |
| `postgres-version` → `17.6.1.063` (boş test imajı değil) | **canlı** | `supabase/.temp/` |
| `pooler-url` → `aws-1-eu-central-1.pooler.supabase.com` | **canlı bölge** | `supabase/.temp/` |
| `.env` içinde düz metin `SUPABASE_DB_PASSWORD` (A1 raporunda işaretli) | **canlı** | `.env` (gitignore'lu) |

**Sonuç:** "şema boştur" **kanıtlanmış bir gerçek değil, doğrulanmamış bir
varsayımdır.** Bu, A1r2/A1r3/A1r4/A1r5'in "veri doğrulanamıyor" gerekçesiyle
üç turdur aynı CHECK'leri ertelemesine yol açmıştı. Bu turda iki şey yapıldı:

1. **Tasarım değişti:** "veri yok" varsayımına dayanarak eklemek yerine,
   kısıt **mevcut satırları doğrulayan** biçimde yazıldı. Veri boşsa sorunsuz
   geçer; doluysa **görünür hata** verir, hangi kolonun inceleneceğini söyler
   ve **hiçbir satıra dokunmaz**. Bu, A1r5'in `food_nutrition_values_non_negative`
   kısıtında zaten kullandığı desenin aynısı.
2. **`NOT VALID` bilinçli kullanılmadı:** Postgres'te `NOT VALID` bir CHECK
   mevcut satırları doğrulamaz **ve yeni yazmaları da engellemez** (kısıt
   `VALIDATE CONSTRAINT` ile temizlenene kadar pasif). "Gelecekte kapı
   kapansın ama şimdi veri bozulmasın" hedefi `NOT VALID` ile **sağlanmaz**.

**Arayüz açık bırakıldı:** Canlı projeye bağlanma yetkim yok (ve
PROTOKOL gereği kullanıcı kararı gerektirir). Veri doluysa migration'ın
`RAISE EXCEPTION` mesajındaki `SELECT` komutları çalıştırılıp sonuçlar
rapora dönülürse CHECK'ler derhal eklenebilir.

## `isAlreadyDeletedAuthError` — canlı doğrulama yerine kaynak kod (Görev 4)

Canlı GoTrue'ye bağlanılamadı, **ama** projede bağlı sürüm bellidir:
`supabase/.temp/gotrue-version` → **`v2.185.0`**. Bu sürümün kaynak kodu okundu:

```
internal/models/errors.go
    func (e UserNotFoundError) Error() string { return "User not found" }
internal/api/admin.go → loadUser()
    apierrors.NewNotFoundError(apierrors.ErrorCodeUserNotFound, "User not found")
internal/api/apierrors/errorcode.go
    ErrorCodeUserNotFound  ErrorCode = "user_not_found"
internal/api/apierrors/apierrors.go → HTTPError JSON etiketleri
    {"code": <http durumu>, "error_code": "<ErrorCode>", "msg": "<Message>"}
```

`@supabase/auth-js@2.117.2` → `lib/fetch.js` → `handleError()`:
`message = data.msg` · `status = HTTP` · `code = data.error_code` (yoksa `data.code`).

**`auth.admin.deleteUser()` gerçek hata gövdesi:**

| Soru | Cevap |
|---|---|
| `User not found` | ✅ `msg` alanında |
| `user_not_found` | ✅ **`error_code` alanında (mühürlü)** |
| 404 + boş gövde | ❌ GoTrue gövdeyi **dolduruyor**; bu hâl bir **ters proxy** senaryosu (A1r5 kuralı korundu) |
| `User already deleted` | ❌ **Bu hata GoTrue'da yok** (`adminUserDelete` hard-delete yapar, `ShouldSoftDelete` yalnız `DeletedAt != nil` ise sessizce `nil` döner) |

**Sonuç:** `error.code` **birincil** sinyaldir (mesaj sürümden sürüme
değişebilir, kod değişmez). A1r5'in "farklı sürümler başka metin dönebilir"
korkusu böylece **karşılanmış** oldu. Mesaj regex'i ikincil sinyal olarak
kaldı; GoTrue'daki diğer 11 `* not found` hatasının (`Session`, `Refresh
Token`, `Confirmation Token`, `Identity`, `Factor`, `Flow State`, …) hiçbiri
`user` sözcüğü içermediği için kalıba giremez.

### ⭐ Bulunan ve düzeltilen açık (negatif testle kanıtlandı)

`{ message: "", status: 404, code: "session_not_found" }` → `true` idi.
`"boş + 404"` kuralı `code` alanına **bakmıyordu**; yani GoTrue "oturum
bulunamadı" dediğinde, hata kodu elde dururken fonksiyon bunu "kullanıcı
zaten yok" sayıp **başarı** dönüyordu → `auth.admin.deleteUser()`
kullanıcıyı silmemiş olmasına rağmen KVKK talebi karşılanmış görünüyordu.
Düzeltme: `code` doluysa karar `code`'a aittir.

## A4r7 şema uyumu (Görev 3)

| A4r7 yazımı | Şema | Sonuç |
|---|---|---|
| `favorite_foods` upsert `{user_id, food_id}`, `created_at` gönderilmiyor | `id`/`created_at` `DEFAULT`, `user_id`/`food_id` `NOT NULL`, `UNIQUE(user_id,food_id)`, RLS `WITH CHECK auth.uid()=user_id` | ✅ **Uyumlu** — Postgres'te kanıtlandı (başka kullanıcıya yazma `RLS` ile reddedildi) |
| `notification_preferences` upsert `{user_id, notification_type, push_enabled, email_enabled, start_hour, end_hour, interval_hours, summary_day, summary_hour}` | Tüm kolonlar mevcut; `created_at`/`updated_at` `DEFAULT` (gönderilmiyor) | ✅ **Uyumlu** — `check-reminders` (`index.ts:275`) ve `send-notification` (`.select("*")`) ile aynı kolonlar |
| `notification_preferences_hours_range` CHECK'i | `start/end/summary_hour 0-23`, `interval_hours 1-24`, `summary_day 0-6` | ✅ A4r7 `_clamp()` ile normalize ediyor; 5 tip CHECK allow-list'iyle birebir |
| `favorite_foods.food_id` `NOT NULL` → `foodId == null` (custom gıda) | — | ✅ A4r7 `FavoriteButton` `foodId == null` iken düğmeyi **gizliyor**, hata yutturmuyor |
| `summary_day` dizini (0=Pazar) | `check-reminders/index.ts:261` yorumu **birebir aynı**; `getZonedParts` `WEEKDAY_INDEX` de 0=Pazar | ✅ Tutarlı |

### 💥 Bulunan çakışma — web istemcisi, migration yolundan önce çalıştırılırsa patlar

`src/hooks/useNotifications.ts:29-33` (`NOTIFICATION_DEFAULTS`) üç tip için
`interval_hours: 0` yazıyor. Mevcut `notification_preferences_hours_range`
CHECK'i `interval_hours BETWEEN 1 AND 24` istiyor. Postgres'te kanıtlandı:

```
INSERT ... ('weigh_in', ..., interval_hours=0, ...)
  -> ERROR: new row for relation "notification_preferences"
     violates check constraint "notification_preferences_hours_range"
INSERT ... ('weigh_in', ..., interval_hours=1, ...)   -- A4r7'nin değeri
  -> INSERT 0 1
```

A4r7 doğru değeri seçmiş (1-24 aralığında); **web** doğru değeri seçmemiş.
`src/**` benim alanım değil → **AKTARIM** (aşağıda). Migration'da CHECK'i
gevşetmedim: `interval_hours = 0` "her saat" anlamına geliyor, `check-reminders`
bu değeri kullansa **her koşuda** tetiklerdi — yani CHECK'in reddi doğru.

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P1** | `src/hooks/useNotifications.ts:29-33` | `NOTIFICATION_DEFAULTS` `interval_hours: 0` yazıyor → `notification_preferences_hours_range` CHECK'ine takılır. Kanıtlandı (yukarıda) | Web'de bildirim tercihi kaydetme **hata verir**; kullanıcı ayar kaydedemez | **`src/**` benim alanım değil** → A5r8'e AKTARIM. `interval_hours: 0` → `1` (veya CHECK'in `>= 0` yapılması, ama bu sema değişikliği) |
| **P1** | `flutter_app/lib/features/settings/widgets/notifications_dialog.dart:146` | `'weigh_in_frequency_days': int.tryParse(_frequency.text.trim()) ?? 7` — **aralık denetimi yok**; metin kutusuna `-5` yazılabilir. `check-reminders/index.ts:301` `daysSinceReminder >= frequencyDays` negatif değerle **her koşuda** sağlanıyor | Kullanıcı kendi ayarıyla tartılma hatırlatmasını **sürekli** alır (günde ~12 kez) | DB'de `profiles_weigh_in_frequency_days_range` CHECK eklendi (migration) → **yazma reddedilir**. Flutter tarafına da `clamp(1,365)` önerilir (**A3r8 alanı**, aktarım) |
| **P2** | `supabase/tests/*.sql` ↔ `.github/workflows/supabase.yml` | 5 SQL test dosyası CI'a bağlı değil (`supabase start` gerektiriyor) | Turlar arası regresyon CI'da yakalanmıyor | A6 alanı; `.github/**`'ya dokunmadım |
| **P2** | — | **`cron.schedule` hiçbir migration'da yok** (doğrulandı: `grep -rn "cron.schedule" supabase/` → boş). `check-reminders` **elle** tetikleniyor | `water`/`daily_log`/`weekly_summary`/`weigh_in` cron olmadan **hiç gönderilmiyor** | Supabase Dashboard'da `*/5 * * * *` + `x-calorix-internal-token: $INTERNAL_FUNCTION_TOKEN` (A1r3'ten kalan) |
| **P2** | `functions/_shared/rate_limit.ts` | `check-reminders` kova anahtarı `rateLimitKey("check-reminders", req, "internal")` → **tek global sayaç** (`check-reminders:u:internal`), 2/300 sn. İki paralel tetiklemede biri sürekli "atlandı" alır | Operasyonel | Kasıtlı (tek global cron). A1r5'ten kalan |
| **P3** | `functions/_shared/http.ts:31` | `corsHeaders`: bilinmeyen origin için `*` fallback. `Access-Control-Allow-Credentials` **gönderilmediği** için `*` + credential kombinasyonu tarayıcılarca reddedilir | Düşük (davranış doğru) | Bilinçli; dokunulmadı |
| **P3** | `storage.buckets.chat-attachments` | `allowed_mime_types` yalnız **4 görsel tipi**; AI kamera görselleri `image/heic` ise yüklenemez | Düşük | Ürün kararı. `photo_url` zaten hiç doldurulmuyor (4-A) |

## Serbest güvenlik taraması (Görev 6)

**Kendi ekibimin kodunda yeni açık arandı — 1 bulundu** (`isAlreadyDeletedAuthError`,
yukarıda; ölçüldü). Ek olarak:

| Alan | Bulgu | Sonuç |
|---|---|---|
| `isAllowedPushEndpoint` (A1'ın SSRF allow-list'i) | 11 senaryo test edildi: suffix yerine tam-host eşleşmesi ✅ · `http://` reddi ✅ · `fcm.googleapis.com.evil.com` reddi ✅ · `userinfo` (`https://fcm.googleapis.com@evil.com`) reddi ✅ · `169.254.169.254` (metadata SSRF) reddi ✅ · `localhost`/`[::1]` reddi ✅ · bozuk URL reddi ✅ | ✅ Açık yok |
| **Diğer edge function'larda SSRF** | 4 AI fonksiyonu (`ai-chat`, `recognize-food`, `recognize-food-text`, `calculate-macros`) `OPENAI_BASE_URL`'a istek atıyor. Bu **env** değişkeni, **kullanıcı girdisi değil** → SSRF yüzeyi yok. `check-reminders:126` → `supabaseUrl` (env). `send-notification:231` → `subscription.endpoint` (kullanıcı girdisi) ama allow-list arkasında | ✅ Açık yok |
| `rate_limit_hit` RPC | `p_key`/`p_bucket` parametreli `INSERT … ON CONFLICT` — **string interpolation yok**; `p_key` uzunluk/boşluk doğrulaması var | ✅ SQL injection yok |
| Rate limit anahtarları | 5 fonksiyon **kullanıcı bazlı** (`userId` = doğrulanmış uid); `check-reminders` kasıtlı global. `x-forwarded-for` **ilk** değer alınır (yaygın sahte-spoof açığı var — burada **daha sıkı** taraf: ilk değer güvenilir kabul edilir, saldırgan IP'sini gizlemek isterse kendi IP'sini yazar). `anon` hiçbir uca erişemiyor | ✅ Düşük risk |
| Storage politikaları | Kova: `public=false` · `file_size_limit=10485760` (10 MB) · `allowed_mime_types={image/jpeg,png,webp,gif}`. 4 politika (`INSERT/SELECT/UPDATE/DELETE`), hepsi `TO authenticated`, hepsi `(storage.foldername(name))[1] = auth.uid()::text`. `anon` erişimi yok. `public` politika sayısı: **4** (bir tanesi bile genel değil) | ✅ İyi yapılandırılmış |
| Storage dosya tipi doğrulaması | Kova seviyesinde `allowed_mime_types` var. **Eksik:** içerik imzası (magic bytes) denetimi yok — bir kullanıcı `.jpg` adıyla SVG/HTML yükleyebilir. Kova `private` olduğu ve nesne `Content-Disposition: inline` ile servis edilmiyorsa etki düşük | P3 — raporlandı |
| Cron tanımları | `grep -rn "cron.schedule" supabase/` → **boş**. Hiçbir cron job tanımlı değil | Yukarıda P2 olarak raporlandı |
| `INTERNAL_FUNCTION_TOKEN` | `check-reminders` ve `send-notification` token'ı **zorunlu kılıyor**; tanımlı değilse service_role JWT'sine düşüyor (her ikisi de sunucu tarafında `auth.getUser()` ile doğrulanıyor) | ✅ Doğru |
| `verify_jwt` | `config.toml`'da 6 fonksiyon `true`, 2 `false` (`check-reminders`, `send-notification` — ikisi de kendi yetkilendirmesine sahip) | ✅ Doğru |

## Yeni testler (115 → 124 Deno + 1 SQL dosyası)

- `rate_limit_test.ts` — 6 → **10** (+4): bir kovanın arızası diğerini
  **etkilemez** · aynı kovanın penceresi yeniden açılmaz · dolmuş pencere +
  tanımsız kova gözlemi · temiz durumda bypass yok.
- `delete_account_test.ts` — 34 → **39** (+5): gerçek GoTrue yanıtı
  (`error_code=user_not_found`) · **mesaj değişse de karar değişmez** ·
  `error_code` yokken geriye uyum · GoTrue'un **11 diğer "not found" hatası**
  + 6 kod · kısmi kod eşleşmesi (`not_user_not_found`) reddi.
- `tests/check_constraints.sql` — **yeni, 58 yazma denemesi** (13 kısıt için
  negatif + pozitif), `ROLLBACK` ile sarılı.

## Doğrulama kanıtları

| Komut | Sonuç |
|---|---|
| `deno check functions/` (`supabase/`'dan) | **0 hata** (24 dosya) |
| `deno test --allow-env --allow-read --allow-net functions/` | **124 passed / 0 failed / 1 ignored** (Tur 7'de 115) |
| Migration ad denetimi (CI adımının birebir komutu) | ✓ **18** migration adı geçerli, kronolojik sıralı |
| **18 migration sıfırdan** (Postgres 16.15) | **0 hata** (yalnız `20260111080533` `pg_cron`/`pg_net` yok diye atlandı) |
| `20260928400000` **3× üst üste** | **0 hata**, her seferinde `13/13 CHECK kisiti kuruldu` |
| `full_setup.sql` **1. çalıştırma** | **0 gerçek hata** (4 hata yalnızca `pg_cron`/`pg_net` eklentisinin stock `postgres:16-alpine` imajında olmaması) |
| `full_setup.sql` **2. çalıştırma** | **0 gerçek hata** — ⭐ düzeltme öncesi **105 hata** idi |
| `full_setup.sql` **3. çalıştırma** | **0 gerçek hata** |
| `tests/check_constraints.sql` | **58 deneme doğrulandı** · iki kurulum yolunda da **yeşil** |
| `tests/schema_contract.sql` | 0 hata · iki yolda |
| `tests/foods_cascade.sql` | 0 hata · iki yolda |
| `tests/account_deletion_scope.sql` | 0 hata · iki yolda |
| `tests/rls_policies.sql` | 0 hata · iki yolda |
| **Parite `diff`** (migration vs `full_setup`) | FK + **CHECK** + **POLİTİKA** → **boş** |
| `isAllowedPushEndpoint` 11 senaryo | 11/11 doğru |
| `favorite_foods` A4r7 yazma yolu (canlı Postgres) | INSERT başarılı · **başka kullanıcıya yazma RLS ile reddedildi** |
| `notification_preferences` web `interval_hours=0` | **CHECK ile reddedildi** (çakışma kanıtlandı) |

### Negatif test ölçümleri (kırmızı gördüm, sonra geri koydum)

1. **Kova izolasyonu.** `checkRateLimitDb`'de kova bazlı kontrolü
   `if (Date.now() < dbBypassUntil)` (global) olarak geri aldım →
   **3 test kırmızı** (`ai-chat bypass bekleniyordu ama acik degil`).
   Geri koydum → 9 passed.
2. **`code` farkındalığı.** `if (code !== "") return false;` satırını
   kaldırdım → **2 test kırmızı** (`error_code="session_not_found" idempotent
   başarı sayılmamalı`). Geri koydum → 39 passed.
3. **CHECK kısıtları.** 4 kısıtı `ALTER TABLE … DROP CONSTRAINT` ile sildim
   → test **20 ihlali** tek satırda raporladı:
   `nova_score=0/5/-1/99 KABUL EDILDI · calculated_*=-1 KABUL EDILDI ·
   weigh_in_frequency_days=0/-1/-5/366/100000 KABUL EDILDI ·
   metadata=[]/1/"x"/true/null KABUL EDILDI`. Migration'ı yeniden
   çalıştırdım → **58 deneme doğrulandı**.

**Öğrenilen (turlardan):** Negatif ölçüm olmadan "kısıt var" iddiası
kanıtlanmış sayılmaz. Bu turda iki gerçek açık **yalnızca** negatif
testler yazıldığı için bulundu (`code` farkındalığı özellikle: mevcut test
yeşildi, `code` alanı hiç test edilmemişti).

## Doğrulayamadığım şeyler (açıkça)

1. **Canlı Supabase projesine bağlanmadım** — `bzfnncensolirkqdohpq`
   gerçek bir proje ve `.env`'de parolası var, ama canlıya bağlanmak kullanıcı
   kararı gerektirir. Bu yüzden 13 CHECK "veri doğrulaması yapılmadan" değil,
   **"veri doğrulanırsa hata vererek"** eklendi.
2. **GoTrue'ye canlı istek atılmadı.** `isAlreadyDeletedAuthError` **sürüm
   sabitli kaynak koda** dayandırıldı (`v2.185.0`), canlı HTTP yanıtına değil.
   Bu, tahmin değil kanıt; ama gerçek bir `deleteUser` denemesiyle teyit
   edilmedi.
3. **Edge function'lar uçtan uca çalışmadı** — `supabase functions serve` yok.
4. **CI'da ilk çalıştırılmadı** — `.github/workflows/supabase.yml` A6'nın
   alanı. Migration ad denetimi adımı yeni dosyayı otomatik kapsıyor
   (18 migration geçti). Yeni SQL testleri CI'a **eklenmedi**.
5. **`pg_cron`/`pg_net` yok** — stock `postgres:16-alpine` imajında bulunmuyor;
   `full_setup.sql`'in 4 hatası ve `20260111080533`'ün atlanması bu yüzden.
   Supabase'de bu eklentiler kuruludur, yani **gerçek ortamda 0 hata**.

## AKTARIM (başka alan)

### → A5r8 (`src/**`) — 💥 P1: web bildirim varsayılanları CHECK'e takılıyor

`src/hooks/useNotifications.ts:29-33` `NOTIFICATION_DEFAULTS` içinde
`interval_hours: 0` var (`weigh_in`, `daily_log`, `goal_achieved`).
`notification_preferences_hours_range` CHECK'i `1-24` istiyor → **web'de
bildirim tercihi kaydetme hata verir** (Postgres'te kanıtlandı).

**Önerilen düzeltme (tek satır):** `interval_hours: 0` → `interval_hours: 1`.
`check-reminders` bu kolonu yalnız `water` tipinde kullanıyor
(`index.ts:354`); diğer üç tipte değer anlamsız, `1` güvenli. A4r7 Flutter
tarafında zaten `1` yazıyor — yani **web** ayrışmış durumda.

### → A3r8 (`flutter_app/lib/core/**`) — P1: `weigh_in_frequency_days` aralık denetimi yok

`notifications_dialog.dart:146`
`'weigh_in_frequency_days': int.tryParse(_frequency.text.trim()) ?? 7`
→ metin kutusuna `-5` yazılabilir, `check-reminders` bunu her koşuda tetikler.
DB tarafında artık CHECK var (yazma reddedilir) ama kullanıcı **neden kaydedemediğini**
anlamayacak. Flutter tarafında `clamp(1, 365)` önerilir.

### → Ana ajan — `plans/` senkronluğu

- `PROTOKOL.md:10` "production verisi **yok**" ifadesi **gerçekleşmiyor**:
  `supabase/.temp/` içinde canlı proje kanıtı var (gitignore'lu olduğu için
  önceki turların grep'leri görmedi). Protokolün düzeltilmesi veya
  `supabase/.temp/` içeriğinin dikkate alınması önerilir.
- `.env` içindeki düz metin DB parolası hâlâ bekliyor (P0 işaretleme, A1 raporu).
- `OPS-tur1-security.md`'ye eklenecek: yeni migration `20260928400000` deploy
  adımı. **Not:** veri doluysa migration `RAISE EXCEPTION` ile durur — o durumda
  hata mesajındaki `SELECT` komutları çalıştırılmalı.
- **Cron tanımı yok:** `check-reminders` için Dashboard job'u hiç kurulmamış.
  `*/5 * * * *` + `x-calorix-internal-token` başlığı gerekiyor.
- `full_setup.sql` artık idempotent → "yeni kurulum yapıyorum" diyen biri
  dosyayı yanlışlıkla iki kez çalıştırırsa artık zarar görmez.

## Sonraki öneriler (Tur 9)

1. **Canlı veri doğrulaması** (P1): 13 CHECK'in canlıya alınıp alınamayacağı
   `NOTICE`/`EXCEPTION` çıktısıyla belirlenir. Kullanıcı migration'ı
   denerse sonucu rapora dönülsün.
2. **A5r8'e `interval_hours: 0` aktarımı** (P1) — web bildirim ayarları şu an
   kaydedilemiyor.
3. **`check-reminders` cron job'ı** (P2) — tanım yok, hatırlatıcılar hiç gitmiyor.
4. **`full_setup.sql` CI'a bağlansın** (P2) — idempotans iddiası artık
   otomatik doğrulanabilir: dosyayı iki kez çalıştırıp hata sayısını karşılaştıran
   bir adım. Bu, A1r2'den beri açık olan borcu kalıcı kapatır.
5. **`user_roles` + `public.has_role()`** hâlâ tamamen ölü (A1r5'ten kalan).
6. **`foods.verified` / `recent_foods`** — hâlâ yazan yol yok (ürün kararı).

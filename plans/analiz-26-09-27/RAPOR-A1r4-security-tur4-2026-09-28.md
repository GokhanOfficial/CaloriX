# RAPOR — A1r4-security — 2026-09-28 — Tur 4

> Kapsam: `supabase/**` (migration + edge function + config + test),
> `.github/workflows/supabase.yml` (**yeni**).
> `flutter_app/**`, `src/**`, `tool/**` dosyalarına **dokunulmadı**
> (`AndroidManifest.xml` yalnızca **okundu**, bulgular raporlandı).
> Doğrulama ortamı: **Postgres 16.15 (Docker `a1r2-pg`, veritabanları
> `a1r4` / `a1r4fs` / `a1r4final`)**, `deno 2.9.7`, `python3` + `PyYAML`.

## Özet (5 madde)

1. **CI'da edge function kapısı eklendi** (`.github/workflows/supabase.yml`).
   Daha önce `.github/workflows/` altında yalnızca `flutter.yml` (Dart) ve
   `react.yml` (`src/**`) vardı; `deno check` / `deno test` **hiçbir yerde
   çalışmıyordu**. 19 edge testi (Tur 3'te 54'e çıktı) yalnızca lokalde
   koşuyordu: bir güvenlik düzeltmesi regresyona uğrasa CI sessizce yeşil
   kalırdı. Yeni iş `supabase/` dizininde `deno check functions/` +
   `deno test --allow-env --allow-read --allow-net functions/` +
   migration dosya adı/sırası denetimi çalıştırır. `denoland/setup-deno`
   **SHA'ya pinlendi** (`22d081ff…` = v2.0.5, GitHub API ile doğrulandı).
2. **Kendi ekibimin kodunda 3 gerçek hata bulundu ve düzeltildi:**
   (a) `ValidationError` mesajı **4 edge function'da doğrudan istemciye**
   gönderiliyordu (`"height_cm 100-260 aralığında olmalı"` → şema sızıntısı);
   (b) `delete-account` tablo silme hatalarını `continue` ile **yutup başarı
   dönüyordu** (KVKK açısından eksik silme iddiası); (c) push şifrelemede
   `MAX_PLAINTEXT_BYTES` **iç tutarsız** hesaplanmıştı → 3993-4058 bayt
   arası gövdeler **sessizce** reddediliyordu.
3. **`profiles.timezone` artık okunuyor** (üç turdur kullanılmıyordu) ve
   serbest metin kapısı kapatıldı. `check-reminders` sabit `UTC+3` yerine
   `Intl` tabanlı `getZonedParts()` kullanıyor; yeni migration
   `profiles_timezone_is_valid_iana` CHECK kısıtı ile kolonu gerçek bir IANA
   dilimiyle sınırlıyor. **TR kullanıcıları için davranış değişmiyor.**
4. **Push şifreleme kenar durumları tarandı ve 2 gerçek açık kapatıldı:**
   `decryptPushBody` `rs` değerini hiç doğrulamıyordu (`rs = 0` → kayıt
   ayrıştırması anlamsızlaşıyor, sessizce yanlış metin riski) ve `idlen > 0`
   durumunda gövdeye gömülü `as_public` ile `Crypto-Key: dh=` başlığındaki
   anahtarı **karşılaştırmıyordu** (KCI). Ayrıca `encryptPushBody` RFC 8291
   §4'ün "rs > plain + 1 + tag" şartını **uygulamıyordu**.
5. **Doğrulama:** `deno check functions/` **0 hata** · `deno test` **100
   passed / 0 failed / 1 ignored** (54 → 100, **+46 test**) · **16 migration
   sıfırdan** Postgres 16'ya 0 hata (1'i yalnızca `pg_cron`/`pg_net`
   uzantısı eksikliği nedeniyle shim'le atlandı) · yeni migration **3×
   üst üste** idempotent · `rls_policies.sql` **49/49** (migration yolu **ve**
   `full_setup.sql` yolu) · `full_setup.sql` sıfırdan **0 hata, 55 politika** ·
   CI YAML'u `yaml.safe_load` ile **geçerli**.

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `.github/workflows/supabase.yml` (**yeni**) | Edge CI kapısı: `setup-deno` SHA'ya pinli (`22d081ff2d3a40755e97629de92e3bcbfa7cf2ed` # v2.0.5), `DENO_VERSION: "2.9.7"` (lokal ile birebir), `cache: true` (kök `deno.lock` hash'lenir → CI **lokal** ile aynı bağımlılık grafiğini çözer), `working-directory: supabase`, `timeout-minutes: 15`, `permissions: contents: read`, `concurrency` (cancel-in-progress), `paths: supabase/**` + workflow dosyası, `deno check` **önce** `deno test`'ten önce | YAML geçerli; her iki komut lokalde yeşil |
| **P1** | `functions/{calculate-macros,recognize-food,recognize-food-text,send-notification}/index.ts` | `ValidationError` mesajı istemciye sızdırıyordu (alan adı + beklenen aralık). Artık `console.error` ile **yalnızca sunucu loguna**, istemciye sabit `"Eksik veya geçersiz istek"` | `auth_order_test.ts` (yeni, 10 test) |
| **P1** | `functions/delete-account/index.ts` + `helpers.ts` | Tablo silme hatası `continue` ile yutuluyor, `deleted` listesine girmiyor, **200 başarı** dönüyordu. Yeni sözleşme `{ deleted, failed }`; `auth.admin.deleteUser()` başarısızsa kullanıcıya `DELETION_PARTIAL_MESSAGE` (sabit, şemasız) + `retryRecommended: true` | `delete_account_test.ts` 14 → **19 test**; `supabase/tests/account_deletion_scope.sql` (yeni, 6 adım, her iki kurulum yolunda) |
| **P1** | `functions/delete-account/index.ts` | Rate limit **5/saat → 2/saat**. Gerekçe: silme yıkıcı ve geri alınamaz; parola doğrulandığı için kaba kuvvet için 2 yeterli, 5 başarısız/zorlanmış silmeye izin veriyordu | `delete_account_test.ts` "rate limit kullanıcı bazlı ve 2/saat" |
| **P1** | `functions/_shared/web_push_crypto.ts` | `MAX_PLAINTEXT_BYTES` 3993 → **4058** (ölçüm: gövde = 21 + plain + 1 + 16; 4096 sınırı). 3993-4058 arası gövdeler sessizce reddediliyordu | `web_push_crypto_edge_test.ts` (yeni, 19 test) |
| **P1** | `functions/_shared/web_push_crypto.ts` | `encryptPushBody` artık RFC 8291 §4'ün "rs > plain + 1 + tag" şartını uyguluyor (küçük `rs` ile üretilen açılabilir olmayan gövde engellendi) | `web_push_crypto_edge_test.ts` "çok küçük rs'de düz metin reddedilir" |
| **P1** | `functions/_shared/web_push_crypto.ts` | `decryptPushBody`: `rs = 0` artık reddediliyor (`geçersiz kayıt boyutu (rs=0)`); `idlen > 0` durumunda gövdeye gömülü `as_public` ile `dh=` başlığı **sabit zamanlı** karşılaştırılıyor (uyumsuzluk reddediliyor) | `web_push_crypto_edge_test.ts` idlen/rs testleri |
| **P1** | `functions/check-reminders/index.ts` + `helpers.ts` | Dört damga yazımı `writeReminderStamp()` üzerinden tek noktadan geçiyor; hata **yutulmuyor**, `console.error` ile "TEKRAR gönderilebilir" diye loglanıyor ve koşu özetine `stampFailures` sayacı giriyor | `check_reminders_test.ts` 7 → **20 test** |
| **P1** | `functions/check-reminders/index.ts` | Sabit `UTC+3` (`now.getUTCHours() + 3`) kaldırıldı; `profiles.timezone` SELECT'e eklendi ve `getZonedParts()` ile gün/saat/tarih hesaplanıyor. `now.getDay()` (çalıştıranın yerel günü) ve `now.toISOString().split("T")[0]` (UTC günü) de kaldırıldı | `check_reminders_test.ts` 8 saat dilimi testi (TR, Tokyo, Berlin CEST/CET, Kolkata, Kathmandu, Chatham) |
| **P2** | `migrations/20260928200000_profiles_timezone_hygiene.sql` (**yeni**) | `public.is_valid_timezone(TEXT)` (`STABLE`, `search_path = ''`) + `profiles_timezone_is_valid_iana` CHECK; NULL/boş satırlar `Europe/Istanbul`'a normalize edilir; 8 referans dilim doğrulanır | 3× idempotent; geçerli/geçersiz/NULL değer denendi (reddedildi) |
| **P2** | `full_setup.sql` | Aynı `is_valid_timezone()` fonksiyonu + CHECK + `COMMENT` eklendi (**senkronluk** bozulmasın) | Sıfırdan 0 hata, 55 politika, 49/49 RLS |
| **P2** | `send-notification/index.ts` | `getEmailTemplate` imzasındaki **ölü `title` parametresi** kaldırıldı (Tur 1'den kalan P2). `subject: title` **korundu** | `auth_order_test.ts` imza testi |
| **P2** | `config.toml` | `delete-account` bloğuna `verify_jwt = true` gerekçesi yazıldı (neden `false` yanlış olurdu, neden `true` doğru, OAuth eklenirse ne değişir) | `auth_order_test.ts` config tutarlılık testi |
| **P2** | `functions/_shared/auth_order_test.ts` (**yeni**) | Kimlik doğrulama **sırası** denetimi: CORS/405 → auth → rate limit → gövde. Ayrıca `config.toml` kapsamı, `verify_jwt=false` yasağı, hata sızıntısı, CORS | 10 test |
| **P2** | `supabase/tests/account_deletion_scope.sql` (**yeni**) | `DATA_TABLES` (12) ↔ gerçek şema bağı; **kapsam boşluğu** taraması (`user_id` kolonlu ama listede olmayan tablo); FK sırası; gerçek silme; B kullanıcısının korunması; **idempotansiy** (2. tur) | 6/6 adım, her iki kurulum yolunda |

### `MAX_PLAINTEXT_BYTES` hatasının somut etkisi (ölçüm)

`preparePushPayload` (vapid.ts) düz metni 4096 **karaktere** kadar kabul eder
(`data` düşürerek/keserek sığdırır), `encryptPushBody` ise 3993 bayt üstünü
reddederdi. Aradaki **3993-4058 baytlık** pencerede:

```
3993 bayt düz metin → gövde = 21 + 3993 + 1 + 16 = 4031 bayt  → 4096 sınırında ✔ (eskiden reddediliyordu)
4058 bayt düz metin → gövde = 21 + 4058 + 1 + 16 = 4096 bayt  → tam sınır     ✔ (eskiden reddediliyordu)
4059 bayt düz metin → gövde = 4097                             → doğru reddedilir
```

`check-reminders` haftalık özeti **HTML** gövde gönderir (`<ul><li>…` ~200-400
bayt) ve `data` alanı taşıyabildiği için bu pencereye girebilir. Etki:
**push sessizce atlanır**, e-posta + `notifications` satırı yazıldığı için
hata görünmez; `send-notification` yalnızca `console.error` basar.

### `rs` doğrulaması gerçekten gerekli miydi? (ölçülen davranış)

Brifte varsayılan "sonsuz döngü / `Number` taşması" **yanlış çıktı**:
`rs = 0xFFFFFFFF` → `perRecord = 4294967311` JS'te güvenli tam sayı, döngü gövdeyi
**tek kayıt** olarak işleyip biter. Gerçek sorun `rs = 0`'dır: `perRecord = 16`
olur ve kayıt sınırları şifreli metinle **hizasız** olduğu için çözülen metin
anlamsızlaşır (delimiter rastgele yerde aranır; nadiren **sessizce** yanlış
metin üretir). `rs = 0` reddedildi; `0xFFFFFFFF` güvenli bulunduğu için
kısıtlanmadı (test bunu belgeler).

## `check-reminders` damga hatası (Görev 2)

**Sorun (A1r3'ün bıraktığı P2):** dört ayrı yerde
`await supabase.from("profiles").update({...}).eq("id", profile.id)` çağrısı
vardı ve **hiçbirinde** dönen `error` kontrol edilmiyordu. Damga yazılamazsa
(RLS, ağ hatası, kolon eksikliği) o tip hatırlatma **bir sonraki cron koşusunda
tekrar gönderilir** — kullanıcı günde ~12 kez aynı bildirimi alır, hata
sessizce yutulur.

**Çözüm:** `writeReminderStamp(client, userId, column, value, log?)`
(`check-reminders/helpers.ts`):

- `{ error }` **kontrol edilir**; hata varsa `false` döner,
- `log` (üretimde `console.error`) ile **"bu tip hatırlatma bir sonraki koşuda
  TEKRAR gönderilebilir"** açıkça yazılır (izlenebilirlik),
- istisna (ağ/PostgREST) yakalanır, fonksiyon **çökmez**,
- `index.ts` `stampFailures` dizisine yazar ve koşu sonunda **tek satır**
  toplam loglar; HTTP gövdesine `stampFailures: <sayı>` döner (cron alarmı
  üretebilir), gövdede tablo/kolon adı yoktur.

**Testler (4 yeni, sahte PostgREST builder ile):** başarılı yazma `true` +
`logs.length === 0` · DB hatası `false` + 1 log + kolon/kullanıcı adı + "TEKRAR"
· ağ istisnası `false` + log · logger yoksa da çalışır. Artı bir kaynak
senkronizasyon testi: `index.ts`'te kontrolsüz `profiles.update(` deseni **0**
olmalı ve `writeReminderStamp(` **4** kez geçmeli.

## `profiles.timezone` kararı ve risk analizi (Görev 3)

**Karar: kolonu okuyan yol kuruldu** (brifin 1. şıkkı) + **migration ile
veri kaynağı güvenli hale getirildi**.

Kolon 20260111075621'den beri `text DEFAULT 'Europe/Istanbul'` idi ve
**hiç okunmuyordu**. Eski kod iki ayrı hata yapıyordu:

| Eski | Doğru | Etki |
|---|---|---|
| `now.getUTCHours() + 3` | `getZonedParts(profile.timezone, now).hour` | Berlin'de yaz saati 1 saat, Hint/Nepal'de 30/45 dk, Chatham'da 45 dk sapma |
| `now.getDay()` | `getZonedParts(...).weekday` | Edge Runtime UTC'de çalışır → **UTC günü**; TR'de 03:00'e kadar **bir gün geri** |
| `now.toISOString().split("T")[0]` | `getZonedParts(...).date` | Su hatırlatmasının "bugün" süzgeci UTC günüydü |

**Hangi hesaplar duyarlı, etkisi ne:**

1. `timezone IS NULL` → `handle_new_user` trigger'ı kolonu **doldurmuyor**,
   `DEFAULT` yalnızca INSERT anında işlediği için **yeni hesaplarda da NULL**.
   Migration bunları `Europe/Istanbul`'a normalize eder → **TR kullanıcıları
   için davranış bit bit aynı** (`NULL`da eski kod da UTC+3 sayıyordu, çünkü
   sabit `+3` idi). Sıfır risk.
2. Kolonu TR dışı bir IANA adıyla doldurmuş hesap **sayısı bilinmiyor**
   (proje frozen, canlı veri yok). Migration **hiçbir satırı değiştirmez**
   (yalnızca NULL/boş → TR), dolayısıyla pratikte etkilenen hesap sayısı
   sıfıra yakındır. Canlıya uygulamadan önce:
   `select timezone, count(*) from profiles group by 1 order by 2 desc;`
3. Flutter tarafında **hiçbir yol `timezone` yazmıyor** (doğrulandı:
   `flutter_app/lib/**` ve `src/**` içinde yalnızca `flutter_timezone` paketi
   ve yerel `tz` kullanımı var; `profiles.timezone`'a hiç yazma yok).
   Yani kolon bugün **kullanıcı tarafından da doldurulamıyor** → yeni davranış
   riski yok, yararı da sınırlı (ileri turda istemciye bir ayar eklenmeli).
4. **Migration riski:** CHECK kısıtı mevcut satırları doğrular; bozuk
   (boş/çöp) satır varsa `ADD CONSTRAINT` **hata verir** ve migration
   durur — bu, sessiz veri kaybı yerine **görünür** bir hata olması için
   bilinçli bir tercihtir (bilgide belgelendi). Postgres 16'da 0 hata.

**Kolonun veri kaynağı olması:** kolon `text` olduğu için RLS
(`Users can update their own profile`) kullanıcının **serbest metin**
yazmasına izin veriyordu. Yeni `public.is_valid_timezone()` + CHECK:
`Europe/Nowhere`, `''`, `'   '`, `'+03:00'`, `'UTC+3'`, `'x'`, `NULL` → hepsi
reddedildi (doğrulandı), `Europe/Berlin` → kabul edildi.

**Migration yazım notu (öğrenilen hata):** ilk denemede CHECK içine
`pg_timezone_names()` **alt sorgusu** yazıldı; Postgres reddetti:
`ERROR: cannot use subquery in check constraint`. Alt sorguyu kısıtın değil
`STABLE` bir **fonksiyonun gövdesine** taşımak çözdü (SQL dilinde fonksiyon
gövdesi sorgu içerebilir). `search_path = ''` + tam şema ön eki uygulandı.

## `delete-account` kendi denetimim (Görev 4)

**Bunlar iyiydi (düzeltilmedi, doğrulandı):** parola hiçbir log/console
ifadesinde geçmiyor ve `JSON.stringify(body)` yok (yeni test); kullanıcı
kimliği yalnızca doğrulanmış JWT'den geliyor, `body.userId` **yok**; JWT
payload decode edilmiyor (`auth.getUser()`); hata mesajları sabit
(`mapPasswordErrorToStatus` bilinmeyen hatayı bile 401'e indiriyor, "relation
/ database" sızmıyor); `service_role` istemcisi yalnızca **parola doğrulandıktan
sonra** kullanılıyor, kapsam `userId`'ye sabit; `INTERNAL_FUNCTION_TOKEN`
bilinçli **kullanılmıyor** (cron değil); storage silme hatası akışı düşürmüyor;
silme sırası `assertSafeDeletionOrder()` ile doğrulanıyor ve **global tablolar
(`foods`, `rate_limits`, `user_roles`) listede yok** (veri sızıntısı koruması).

**Bulunan ve düzeltilen sorunlar:**

1. **[P1] Kısmi silme başarı gibi gösteriliyordu.** `deleteUserRows` hata alan
   tabloyu `continue` ile atlıyor, `deleted` listesine koymuyor ve çağıran
   **200 başarı** dönüyordu. `profiles` silinemezse kullanıcının profili kalır
   ve `auth.admin.deleteUser()` de FK ihlali nedeniyle **başarısız** olur →
   KVKK "sil" talebi karşılanmamış. Düzeltme: `{ deleted, failed }` +
   `DELETION_PARTIAL_MESSAGE` (sabit, şemasız; "tekrar deneyin" yönlendirmesi
   içeriyor) + `retryRecommended: true`. Detay yalnızca sunucu logunda.
2. **[P1] Rate limit 5/saat → 2/saat.** 5 deneme, silmeyi bilen biri için
   5 yıkıcı işleme izin veriyordu. Anahtar **kullanıcı bazlı**
   (`delete-account:u:<uuid>`) — IP tabanlı olsaydı NAT arkasındaki
   kullanıcılar birbirini kilitlerdi; bu doğrulandı ve teste bağlandı.
3. **[P2] `mapPasswordErrorToStatus` 429'u koruyor** ama `signInError.status`
   Supabase'te string olabilir; tip `number` varsayıyor (`as` ile zorlanmış).
   Gerçek davranış doğru (`Error: 429` string'i `status` alanına gelmezse
   401'e düşer, yani **güvenli** taraf). Dokunulmadı, raporlandı.

**Doğrulayamadığım:** `signInWithPassword` yolu, `listBuckets()` ve
`auth.admin.deleteUser()` gerçek Supabase Auth'e karşı denenmedi (CLI yok).
`auth.admin.deleteUser()` yetkisi `service_role` ile gelen JWT'ye bağlı;
`requireUserContext(req, { serviceRole: true })` `SUPABASE_SERVICE_ROLE_KEY`
eksikse `AuthError(500)` fırlatır → istemciye "İstek işlenemedi" döner
(konfigürasyon hatası, sızıntı yok).

## Push şifreleme kenar durumları (Görev 4)

19 yeni test (`web_push_crypto_edge_test.ts`), hepsi geçiyor. Ölçülen sonuçlar:

| Kenar durum | Ölçülen davranış | Sonuç |
|---|---|---|
| `idlen = 65` + `dh=` **uyuşuyor** | eski (pre-RFC-8291-§4) biçim çözülüyor | destekleniyor (test) |
| `idlen = 65` + `dh=` **uymuyor** | reddediliyor ("KCI ihlali olabilir") | **düzeltildi** |
| `idlen = 255`, gövde yetersiz | reddediliyor ("idlen gövde sınırını aşıyor") | zaten vardı |
| `rs = 0` | reddediliyor ("geçersiz kayıt boyutu (rs=0)") | **düzeltildi** |
| `rs = 0xFFFFFFFF` | **sonsuz döngü YOK**; tek kayıt sayılıyor, içerik bozulmuyor | davranış belgelendi (düzeltme gerekmedi) |
| Üretici `rs` girdisi 0/-1/1.5/2³²/NaN | reddediliyor | zaten vardı |
| 4058 bayt düz metin | kabul (gövde tam 4096) | **düzeltildi** (eskiden reddediliyordu) |
| 4059 bayt düz metin | reddediliyor | yeni doğru sınır |
| `rs = 32`, 40 bayt düz metin | reddediliyor (RFC §4 şartı) | **düzeltildi** |
| Çoklu kayıt (`rs < plain`) | üretici desteklemez (tek kayıt zorunlu) | sözleşme testle sabitlendi |
| Kesik gövde (son kayıt eksik) | reddediliyor ("GCM etiketi doğrulanmadı") | zaten vardı |
| `dh` eksik/bozuk/65 bayt değil | reddediliyor (4 varyant) | zaten vardı |
| Gövde < 21 bayt | reddediliyor | zaten vardı |
| Yanlış `Content-Encoding` | reddediliyor | zaten vardı |
| `as_public` mesaj başına yenileniyor | 5 mesaj = 5 farklı `dh` | zaten vardı |

**Önemli ölçüm:** `Intl.DateTimeFormat` **ISO ofset dizgelerini de kabul
ediyor** (`+03:00` ✔, `GMT+3`/`UTC+3`/`+3` ✘). Migration'daki CHECK
`pg_timezone_names()` ile doğrular ve `+03:00` O LİSTEDE **yoktur** → yazma
engellenir. Yani kanonik girdi daima IANA adı; bir ofset dizgesi yine de
sızarsa `Intl` çözer ve akış kırılmaz (sessizce UTC'ye de düşmez).

## Diğer güvenlik bulguları (Görev 4)

| Alan | Sonuç |
|---|---|
| **Kimlik doğrulama sırası** | **Tutarlı.** 7 fonksiyonun hepsinde: `OPTIONS` → 405 → **auth** → rate limit → gövde. Kimliksiz istek `checkRateLimit`'e (DB'ye yazan sayaç) ulaşmıyor. Test ile sabitlendi; yeni fonksiyon eklendiğinde test kırılıp yeniden inceleme zorunlu kılıyor |
| `config.toml` kapsamı | **7/7 fonksiyon tanımlı.** `verify_jwt = false` yalnızca `check-reminders` ve `send-notification` (kendi token doğrulamaları var). Kullanıcı uç noktalarının hepsi `true`. Test ile sabitlendi |
| `delete-account verify_jwt` | **`true` doğru.** `false` olsaydı koruma işlevsel olarak sürerdi (`requireUserContext` yine doğruluyor) ama gateway öncesi reddetme, daha küçük yüzey alanı ve `service_client` oluşturma maliyetinden tasarruf sağlamazdı. Gerekçe `config.toml`'ya yazıldı |
| `recognize-food*` `verify_jwt` | **Doğru** (`true`). `readJsonBody(req, 8_000_000)` 8 MB'ı açıkça geçiyor, gövde limiti `requireImageBase64` ile 8 MB'a sabit |
| **Hata sızıntısı** | **4 fonksiyonda `ValidationError` mesajı sızdırıyordu** (düzeltildi). `ai-chat` zaten sabit mesaj kullanıyordu |
| `AndroidManifest.xml` (**okundu, dokunulmadı**) | `INTERNET`, `CAMERA`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE` — hepsi meşru ve gerekli. `MainActivity` `exported="true"` yalnızca LAUNCHER filtresiyle (doğru). İki widget provider'ı `exported="true"` — **zorunlu** (launcher bulunmayan provider aksi halde görünmez). `autoVerify="false"` doğru (özel şema `io.supabase.calorix`, app link değil). `action:PROCESS_TEXT` sorgusu Flutter engine'in standardı. **Bulgu yok** |
| `rate_limits` anahtarı | `checkRateLimitKey(scope, req, userId)` **kullanıcı bazlı**; `userId` yoksa IP'ye düşüyor. `delete-account` kullanıcı bazlı çağırıyor |
| RLS `TO public` | Yok (49/49 test) |
| `foods.created_by` FK | `ON DELETE SET NULL` (20260927120000) — `auth.admin.deleteUser()` **başarısız olmaz**; gıda kalır, `created_by` NULL olur. Kullanıcının gıdası (kişisel veri) silinmiyor → **raporlandı, düzeltilmedi** (bkz. aşağıda) |

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P2** | `delete-account/helpers.ts:26` (`DATA_TABLES`) | `foods` tablosu listede **yok**, `ON DELETE SET NULL` nedeniyle silmeden sonra **kullanıcının gıda kayıtları kalır** (`created_by` NULL). Doğrulandı: `DELETE FROM auth.users` başarılı, `foods` satırı duruyor | KVKK: "tüm verilerim silinsin" talebi eksik karşılanır. `food_nutrition` de öyle | Karar gerekiyor: global gıda kataloğu **ortak** veri olabilir (aynı gıdayı başkaları da kullanıyor). Silinirse **başka kullanıcıların** kayıtları bozulur. Doğru çözüm: kullanıcıya "gıda kataloğunda X gıdam var, silinsin mi?" onayı + `DELETE FROM foods WHERE id IN (foods KULLANILMAYANlar)`. Bu bir **ürün kararı**, bu turda kapsam dışı |
| **P2** | `rate_limit.ts:32` (`dbBypassUntil`) | DB yolu 60 sn kısa devrede; bu sürede çok-instance'da zayıf sayım | Tur 2'den kalan | `console.error` logu izlenmeli |
| **P2** | `delete-account/index.ts:174` (`deleteAuthUser`) | `message.includes("not found")` **çok geniş** eşleşme: `"User not found"`, `"not found"` ve beklenmeyen bir hatanın içinde geçen herhangi bir "not found" ifadesi idempotent başarı sayılıyor. Örn. "schema not found" | Gerçek bir silme hatası başarı sayılabilir | `includes("user not found")` ile daralt |
| **P2** | `check-reminders/index.ts:29` | `RATE_LIMIT = { 300 sn, max: 2 }` **global** (`rateLimitKey("check-reminders", req, "internal")`) — kullanıcı bazlı değil, sabit `"internal"`. İki paralel cron çalıştırılırsa biri sürekli 200 + "atlandı" alır | Operasyonel, düşük | Kasıtlı (tek global cron); not düşüldü |
| **P3** | `check-reminders` `generateMotivationalMessage()` | Profil başına **tek** çağrı yapılmıyor; yalnızca `daily_log` koşulunda çağrılıyor, tüm kullanıcılara **aynı** mesaj gidiyor | Kişiselleştirme eksik | Tur 1'den kalan |
| **P3** | `ai-chat` tool iterasyonu 5 sabit | "şunları da ekle" isteği yarım kalır | UX | Tur 1'den kalan |
| **P3** | `rate_limit.ts` | `checkRateLimit` DB hatasında `dbBypassUntil` **global** değişken; bir instance'ta DB'ye ulaşılamadıysa **tüm** istekler 60 sn bellek içi yola düşer | Çok-instance'da kaba sınır | `p_bucket` ile ayrılabilir |

## CI: migration SQL sözdizimi adımı — neden uydurma adım yok

Brif "migration dosyalarının SQL sözdizimini doğrulayan ucuz bir adım" istedi.
Gerçek sözdizimi doğrulaması **Postgres gerektirir** (gramer `libpg_query`
ya da canlı `PREPARE`/`\i`); GitHub `ubuntu-latest` üzerinde `psql` **vardır**
ama bağlantılı bir Postgres **yoktur** ve `supabase start` (Docker + CLI)
kurulumu dakikalar sürer. Bu yüzden:

- **Yapılan:** dosya adı biçimi (`^\d{14}_[slug].sql$`), kronolojik sıralama,
  yinelenen zaman damgası. Bu, Supabase'ın migration'ı **kronolojik sırasla
  uygulaması** nedeniyle gerçek bir hatayı yakalar (yanlış damga = yanlış
  sıra = bozuk şema).
- **Yapılmayan:** "SQL geçerli" diyen uydurma adım. Bunun yerine aynı işin
  doğrulaması **bu ajan tarafından canlı Postgres 16'da** yapıldı
  (bkz. Doğrulama kanıtları) ve raporlandı.
- **A6'ya öneri:** `supabase/tests/rls_policies.sql` ve yeni
  `account_deletion_scope.sql` CI'a ancak `supabase start` ile bağlanabilir
  (bkz. A1r2 raporu "Bulunurlar"). Supabase CLI'ın GitHub Action'ı
  (`supabase/setup-cli`) ve `supabase start` + `supabase db reset` ile
  eklenebilir; bu turda Docker bağımlılığı nedeniyle eklenmedi.

## Yeni testler (46 → toplam 100)

- `functions/_shared/web_push_crypto_edge_test.ts` — **19 test**. `idlen` 0/65/255,
  gövde/başlık KCI uyuşmazlığı, `rs` 0 / 0xFFFFFFFF / geçersiz girdiler,
  4058-4059 bayt sınırı, 3993 bayt regresyon kanıtı, `dh` başlığı 4 varyant,
  kısa gövde, yanlış `Content-Encoding`, kesik gövde, `as_public` yenileme,
  gövde matematiği
- `functions/_shared/auth_order_test.ts` — **10 test**. Auth sırası (7
  fonksiyon), CORS/405, rate limit & gövde sırası, BOLA, `config.toml`
  kapsamı, `verify_jwt=false` yasağı, dahili token gerçekliği, hata sızıntısı
  (çok satırlı desen), `ValidationError` politikası, CORS yardımcısı,
  `getEmailTemplate` imzası
- `functions/check-reminders/check_reminders_test.ts` — 7 → **20** (+13):
  8 saat dilimi testi, 4 damga testi, 1 kaynak senkronizasyon testi
- `functions/delete-account/delete_account_test.ts` — 14 → **19** (+5):
  kısmi silme sözleşmesi, mesaj ayrımı + şema sızıntısı, `{deleted,failed}`
  tipi, rate limit, parola sızıntısı
- `supabase/tests/account_deletion_scope.sql` — **6 adım**: şema ön koşulu,
  **kapsam boşluğu taraması**, FK sırası, gerçek silme + B koruması,
  idempotensi (2. tur), temizlik

## Doğrulama kanıtları

| Komut | Sonuç |
|---|---|
| `deno check functions/` (`supabase/`'dan) | **0 hata** (18 dosya) |
| `deno test --allow-env --allow-read --allow-net functions/` | **100 passed / 0 failed / 1 ignored** (Tur 3'te 54) |
| `python3 -c "yaml.safe_load(...)" .github/workflows/supabase.yml` | **geçerli** (`jobs: ['edge']`, `permissions: {contents: read}`, `timeout: 15`, `concurrency: true`, `wd: supabase`) |
| Migration ad denetimi (CI adımının birebir komutu) | `✓ 16 migration adı geçerli ve kronolojik sıralı` |
| **16 migration sıfırdan** Postgres 16.15'e sıralı | **0 hata** (yalnızca `20260111080533`'teki `pg_cron`/`pg_net` `CREATE EXTENSION` satırları shim'lendi — bu uzantılar bare `postgres:16-alpine` imajında yok) |
| `20260928200000` **3× üst üste** | **0 hata** (`NOTICE: ... CHECK aktif; 8 referans dilimin tamami tanimli`) |
| `timezone` CHECK davranışı | `Europe/Berlin` ✔ · `Europe/Nowhere`/`''`/`'   '`/`+03:00`/`UTC+3`/`x`/`NULL` ✘ (7/7 doğru reddedildi) |
| `supabase/tests/rls_policies.sql` (migration yolu) | **49 test / 0 başarısız** |
| `supabase/tests/rls_policies.sql` (`full_setup.sql` yolu) | **49 test / 0 başarısız** |
| `full_setup.sql` sıfırdan | **0 hata**, 55 politika |
| `supabase/tests/account_deletion_scope.sql` | **6/6 GEÇTİ** (migration yolu **ve** `full_setup.sql` yolu) |

**Migration uygulama yöntemi (A1r2/A1r3 ile aynı):** `supabase` CLI bu
ortamda kurulu değil → `docker exec a1r2-pg psql` ile shim'li Postgres 16'ya
elle, sıralı uygulandı. Shim (`auth.users`/`auth.uid()`/`auth.role()`/
`auth.jwt()`, `storage.buckets`/`objects`/`foldername()` (Supabase imzasıyla
aynı: `text[]`), `cron.schedule`/`unschedule`, `anon`/`authenticated`/
`service_role` rolleri) `/tmp/opencode/shim.sql` altında.

## Doğrulayamadığım şeyler (açıkça)

1. **Edge function'lar çalışır halde uçtan uca koşmadı** — `supabase
   functions serve` yok. Şifreleme RFC 8291 Ek A vektörleriyle güçlü kanıt
   (Tur 3) + 19 kenar durum testi, ancak **gerçek bir push servisine (FCM)
   istek atılmadı**; `dh` başlığının servisle uyumu canlı smoke test ister.
2. **`delete-account` canlı test edilmedi** — `signInWithPassword`,
   `listBuckets()`, `auth.admin.deleteUser()` gerçek Supabase Auth'e karşı
   denenmedi. SQL akışı (12 tablo, idempotensi, B koruması) Postgres 16'da
   doğrulandı.
3. **`check-reminders` uçtan uca koşmadı** — zaman dilimi matematiği saf
   fonksiyon olarak test edildi (9 senaryo), ama cron + gerçek `profiles`
   satırları ile birleşik akış denenmedi.
4. **Canlı `profiles.timezone` dağılımı bilinmiyor** (proje frozen). Canlıya
   uygulamadan önce `select timezone, count(*) ...` çalıştırılmalı.
5. **CI'da ilk çalıştırıldı** — YAML sözdizimi ve adımlar lokalde birebir
   koşturuldu, ancak GitHub runner'da `denoland/setup-deno` eyleminin
   davranışı (cache, PATH) doğrulanmadı. `deno --version` adımı eklendi;
   ilk çalışmada gözlenmeli.
6. **Dependabot bu depoda yok** (`.github/dependabot.yml` mevcut değil);
   `setup-deno` sürüm güncellemesi elle yapılacak.

## AKTARIM (başka alan)

1. **A6 (CI) — `.github/workflows/supabase.yml` yeni iş:** `supabase/**`
   değişikliklerinde `deno check` + `deno test` + migration ad denetimi
   çalışır. React/Flutter işleriyle **bağımsız**; üçü paralel koşar.
   Dikkat: `deno.lock` kök dizinde ve **takip edilmiyor durumda** (`git
   status`'ta `?? deno.lock` görünüyor) → `cache: true` ilk çalışmada
   hash'leyecek ama repoya girmezse CI her seferinde yeniden indirir. A6:
   `deno.lock`'u repoya eklemek ya da `deno.lock` üretmemek kararı.
2. **A4r4 (hesap silme arayüzü) — davranış değişti:** 200 yanıtında artık
   iki mesaj olabilir:
   - tam: `{success:true, message:"Hesabınız ve tüm verileriniz kalıcı olarak silindi."}`
   - kısmi: `{success:true, message:"Hesabınızın bir bölümü silinemedi. Lütfen birkaç dakika sonra tekrar deneyin.", retryRecommended:true}`
   Arayüz `retryRecommended`'ı görürse "Tekrar Dene" sunmalı. Ayrıca
   **rate limit 2/saate düştü**: kullanıcı parolasını 3 kez yanlış girerse
   429 alır ve **bir saat** bekler — arayüzde bekleme mesajı gösterilmeli.
3. **Flutter (A2/A3) — `profiles.timezone` güncellenmeli:** hiçbir yol bu
   kolonu yazmıyor (`flutter_app/lib/**` ve `src/**` doğrulandı). Profil
   ayarlarına saat dilimi seçimi (cihaz `flutter_timezone`'u varsayılan)
   eklenirse `check-reminders` **doğru** saatte çalışır. Eklenmezse
   davranış TR'de **değişmez** (NULL → migration `Europe/Istanbul`).
   Migration `profiles_timezone_is_valid_iana` CHECK'i nedeniyle yazılacak
   değer **geçerli IANA adı olmak zorunda** (örn. `Europe/Istanbul`,
   `Europe/Berlin`; `GMT+3` reddedilir).
4. **Ana ajan → `plans/` senkronluğu:** A1r3'ün "5. `profiles.timezone`
   hâlâ okunmuyor" maddesi **kapandı**; "1. CI'da deno kapısı yok" maddesi
   **kapandı**; `OZET-tur3.md` 7. maddedeki "`flutter.yml` push branch'leri"
   sorunu A1r4'ün alanı değil.
5. **`OPS-tur1-security.md` güncellenmeli** (A1 alanı, bu raporla aynı iş):
   yeni migration `20260928200000` deploy adımları, `check-reminders`
   saat dilimi davranış değişikliği, `delete-account` rate limit 2/saat ve
   kısmi silme mesajı, push `MAX_PLAINTEXT_BYTES` etkisi.

## Sonraki öneriler (tur 5)

1. `deleteAuthUser`'daki `includes("not found")` eşleşmesini
   `includes("user not found")` ile daralt.
2. `foods`/`food_nutrition` KVKK kapsamı: ürün kararı gerekli (bkz.
   Bulunurlar).
3. `deno.lock`u repoya ekle (A6) → CI cache gerçekten işe yarar.
4. `profiles.timezone` yazan istemci yolu + profil ayarı ekranı
   (A3/A4 alanı).
5. `check-reminders` için Supabase dashboard cron'u: `*/5 * * * *` +
   `INTERNAL_FUNCTION_TOKEN` başlığı (A1r3'ten kalan, teyit edilmeli).
6. `supabase/tests/*.sql` dosyalarını CI'a `supabase start` ile bağlamak
   (A6 + Docker bağımlılığı).
7. `generateMotivationalMessage()`'ı profil başına çağırmak (kişiselleştirme).

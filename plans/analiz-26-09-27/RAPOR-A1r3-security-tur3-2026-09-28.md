# RAPOR — A1r3-security — 2026-09-28 — Tur 3

> Kapsam: `supabase/**` (migration + edge function'lar + `full_setup.sql` + `config.toml`),
> `plans/analiz-26-09-27/OPS-tur1-security.md`.
> Doğrulama ortamı: **Postgres 16.15 (Docker, `a1r2-pg`)**, `deno 2.9.7`.
> `supabase` CLI bu ortamda kurulu değil → `supabase db reset` yerine migration'lar
> shim'li Postgres 16'ya elle, sıralı uygulandı (A1r2 ile aynı yöntem).
> `flutter_app/**`, `src/**`, `tool/**`, `.github/**` dosyalarına **dokunulmadı**.

## Özet (5 madde)

1. **Görev brifindeki push şifreleme reçetesi teknik olarak YANLIŞTI ve bu
   kanıtlandı; brifi uygulayan bir ajan tarayıcının açamayacağı (sessizce
   kaybolan) push üretirdi.** Brif "ECDH ile ECDH-ES türet → `cek_info`/`nonce_info`
   ile iki HKDF adımı" diyordu ve "`authSecret` = abonelik `auth` alanı —
   **`p256dh` gerekmez**; Web Push (RFC 8291) yalnızca `auth` (shared secret)
   kullanır. (Doğrula!)" diye **israr** ediyordu. RFC 8291 §3.3/§3.4 ve Ek A
   tam tersini söylüyor: **üç** HKDF adımı vardır, `p256dh` **gereklidir**
   (ECDH peer key'i + `key_info` içinde bağlama girdisi), `auth` yalnızca
   HKDF'in *salt* girdisidir. Doğru akış uygulandı ve **RFC'nin kendi
   yayımlanmış ara değerleriyle** (`ecdh_secret`, `PRK_key`, `IKM`, `PRK`,
   `CEK`, `NONCE`, `key_info`) **bayt bayt** doğrulandı. 14/14 test geçti.
2. **Push gövdesi artık gerçekten şifreleniyor** (RFC 8188 + 8291 `aes128gcm`).
   `send-notification` `Content-Encoding: aes128gcm`, `application/octet-stream`,
   `Crypto-Key: dh=`, `TTL`, `Urgency` gönderiyor; **VAPID imzası bozulmadan
   birlikte** çalışıyor (RFC 8291 §3.3: şifreli istekte VAPID zorunludur).
   Bozuk/eksik `auth` **veya** `p256dh` fırlatır → push atlanır, e-posta + DB
   kaydı akışı sürer. `p256dh`/`auth` kolonları şema için **yeterli** (değişiklik yok).
3. **Hesap silme (KVKK / Google Play zorunluluğu) eklendi**:
   `supabase/functions/delete-account/`. Kullanıcı **kendi JWT'si + mevcut
   parolasıyla** siler (parola onayı hesabın başkası tarafından silinmesini
   engeller). 12 tablo + Storage + `auth.admin.deleteUser()`, **sıralı ve
   idempotent**; RLS'e güvenilmez (service_role kullanılır). 14/14 test geçti ve
   akış **gerçek Postgres 16'da uçtan uca doğrulandı** (14 tablo 0'a, başka
   kullanıcının verisi sağlam).
4. **Serbest taramada 2 yeni P1 bulundu ve düzeltildi:** (a) `check-reminders`
   **haftalık özeti her koşuda tekrar gönderiyordu** (`last_weekly_summary`
   sütunu hiç yoktu → kullanıcıya günde ~12 kez özet; `sentThisRun` yalnızca
   koşu içini koruyordu). (b) `push_subscriptions` kullanıcı başına **sınırsız**
   (A1b'nin P2'si; artık trigger ile 7 cihaz sınırı). Ayrıca `readJsonBody`'nin
   1 MB'lık varsayılan sınırı **256 KB**'a çekildi (görsel taşıyan
   `recognize-food` 8 MB sınırını artık **açıkça** geçiyor).
5. **Doğrulama:** `deno check` 17 dosyada temiz · `deno test` **54 passed / 0 failed**
   (Tur 2'de 19'dı) · 15 migration **sıfırdan** Postgres 16'ya 0 hata ·
  yeni migration **3× üst üste** idempotent · `rls_policies.sql` her iki kurulum
  yolunda **98/98** (regresyon yok) · hesap silme akışı canlı SQL ile doğrulandı.

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `functions/_shared/web_push_crypto.ts` (yeni, ~600 satır) | RFC 8188 + RFC 8291 `aes128gcm`: rastgele 16 bayt `salt`, `rs=4096`, `idlen=0`, ECDH P-256, HKDF-SHA256 (Extract/Expand elle), AES-128-GCM, padding delimiter `0x02`, `Crypto-Key: dh=` | **RFC 8291 Ek A vektörleri bayt bayt** + 14/14 test |
| **P1** | `functions/_shared/web_push_crypto_test.ts` (yeni) | 14 test: RFC vektörleri, gidiş-dönüş, yapı, başlık, rastgelelik, bozuk `auth`/`p256dh`, boyut, TR/emoji, padding | `deno test` → **14/14** |
| **P1** | `functions/send-notification/index.ts` | Push isteği şifreli gövde + şifreleme başlıkları; VAPID `Authorization` korundu; `PushEncryptionError` yakalanıp **akış kırılmadan** push atlanır | `deno check` temiz |
| **P1** | `functions/delete-account/{index.ts,helpers.ts}` (yeni) | Hesap silme: JWT (kendi) + **parola onayı**, rate limit, Storage, 12 tablo (sıralı), `auth.admin.deleteUser()`, sabit mesaj, `INTERNAL_FUNCTION_TOKEN` **kullanılmıyor** | 14/14 test + gerçek PG akışı |
| **P1** | `migrations/20260928120000_push_idempotency_and_limits.sql` (yeni) | `profiles.last_weekly_summary` (idempotency) + `limit_push_subscriptions_per_user()` trigger (kullanıcı başına 7, semasız hata mesajı) | 3× idempotent + fonksiyonel test |
| **P1** | `functions/check-reminders/{index.ts,helpers.ts}` | Haftalık özet artık **aynı ISO haftasında 1 kez**; `last_weekly_summary` okunup yazılıyor; `isSameIsoWeek()` saf yardımcıya taşındı | 7/7 test |
| **P1** | `functions/_shared/auth.ts` | `readJsonBody` varsayılan sınırı 1 MB → **256 KB** (`DEFAULT_MAX_BODY_BYTES`); `Content-Type: application/json` zorunluluğu (415) | `deno check` temiz |
| **P1** | `functions/recognize-food/index.ts` | Görsel taşıdığı için 8 MB sınır **açıkça** verildi (varsayılan küçülünce kırılmasın) | `deno check` temiz |
| **P2** | `config.toml` | `[functions.delete-account] verify_jwt = true` kaydı | — |
| **P2** | `full_setup.sql` | `last_weekly_summary` kolonu + push adet sınırı trigger'ı eklendi (**senkronluk bozulmasın diye**) | Sıfırdan kurulum 0 hata, 98/98 test |
| **P2** | `OPS-tur1-security.md` | Tur 3 bölümü: yeni migration listesi, `delete-account` deploy adımları, davranış değişikliği tablosu, push şifreleme durumu | — |

### RFC 8291: brifin reçetesi neden yanlıştı (kanıt)

Brif: *"ECDH P-256 (`p256dh` ↔ `auth`) ile ECDH-ES (HKDF) türet… `authSecret` =
abonelik `auth` alanı (16 bayt) — **`p256dh` gerekmez**"*.

RFC 8291 §3.3/§3.4 (ve Ek A çalışma örneği) bunun tersini söylüyor:

```
ecdh_secret = ECDH(as_private, ua_public)                §3.1  -> p256dh ŞART
PRK_key     = HKDF-Extract(salt=auth_secret, IKM=ecdh)    §3.3  -> auth = SALT
key_info    = "WebPush: info" || 0x00 || ua_public || as_public
IKM         = HKDF-Expand(PRK_key, key_info, L=32)        §3.3
PRK         = HKDF-Extract(salt=salt, IKM=IKM)           RFC8188
CEK         = HKDF-Expand(PRK, cek_info,  L=16)
NONCE       = HKDF-Expand(PRK, nonce_info, L=12)
```

Test, modülün ürettiği ara değerleri RFC'nin **kendi yayımladığı** değerlerle
karşılaştırıyor (hepsi eşleşiyor):

```
RFC 8291 Ek A: ECDH ortak gizli tam olarak RFC değerini üretir ... ok
RFC 8291 §3.3: key_info = 'WebPush: info' || 0x00 || ua || as (RFC metniyle birebir) ... ok
RFC 8291 Ek A: IKM/PRK/CEK/NONCE zinciri bayt bayt RFC ile aynı ... ok
RFC 8291 §5: örnek mesaj şifrelenir ve çözülür (gidiş-dönüş) ... ok
```

> `key_info` içindeki `ua_public` **kendi public key'ini bilmeyi gerektirir**;
> sunucuda elimizde `p256dh` var, `as_public` ise mesaj başına üretilir. Brifin
> "`p256dh` gerekmez" iddiası, `key_info` bağlama adımının (KCI koruması)
> tamamen atlanması demek — hem şifre yanlış hem de kurcalamaya açık olurdu.

### `dh` başlığı / `idlen=0` kararı

Yayımlanmış RFC 8291 §4, AS public key'in `keyid` alanında taşınmasını ister.
Ancak **Web Push bu taslağın önceki sürümlerini uygular**: tüm push servisleri
(FCM, Mozilla autopush, WNS) ve tarayıcı istemcileri `Crypto-Key: dh=` +
`idlen=0` bekler (bkz. `web-push`, `web-push-crypto` referans uygulamaları).
Modül bu (yayın öncesi) biçimi üretir; **HKDF zinciri ise Ek A vektörleriyle
birebir doğrulanmıştır**. Modül başlığında bu sapma açıkça belgelendi.

## Yeni testler

- `functions/_shared/web_push_crypto_test.ts` — **14 test**. RFC 8291 Ek A
  vektörleri (ECDH, public key türetme, `key_info`, `IKM`/`PRK`/`CEK`/`NONCE`,
  §5 örneğinin şifre+çöz gidiş-dönüşü), tarayıcı abonelik taklidi ile uçtan uca
  gidiş-dönüş, çıktı yapısı (`salt` 16 / `rs` 4 / `idlen` 1), `aes128gcm` üst
  başlığı zorunluluğu, **aynı secret ile farklı ciphertext** (rastgele salt),
  bozuk/eksik `auth` **ve** `p256dh`, 4096 bayt sınırı, TR/emoji, bozuk ciphertext.
- `functions/delete-account/delete_account_test.ts` — **14 test**. Tablo listesi
  kapsamı (12) ve tekrarsızlığı, `profiles.id` filtre istisnası, **global
  tabloların (`foods`, `rate_limits`, `user_roles`) listede olmaması** (veri
  sızıntısı koruması), FK sırası (`chat_messages → chat_threads → profiles`),
  bozuk sıralamanın reddi, parola hatası → 401 sabit mesaj, **bilinmeyen hatada
  şema detayı sızmaması**, `index.ts`/`helpers.ts` senkronluğu.
- `functions/check-reminders/check_reminders_test.ts` — **7 test**. ISO hafta
  karşılaştırması, yıl sınırı (2020-W53 ≠ 2021-W01), geçersiz tarih,
  **kritik senaryo: aynı hafta 12 koşuda 1 gönderim**.

## Doğrulama kanıtları

| Komut | Sonuç |
|---|---|
| `deno check` (7 edge function + 10 shared/test) | **17/17 temiz** |
| `deno test --allow-env --allow-read --allow-net supabase/functions/` | **54 passed / 0 failed / 1 ignored** |
| 15 migration **sıfırdan** Postgres 16'ya, sıralı | **0 hata** |
| `20260928120000` **3× üst üste** | **0 hata** (idempotent) |
| `supabase/tests/rls_policies.sql` (migration yolu) | **98/98 geçti** |
| `supabase/tests/rls_policies.sql` (`full_setup.sql` yolu, sıfırdan) | **98/98 geçti** |
| Push adet sınırı (7 geçer / 8. reddedilir / upsert geçer) | **doğrulandı** |
| Hesap silme akışı gerçek PG'de | **14 tablo → 0, `user_roles` cascade, idempotent, kullanıcı B sağlam** |

Hesap silme akışının kanıtı:

```
 SONUC A (hepsi 0 olmali): | me | we | wt | nt | np | us | ff | rf | ps | cm | ct | pf | ur | au
                         |  0 |  0 |  0 |  0 |  0 |  0 |  0 |  0 |  0 |  0 |  0 |  0 |  0 |  0
 KORUMA (B verisi durmali): | me=1  ct=1  pf=1
```

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P2** | `send-notification/index.ts` `getEmailTemplate(type, title, ...)` | `title` parametresi kullanılmıyor (Tur 1'den kalan lint) | Ölü parametre | Silinebilir; davranış etkisi yok |
| **P2** | `_shared/rate_limit.ts` `dbBypassUntil` | DB yolu 60 sn kısa devrede; bu sürede çok-instance zayıf sayım | Tur 2'den kalan | Migration uygulandı, log izlenmeli |
| **P2** | `check-reminders` `update_updated_at_column` | `profiles.update(...)` hata sonucu **yok sayılıyor** (`.update()` çağrısının hatası kontrol edilmiyor) | Damga yazılamazsa haftalık özet tekrar gönderilebilir (kendi kendini iyileşmez) | Sonraki tur: `if (error) console.error(...)` |
| **P3** | `check-reminders` `UTC+3` sabit | `profiles.timezone` hâlâ okunmuyor | Yanlış saatte hatırlatma | Tur 1'den kalan; A1r2 de bildirmiş |
| **P3** | `check-reminders` `generateMotivationalMessage()` | Profil başına **tek** çağrı yapılmıyor; yalnızca `daily_log` koşulunda çağrılıyor, tüm kullanıcılara aynı mesaj gidiyor | Kişiselleştirme eksik | Tur 4 |
| **P3** | `ai-chat` tool iterasyonu 5 sabit | "şunları da ekle" isteği yarım kalır | UX | Tur 4 |

## AKTARIM (başka alan) — Flutter tarafı

**`flutter_app/**` dosyalarına dokunulmadı** (alan sahipliği). Aktarılacaklar:

1. **Hesap silme UI'ı — mağaza zorunluluğu (P0, Play Console).**
   `delete-account` edge function'ı hazır, ancak kullanıcıya bir **"Hesabımı
   Sil"** girişi ve parola doğrulama ekranı gerekiyor. Akış:
   `POST {SUPABASE_URL}/functions/v1/delete-account`, gövde `{"password": "..."}`,
   `Authorization: Bearer <kullanıcı access token>` (anon değil).
   200 → `{success:true, message:...}` · 401 → `"Parola hatalı"` · 429 → bekle.
   Önerilen yer: Profil/Ayarlar > Hesap bölümü, **zorunlu onay diyaloğu** ile.
   i18n: 13 dil dosyasına `deleteAccount*` anahtarları gerekir.
2. **Aynı anda `signOut()` çağrısı:** Silme başarılı olduktan sonra oturum
   zaten geçersizdir (`auth.admin.deleteUser()`); istemci yine de
   `supabase.auth.signOut()` + yerel önbelleği temizlemelidir.
3. **Push (PWA) tarafında değişiklik gerekmiyor.** `applicationServerKey`
   = `VAPID_PUBLIC_KEY` ve abonelik kaydı (`p256dh`/`auth`) aynı kalır; standart
   Web Push istemcisi şifreli gövdeyi otomatik açar. (A1b'nin aktarımı geçerli.)
4. **Yeni push adet sınırı (7):** `push_subscriptions` INSERT'i artık 8. cihazda
   hata verir. Flutter tarafında abonelik kaydı hatası **sessizce yutulmamalı**
   (`useNotifications`/`core/notifications` — A3 alanı); kullanıcıya
   "cihaz sınırı aşıldı" gösterilmeli. Zaten push kırılmaya devam eder
   (e-posta akışı etkilenmez), bu yüzden P1 değil.
5. **Gövde boyutu (256 KB) değişikliği:** `readJsonBody` artık
   `Content-Type: application/json` **zorunlu** kılıyor ve varsayılan 256 KB.
   Flutter istemcisi `supabase.functions.invoke()` kullanıyorsa başlık otomatik
   gelir; **elle `fetch` eden** herhangi bir yol varsa `Content-Type` eklenmeli
   (aksi halde 415). `recognize-food` görsel yükleme yolu 8 MB sınırını koruyor.
6. **`profiles.last_weekly_summary`:** Flutter'ın profil tipleri/select'leri bu
   kolonu içermek zorunda değil; yalnızca `check-reminders` kullanıyor.

## Yeni güvenlik bulguları (Görev 3 taraması)

| Alan | Sonuç |
|---|---|
| Kalan `TO public` politikalar | **Yok** — `rls_policies.sql` "hicbir politika TO public degil" diye doğruluyor (98/98) |
| `SECURITY DEFINER` + `search_path` kaçağı | **Yok** — 5 fonksiyonun tamamında `search_path = ''`; test doğruluyor |
| Gövde boyut limiti | **Vardı ama çok yüksekti** → 1 MB → 256 KB (P1, düzeltildi) |
| `service_role` sızma yolu | **Bulunamadı** — istemci tarafında `env.dart` `isSecretKey()` ile guard'lı, `SUPABASE_SERVICE_ROLE_KEY` build'de tanımlanırsa uygulamayı yapılandırılmamış sayıyor; `src/vite-env.d.ts`'te `VITE_` uyarısı var |
| Hata mesajı şema sızıntısı | Edge: **temiz** (tüm `errorResponse` çağrıları sabit mesaj). **Yeni**: push adet sınırı trigger'ının hatası tablo adı sızdırıyordu → semasız mesaja çevrildi |
| SQL injection (string interpolasyon) | **Yok** — tüm `EXECUTE format(...)` çağrılarında tanımlayıcılar `%I` ile quote ediliyor; sabit dizi listeleri. Edge'de `.or()/.filter()/raw SQL` **hiç yok** — tüm sorgular PostgREST builder |
| Çift gönderim (idempotency) | **P1 bulundu ve düzeltildi**: haftalık özet damgası yoktu (günde ~12 kez) |
| `INTERNAL_FUNCTION_TOKEN` deseni | `check-reminders`/`send-notification`'da doğru; **`delete-account` bunu bilinçli KULLANMAZ** (cron değil) ve `config.toml`'da `verify_jwt = true` |

## Doğrulayamadığım şeyler (açıkça)

1. **`supabase db reset` çalıştırılamadı** — CLI kurulu değil; A1r2'nin shim'li
   Postgres 16'sı kullanıldı. Gerçek Supabase'te `supabase db reset` ile tekrar
   doğrulanmalı (özellikle `auth.uid()`, JWT doğrulama, `default privileges`).
2. **Edge function'lar çalışır halde uçtan uca test edilmedi** — `supabase
   functions serve` yok. Şifreleme doğrulaması RFC vektörleriyle güçlü kanıt,
   ancak **gerçek bir push servisine (FCM) istek atılmadı**; `dh` başlığının
   servisle uyumu canlı smoke test gerektirir (OPS'ta yazılı).
3. **Hesap silme canlı test edilmedi** — parola doğrulama yolu
   (`signInWithPassword`), `listBuckets()` ve `auth.admin.deleteUser()` gerçek
   Supabase Auth'e karşı denenmedi. SQL akışı ve mantık doğrulandı.
4. **13 dil `i18n` çevirisi yapılmadı** — `flutter_app` alan dışı (aktarım).
5. **`profiles.timezone`** hâlâ kullanılmıyor (`UTC+3` sabit) — dokunulmadı.

## Sonraki öneriler (tur 4)

1. `flutter_app` tarafına hesap silme ekranı + i18n (mağaza şartı).
2. `check-reminders` `profiles.update()` hata kontrolü (`P2` yukarıda).
3. `cleanup_rate_limits()` için Dashboard cron tanımı.
4. `profiles.timezone`'ı gerçekten kullan (`UTC+3` sabitini kaldır).
5. `full_setup.sql` ile migration seti arasındaki senkronluğu CI'da denetleyen
   bir kontrol (A6 alanı).

# RAPOR — A1b-security (push bildirimleri) — 2026-09-27 — Tur 1 devam

> Kapsam: `supabase/functions/**` (push gönderim ayağı), `plans/analiz-26-09-27/OPS-tur1-security.md`
> Doğrulama: `deno check` (2.9.7, 6 edge function + 5 _shared modülü), `deno lint`,
> `deno test --allow-env supabase/functions/_shared/vapid_test.ts` → **14/14 geçti**,
> ayrıca geçici bir uçtan uca betikle mock push sunucusuna imzalı istek atıp
> `crypto.subtle.verify()` ile doğrulandı (betik sonrası silindi, repoya girmedi).

## Özet (5 madde)

1. **P1 kapatıldı: VAPID JWT artık gerçekten üretiliyor.** `Authorization: vapid
   t=<public key>` (imzasız) yerine RFC 8292 uyumlu `Authorization: vapid t=<imzalı
   ES256 JWT>, k=<applicationServerKey>` gönderiliyor. Web push bildirimleri artık
   tarayıcı tarafından reddedilmiyor.
2. **`npm:web-push` yerine bağımlılıksız WebCrypto uygulaması** yazıldı
   (`_shared/vapid.ts`). Gerekçe: `web-push` Node'a `Buffer`/stream'e bağımlıdır ve
   Deno/Edge Runtime'da ek polyfill + cold-start maliyeti getirir; VAPID imzası
   zaten tek bir ECDSA P-256 (ES256) JWT imzasıdır.
3. **`VAPID_PRIVATE_KEY` üç biçimi de destekliyor** ve sessizce geçmiyor: base64url ham
   32 bayt, PKCS#8 `PRIVATE KEY` PEM, SEC1 `EC PRIVATE KEY` PEM (+ base64url kodlanmış
   PKCS#8/SEC1 DER). Yanlış/bozuk anahtarlar `VapidError` ile reddediliyor; içe
   aktarılan anahtarın skaleri beklenen baytlarla karşılaştırılarak doğrulanıyor.
4. **Secret eksikse akış bozulmuyor**: düz bir `console.error` + push kolunun atlanması;
   e-posta gönderimi ve `notifications` tablosu kaydı normal devam ediyor (A1'in P3
   izlenebilirlik maddesi de bu yolla kısmen kapandı — sebep logda görünüyor).
5. **Payload doğrulaması + ölü abonelik temizliği** eklendi: şema/boyut kontrolü
   (4096 bayt), `201` dışı yanıtların token'ları maskelenerek loglanması, 404/410
   dönen aboneliklerin `push_subscriptions`'tan silinmesi.

## VAPID format kararları

| Konu | Karar | Gerekçe |
|---|---|---|
| JWT başlığı | `{ typ: "JWT", alg: "ES256" }` | RFC 8292 §2.1 `typ` zorunlu |
| JWT gövdesi | `{ aud, exp, sub }` — **yalnızca 3 alan** | `aud` = push endpoint'inin `origin`'i (yol/sorgu atılır); `exp` = now + 12h (RFC 8292: 24 saatten kısa olmalı) |
| `sub` | `mailto:` veya `https://` ile zorunlu | RFC 8292 §2.1; `isValidVapidSubject()` ile doğrulanır, aksi halde `VapidError` |
| İmza algoritması | WebCrypto `ECDSA` + `SHA-256`, P-256 | JWS ES256 |
| İmza kodlaması | **Ham R‖S (64 bayt)** | Deno zaten P1363 (ham) üretiyor; `normalizeEcdsaSignature()` ayrıca DER girdiyi de (bazı runtime'lar DER döndürebilir) doğru ayrıştırıp 32+32'ye hizalıyor. Testte her iki yol da doğrulanıyor |
| `k` (public key) | `VAPID_PUBLIC_KEY` varsa onu kullan, yoksa private key'den **türet** | İstemcide kayıtlı `applicationServerKey` ile eşleşmeli; ikisi farklı çiftse servis 403 döner |
| PKCS#8 sarmalama | Uzunluk baytları **hesaplanarak** üretiliyor (sabit `0x41`/`0x27` yazmak kolanlıkla yanlış DER üretiyor — bu hatayı geliştirme sırasında yaptım, testler yakaladı) | Sabit baytlarda hata sessiz kalıyor |
| `ECPrivateKey` gövdesi | **Minimal** (`version` + `privateKey`); `[0] parameters` / `[1] publicKey` atılır | openssl'in tam SEC1 çıktısı Deno'nun PKCS#8 çözücüsünde `expected valid PKCS#8 data` hatası veriyor (deneyimle doğrulandı) |
| Anahtar içe aktarma | `extractable = true` | WebCrypto'da EC public key'i yalnızca JWK dışa aktarımıyla elde edilebiliyor |
| `Content-Type` | `application/octet-stream` (önceden `application/json` idi) | RFC 8030 §5: gövde şifreli/şemasız bayt dizisi |
| Token ömrü | 12 saat | Uzun ömürlü token'lar anahtar rotasyonu sonrası geçersizleşir |

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `supabase/functions/_shared/vapid.ts` (yeni, 460 satır) | VAPID JWT üretimi, anahtar içe/dışa aktarma (base64url/PKCS#8/SEC1), DER↔PEM, imza normalizasyonu, `sub` doğrulama, payload şema/boyut doğrulama | `deno test` 14/14, `deno check` temiz |
| **P1** | `supabase/functions/send-notification/index.ts:118-225` | `Authorization: vapid t=<JWT>, k=<public key>`; `aud` endpoint origin'i; anahtar önbelleği; secret eksikliğinde düz log + push atlanır | `deno check` temiz |
| **P1** | `supabase/functions/send-notification/index.ts` (push döngüsü) | `201` dışı yanıt → 300 karakter, 40+ karakterlik token'lar `<redacted>` ile loglanır; **istemciye yalnızca durum kodu/sabit mesaj** döner | `deno check` temiz |
| **P2** | `supabase/functions/send-notification/index.ts` (push döngüsü) | 404/410 dönen abonelikler toplanıp `push_subscriptions`'tan siliniyor (ölü abonelik birikimi önlenir) | `deno check` temiz |
| **P2** | `supabase/functions/_shared/vapid.ts` `preparePushPayload` | `title`/`body` tip+uzunluk, `data` yalnızca düz JSON (derin/NaN/fonksiyon düşürülür), 4096 bayt sınırı (önce `data`, sonra `body` kesilir) | Test "push payload şeması ve boyut sınırı" |
| **P2** | `supabase/.env.example` | `VAPID_SUBJECT` eklendi, üç anahtarın da formatı ve zorunluluğu açıklandı | — |
| **P2** | `plans/analiz-26-09-27/OPS-tur1-security.md` | VAPID maddesi "çözüldü" olarak güncellendi + üretim komutları eklendi | — |

## Yeni testler

`supabase/functions/_shared/vapid_test.ts` — 14 test, tamamı assertion'lı:

1. base64url gidiş-dönüş (dolgu/boşluk toleransı, karakter kümesi)
2. PKCS#8 sarmalayıcı DER yapısı (her bayt konumu doğrulanıyor)
3. base64url 32 bayt anahtar içe aktarma + public key türetme (65 bayt, `0x04` işareti, deterministiklik)
4. PKCS#8 PEM içe aktarma (base64url ile **aynı** public key)
5. SEC1 PEM içe aktarma (minimal + openssl tam biçimi)
6. SEC1 `[1] publicKey` alanındaki **yanlış** public key'in skalerin önüne geçmemesi
7. Bozuk girdiler: boş, public key konmuş, `PUBLIC KEY` PEM, yarım PEM, yanlış uzunluk
8. `sub` doğrulaması (`mailto:`/https kabul, `http://` ve önek'siz red)
9. İmza normalizasyonu: ham geçerli, DER→ham dönüşümü (0x00 dolgu + 31 bayt `s` hizalaması)
10. **JWT başlık/gövde/imza**: `typ`/`alg`/`aud`(origin'e indirgenmiş)/`exp`/`sub` + **imzanın `crypto.subtle.verify` ile doğrulanması**
11. Kurcalanmış gövde ve yanlış public key ile doğrulama **reddediliyor** (aynı testte)
12. Üretim yolu: `exp` = now + 12 saat, gelecekte
13. Geçersiz `sub`/audience reddi
14. `Authorization` başlığı regex ile RFC 8292 biçiminde, `k` = 65 bayt
15. Payload şeması ve boyut sınırı

```
$ deno test --allow-env supabase/functions/_shared/vapid_test.ts
running 14 tests from ./supabase/functions/_shared/vapid_test.ts
base64url gidiş-dönüş (dolgu/boşluk toleranslı) ... ok
PKCS#8 sarmalayıcı doğru yapı üretir ... ok
base64url 32 bayt özel anahtar içe aktarılır ve public key türetilir ... ok
PKCS#8 PEM özel anahtar içe aktarılır ... ok
SEC1 (EC PRIVATE KEY) PEM içe aktarılır ... ok
SEC1: [1] alanındaki yanlış public key skalerin önüne geçmez ... ok
bozuk/hatalı anahtar girdileri sessizce geçmez ... ok
VAPID subject doğrulaması (RFC 8292) ... ok
ECDSA imzası ham R||S (64 bayt) olarak normalize edilir ... ok
VAPID JWT: typ/alg/aud/exp/sub ve imza doğrulanır ... ok
VAPID JWT: üretimde exp gelecekte olur (now + 12 saat) ... ok
VAPID JWT: geçersiz subject / audience reddedilir ... ok
Authorization başlığı RFC 8292 biçiminde ... ok
push payload şeması ve boyut sınırı ... ok
ok | 14 passed | 0 failed
```

Ek olarak (repoya girmeyen geçici betikle) mock bir push sunucusuna istek atılıp
gelen `Authorization` başlığı çözüldü ve imza doğrulandı:

```
header : {"typ":"JWT","alg":"ES256"}
payload: {"aud":"https://localhost:34137","exp":1790581298,"sub":"mailto:ops@calorix.app"}
imza uzunluğu: 64 (ES256 ham R||S = 64 beklenir)
İMZA DOĞRULANDI: true
k == applicationServerKey: true
```

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P1** | `send-notification/index.ts` (payload) | Gövde **şifrelenmiyor** (RFC 8291 `aes128gcm` yok). `push_subscriptions.p256dh`/`auth` okunuyor ama kullanılmıyor → push içeriği ağ üzerinde düz metin gider. | Gönderilen metin (ör. "kilo kaydı") ağda görülebilir | AES128GCM şifreleme + `web-push-crypto` gerekir; işlevsel ve kapsamlı bir değişiklik → Tur 2. Not: `vapid.ts` başlığına bu kapsam dışı sınır notu düşüldü |
| **P2** | `send-notification/index.ts:395-430` | Abonelikler kullanıcı başına sınırsız sayıda; `UNIQUE(user_id, endpoint)` koruması var ama adet limiti yok | Kötüye kullanımda çok istek | Tur 2'de kullanıcı başına özel abonelik limiti |
| **P2** | `_shared/vapid.ts` anahtar önbelleği | Süreç ömrü boyunca cache'leniyor; secret döndürülürse açık süre boyunca eski anahtar kullanılır | Düşük (Supabase secret rotasyonu instance yeniden başlatır) | Rotasyon sonrası redeploy önerilir |
| **P2** | `_shared/rate_limit.ts` | Bellek içi sayaç (A1 Tur 1'den devralındı) | Çok instance'da bypass | Tur 2'de kalıcı sayaç tablosu |
| **P3** | `deno lint` | 4 lint uyarısı: inline `https://` import'lar (3 dosya) + `getEmailTemplate`'te kullanılmayan `title` parametresi | Stil | Yeni yazdığım `_shared/vapid.ts` ve `vapid_test.ts` **temiz**; diğerleri tur öncesinden mevcut, dokunulmadı |

## AKTARIM (başka alana)

- **A3-flutter-core** → PWA tarafı: `applicationServerKey` olarak `VAPID_PUBLIC_KEY`
  kullanılmalı (base64url, 0x04 ile başlayan 65 bayt). İstemci şu an push subscription
  kaydederken hangi anahtarı kullandığını doğrulaması gerekir; farklıysa sunucu 403 döner.
- **Ana ajan / operasyon** → Aşağıdaki dashboard adımları zorunlu.

## Doğrulama için gerekli dashboard adımları

1. **Supabase Dashboard → Edge Functions → Secrets** (üçü de zorunlu):
   - `VAPID_SUBJECT` = `mailto:ops@calorix.app` (ya da `https://calorix.app`).
     **`mailto:` öneki olmadan yazılırsa push sessizce gitmez** (kural gereği reddedilir).
   - `VAPID_PRIVATE_KEY` = base64url ham 32 bayt. Üretim:
     ```bash
     openssl ecparam -name prime256v1 -genkey -noout -out vapid.pem
     # VAPID_PUBLIC_KEY (base64url, 65 bayt, 0x04 ile başlar):
     openssl ec -in vapid.pem -pubout -outform DER 2>/dev/null | tail -c 65 \
       | openssl base64 -A | tr '+/' '-_' | tr -d '='
     ```
     `web-push`'ın beklediği `VAPID_PRIVATE_KEY` ham skaler olmalı; PEM de kabul edilir.
   - `VAPID_PUBLIC_KEY` = yukarıdaki komutun çıktısı. **Boş bırakılırsa** fonksiyon
     private key'den türetir (iki değer **aynı çift** olmalı).
2. **PWA istemcisi** `applicationServerKey` değeri `VAPID_PUBLIC_KEY` ile birebir aynı
   olmalı; aksi halde tarayıcı abonelik kaydını reddeder.
3. **Push gövdesi şifrelenmediği** için (yukarıdaki P1) hassas veri gönderilmemeli.
4. Deploy sonrası smoke test: bir kullanıcıya `water` bildirimi tetikleyip
   `send-notification` logunda `Push reddedildi: status=...` satırı **olmadığını**
   doğrulayın. 403/401 görürseniz `k`/`sub`/anahtar eşleşmesi hatalıdır.
5. `VAPID_SUBJECT`/`VAPID_PRIVATE_KEY` eksikse logda
   `VAPID yapılandırması eksik ... — push atlandı, e-posta akışı sürüyor` görürsünüz;
   bu bir hata değil, e-posta kolunun çalıştığının işaretidir.

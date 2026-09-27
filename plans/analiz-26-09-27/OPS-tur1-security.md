# Operasyon Notları — Tur 1 (A1-security aktarımı)

Commit: `6653687` — `fix(security): edge function auth/CORS/validation + RLS sertleştirme`

## Dashboard'da / deploy'da yapılması ZORUNLU olanlar

1. **`INTERNAL_FUNCTION_TOKEN` secret'ı tanımla** (Supabase Dashboard → Edge Functions → Secrets).
   Değer `openssl rand -hex 32` ile üret. `check-reminders` ve `send-notification`
   artık yalnızca bu token'ı taşıyan cron çağrısını kabul ediyor.
2. **VAPID secret'ları**: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`
   (mevcut `VAPID_PUBLIC_KEY` tek başına yeterli değil — imza üretilmiyor).
   - `VAPID_SUBJECT` **zorunlu**, format: `mailto:ops@calorix.app` ya da `https://calorix.app`.
   - `VAPID_PRIVATE_KEY` üç biçimde kabul edilir: **base64url ham 32 bayt** (önerilen),
     `-----BEGIN PRIVATE KEY-----` (PKCS#8 PEM) veya `-----BEGIN EC PRIVATE KEY-----` (SEC1 PEM).
     PKCS#8 DER'in base64url'u da çalışır. `VAPID_PUBLIC_KEY` verilmezse private
     key'den türetilir (ikisi **aynı çift** olmalı, aksi halde push servisi 401/403 döner).
   - Üretim (üretici/bağımlılıksız, `web-push` npm paketi gerekmez):
     ```bash
     openssl ecparam -name prime256v1 -genkey -noout -out vapid.pem
     # VAPID_PRIVATE_KEY = base64url(skaler)  -> aşağıdaki komut çıktısı
     openssl ec -in vapid.pem -noout -text 2>/dev/null | grep -A2 'priv:' | tail -1
     # VAPID_PUBLIC_KEY = aşağıdaki komut (base64url, 0x04 ile başlayan 65 bayt)
     openssl ec -in vapid.pem -pubout -outform DER 2>/dev/null | tail -c 65 \
       | openssl base64 -A | tr '+/' '-_' | tr -d '='
     ```
3. **Auth → Site URL**: `https://calorix.app` olarak ayarla. Site URL yanlışsa
   e-posta yönlendirmeleri ve invite akışları kırılır.
4. **Cron job güncellemesi**: `check-reminders` cron tanımı artık
   `x-calorix-internal: 1` **değil**, `Authorization: Bearer <INTERNAL_FUNCTION_TOKEN>`
   göndermeli. Eski header artık reddedilir (güvenlik gereği).
5. **Yeni migration'ları uygula** (düzenli/aylık):
   - `supabase/migrations/20260927120000_security_hardening_round1.sql`
   - `supabase/migrations/20260927220000_rls_update_with_check.sql`
   - `supabase/migrations/20260927220500_persistent_rate_limit.sql`
   - `supabase/migrations/20260928120000_push_idempotency_and_limits.sql` (Tur 3)
   Proje frozen olduğu için düzeltmeler yeni dosyaya yazıldı; mevcut migration'lar
   hiçbir ajan tarafından düzenlenmedi. Tümü **idempotent**'tir (3× çalıştırıldı).

## Yeni edge function: `delete-account` (Tur 3 — KVKK / Google Play)

`supabase/functions/delete-account/` klasörü yeni eklendi. Deploy edildiğinde
kullanıcı hesabını **kendi JWT'si + mevcut parolasıyla** silebilir.

### Dashboard'da yapılması ZORUNLU

1. **Yeni secret gerekmiyor.** Fonksiyon yalnızca zaten tanımlı olan
   `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`
   değişkenlerini kullanır. `INTERNAL_FUNCTION_TOKEN` **kullanılmaz** (bu bir
   cron değil, kullanıcı uç noktası).
2. **Deploy:** `supabase functions deploy delete-account`
   (config.toml'da `verify_jwt = true` ile tanımlıdır).
3. **Fonksiyonu JWT'ye aynı veya daha geniş yetkiyle erişebilen** roller
   çağırabilir — istemci tarafında yalnızca **kendi oturumu** ile çağrılmalı.
4. **Mağaza beyanı:** Google Play "Data safety" formunda hesap silme
   özelliğinin bulunduğu beyan edilmelidir; Play Console ayrıca uygulama içi
   bir "Hesabımı sil" girişi zorunlu tutar (bkz. AKTARIM bölümü).
5. **Smoke test:**
   ```bash
   curl -X POST "$SUPABASE_URL/functions/v1/delete-account" \
     -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"password":"<KULLANICI_PAROLASI>"}'
   # 200 {"success":true,"message":"Hesabınız ve tüm verileriniz kalıcı olarak silindi."}
   # yanlış parola -> 401 {"error":"Parola hatalı"}
   ```
   Yanlış parola denemesi `notifications`/`profiles` tablolarına **dokunmaz**.
6. **Sıralama/etiket notu:** Silme sırası Storage → 12 uygulama tablosu →
   `auth.admin.deleteUser()`. Bu kova (bucket) listesi **çalışma anında
   `listBuckets()` ile alınır**; yeni bir kova eklendiğinde otomatik kapsama
   girer (sabit kova listesi yüzünden unutulma riski yoktur).


## Dikkat: davranış değişiklikleri (regresyon riski)

| Fonksiyon | Değişiklik | Etki |
|---|---|---|
| `check-reminders` | Artık internal token istiyor | Eski cron tanımı 401 alır, hatırlatıcılar düşmez |
| `send-notification` | `userId` parametresi ile BOLA engellendi; çağıran kendi `sub` ile eşleşmeli | Eski istemci çağrıları 403 alır |
| `recognize-food`, `recognize-food-text` | Derleme hatası giderildi (çift `return new Response`) — **bu fonksiyonlar önceden hiç çalışmıyordu** | Artık çalışıyor; beklenmeyen davranış/çıktı farkı olabilir |
| `calculate-macros` | Yanıt normalize: `bmr`/`tdee`/makro/sup sayısal ve yuvarlanmış | Flutter `as num` kullanıyor, uyumlu |
| Tüm edge function'lar | Timeout + rate limit eklendi | Yoğun kullanımda 429 dönebilir |
| Tüm tablolar | `anon` rolüne `REVOKE ALL` | Doğrudan anon erişimi olan bir istemci kırılır (olmamalı) |

## Ek davranış değişiklikleri (Tur 3)

| Bileşen | Değişiklik | Etki / yapılacak |
|---|---|---|
| **Push gövdesi** | `Content-Encoding: aes128gcm` ile **şifreleniyor** (RFC 8291) + `Crypto-Key: dh=` başlığı | Push servisi şifreli gövdeyi açar; **tarayıcı tarafında değişiklik gerekmez**. Smoke test: logda hata yoksa tamam |
| **`profiles`** | Yeni kolon `last_weekly_summary TIMESTAMPTZ` | **Migration uygulanmazsa** haftalık özet gönderimi `SELECT ... last_weekly_summary` hatası verir ve cron 500 döner. `20260928120000` **zorunlu** |
| **`check-reminders`** | Haftalık özet artık aynı ISO haftasında **bir kez** gönderiliyor | Kullanıcı artık günde ~12 kez özet almaz (davranış düzeltmesi) |
| **`readJsonBody`** | Varsayılan gövde sınırı 1 MB → **256 KB**; `Content-Type: application/json` zorunlu | `recognize-food` 8 MB sınırını **açıkça** geçiyor. Diğer istemcilerde 413/415 normal |
| **`push_subscriptions`** | Kullanıcı başına en fazla **7** abonelik (trigger) | 8. cihaz kaydı "Cihaz sınırı aşıldı" hatası verir. Migration zorunlu |

## Yeni dosyalar

- `supabase/functions/_shared/{auth,http,rate_limit,validate}.ts` — ortak katman.
- `supabase/functions/_shared/rate_limit.ts` bellek içi sayaç kullanıyor; çok instance
  dağıtımda bypass mümkün. Kalıcı sayaç tablosu + RPC, Faz 2'de.

## Takip edilecek açık maddeler (A1'den devralındı)

- ~~**P1** VAPID JWT imzası üretilmiyor → web push bildirimleri fiilen gitmiyor.~~
  **ÇÖZÜLDÜ (A1b):** `supabase/functions/_shared/vapid.ts` — bkz. aşağıdaki blok.
- ~~**P1** Push gövdesi düz metin gidiyor (RFC 8291 yok).~~ **ÇÖZÜLDÜ (A1r3, Tur 3):**
  `supabase/functions/_shared/web_push_crypto.ts` ile RFC 8188 + RFC 8291
  `aes128gcm` şifrelemesi eklendi (ECDH P-256 → HKDF → AES-128-GCM).
  `send-notification` artık `Content-Encoding: aes128gcm`,
  `Content-Type: application/octet-stream`, `Crypto-Key: dh=<as_public>`,
  `TTL`, `Urgency` başlıklarını gönderiyor; VAPID imzası bozulmadan **birlikte**
  çalışıyor (RFC 8291 §3.3 gereği şifreli istekte VAPID zorunludur).
  Doğrulama: **RFC 8291 Ek A'daki yayımlanmış ara değerler** (`ecdh_secret`,
  `PRK_key`, `IKM`, `PRK`, `CEK`, `NONCE`, `key_info`) modülün ürettiği değerlerle
  **bayt bayt** eşleşiyor → `deno test supabase/functions/_shared/web_push_crypto_test.ts`
  → **14/14 geçti**. Tarayıcı tarafında değişiklik gerekmez.
  *Şema notu:* `push_subscriptions` kolonları (`endpoint`, `p256dh`, `auth`)
  şifreli gövde için **yeterlidir** — `p256dh` 65 bayt, `auth` 16 bayt olmalı.
  Kötü veri (eski/bozuk satır) şifrelemeyi reddeder, push atlanır, e-posta akışı sürer.
- **P2** `full_setup.sql` yeni migration'lardan geride → yeni kurulumlar zayıf korumalı.
  Tur 3'te yeni kolon/trigger da eklendi (`last_weekly_summary`, push adet
  sınırı) → **Senkron kalmadı**, `supabase/full_setup.sql` güncellenmeli.
- **P2** `ai-chat` dosyasında `@ts-nocheck` duruyor; `supabase gen types` gerekiyor.
- **P3** `profiles.timezone` kolonu hiç kullanılmıyor, `UTC+3` sabit kodlanmış.

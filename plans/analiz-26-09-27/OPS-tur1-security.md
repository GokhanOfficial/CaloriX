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
5. **Yeni migration'ı uygula**: `supabase/migrations/20260927120000_security_hardening_round1.sql`.
   Proje frozen olduğu için düzeltmeler yeni dosyaya yazıldı; mevcut migration'lar
   hiçbir ajan tarafından düzenlenmedi.

## Dikkat: davranış değişiklikleri (regresyon riski)

| Fonksiyon | Değişiklik | Etki |
|---|---|---|
| `check-reminders` | Artık internal token istiyor | Eski cron tanımı 401 alır, hatırlatıcılar düşmez |
| `send-notification` | `userId` parametresi ile BOLA engellendi; çağıran kendi `sub` ile eşleşmeli | Eski istemci çağrıları 403 alır |
| `recognize-food`, `recognize-food-text` | Derleme hatası giderildi (çift `return new Response`) — **bu fonksiyonlar önceden hiç çalışmıyordu** | Artık çalışıyor; beklenmeyen davranış/çıktı farkı olabilir |
| `calculate-macros` | Yanıt normalize: `bmr`/`tdee`/makro/sup sayısal ve yuvarlanmış | Flutter `as num` kullanıyor, uyumlu |
| Tüm edge function'lar | Timeout + rate limit eklendi | Yoğun kullanımda 429 dönebilir |
| Tüm tablolar | `anon` rolüne `REVOKE ALL` | Doğrudan anon erişimi olan bir istemci kırılır (olmamalı) |

## Yeni dosyalar

- `supabase/functions/_shared/{auth,http,rate_limit,validate}.ts` — ortak katman.
- `supabase/functions/_shared/rate_limit.ts` bellek içi sayaç kullanıyor; çok instance
  dağıtımda bypass mümkün. Kalıcı sayaç tablosu + RPC, Faz 2'de.

## Takip edilecek açık maddeler (A1'den devralındı)

- ~~**P1** VAPID JWT imzası üretilmiyor → web push bildirimleri fiilen gitmiyor.~~
  **ÇÖZÜLDÜ (A1b, commit bkz. rapor):** `supabase/functions/_shared/vapid.ts` ile
  bağımlılıksız ES256 (ECDSA P-256) VAPID JWT üretimi eklendi (`web-push` npm paketi
  yerine WebCrypto; Edge Runtime'da Node `Buffer` bağımlılığı yok). `send-notification`
  artık `Authorization: vapid t=<imzalı JWT>, k=<applicationServerKey>` gönderiyor;
  push payload şeması + 4096 bayt sınırı uygulanıyor, `201` dışı yanıtlar
  (token maskelenerek) loglanıyor ve 404/410 dönen ölü abonelikler
  `push_subscriptions`'tan siliniyor. Doğrulama: `deno test --allow-env
  supabase/functions/_shared/vapid_test.ts` → **14/14 geçti** (imza `crypto.subtle.verify`
  ile doğrulanıyor, kurcalama reddi test ediliyor) + `deno check` tüm edge
  function'larda temiz.
- **P2** `full_setup.sql` yeni migration'lardan geride → yeni kurulumlar zayıf korumalı.
- **P2** `ai-chat` dosyasında `@ts-nocheck` duruyor; `supabase gen types` gerekiyor.
- **P3** `profiles.timezone` kolonu hiç kullanılmıyor, `UTC+3` sabit kodlanmış.

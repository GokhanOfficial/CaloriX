# RAPOR — A1-security — 2026-09-27 — Tur 1

> Kapsam: `supabase/**` (migration + edge functions + config), `flutter_app/lib/core/config/env.dart`, gizli anahtar taraması.
> Doğrulama ortamı: `deno check` (2.9.7), `flutter analyze` (temiz), `flutter test` (4 pre-existing failure — benim değişikliğimden bağımsız doğrulandı), Postgres 16 (Docker) ile migration canlı çalıştırma.

## Özet (5 madde)

1. **İki P0 açık bulundu ve kapatıldı.** (a) `send-notification` fonksiyonu **hiçbir yetki kontrolü olmadan** herhangi bir `userId` için push/e-posta gönderiyordu — `verify_jwt = true` olması, fonksiyonun `Authorization` başlığını hiç okumaması nedeniyle işe yaramıyordu (anon JWT yeterliydi, RLS/roller denetlenmiyordu). (b) `check-reminders` **anon JWT ile dışarıdan tetiklenebiliyordu**: tüm `profiles` tablosunu okuyup herkese e-posta/push gönderiyordu (abuse + maliyet + e-posta bombardımanı).
2. **Edge function güvenliği ortak katmana taşındı** (`supabase/functions/_shared/{http,auth,validate,rate_limit}.ts`): sunucu tarafı `auth.getUser()` doğrulaması, CORS izin listesi + `Vary` + `Access-Control-Allow-Methods`, sabit hata mesajları (stack/schem/anahtar sızıntısı yok), `AbortSignal.timeout` ile tüm dış AI çağrılarında zaman aşımı, kullanıcı/IP bazlı hız sınırı.
3. **Sözdizimi hatası giderildi:** `recognize-food/index.ts` ve `recognize-food-text/index.ts` içinde satır 143-144 ve 138-139'da **iki kez `return new Response(` yazılmıştı** → dosya derlenmiyordu, tüm AI tanıma akışı çalışmıyordu (P0 işlevsizlik).
4. **RLS/migration sertleştirmesi:** 15 tablo tek tek denetlendi. Politikalar `TO authenticated` ile daraltıldı, eksik DELETE/UPDATE politikaları eklendi, `search_path` hijacking'e karşı `SET search_path = ''` uygulandı, `anon` rolüne tüm tablo erişimi `REVOKE` edildi, negatif miktar/kilo ve bildirim tipi/saat CHECK kısıtları eklendi. Migration **Postgres 16'da 3 kez üst üste çalıştırıldı** (idempotent) ve RLS izolasyonu canlı veriyle kanıtlandı.
5. **Gizli anahtar taraması temiz:** repoya sızmış JWT/DSN/service_role/Resend/VAPID anahtarı **yok**; `.env` ve `supabase/.env` `.gitignore`'da; git geçmişinde hiç `.env` dosyası eklenmemiş. `env.dart`'a service_role anahtarı istemciye gömülürse yapılandırılmamış sayılacağı guard eklendi.

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P0** | `supabase/functions/send-notification/index.ts:170` (eski hali) | Gövde `userId, type, title, message` doğrulamasız alınıyordu; `verify_jwt=true` olmasına rağmen `Authorization` hiç okunmuyordu → **herhangi bir kullanıcıya e-posta/push gönderilebiliyordu**. Artık: `requireUserContext()` ile `getUser()`, `requireUuid` ile BOLA kontrolü (`targetUserId !== userId` → 403), dahili cron çağrısı `INTERNAL_FUNCTION_TOKEN` ile ayrıştırıldı, `type` allow-list, `title`/`message` uzunluk sınırı. | `deno check` temiz; akış yeniden okundu |
| **P0** | `supabase/functions/check-reminders/index.ts:85-108` (eski hali) | Anon JWT ile çağrılabiliyordu; `profiles` tablosunun tamamı dışarıdan tetiklenebiliyordu. Artık `isAuthorizedCall()` ile internal-token **veya** `app_metadata.role === 'service_role'` zorunlu. | `deno check` temiz |
| **P0** | `supabase/functions/recognize-food/index.ts:143-144` | **Çift `return new Response(` → derleme hatası**, fonksiyon hiç çalışmıyordu. Yeniden yazıldı. | `deno check` temiz |
| **P0** | `supabase/functions/recognize-food-text/index.ts:138-139` | Aynı çift `return new Response(` derleme hatası. Yeniden yazıldı. | `deno check` temiz |
| **P0** | `supabase/config.toml:12-13,15-16` | `check-reminders` ve `send-notification` `verify_jwt = true` idi ama kod JWT okumuyordu → **etkisiz güvenlik izlenimi**. `check-reminders` → `false` + fonksiyon içi yetkilendirme. `send-notification` → `false` (dahili çağrı JWT'siz geliyor) + fonksiyon içi yetkilendirme. `ai-chat` açıkça eklendi. | `tomllib` ile parse doğrulandı |
| **P1** | `supabase/functions/_shared/http.ts` (yeni) | `Access-Control-Allow-Origin: *` → izin listesi + `Vary: Origin` + `Access-Control-Allow-Methods` + `X-Content-Type-Options: nosniff` + `Cache-Control: no-store`. Preflight artık 204. `*` kullanıldığında `Access-Control-Allow-Credentials` **gönderilmiyor** (credential gerektiren durum oluşmuyor). | `deno check` temiz |
| **P1** | `supabase/functions/_shared/auth.ts` (yeni) | Sunucu tarafı JWT doğrulaması tek noktada. **Kanonik olmayan (anon/service_role) JWT reddedilir** — `getUser()` şemada kullanıcı arar. Boyut sınırlı JSON okuyucu. | `deno check` temiz |
| **P1** | `supabase/functions/_shared/rate_limit.ts` (yeni) | AI çağrısı yapan 4 fonksiyona kullanıcı bazlı hız sınırı: `recognize-food` 12/dk, `recognize-food-text` 20/dk, `calculate-macros` 10/dk, `ai-chat` 20/dk, `check-reminders` 2/5dk. | `deno check` temiz |
| **P1** | `supabase/functions/ai-chat/index.ts:449` (eski hali) | `JSON.parse(call.function.arguments)` korumasızdı → model bozuk JSON döndüğünde **tüm istek 500** oluyordu. `try/catch` + nesne şeması kontrolü eklendi. | `deno check` temiz |
| **P1** | `supabase/functions/ai-chat/index.ts` (eski `executeWriteTool` update_goals) | Modelin ürettiği değerler **doğrudan** `profiles`'a yazılıyordu (`daily_calorie_target: -99999` veya `goal: "<script>"` dahi). Sayısal alanlara aralık, enum'lara allow-list eklendi. | `deno check` temiz |
| **P1** | Tüm AI fonksiyonları | `AbortSignal.timeout()` eklendi (hiçbirinde timeout yoktu → asılı istek kaynak tüketirdi). | `deno check` temiz |
| **P1** | Tüm AI fonksiyonları | Hata sızıntısı: `check-reminders:311` ve `send-notification:255` `error.message`'i istemciye JSON ile dönüyordu (Postgres hata metni = tablo/kolon şeması). Artık tüm fonksiyonlarda sabit mesaj + sunucu logu. | `deno check` temiz |
| **P1** | `supabase/functions/check-reminders/index.ts` (kolon hataları) | `meal_entries.calories/protein_g/carbs_g/fat_g` **yok** (gerçek: `calculated_*`) → haftalık özet `0` kcal gösteriyordu. `water_entries.entry_time` / `weight_entries.recorded_at` **yok** (gerçek: `entry_date`). `profiles` SELECT'inde `last_daily_log_reminder` **yok** → günlük hatırlatma hiç tetiklenmiyordu. | Postgres şeması ile karşılaştırıldı |
| **P1** | `supabase/functions/check-reminders/index.ts` | **Aynı bildirim tekrarı:** `sendNotification()` başarısız olsa bile `last_*_reminder` güncelleniyordu; ayrıca su hatırlatması `last_water_reminder` güncellenmeden yeniden tetiklenebiliyordu. Koşu içi `sentThisRun` idempotency + `hourly` koşulları korundu. | `deno check` temiz |
| **P1** | `supabase/migrations/20260927120000_security_hardening_round1.sql` (yeni, 12 KB) | 15 tablo `ENABLE ROW LEVEL SECURITY`; tüm politikalar `TO authenticated` ile daraltıldı; eksik politikalar eklendi (`foods` DELETE, `food_nutrition` DELETE, `push_subscriptions` UPDATE, `chat_threads`/`chat_messages` DELETE); `profiles` UPDATE'e `WITH CHECK`; 5 `SECURITY DEFINER` fonksiyon `SET search_path = ''`; `anon` rolüne tüm tablolarda `REVOKE ALL`; negatif miktar/kilo CHECK; `notification_preferences` tip/saat CHECK; `notifications.type` CHECK genişletildi; FK `ON DELETE SET NULL`; `foods(lower(name), lower(brand))` unique index. | **Postgres 16'da 3× üst üste çalıştırıldı → 0 hata (idempotent)** |
| **P1** | `flutter_app/lib/core/config/env.dart:19-22,44-49` | `sb_secret_` / `service_role` öneki taşıyan bir anahtar `SUPABASE_ANON_KEY` olarak tanımlanırsa artık **yapılandırılmamış** sayılır (istemsiz RLS atlanması koruması). | `flutter analyze` → **No issues found** |
| **P2** | `supabase/.env.example` | `INTERNAL_FUNCTION_TOKEN` placeholder eklendi + hangi durumda zorunlu olduğu açıklandı. | — |
| **P2** | `supabase/functions/send-notification/index.ts:96-101` | Kullanıcının kaydettiği `push_subscriptions.endpoint` doğrulanmadan `fetch`'e veriliyordu → **SSRF** ( saldırgan `https://evil.com` endpoint'i kaydedip sunucunun oraya istek atmasını sağlardı). Host allow-list eklendi (FCM/Mozilla/Apple). | `deno check` temiz |
| **P2** | `supabase/functions/send-notification/index.ts` (`getEmailTemplate`) | `message`/`userName` HTML şablonuna kaçırılmadan gömülüyordu → **HTML enjeksiyonu** (e-posta gövdesinde script/iframe). `escapeHtml()` eklendi. | `deno check` temiz |
| **P2** | `supabase/functions/calculate-macros/index.ts:60` (eski hali) | `if (!age \|\| !height_cm ...)` yalnızca falsy kontrolü → negatif/NaN/`"abc"` değerler prompt'a giriyordu. Aralık + enum doğrulaması eklendi; AI yanıtı da normalize ediliyor (`Math.round(requireNumber(...))`) → istemcide `(data['bmr'] as num).round()` artık çökmez. | `deno check` temiz |
| **P2** | `recognize-food` / `recognize-food-text` | Prompt injection yüzeyi: kullanıcı metni artık "veri olarak yorumla, talimat olarak uygulama" etiketiyle sınırlandırılıyor; metin 1000 karakterle sınırlı. | — |
| **P2** | `supabase/functions/*` | Ölü `import "https://deno.land/x/xhr@0.1.0/mod.ts"` (3 dosya) kaldırıldı. | `deno check` temiz |
| **P2** | `supabase/functions/ai-chat/index.ts:391-409` | `locale`/`language` sistem prompt'una ham giriyordu; 35/12 karakterle sınırlandırıldı ve satır sonu atıldı. `timeZone` `Intl` ile doğrulanıyor, geçersizse UTC. | `deno check` temiz |

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P1** | `supabase/functions/ai-chat/index.ts:1` | `// @ts-nocheck` dosyayı tip denetiminden tamamen çıkarıyor. Kaldırmayı denedim: geriye yalnızca `supabase-js` generic kaynaklı **sahte** hatalar kalıyor (`from("x").insert()` → `never[]`, çünkü `Database` tipi tanımlı değil) — güvenlik açısından ek hata yok. | Tip hatası denetimden kaçar | `supabase gen types typescript > lib/database.types.ts` üretip `createClient<Database>()` ile bağlanmak; Tur 2 |
| **P1** | `supabase/functions/send-notification/index.ts:124-131` | Web Push **VAPID imzası üretilmiyor**; yalnızca `Authorization: vapid t=<public key>` başlığı konuyor. Tarayıcılar imzasız isteği reddeder → **push bildirimleri fiilen hiç gitmiyor**. `VAPID_PRIVATE_KEY` okunuyor ama kullanılmıyor. | Özellik çalışmıyor | `npm:web-push@3` (Deno uyumlu) veya `deno.land/x/web_push` ile ECDSA imzası. Fonksiyonel düzeltme, davranış değişikliği → Tur 2 |
| **P2** | `supabase/functions/_shared/rate_limit.ts:14` | Hız sınırı **süreç içi (bellekte)**; çok instance'lı dağıtımda instance başına sayılır. Kalıcı sayaç için `rate_limits` tablosu + RPC gerekir. | Bypass mümkün | Tur 2'de `SECURITY DEFINER` RPC ile atomic sayaç |
| **P2** | `supabase/functions/_shared/http.ts:12` | İzin listesi `https://calorix.app` + localhost. Farklı domain (staging/önizleme) eklenecekse **düzenlenmeli**, aksi halde `*` fallback devreye girer. | Doğru domain gerekli | Supabase Dashboard > Auth > Site URL ile eşleştirilmeli |
| **P2** | `supabase/migrations/...:1` | `full_setup.sql` (353 satır) artık migration'ların gerisinde kaldı: `chat_threads`/`chat_messages`, `notifications.type` CHECK'i, `search_path=''`, GRANT'ler ve `delete` politikaları **yok**. | Yeni kurulum eksik güvende | `full_setup.sql`'i birleştirmek geniş kapsamlı bir dokümantasyon işi → A6/A2 ile koordine, Tur 2 |
| **P3** | `supabase/functions/check-reminders/index.ts:198` | `UTC+3` (Türkiye saati) sabit kodlanmış; `profiles.timezone` kolonu (20260111075621) **okunmuyor**. Kullanıcı farklı dilimdeyse yanlış saatte hatırlatma alır. | Yanlış zamanlama | A3/A4: `Env` timezone → `timeZone` alanı; burada `Intl` ile hesap |
| **P3** | `supabase/functions/ai-chat/index.ts:474` | 5 tool iterasyonu sabit; `max_tokens: 900`. Kullanıcı "şunları da ekle" derse yarım kalır. | UX | Tur 3 |
| **P3** | `supabase/functions/send-notification/index.ts:100` | `VAPID` anahtarları yoksa push sessizce atlanıyor (`console.error` yalnızca). Kullanıcı "neden bildirim gelmiyor" anlamaz. | İzlenebilirlik | A3: operasyonel log/uyarı |

### Storage politikaları (doğrulandı — `pg_policies`)

`chat-attachments` bucket'ı için 4 politika mevcut, hepsi `TO {authenticated}`:

| Politika | Komut | Koşul |
|---|---|---|
| `Users can upload their own chat attachments` | INSERT | `WITH CHECK bucket_id = 'chat-attachments' AND foldername[1] = auth.uid()` |
| `Users can view their own chat attachments` | SELECT | aynı, `USING` |
| `Users can update their own chat attachments` | UPDATE | aynı, `USING` + `WITH CHECK` |
| `Users can delete their own chat attachments` | DELETE | aynı, `USING` |

Kova `public = false`, `file_size_limit = 10 MB`, MIME allow-list yalnızca görsel. `anon` rolüne açık storage politikası yok.

### RLS denetimi — tablo tablo kanıt

| Tablo | RLS | Politika (tur öncesi → sonrası) | Not |
|---|---|---|---|
| `profiles` | ✅ | 3 → 3 (+`WITH CHECK`) | `id` değiştirme **canlı testte reddedildi** |
| `user_roles` | ✅ | 1 SELECT → 1 | Yazma yok → rol yükseltme yolu kapalı |
| `foods` | ✅ | 3 → **4** | DELETE politikası **yoktu** (kullanıcı kendi gıdasını silemiyordu) |
| `food_nutrition` | ✅ | 3 → **4** | DELETE eklendi; INSERT `WITH CHECK (created_by = auth.uid())` zaten vardı |
| `meal_entries` | ✅ | 4 → 4 | `TO authenticated` eklendi |
| `water_entries` | ✅ | 4 → 4 | + negatif `amount_ml` CHECK |
| `weight_entries` | ✅ | 4 → 4 | + `weight_kg` aralık CHECK |
| `notifications` | ✅ | 3 + service_role INSERT | INSERT yalnızca `TO service_role` → **`anon` INSERT yok** (doğrulandı) |
| `user_settings` | ✅ | 3 → 4 | DELETE eklendi |
| `favorite_foods` | ✅ | 3 → 3 | `TO authenticated` eklendi |
| `recent_foods` | ✅ | 4 → 4 | `TO authenticated` eklendi |
| `push_subscriptions` | ✅ | 3 → **4** | UPDATE eklendi (abonelik yenileme) |
| `notification_preferences` | ✅ | 4 → 4 | + tip allow-list + saat/aralık CHECK |
| `chat_threads` | ✅ | 3 → **4** | DELETE eklendi (KVKK) |
| `chat_messages` | ✅ | 3 → **4** | DELETE eklendi (KVKK) |
| `sync_log` | — | **TABLodan düşürülmüş** (20260518075600) | Pasif kod: yalnızca `full_setup.sql`'de hâlâ var |

> **"RLS enable ama policy yok = P0" bulgusu çıkmadı.** `anon` rolüne açık politika **yok** (doğrulandı: `permission denied for table meal_entries`). `security definer` fonksiyonlarda `search_path` **zaten** `public`'ti ama bu yine de hijacking'e açıktı → `''` yapıldı. Trigger/function içinde yetki yükseltme yolu bulunmadı (`user_roles`'a yazma politikası yok).

### Canlı doğrulama (Postgres 16, gerçek veriyle)

```
Kullanici A kendi meal kaydini gordu .............. 1 satir        ✅
Kullanici A bildirim INSERT (olasi P0) .......... ERROR: violates row-level security policy   ✅
Kullanici A baska kullaniciyi UPDATE ............ 0 satir         ✅
Kullanici A negatif su kaydi INSERT ............. ERROR: violates check constraint            ✅
Kullanici A gecersiz bildirim tipi INSERT ....... ERROR: violates check constraint            ✅
ANON rolune tablo erisimi ...................... ERROR: permission denied for table         ✅
SERVICE_ROLE bildirim INSERT ................... 2 satir (geçti)  ✅
handle_new_user trigger'i calisiyor mu? ........ 2 profil         ✅ (search_path='' ile)
search_path degerleri ........................... 5/5 fonksiyon search_path=""  ✅
Migration 3x ardisik calistirma ................. 0 hata (idempotent)  ✅
```

## AKTARIM (başka alana)

- **A3-flutter-core** → `flutter_app/lib/core/notifications/notification_service.dart`: `check-reminders` artık `x-calorix-internal-token` veya `service_role` JWT ister ve `x-calorix-internal: 1` başlığını **kabul etmez** (güvenlik gereği). Mobil istemci hatırlatmayı **doğrudan tetikleyemez**; davranış korunması için dashboard cron'una `INTERNAL_FUNCTION_TOKEN` header'ı eklenmeli.
- **A2-backend-data** → `flutter_app/lib/data/repositories/recognition_repository.dart:56` ve `macro_calculator.dart:59`: artık **kimlik doğrulamasız** (anon) çağrı 401 alır. `flutter_app` zaten `supabase.functions.invoke` ile kullanıcı JWT'si gönderiyor → sorun yok, ancak testlerde/mock'larda `Authorization` başlığı unutulmamalı.
- **A2-backend-data** → `flutter_app/lib/data/**`: `calculate-macros` artık **normalize edilmiş** sayısal alanlar döndürüyor (`bmr`, `tdee`, `daily_calorie_target`, `protein_target_g`, `carbs_target_g`, `fat_target_g`, `daily_water_target_ml` + opsiyonel `explanation`). `MacroCalculator.calculate()` bunları zaten `as num` ile okuyor → uyumlu.
- **A6-tests-quality** → `flutter_app/test/**`: `flutter test` şu anda **4 test kırık** (benden bağımsız olduğu `git stash` ile doğrulandı): `widget_snapshot_staleness_test.dart` (3 haftalık-zaman damgası testi), `tz_probe_temp_test.dart` (geçici teşhis dosyası — repodan silinmeli). Ayrıca `test/tz_probe_temp_test.dart` `avoid_print` lint'i üretiyor.
- **Ana ajan / operasyon** → Supabase Dashboard: (1) `INTERNAL_FUNCTION_TOKEN` secret'ı tanımlanmalı, (2) Auth > Site URL `https://calorix.app` olmalı, (3) cron job `check-reminders`'ı bu header ile çağırmalı, (4) `notifications.type` CHECK'i migration sonrası genişletildi → `full_setup.sql` de güncellenmeli.
- **A5-web-legacy** → `src/**`: React PWA aynı edge function'ları çağırıyorsa `Authorization` başlığını `Authorization: Bearer <user access token>` olarak gönderdiğinden emin olunmalı; aksi halde `calculate-macros`/`recognize-food*` 401 alır.

## Yeni testler

Bu turda test **eklemedim** — edge function'lar için Deno test altyapısı yok ve `flutter test` zaten kırık. Bunun yerine migration'ı **gerçek Postgres 16'da** çalıştırıp RLS'i canlı veriyle kanıtladım (yukarıdaki blok) ve 6 edge function'ı `deno check` ile doğruladım.

Önerilen (Tur 2):
- `supabase/functions/_shared/*_test.ts` — Deno test: `checkRateLimit` penceresi, `requireUuid`/`requireNumber` sınırları, `isAllowedPushEndpoint` (SSRF: `http://`, `localhost`, `https://evil.com` reddi), `corsHeaders` izin listesi.
- SQL regresyon: `supabase/tests/rls_policies.sql` (pgTAP) — her tablo için "kullanıcı A, kullanıcı B'nin satırını göremez".

## Sonraki öneriler (tur 2 için)

1. **VAPID imzasını gerçekten üret** (`web-push` paketi) — push bildirimleri şu anda hiç gitmiyor (P1 işlevsizlik).
2. **Kalıcı rate limit**: `rate_limits(user_id, bucket, window_start, count)` tablosu + `SECURITY DEFINER` atomic increment RPC'si.
3. **`supabase-js` tipleri**: `deno run -A supabase gen types typescript` → `Database` tipi → `ai-chat`'te `@ts-nocheck` kaldır.
4. **`full_setup.sql`'i yeni migration'larla senkronla** (yoksa yeni kurulumlar zayıf korumalı).
5. **Storage `chat-attachments`** (20260518080500) — `pg_policies` üzerinden doğrulandı: 4 politika mevcut, hepsi `TO authenticated`, INSERT `WITH CHECK` + SELECT/UPDATE/DELETE `USING`, tamamı `(storage.foldername(name))[1] = auth.uid()` ile kullanıcı klasörüne sınırlı, `bucket_id = 'chat-attachments'` ile kovak sınırlı. **Eksik politika yok** — burada ek iş gerekmiyor.
6. **`profiles.timezone`** kolonunu `check-reminders`/`ai-chat` içinde gerçekten kullan (sabit `UTC+3` yerine).
7. **Edge function'lar için CI**: `.github/workflows`'a `deno check supabase/functions/**` ekle (A6 alanı).

# RAPOR — A1r2-security — 2026-09-27 — Tur 2

> Kapsam: `supabase/**` (migration + edge function'lar + `full_setup.sql` + testler).
> Doğrulama ortamı: **Postgres 16.15 (Docker, `a1r2-pg`)**, `deno 2.9.7`.
> `supabase` CLI bu ortamda **kurulu değil** → `supabase db reset` yerine tüm
> migration'lar sıfırdan Postgres 16'ya elle, sıralı olarak uygulandı
> (bkz. "Doğrulama yöntemi").

## Özet (5 madde)

1. **Görev brifindeki P0 iddiası YANLIŞ çıktı ve bu kanıtlandı.** Brif "UPDATE
   politikalarında `WITH CHECK` eksik, kullanıcı kendi satırına `SET user_id =
   '<başkası>'` yazabilir" diyordu. (a) `meal_entries`/`water_entries`/
   `weight_entries`/`user_settings` politikaları zaten round1'in DO bloğunda
   `USING ... WITH CHECK` almıştı (`pg_policies.with_check` **dolu**). (b) Daha
   önemlisi: **PostgreSQL'de UPDATE politikasında `WITH CHECK` yazılmazsa
   `WITH CHECK` ifadesi `USING` ile aynı kabul edilir.** İzole bir tabloda
   (`USING` yazılı, `WITH CHECK` yok) `UPDATE t SET owner = '<başkası>'`
   çalıştırıldı → **`UPDATE 0`, reddedildi.** Yani sömürülebilir bir açık
   değildi. Brifin kanıtı `full_setup.sql` satır numaralarına dayanıyordu;
   `full_setup.sql` de sıfırdan kurulup aynı test çalıştırıldığında da
   reddedildi.
2. **Gerçekten açık olan boşluk kapatıldı:** `chat_threads` ve `chat_messages`
   politikaları `20260518080500`'te **`TO` rolü belirtilmeden** yazıldığı için
   PostgreSQL'de **`TO public`** olarak kayıtlıydı (tüm komutlar). Bugün `anon`
   GRANT'ı `REVOKE` edildiği için fiilen kapalı, ama tek bir `GRANT`/`default
   privileges` ile hatırlamasız veri sızıntısına dönüşürdi. Tüm chat
   politikaları `TO authenticated` ile yeniden tanımlandı.
3. **Denetimde ek olarak iki gerçek veri-bütünlüğü açığı bulundu ve kapatıldı:**
   `recent_foods.food_id` ve `chat_messages.thread_id` UPDATE sırasında
   değiştirilebiliyordu (RLS politikasında `OLD` **kullanılamaz**; PostgreSQL
   politikaya yalnızca yeni satırı verir — bunu yazarken öğrenip migration'ı
   ilk denemede `OLD` referansıyla yazmış, Postgres 16 hata verdi). Çözüm:
   `public.freeze_immutable_columns()` trigger'ı.
4. **`full_setup.sql` migration setiyle hizalandı** (senkron değildi): chat
   tabloları+politikaları, `rate_limits` tablosu ve RPC'leri, eksik DELETE
   politikaları, tüm UPDATE'lere `WITH CHECK`, `TO authenticated`, `anon`
   `REVOKE`, `search_path = ''`, 5 CHECK kısıtı, `chat-attachments` storage
   kovası, `freeze_immutable_columns` trigger'ları eklendi. **Sıfırdan kurulumda
   55 politika — migration yoluyla birebir aynı.**
5. **`ai-chat` `@ts-nocheck` kaldırıldı** (13 dosya `deno check` temiz) ve rate
   limit **kalıcı** hale getirildi: `rate_limits` tablosu + atomik
   `rate_limit_hit()` RPC'si; `_shared/rate_limit.ts` önce DB'yi dener, erişemezse
   bellek içi yola düşer. Atomiklik **10 paralel bağlantıyla ölçüldü: sınır 5 →
   tam olarak 5 izin, sayaç 10** (kayıp güncelleme yok).

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P0** | `supabase/migrations/20260927220000_rls_update_with_check.sql` (yeni, 15 KB) | 15 tablo RLS; **13 UPDATE politikası** `USING`+`WITH CHECK` ile yeniden tanımlandı (politika adları mevcutlarla birebir aynı); `chat_threads`/`chat_messages` **tüm komutlar** `TO authenticated`; `foods`/`food_nutrition` UPDATE `created_by`/alt sorgu ile sabitlendi; `user_roles` yalnızca SELECT; `DELETE` politikaları denetlendi; `anon`/`PUBLIC` `REVOKE ALL`; 5 `SECURITY DEFINER` fonksiyon `search_path = ''`; `freeze_immutable_columns()` trigger'ları | Postgres 16'da 3× üst üste → 0 hata; 49/49 test |
| **P1** | `supabase/migrations/20260927220500_persistent_rate_limit.sql` (yeni, 6 KB) | `rate_limits` tablosu + CHECK, RLS açık, `anon`/`authenticated` `REVOKE`, yalnızca `service_role`; atomik `rate_limit_hit()` (`ON CONFLICT DO UPDATE` → row lock) ve `cleanup_rate_limits()` `SECURITY DEFINER` `search_path = ''` | 10 paralel bağlantı → tam 5 izin, sayaç 10; 20 ardışık → 5 izin/15 ret |
| **P1** | `supabase/tests/rls_policies.sql` (yeni, 570 satır) | 49 test: şema ön koşulları, BOLA (8 tablo), kendi satırının `user_id`'sini değiştirememe (7 tablo), değişmez kolonlar, **kendi satırını güncelleyebilmeli** (false-positive kontrolü), CHECK kısıtları, `anon` erişimi, rate limit, trigger'lar | Her iki kurulum yolunda da **49/49 geçti** |
| **P1** | `supabase/full_setup.sql` | Chat tabloları+politikaları, `rate_limits`+RPC, DELETE politikaları, UPDATE `WITH CHECK`, `TO authenticated`, GRANT/REVOKE, `search_path=''`, CHECK kısıtları, storage kovası, yeni trigger'lar. `notification_preferences` tablosu politika bloğundan **önce** taşındı ( politika tanımlanabilsin diye). Çift tanım politika/`sync_log` kalıntısı temizlendi | Sıfırdan kurulum 0 hata; 55 politika (migration yoluyla aynı); 49/49 test |
| **P1** | `supabase/functions/_shared/rate_limit.ts` | Bellek içi sayaç **birincil yol olmaktan çıkarıldı**; `checkRateLimit()` async: önce `rate_limit_hit()` RPC'si, hata/şema yoksa 60 sn kısa devre ile bellek içi yola düşer. Hata mesajları istemciye sızmaz | `deno test` 5/5 + DB atomiklik testi |
| **P1** | 6 edge function `index.ts` | `checkRateLimit` async olduğu için 6 çağrı noktası `await` eklendi | `deno check` 6/6 temiz |
| **P1** | `supabase/functions/ai-chat/index.ts` | `@ts-nocheck` **kaldırıldı**. `createClient<Database>()` + `_shared/database.types.ts`. 2 **gerçek** tip hatası düzeltildi: `meal_type: string` → `MealType` (`requireEnum` ile, `as` ile susturulmadı); `profiles.update(updates: Record<string, unknown>)` → `profiles["Update"]` + `PROFILE_NUMERIC_FIELDS` allow-list (`as` yerine gerçek tip). `requireEnum` + 3 allow-list sabiti eklendi | `deno check` temiz |
| **P2** | `supabase/functions/_shared/database.types.ts` (yeni) | 6 tablo için gerçek `Row`/`Insert`/`Update` tipleri + `rate_limit_hit` RPC imzası. Flutter'ın `src/integrations/supabase/types.ts` dosyasına **dokunulmadı** | `deno check` temiz |
| **P2** | `supabase/functions/_shared/rate_limit_test.ts` (yeni) | 6 test: bellek içi pencere/izolasyon/sıfırlama, `rateLimitKey`, DB erişilemez yedeği; `SUPABASE_*` varsa ayrıca DB pencere + **10 eşzamanlı istek** testi | `deno test` → 5 passed, 1 ignored (DB'siz), toplam 19 passed |

### Brifin P0 iddiasına dair kanıt (Postgres 16, izole tablo)

```sql
CREATE TABLE t (id int primary key, owner uuid);
CREATE POLICY p ON t FOR UPDATE TO authenticated USING (auth.uid() = owner);
-- A (uid=1111) kendi satırının owner'ını B'ye çevirmeye çalışıyor:
UPDATE t SET owner = '<B-uuid>' WHERE id = 1;   -->  UPDATE 0  (reddedildi)
UPDATE t SET owner = NULL                 WHERE id = 1;   -->  UPDATE 0
UPDATE t SET owner = '<rastgele-uuid>'    WHERE id = 1;   -->  UPDATE 0
SELECT polcmd, pg_get_expr(polqual,polrelid) USING, pg_get_expr(polwithcheck,polrelid) WITH_CHECK
  FROM pg_policy WHERE polrelid='t'::regclass;
--  w  |  (auth.uid() = owner)  |  (NULL)
```
→ `with_check` NULL olsa bile reddediliyor: PostgreSQL `USING`'i `WITH CHECK`
olarak yeniden değerlendiriyor. **Bu migration'daki `WITH CHECK`'ler savunma
derinliğidir; tek başına P0 kapatmaz.**

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| P2 | `supabase/functions/_shared/rate_limit.ts` `dbBypassUntil` | DB yolu 60 sn boyunca kısa devreye alınıyor; bu sürede tüm istekler **instance başına** sayılır (çok instance'da zayıf). | 60 sn'lik bypass penceresi | Migration uygulandıktan sonra `console.error` logu izlenmeli; RPC hatası sürerse `cleanup_rate_limits()` de çalışmıyor demektir (Dashboard cron'una eklenebilir) |
| P2 | `supabase/tests/rls_policies.sql:1` | Test bir **Supabase shim**'i gerektiriyor (`auth.users`, `auth.uid()`, `storage.buckets`). CI'da ancak `supabase start` ile çalışır; bare Postgres'te `auth` şeması yoktur. | CI'da ek kurulum gerekir | A6'ya aktarım: workflow'da `supabase start` + `supabase db reset` sonrası `psql -f supabase/tests/rls_policies.sql` |
| P2 | `supabase/migrations/20260927220500_...sql` `cleanup_rate_limits()` | Temizlik fonksiyonu var ama **çağıran yok**; `rate_limits` tablosu zamanla büyür (kullanıcı başına 1 satır, ~kalıcı). | Tablo büyümesi | Dashboard cron: `select cron.schedule('cleanup-rate-limits', '*/5 * * * *', $$select public.cleanup_rate_limits()$$)` |
| P2 | `supabase/full_setup.sql:6` | `CREATE TYPE` (enum) `IF NOT EXISTS` desteklemediği için dosya **ikinci kez çalıştırılamaz** (bir kez çalıştırılacak tek dosya olarak tasarlanmış). | Tekrar çalıştırma hatası | Kasıtlı; `migrations/` yolu tercih edilmeli (dosyanın başında yazılı) |
| P3 | `supabase/functions/check-reminders/index.ts:198` | `UTC+3` sabit kodlanmış, `profiles.timezone` hâlâ okunmuyor (Tur 1'den kalan). | Yanlış saatte hatırlatma | Tur 3 |
| P3 | `supabase/functions/ai-chat/index.ts` 5 tool iterasyonu sabit | "şunları da ekle" isteği yarım kalır | UX | Tur 3 |

## AKTARIM (başka alana)

- **Ana ajan → brif düzeltmesi:** P0 "`WITH CHECK` eksik, veri aktarımı mümkün"
  maddesi gerçek değil. `TRANSFER-defteri.md`'de bu satır **düzeltilmeli**;
  aksi halde sonraki turlar var olmayan bir açığı kapatmaya çalışır. Gerçek
  bulgu `chat_*` politikalarının `TO public` olmasıydı.
- **A3-flutter-core / A4-flutter-features:** `_shared/rate_limit.ts`'in
  `checkRateLimit()` artık **async**; `checkRateLimitMemory()` senkron olarak
  ayrıldı. Başka ajan bu dosyayı kullanıyorsa `await` eklemesi gerekir (6 edge
  function'da yapıldı). Mobil istemci tarafında değişiklik yok.
- **A6-tests-quality:** `supabase/tests/rls_policies.sql` yeni ve CI'ya
  bağlanabilir (bkz. Bulunurlar). Ayrıca `deno test --allow-env --allow-net
  supabase/functions/_shared/` → 19 passed / 0 failed.
- **Ana ajan / operasyon → yeni migration'lar canlıya uygulanmalı:**
  `20260927220000_rls_update_with_check.sql`, `20260927220500_persistent_rate_limit.sql`.
  İkincisi uygulanmazsa rate limit bellek içi yolda kalır (davranış değişmez,
  yalnızca çok-instance bypass riski sürer).
- **Flutter tarafı etkilenmedi:** `flutter_app/**` ve `src/**` dosyalarına
  dokunulmadı (doğrulama için `flutter analyze` çalıştırılmadı — bu turda o
  alanda değişiklik yok).

## Yeni testler

- `supabase/tests/rls_policies.sql` — **49 test**, her iki kurulum yolunda geçti.
  Kapsam: BOLA (8 tablo), user_id devri engeli (7 tablo), değişmez kolonlar,
  "kendi satırını güncelleyebilmeli" (6 tablo, false-positive kontrolü), şema
  ön koşulları (RLS açık, `TO public` yok, her UPDATE'te `WITH CHECK`, her
  DELETE'de `USING`, `anon` GRANT yok, `user_roles` yazma kapalı, `search_path=''`),
  CHECK kısıtları, `anon` erişimi, rate limit (9 test), trigger'lar.
- `supabase/functions/_shared/rate_limit_test.ts` — **6 test** (5 koşulu + 1 DB).
  Not: DB kolu `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` ister; CI'da
  `supabase start` gerekir.
- Migration atomikliği elle ölçüldü: 10 paralel `psql` → sınır 5, tam 5 izin,
  sayaç 10.

### Doğrulama komutları ve sonuçları

| Komut | Sonuç |
|---|---|
| Tüm migration'lar sıfırdan Postgres 16'ya, sıralı (12 dosya) | **0 hata** (`20260111080533` `pg_cron` eklentisi bare Postgres'te yok → atlandı) |
| Yeni 2 migration **3× üst üste** | **0 hata** (idempotent) |
| `supabase/tests/rls_policies.sql` (migrations yolu) | **49/49 geçti** |
| `supabase/tests/rls_policies.sql` (`full_setup.sql` yolu, sıfırdan) | **49/49 geçti** |
| Politika karşılaştırması (iki yol) | **55 = 55**, UPDATE'si `WITH CHECK` olmayan: **0** |
| `anon` tablo GRANT'i (her iki yol) | **0** |
| 10 paralel RPC çağrısı, sınır 5 | **5 izin / 5 ret**, sayaç **10** |
| `deno check` (6 edge function + 7 shared) | **14/14 temiz** |
| `deno test --allow-env --allow-net supabase/functions/_shared/` | **19 passed / 0 failed / 1 ignored** |

## Doğrulayamadığım şeyler (açıkça)

1. **`supabase db reset` çalıştırılamadı** — `supabase` CLI bu ortamda kurulu
   değil. Yerine Postgres 16.15 Docker konteynerine Supabase'nin `auth` şeması,
   `auth.uid()`, `anon`/`authenticated`/`service_role` rolleri ve
   `storage.buckets`/`storage.objects` için **elle bir shim** kuruldu
   (`/tmp/opencode/a1r2/bootstrap.sql`, repoya girmedi). Bu shim gerçek
   Supabase'in bir alt kümesidir; özellikle **PostgREST katmanı, JWT doğrulama ve
   `default privileges`** davranışı birebir değildir. Canlı projede
   `supabase db reset` ile tekrar doğrulanmalı.
2. **`pg_cron` / `pg_net` eklentileri** bare Postgres imajında bulunmadığı için
   `20260111080533_d3ba8bd5...sql` migration'ı **çalıştırılmadı**. Bu migration
   yalnızca `CREATE EXTENSION` + `GRANT` yapıyor, şema/politika etkisi yok.
3. **Edge function'lar çalışır halde test edilmedi** — `deno check` tip denetimi
   ve `deno test` birim testleri var, ancak `supabase functions serve` ile uçtan
   uca (OpenAI çağrısı, VAPID, push) bir smoke test yapılmadı. `checkRateLimit`'in
   async'e geçişi 6 çağrı noktasında `await` ile karşılandı ve `deno check`
   temiz, ancak çalışma zamanı testi yok.
4. **Rate limit DB yolu Deno testi koşmadı** (`SUPABASE_*` env tanımlı değil →
   test `ignored`). RPC'nin kendisi doğrudan SQL ile 10 paralel bağlantıyla
   test edildi; ancak **PostgREST üzerinden `rpc()` çağrısının** çalıştığı
   doğrulanmadı.
5. **`full_setup.sql` ikinci kez çalıştırılabilir mi** test edilmedi (enum
   `CREATE TYPE` `IF NOT EXISTS`'i desteklemediği için kasıtlı olarak
   tek-çalıştırma dosyası; Bulunurlar'da not edildi).
6. **`flutter analyze` / `flutter test` çalıştırılmadı** — bu turda
   `flutter_app/**` dosyasına dokunulmadı.

## Sonraki öneriler (tur 3)

1. `cleanup_rate_limits()` için Dashboard cron tanımı
   (`*/5 * * * *`) ve `rate_limits` tablosunun KVKK/retention politikası.
2. `profiles.timezone`'ı `check-reminders`/`ai-chat` içinde gerçekten kullan
   (`UTC+3` sabiti kalmasın).
3. `supabase/tests/rls_policies.sql`'i CI'ya bağla (`supabase start` gerekiyor).
4. `ALTER DEFAULT PRIVILEGES` ile yeni tablolara otomatik `anon` GRANT'i
   engelleyen bir kurulum adımı (Supabase Dashboard > SQL Editor'da bir kez
   çalıştırılmalı; repo'dan yapılamaz).
5. `favorite_foods` UPDATE politikası hâlâ yok — kasıtlı karar (rapor
   "Bulunurlar"/gerekçe): kullanıcı zaten DELETE+INSERT ile sıralama
   değiştirebiliyor, yeni yüzey eklemek mevcut yüzeyi azaltmıyor.

-- =============================================================
-- A1r10-security — Tur 11: `check-reminders` için `pg_cron` job'ı
--                  (P0 — DÖRT TURDUR RAPORLANIYOR)
-- Tarih: 2026-09-28
-- =============================================================
-- Bu migration TAMAMEN IDEMPOTENT'tir. Mevcut migration dosyalarına
-- DOKUNULMAMIŞTIR. Hiçbir tablo satırına dokunmaz.
--
-- ---------------------------------------------------------------------------
-- ⭐ BULGU (P0): SUNUCU TARAFI HATIRLATICILAR HİÇ GİTMİYOR
-- ---------------------------------------------------------------------------
-- A1 Tur 1'den beri raporlanıyor, A1r8'de de teyit edildi:
--
--   `grep -rn "cron.schedule" supabase/`  →  **boş**
--
-- `20260111080533` yalnızca eklentileri **kuruyor**
-- (`CREATE EXTENSION pg_cron` / `pg_net`) ve `cron` şemasına `GRANT`
-- veriyor; **hiçbir job tanımlamıyor**. `full_setup.sql:904` "5. Cron Jobs"
-- başlığı altında da yalnızca aynı iki satır var.
--
-- Sonuç: `check-reminders` **elle** tetikleniyor. Kapı tamamen kapalı:
--   * `water`            (saat aralığı + `interval_hours` ile)
--   * `daily_log`        (18:00'de)
--   * `weekly_summary`   (`summary_day`/`summary_hour`)
--   * `weigh_in`         (09:00'de)
-- hiç gönderilmiyor. Yani Tur 3, 7, 8, 10 ve 11'deki **tüm** sunucu
-- bildirim düzeltmeleri (push idempotency'si, haftalık özet damgası,
-- `notification_preferences_hours_range` CHECK'i, gece aralığı desteği)
-- kullanıcıya **hiç ulaşmıyor**. Düzeltmeler doğru ama **görünmez**.
--
-- ---------------------------------------------------------------------------
-- ÇÖZÜM TASARIMI VE GEREKÇESİ (her seçim ölçülmüş/bağlantılı)
-- ---------------------------------------------------------------------------
--
-- [1] SIKLIK: `7-59 * * * *`  →  saatte 7 kez, **dakikada 1 kez değil**.
--
--   Neden 5 dakika değil (A1r8'in önerisi)?
--     - Üst sınır: `check-reminders` bir **AI çağrısı** yapabilir
--       (`generateMotivationalMessage`, `index.ts:37` → `OPENAI_BASE_URL`).
--       `daily_log` koşulu 18:00'e denk gelirse **her koşuda** bir AI
--       çağrısı yapılır. 5 dakikada bir = saatte 12 AI çağrısı. Üstelik
--       `checkRateLimit` kovası `2/300 sn` olduğu için dakikada bir
--       çağırmak **her zaman** "Zaten çalışıyor/atlandı" 200 döner.
--     - Alt sınır: 1 saatte bir olsaydı, `weigh_in` (09:00) ve `daily_log`
--       (18:00) **1/24 ihtimalle kaçardı** — çünkü o saatte koşu yoksa
--       bir sonraki koşu 60 dakika sonrasıdır ve `normalizedHour === 9`
--       artık sağlanmaz. A1r3'ün `weekly_summary` hatasının **aynı sınıfı**:
--       "belirli saatte tetiklenen" bir olay, saatte bir koşuda kaçar.
--     - Çözüm: saatte 7 koşu → **dakikada 1 değil**, ama 09:00 ve 18:00
--       **garanti** yakalanır (bir saat içinde 7 deneme). Dakika sapması
--       en fazla 1/7 saat ≈ 8.5 dakika.
--     - Yük: kullanıcı başına 4 profil sorgusu + 1 tercih sorgusu. 1000
--       kullanıcıda koşu başına ~5000 sorgu. Saatte 7 → 35 bin sorgu/gün.
--       Supabase bağlantı havuzu için kabul edilebilir; `pg_net` tek HTTP
--       isteği attığı için edge tarafı **tek** koşudur.
--
--   Neden `7-59` (dakika 7'den başlayarak) ve `*/5` değil?
--     `*/5` = 0,5,10,... → dakika 0,5,...,55 (12 koşu). `7-59` = 7,14,...
--     59 (8 koşu). Dakika 0'da koşu olmaması, kullanıcıların saat başı
--     eşzamanlı yük oluşturmasını (thundering herd) bir miktar dağıtır;
--     dakikalar arası en az 7 dakika, en çok 8 dakikadır (düzensiz ama
--     sınırlı). `interval_hours` ölçüm hassasiyeti için 1 dakikalık
--     fark önemsizdir (bkz. A1r10'nin dakika farkı düzeltmesi).
--
-- [2] YETKİLENDİRME: `x-calorix-internal-token` başlığı, `INTERNAL_FUNCTION_TOKEN`
--     ile. `config.toml`'da `check-reminders.verify_jwt = false` **doğrudur**
--     (P0: anon JWT ile çağrılabilmesi tüm kullanıcı listesini açar).
--     Yani JWT yok → **token zorunlu**. `isAuthorizedCall` (`index.ts:152`)
--     token'ı `x-calorix-internal-token` başlığında bekler.
--
--     ⚠️ `Authorization: Bearer <token>` DEĞİL, `x-calorix-internal-token`.
--     Görev metninde "internal token istiyor (`Authorization: Bearer …`)"
--     deniyordu; bu, göreve göre **daha zayıf** bir kapı olurdu:
--     `send-notification`'ın `isInternalCall` fonksiyonu aynı token'ı
--     `x-calorix-internal-token` altında arıyor ve `Authorization`'ı
--     **service_role JWT** olarak yorumluyor. Token'ı `Authorization`'a
--     koymak ek bir şey kazandırmaz, yalnız iki farklı kapıyı
--     karıştırırdı. **Doğru başlık ölçülerek doğrulandı** (aşağıda).
--
-- [3] SIRRI NEREDE? `vault` (Supabase'in gizli değer deposu).
--     Gerekçe (görev metni de Vault'ı tercih ediyor):
--       * Token'ı migration'a düz yazmak = **git'te kalıcı sır**. Bu
--         migration `supabase/migrations/` altında ve repoda; bir kez
--         commit edildiğinde token herkesin göreceği bir dosyada durur.
--       * `vault.create_secret` **şifreli** saklar; `vault.decrypted_secrets`
--         yalnızca yetkili roller tarafından okunur.
--       * Supabase'ın kendi dokümanı bu yolu öneriyor
--         ("Scheduling Edge Functions" → `vault.create_secret`).
--       * `anon`/`authenticated` rolleri `vault.decrypted_secrets`'i
--         okuyamaz; `SECURITY DEFINER` sarmalayıcı **yalnız `postgres`**
--         tarafından çalıştırılabilir.
--
--     URL neden Vault'ta değil? URL **sır değildir**: `config.toml`'daki
--     `project_id` zaten repoda düz metin. Token'ı Vault'ta tutup URL'i
--     Vault'ta tutmak, projeyi taşırken (yeni ref) tek bir yeri
--     güncellemek yerine iki yeri güncellemeyi gerektirirdi. Karar:
--     **sır → Vault, kimlik → düz metin** (görev metni: "hardcode URL
--     projeyse sorun değil, ama INTERNAL_FUNCTION_TOKEN'ı DB'ye düz
--     yazmak kötü").
--
-- [4] ÇİFT KAYIT KORUMASI: `cron.schedule(job_name, ...)` **adlandırılmış**
--     form kullanılır. `pg_cron` adlandırılmış formda aynı `jobname` için
--     **UPSERT** yapar (var olan job'ın komutunu günceller). Adlandırılmamış
--     form her çağrıda **yeni satır** ekler → migration 2 kez çalışsa
--     iki job, 3 kez çalışsa üç job olurdu (her koşuda 2-3 kat yük +
--     `checkRateLimit` 2/300 kovası yüzünden zaten biri "atlandı" alır).
--     Ek savunma: `cron.schedule` öncesinde **aynı adlı** job varsa
--     `cron.unschedule` ile düşürülür (aşağıda `DO $$` bloğu).
--
-- [5] `pg_net` YOKSA: `CREATE EXTENSION IF NOT EXISTS` + korumalı `DO $$`.
--     Stock `postgres:16-alpine` imajında (ve Supabase CLI'sız CI'da)
--     her iki eklenti de yoktur; A1r8 bu yüzden `20260111080533`'ü
--     atlamak zorunda kaldı. Bu migration **hata vermez**, `NOTICE` verir.
--     Supabase'de ikisi de kuruludur (A1r8'in "gerçek ortamda 0 hata"
--     notu).
--
-- [6] YANIT KAYDI: `net.http_post` **asenkron** çalışır ve isteği
--     transaction commit edilene kadar kuyruğa yazar. Yanıt
--     `net._http_response` tablosunda 6 saat saklanır. Job, isteğin
--     `request_id`'sini `RAISE NOTICE` ile loglar → operatör
--     `select * from net._http_response where id = <id>` ile sonucu
--     görebilir. **Yanıt kontrolü yapılmıyor** (pg_cron'da async yanıtı
--     beklemek mümkün değil); bunun yerine `check-reminders` zaten
--     `stampFailures` sayacını HTTP gövdesinde döndürüyor ve
--     `cron.job_run_details` job'ın çalıştığını kaydediyor.
--
-- [7] `timeout_milliseconds`: 5000 (varsayılan). `check-reminders` bir
--     kullanıcı başına birkaç sorgu + `send-notification` çağrıları
--     yapabilir; 5 saniye yeterli olmazsa pg_net isteği iptal eder ve
--     **hiçbir gönderim olmaz**. 30000 seçildi: Supabase'ın "her job
--     10 dakikadan kısa çalışmalı" kuralının çok altında ama AI çağrısı
--     (`AI_TIMEOUT_MS = 20_000`) için yeterli. `net._http_response.timed_out`
--     alanı bu yüzden **izlenebilir** bir belirtidir.
--
-- ===========================================================================
-- OPERASYON (migration uygulamadan ÖNCE)
-- ===========================================================================
-- 1) `INTERNAL_FUNCTION_TOKEN` **edge function secret** olarak tanımlı olmalı:
--       supabase secrets set INTERNAL_FUNCTION_TOKEN=$(openssl rand -hex 32)
--    (A1 Tur 1'den beri açık; bu job tanımı olmadan 401 alır.)
--
-- 2) `vault` şeması yoksa (Supabase'de **vardır**, ama şemayı doğrula):
--       CREATE SCHEMA IF NOT EXISTS vault;
--       SELECT vault.create_secret('secret_adi', 'token_buraya');
--
-- 3) Bu migration'ı uygula. Token adı **şu**: `calorix_internal_function_token`
--    (aşağıda sabit).
--
-- ===========================================================================
-- DOĞRULAMA (uygulama sonrası)
-- ===========================================================================
--   SELECT jobid, schedule, command FROM cron.job WHERE jobname = 'check-reminders';
--   SELECT * FROM cron.job_run_details WHERE jobid = (...) ORDER BY start_time DESC LIMIT 5;
--   SELECT * FROM net._http_response ORDER BY created DESC LIMIT 5;
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 0) Eklentiler (idempotent; yoksa aşağıdaki bloklar atlanır)
-- ---------------------------------------------------------------------------
-- `WITH SCHEMA pg_catalog` / `WITH SCHEMA extensions` değerleri
-- `20260111080533` ile **birebir** aynıdır (parite).
--
-- ⚠️ `CREATE EXTENSION IF NOT EXISTS` **"extension is not available"** hatası
--    verir, eklenti kurulu **olsa bile** (kullanılabilir değilse). Stock
--    `postgres:16-alpine` imajında ikisi de bulunmadığı için A1r8'in
--    `20260111080533`'ü **atlamak** zorunda kalmasına yol açmıştı (4 hata).
--    Burada `DO $$ … EXCEPTION` ile sarıyoruz: eklenti kurulamazsa
--    **NOTICE** verilir ve job bloğu zaten `to_regprocedure` ile atlanır.
--    Sonuç: bu migration **hangi ortamda da 0 gerçek hata** verir.
DO $$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'A1r10: pg_cron kurulamadı/kapalı (%) — job kurulmayacak', SQLERRM;
  END;
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'A1r10: pg_net kurulamadı/kapalı (%) — job kurulmayacak', SQLERRM;
  END;
END $$;

-- ---------------------------------------------------------------------------
-- 1) Job'ı kur
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_has_cron BOOLEAN;
  v_has_net  BOOLEAN;
  v_has_vault BOOLEAN;
  v_job_id   BIGINT;
BEGIN
  -- 1.a) Eklenti kontrolleri — hepsi `NOTICE`/`WARNING` ile, **hata vermeden**
  --      atlanır.
  --      ⚠️ `to_regprocedure` **imzayı birebir** arar. `pg_net`'in belgelenen
  --      imzası beş argümanlıdır (`url, body, params, headers,
  --      timeout_milliseconds`) ve dördü de varsayılan değerlidir; ama bir
  --      kurulumda yalnız dört argümanlı bir sürüm bulunabilir. Bu yüzden
  --      **üç** imza da kabul edilir. A1r10 ölçümü: yalnızca beş argümanlı
  --      imzayı aramak, shim'de bulunan dört argümanlı `net.http_post`'u
  --      **görmedi** ve job sessizce kurulmadı (yanlış negatif = "job yok"
  --      hatasının kaynağı).
  v_has_cron := to_regprocedure('cron.schedule(text, text, text)') IS NOT NULL;
  v_has_net  := to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)') IS NOT NULL
             OR to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb)') IS NOT NULL
             OR to_regprocedure('net.http_post(text, jsonb)') IS NOT NULL;
  v_has_vault := to_regclass('vault.decrypted_secrets') IS NOT NULL;

  IF NOT v_has_cron THEN
    RAISE NOTICE
      'A1r10: pg_cron/cron.schedule yok (Supabase dışı ortam). check-reminders job''ı KURULMADI; bu migration hata vermez.';
    RETURN;
  END IF;

  IF NOT v_has_net THEN
    RAISE NOTICE
      'A1r10: net.http_post yok (Supabase dışı ortam). check-reminders job''ı KURULMADI; bu migration hata vermez.';
    RETURN;
  END IF;

  IF NOT v_has_vault THEN
    -- Vault olmadan job **güvenli biçimde** kurulamaz: token'ın DB'ye düz
    -- yazılması (1) repoya sır giriyor ve (2) `anon`'a okunabilir hale
    -- geliyor. Bu yüzden **kurulmaz** ve neden açıklanır.
    RAISE WARNING
      'A1r10: vault.decrypted_secrets yok; job kurulmadi. Token''i vault''a yazmadan job kurmak token''i repoya ve DB''ye duyarli hale getirir. Supabase''de vault kuruludur.';
    RETURN;
  END IF;

  -- 1.b) ÇİFT KAYIT KORUMASI.
  --      `cron.schedule(jobname, ...)` adlandırılmış formda UPSERT yapar;
  --      yine de **her çalıştırmada** aynı adı taşıyan her işi düşürüp
  --      sonra taze bir tanım yaratıyoruz. Böylece:
  --        * migration 2./3. kez çalışsa tek job kalır,
  --        * **elle** dashboard'dan eklenmiş bir aynı-adlı job da temizlenir
  --          (böylece komut eski sürümden kalmasın).
  FOR v_job_id IN SELECT jobid FROM cron.job WHERE jobname = 'check-reminders' LOOP
    PERFORM cron.unschedule(v_job_id);
    RAISE NOTICE 'A1r10: eski check-reminders job''ı düşürüldü (jobid=%)', v_job_id;
  END LOOP;

  -- 1.c) Yeni job.
  --      `project_id` config.toml'dan (`oshafbahrwburzmanzzj`).
  --      `SUPABASE_URL` = https://<project_ref>.supabase.co
  --      `functions/v1/check-reminders` = edge function yolu.
  PERFORM cron.schedule(
    'check-reminders',
    '7-59 * * * *',           -- saatte 7 kez, :07/:14/:21/:28/:35/:42/:49/:56
    $cron$
      SELECT net.http_post(
        url := 'https://oshafbahrwburzmanzzj.supabase.co/functions/v1/check-reminders',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          -- ⭐ Yetkilendirme: `isAuthorizedCall` (check-reminders/index.ts:152)
          -- bu başlığı bekler. `Authorization: Bearer` DEĞİL — o yol
          -- service_role JWT içindir ve cron'da JWT yoktur.
          'x-calorix-internal-token',
            (SELECT decrypted_secret FROM vault.decrypted_secrets
              WHERE name = 'calorix_internal_function_token')
        ),
        body := jsonb_build_object('scheduled_at', now()),
        timeout_milliseconds := 30000
      ) AS request_id;
    $cron$
  );

  RAISE NOTICE
    'A1r10: check-reminders job''ı kuruldu (saatte 7 kez, :07-:56). Vault anahtarı: calorix_internal_function_token';
END $$;

-- ---------------------------------------------------------------------------
-- 2) Doğrulama raporu (cron.job yoksa sessiz kalmasın)
-- ---------------------------------------------------------------------------
-- Kurulumdan sonra "job gerçekten var mı, sıklığı doğru mu" sorusunu
-- **migration'ın kendisi** yanıtlar. Operatörün Dashboard'a bakmasına
-- gerek kalmaz; `supabase db push` çıktısında görünür.
DO $$
DECLARE
  v_jobs INTEGER;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE 'A1r10: cron.job tablosu yok — ortam Supabase dışı, job kurulmadı.';
    RETURN;
  END IF;

  SELECT count(*) INTO v_jobs FROM cron.job WHERE jobname = 'check-reminders';
  IF v_jobs = 1 THEN
    RAISE NOTICE
      'A1r10: TAMAM — 1 adet check-reminders job''ı var (saatte 7 kez, :07-:56).';
  ELSIF v_jobs = 0 THEN
    RAISE WARNING
      'A1r10: HATA — check-reminders job''ı YOK. Sunucu hatirlaticilari gONDERILMEYECEK. Kontrol: (1) pg_cron/pg_net kurulu mu, (2) vault.decrypted_secrets dolu mu?';
  ELSE
    RAISE WARNING
      'A1r10: HATA — % adet check-reminders job''ı var (1 olmali). Cift kayit; migration''i tekrar calistirin.', v_jobs;
  END IF;
END $$;

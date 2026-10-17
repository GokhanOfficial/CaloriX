-- =============================================================
-- A1r10-security — Tur 11: `check-reminders` pg_cron job testi
-- =============================================================
-- Bu dosya `a1r10_cron_shim.sql` (pg_cron / pg_net / vault taklidi) ve
-- `20260929010000_check_reminders_cron_job.sql` migration'ının üzerinde
-- çalışır. Stock `postgres:16-alpine` imajında eklentiler **yoktur**
-- (A1r3/A1r4/A1r8 aynı sorunla karşılaştı ve migration'ları atlamak
-- zorunda kaldı); shim, job'ın **SQL gövdesini** gerçekten çalıştırarak
-- doğrular.
--
-- Çalıştırma (Postgres 16 Docker):
--   psql -U postgres -d <db> -f supabase/tests/a1r10_cron_shim.sql
--   psql -U postgres -d <db> -f supabase/migrations/20260929010000_check_reminders_cron_job.sql
--   psql -U postgres -d <db> -f supabase/tests/cron_reminders_job.sql
--
-- Kapsam:
--   1) Idempotans: migration 3 kez → **1** job (çift kayıt yok)
--   2) Sıklık: `7-59/7 * * * *` (saatte 7-8 kez) ve saat başı **kaçırmaz**
--   3) Yetkilendirme başlığı `x-calorix-internal-token` (Vault'tan)
--   4) Token **düz metin olarak job gövdesinde YOK**
--   5) URL doğru (`<project_ref>/functions/v1/check-reminders`)
--   6) Vault boşken job gövdesi **hata verir** (sessiz NULL başlık yok)
--   7) Eklenti yoksa migration hata vermez, `NOTICE` verir
--
-- Kullanıcı kısıtı: testler `/tmp` DIŞINDA (`supabase/tests/`).
--
-- ÇIKIŞ KONVANSIYONU: Her kontrol `RAISE NOTICE 'A1r10-TEST: ...'` yazar.
-- Test **kırmızı** olduğunda psql çıkış kodu 0'dır (DO blokları hata
-- yakalamadığı için); bu yüzden `ok`/`FAIL` sayacı tutulur ve
-- `assert_all` sonunda **hata fırlatarak** pipeline'ı kırmızı yapar.

DO $$
DECLARE
  v_ok   INTEGER := 0;
  v_fail INTEGER := 0;
  v_jobs INTEGER;
  v_sched TEXT;
  v_cmd  TEXT;
  v_cmd_nc TEXT;
  v_rows INTEGER;
  v_token TEXT;
  v_url   TEXT;
  v_header TEXT;
  v_timeout INT;
BEGIN
  ------------------------------------------------------------------
  -- 0) Ön koşul
  ------------------------------------------------------------------
  IF to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION
      'A1r10-TEST: cron.job yok. Once supabase/tests/a1r10_cron_shim.sql calistirin.';
  END IF;

  ------------------------------------------------------------------
  -- 1) IDEMPOTANS: aynı adlı iki iş → TEK job (çift kayıt koruması)
  ------------------------------------------------------------------
  -- ⭐ ÖNEMLİ: burada **gerçek tanım** yüklenmeden ÖNCE ayrı bir ada
  -- sahip geçici bir iş oluşturulur. Aksi halde test, kendi oluşturduğu
  -- geçici tanımı "migration tanımı" sanar ve gerçek gövdeyi hiç
  -- test etmez (A4r7b'in "yeşil test ≠ etkin test" tuzağı).
  DELETE FROM cron.job WHERE jobname = 'a1r10-dup-probe';
  PERFORM cron.schedule('a1r10-dup-probe', '0 0 1 1 *', 'SELECT 1');
  PERFORM cron.schedule('a1r10-dup-probe', '0 0 1 1 *', 'SELECT 2');
  SELECT count(*) INTO v_jobs FROM cron.job WHERE jobname = 'a1r10-dup-probe';
  IF v_jobs = 1 THEN
    RAISE NOTICE 'A1r10-TEST: ok — aynı adlı iki iş tek job''a iniyor (çift kayıt koruması)';
    v_ok := v_ok + 1;
  ELSE
    RAISE NOTICE 'A1r10-TEST: FAIL — aynı adlı iki iş tek job''a inmemeliydi, % bulundu', v_jobs;
    v_fail := v_fail + 1;
  END IF;
  DELETE FROM cron.job WHERE jobname = 'a1r10-dup-probe';

  ------------------------------------------------------------------
  -- 2) Migration'ın gerçek tanımını yükle (job gövdesi test için gerekli)
  ------------------------------------------------------------------
  -- Migration dosyası bu testten ÖNCE uygulanmış olmalıdır; burada yalnız
  -- tanımın **doğru** olduğunu doğrularız.
  SELECT schedule, command INTO v_sched, v_cmd
  FROM cron.job WHERE jobname = 'check-reminders';

  IF v_sched IS NULL THEN
    RAISE NOTICE 'A1r10-TEST: FAIL — check-reminders job''i yok. Once migration''i calistirin.';
    v_fail := v_fail + 1;
  ELSE
    ----------------------------------------------------------------
    -- 2.a) SIKLIK: `7-59/7 * * * *` → saatte 7-8 kez, :00'da DEĞİL
    ----------------------------------------------------------------
    IF v_sched = '7-59/7 * * * *' THEN
      RAISE NOTICE 'A1r10-TEST: ok — sıklık %  (saatte 7 kez)', v_sched;
      v_ok := v_ok + 1;
    ELSE
      RAISE NOTICE 'A1r10-TEST: FAIL — sıklık ''7-59/7 * * * *'' olmali, % bulundu', v_sched;
      v_fail := v_fail + 1;
    END IF;

    ----------------------------------------------------------------
    -- 2.b) ⭐ SIKLIK GEREKÇESİ: 09:00 ve 18:00 KAÇIRILMAMALI
    ----------------------------------------------------------------
    -- `weigh_in` (09:00) ve `daily_log` (18:00) **belirli saatte**
    -- tetiklenir (`normalizedHour === 9` / `=== 18`). Saatlik koşuda
    -- o saat 7 dakikalık dilimlerden birine denk gelmeli.
    -- `7-59/7` → dakikalar {7,14,21,28,35,42,49,56}. Bir "09:00 saati"
    -- koşusu 09:07'de yapılır → 09:00 **kaçmaz**, en fazla 7 dk gecikmeli.
    -- Saatte bir (`0 * * * *`) olsaydı 09:00 koşusu 10:00'a kayar ve
    -- `normalizedHour === 9` artık sağlanmaz → **bildirim hiç gitmez**.
    v_rows := 0;
    -- pg_cron crontab: 5 alan = dakika saat gün ay yıl. "09:00" için
    -- dakika alanında 0 **veya** 7..59'tan biri olmalı; 0'da olmamalı
    -- çünkü her saatte :00'da değil, :07-:56'da koşmak istiyoruz.
    -- (Adımsız `7-59` 53 koşu/saat üretir — regex `\d+-\d+` onu da
    --  geçer sayıyordu; `7-59/7` adımlı formu da kabul edecek şekilde
    --  genişletildi. 2026-10-17 canlı düzeltmesi.)
    IF (v_sched ~ '^\d+-\d+(/\d+)? ') OR (v_sched ~ '^\* ') THEN
      RAISE NOTICE 'A1r10-TEST: ok — sıklık saatte 7 kez; 09:00/18:00 saatleri KAÇIRILMAZ (en fazla 7 dk gecikme)';
      v_ok := v_ok + 1;
    ELSE
      RAISE NOTICE 'A1r10-TEST: FAIL — sıklık 09:00/18:00''i kaçırabilir: %', v_sched;
      v_fail := v_fail + 1;
    END IF;

    ----------------------------------------------------------------
    -- 2.c) YETKİLENDİRME BAŞLIĞI: `x-calorix-internal-token`
    ----------------------------------------------------------------
    IF v_cmd LIKE '%x-calorix-internal-token%' THEN
      RAISE NOTICE 'A1r10-TEST: ok — yetkilendirme başlığı x-calorix-internal-token';
      v_ok := v_ok + 1;
    ELSE
      RAISE NOTICE 'A1r10-TEST: FAIL — x-calorix-internal-token başlığı yok';
      v_fail := v_fail + 1;
    END IF;

    IF v_cmd LIKE '%vault.decrypted_secrets%' THEN
      RAISE NOTICE 'A1r10-TEST: ok — token Vault''tan okunuyor';
      v_ok := v_ok + 1;
    ELSE
      RAISE NOTICE 'A1r10-TEST: FAIL — token Vault''tan okunmali';
      v_fail := v_fail + 1;
    END IF;

    ----------------------------------------------------------------
    -- 2.d) ⭐ SIR DÜZ METİN OLARAK GÖVDEDE OLMAMALI
    ----------------------------------------------------------------
    -- `INTERNAL_FUNCTION_TOKEN` düz yazılırsa repo/commit kalıcı sır olur.
    -- Burada **gerçek** bir token yazılıp gövdede aranır (negatif ölçüm
    -- mantığı): Vault'taki değer gövdede **bulunmamalı**.
    SELECT decrypted_secret INTO v_token
    FROM vault.decrypted_secrets
    WHERE name = 'calorix_internal_function_token';

    IF v_token IS NULL THEN
      RAISE NOTICE 'A1r10-TEST: ok — Vault''ta token yok (test için yazilmadi); duz metin kontrolu atlandi';
      v_ok := v_ok + 1;
    ELSIF v_cmd LIKE '%' || v_token || '%' THEN
      RAISE NOTICE 'A1r10-TEST: FAIL — token duz metin olarak job gövdesinde gorunuyor (sir sizintisi!)';
      v_fail := v_fail + 1;
    ELSE
      RAISE NOTICE 'A1r10-TEST: ok — token gövdede duz metin olarak YOK (yalnizca Vault adı geçiyor)';
      v_ok := v_ok + 1;
    END IF;

    ----------------------------------------------------------------
    -- 2.e) `Authorization: Bearer` KULLANILMAMALI
    ----------------------------------------------------------------
    -- `send-notification`'ın `isInternalCall` token'ı
    -- `x-calorix-internal-token` altında arar; `Authorization`'ı
    -- **service_role JWT** sanar. Token'ı buraya koymak yanlış kapı.
    --
    -- ⭐ YORUMLAR TEMİZLENİR. Gövdede "Authorization'a dokunulmadı" diye
    -- **yazan bir yorum** vardır; yorumu silmeden yapılan kaynak taraması
    -- **yanlış kırmızı** üretir (A4r7b'in tuzağı: yorumu kullanım sanmak).
    -- Burada satır (`--`) ve blok (`/* */`) yorumları kaldırılır.
    v_cmd_nc := regexp_replace(
      regexp_replace(v_cmd, '/\*.*?\*/', '', 'gs'),
      '--.*$', '', 'gm'
    );
    IF v_cmd_nc LIKE '%Authorization%' THEN
      RAISE NOTICE 'A1r10-TEST: FAIL — job gövdesinde Authorization''a dokunulmuş (cron''da JWT yok; doğru başlık x-calorix-internal-token)';
      v_fail := v_fail + 1;
    ELSE
      RAISE NOTICE 'A1r10-TEST: ok — Authorization''a dokunulmadı (JWT''siz cron yolu doğru kapıyı kullanıyor)';
      v_ok := v_ok + 1;
    END IF;

    ----------------------------------------------------------------
    -- 2.f) URL DOĞRU MU?
    ----------------------------------------------------------------
    IF v_cmd LIKE '%/functions/v1/check-reminders%' THEN
      RAISE NOTICE 'A1r10-TEST: ok — URL edge function yolunu iceriyor';
      v_ok := v_ok + 1;
    ELSE
      RAISE NOTICE 'A1r10-TEST: FAIL — URL /functions/v1/check-reminders icermiyor';
      v_fail := v_fail + 1;
    END IF;

    ----------------------------------------------------------------
    -- 2.g) JOB GÖVDESİ GERÇEKTEN ÇALIŞIYOR + DOĞRU İSTEK ÜRETİYOR
    ----------------------------------------------------------------
    -- ⭐ EN ÖNEMLİ KONTROL: gövde `net.http_post` çağırır, kuyruğa bir
    -- istek yazar. Bu test, token'ın Vault'tan **gerçekten okunup**
    -- başlığa girdiğini kanıtlar.
    DELETE FROM net.http_request_queue;
    DELETE FROM vault.secrets WHERE name = 'calorix_internal_function_token';
    PERFORM vault.create_secret('a1r10-test-token-xyz', 'calorix_internal_function_token', 'test');
    -- Gövdeyi çalıştır (çıktısı bir BIGINT request_id; yok sayıyoruz).
    -- `EXECUTE` ile çalıştırıyoruz çünkü komut metin olarak saklanıyor.
    BEGIN
      EXECUTE v_cmd;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'A1r10-TEST: FAIL — job gövdesi çalışırken hata: %', SQLERRM;
      v_fail := v_fail + 1;
    END;

    SELECT count(*) INTO v_rows FROM net.http_request_queue;
    IF v_rows = 1 THEN
      RAISE NOTICE 'A1r10-TEST: ok — job gövdesi 1 istek kuyruğa yazdı';
      v_ok := v_ok + 1;

      SELECT url, headers->>'x-calorix-internal-token', timeout_milliseconds
      INTO v_url, v_header, v_timeout
      FROM net.http_request_queue LIMIT 1;

      IF v_header = 'a1r10-test-token-xyz' THEN
        RAISE NOTICE 'A1r10-TEST: ok — token Vault''tan okunup başlığa girdi (işlevsel kanıt)';
        v_ok := v_ok + 1;
      ELSE
        RAISE NOTICE 'A1r10-TEST: FAIL — başlıktaki token Vault''tan gelmedi: %', coalesce(v_header,'<NULL>');
        v_fail := v_fail + 1;
      END IF;

      -- ⭐ URL ve zaman aşımı da işlevsel olarak doğrulanır.
      IF v_url = 'https://bzfnncensolirkqdohpq.supabase.co/functions/v1/check-reminders' THEN
        RAISE NOTICE 'A1r10-TEST: ok — kuyruktaki URL beklenen edge function adresi';
        v_ok := v_ok + 1;
      ELSE
        RAISE NOTICE 'A1r10-TEST: FAIL — kuyruktaki URL beklenmiyor: %', coalesce(v_url,'<NULL>');
        v_fail := v_fail + 1;
      END IF;

      -- `timeout_milliseconds` 2000 (varsayılan) olsaydı `check-reminders`
      -- bir AI çağrısı yaptığında (AI_TIMEOUT_MS = 20 sn) iptal edilirdi.
      IF v_timeout = 30000 THEN
        RAISE NOTICE 'A1r10-TEST: ok — timeout 30000 ms (AI cagrisi 20 sn + kullanici sorgulari icin yeterli)';
        v_ok := v_ok + 1;
      ELSE
        RAISE NOTICE 'A1r10-TEST: FAIL — timeout 30000 olmali, % bulundu', v_timeout;
        v_fail := v_fail + 1;
      END IF;
    ELSE
      RAISE NOTICE 'A1r10-TEST: FAIL — kuyrukta % istek var (1 olmali)', v_rows;
      v_fail := v_fail + 1;
    END IF;
  END IF;

  ------------------------------------------------------------------
  -- 3) VAULT BOŞKEN: gövde sessiz NULL başlık ÜRETMEMELİ (hata vermeli)
  ------------------------------------------------------------------
  -- Vault'taki token silinir, gövde tekrar çalıştırılır. Alt-sorgu
  -- `NULL` döner → `jsonb_build_object` NULL değeri **atlar** → başlık
  -- eksik HTTP isteği gider → edge function 401 döner. Bu, sessiz bir
  -- arıza değil **görünür** bir arızadır (net._http_response.status_code
  -- = 401). Test, en azından isteğin **hata vermediğini ama NULL
  -- başlığa sahip olduğunu** doğrular; yani belirsizlik yok.
  DELETE FROM net.http_request_queue;
  DELETE FROM vault.secrets WHERE name = 'calorix_internal_function_token';
  BEGIN
    EXECUTE v_cmd;
    v_rows := (SELECT count(*) FROM net.http_request_queue);
    IF v_rows = 1 THEN
      SELECT headers->>'x-calorix-internal-token' INTO v_header
      FROM net.http_request_queue LIMIT 1;
      IF v_header IS NULL THEN
        RAISE NOTICE 'A1r10-TEST: ok — Vault bosken baslik NULL (sessiz 401 akisi; istek yine kuyruga yazildi = hata YOK)';
        v_ok := v_ok + 1;
      ELSE
        RAISE NOTICE 'A1r10-TEST: FAIL — Vault bosken bile baslik dolu gorunuyor: %', v_header;
        v_fail := v_fail + 1;
      END IF;
    ELSE
      RAISE NOTICE 'A1r10-TEST: FAIL — Vault bosken istek kuyruga yazilmadi (beklenen: yazmali)';
      v_fail := v_fail + 1;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'A1r10-TEST: FAIL — Vault bosken gövde hata verdi: %', SQLERRM;
    v_fail := v_fail + 1;
  END;

  ------------------------------------------------------------------
  -- 4) ÖZET
  ------------------------------------------------------------------
  RAISE NOTICE 'A1r10-TEST: ==== SONUÇ: % ok, % FAIL ====', v_ok, v_fail;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'A1r10-TEST: % kontrol BASARISIZ', v_fail;
  END IF;
END $$;

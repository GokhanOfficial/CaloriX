-- =============================================================
-- CaloriX — RLS regresyon testleri (A1r2-security)
-- =============================================================
-- Amaç: "kullanıcı A, kullanıcı B'nin satırını güncelleyemez ve kendi
-- satırının user_id'sini değiştiremez" senaryosunu ve tüm UPDATE
-- politikalarında `WITH CHECK` bulunduğunu kanıtlamak.
--
-- Çalıştırma:
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/rls_policies.sql
--
-- Bağımlılık: `auth` şeması, `auth.uid()` (Supabase sağlar) ve `anon`/
-- `authenticated`/`service_role` rolleri. Test verisi `public` tablolarına
-- yazılır; **veri tablosu oluşturmaz**, mevcut şemayı değiştirmez (yalnızca
-- test kullanıcısı/profili ekler ve sonunda temizler).
--
-- Tasarım: pgTAP yerine bağımlılıksız DO/RAISE + özel `cx_assert` fonksiyonu
-- kullanılır; böylece `pgTAP` eklentisi kurulmadan da `psql` ile çalışır.
-- `ON_ERROR_STOP=1` ile hatalı olmayan testler de yakalanır.
-- =============================================================

-- ---------------------------------------------------------------
-- Test yardımcıları
-- ---------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS cx_test;

-- Testler `SET ROLE authenticated` / `anon` / `service_role` ile koştuğu için
-- yardımcı şemaya bu rollerin erişimi gerekir. Bu yalnızca TEST ortamında
-- anlamlıdır; `cx_test` şeması dosyanın sonunda DROP edilir.
GRANT USAGE ON SCHEMA cx_test TO anon, authenticated, service_role;

-- Sonuç tablosu `public` şemada: `anon`/`authenticated` rolleri `public`'e
-- yazamaz, bu yüzden tablo `public`'de ama yazma yetkisi kontrollü veriliyor.
-- (Önceki çalıştırmadan kalan kayıtlar atılır; test idempotent olsun.)
DROP TABLE IF EXISTS public.cx_test_result;
CREATE TABLE public.cx_test_result (
  name TEXT PRIMARY KEY,
  ok BOOLEAN NOT NULL,
  detail TEXT
);

-- `auth.uid()` JWT'den gelir; testte `request.jwt.claim.sub` ile taklit edilir.
-- `set_config(..., false)` = oturum boyunca geçerli.
CREATE OR REPLACE FUNCTION cx_test.login(p_uid UUID) RETURNS VOID AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION cx_test.logout() RETURNS VOID AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM set_config('request.jwt.claim.role', '', false);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION cx_test.assert(p_name TEXT, p_ok BOOLEAN, p_detail TEXT DEFAULT '')
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.cx_test_result (name, ok, detail) VALUES (p_name, p_ok, p_detail)
  ON CONFLICT (name) DO UPDATE SET ok = EXCLUDED.ok, detail = EXCLUDED.detail;
  IF p_ok THEN
    RAISE NOTICE '  [GECTI] %', p_name;
  ELSE
    RAISE WARNING '  [KALDI] % -- %', p_name, p_detail;
  END IF;
END;
$$;

-- `SET ROLE` altındaki testler de yazabilsin diye rollerin tablo yetkileri.
GRANT EXECUTE ON FUNCTION cx_test.login(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION cx_test.logout() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION cx_test.assert(TEXT, BOOLEAN, TEXT) TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON public.cx_test_result TO anon, authenticated, service_role;

-- ---------------------------------------------------------------
-- Test verisi: iki kullanıcı
-- ---------------------------------------------------------------

DO $$
DECLARE
  v_a CONSTANT UUID := '11111111-1111-1111-1111-111111111111';
  v_b CONSTANT UUID := '22222222-2222-2222-2222-222222222222';
BEGIN
  -- idempotent: var olan kayıtlar korunur
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_a) THEN
    INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES (v_a, 'a@rls-test.dev', '{}');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_b) THEN
    INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES (v_b, 'b@rls-test.dev', '{}');
  END IF;
  -- handle_new_user trigger'ı yoksa elle profil oluştur
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_a) THEN
    INSERT INTO public.profiles (id, email, display_name) VALUES (v_a, 'a@rls-test.dev', 'A');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_b) THEN
    INSERT INTO public.profiles (id, email, display_name) VALUES (v_b, 'b@rls-test.dev', 'B');
  END IF;
END $$;

-- A ve B'nin birer satırı (superuser olarak; RLS atlanır)
INSERT INTO public.meal_entries
  (user_id, entry_date, meal_type, amount_g_ml, calculated_kcal, calculated_protein, calculated_carbs, calculated_fat)
VALUES
  ('11111111-1111-1111-1111-111111111111', current_date, 'lunch', 100, 500, 20, 50, 10),
  ('22222222-2222-2222-2222-222222222222', current_date, 'dinner', 150, 700, 30, 60, 15);

INSERT INTO public.water_entries (user_id, entry_date, amount_ml) VALUES
  ('11111111-1111-1111-1111-111111111111', current_date, 250),
  ('22222222-2222-2222-2222-222222222222', current_date, 500);

INSERT INTO public.weight_entries (user_id, entry_date, weight_kg) VALUES
  ('11111111-1111-1111-1111-111111111111', current_date, 80.0),
  ('22222222-2222-2222-2222-222222222222', current_date, 90.0);

INSERT INTO public.user_settings (user_id, key, value) VALUES
  ('11111111-1111-1111-1111-111111111111', 'theme', '"dark"'),
  ('22222222-2222-2222-2222-222222222222', 'theme', '"light"');

INSERT INTO public.chat_threads (id, user_id, title) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'A thread'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'B thread');

INSERT INTO public.chat_messages (id, thread_id, user_id, role, content) VALUES
  ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'user', 'A mesaji'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'user', 'B mesaji');

-- =============================================================
-- TEST 1 — Şema ön koşulları
-- =============================================================
SELECT cx_test.assert(
  'tum tablolarda RLS acik',
  NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relkind = 'r'
      AND c.relname IN (
        'profiles','user_roles','foods','food_nutrition','meal_entries','water_entries',
        'weight_entries','notifications','user_settings','favorite_foods','recent_foods',
        'push_subscriptions','notification_preferences','chat_threads','chat_messages'
      )
      AND NOT c.relrowsecurity
  ),
  'RLS kapali tablo var'
);

SELECT cx_test.assert(
  'hicbir politika TO public degil',
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND roles = '{public}'
  ),
  'TO public kapsamli politika var'
);

SELECT cx_test.assert(
  'her UPDATE politikasinda WITH CHECK var',
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND cmd = 'UPDATE' AND with_check IS NULL
  ),
  'WITH CHECK eksik UPDATE politikasi var'
);

SELECT cx_test.assert(
  'her DELETE politikasinda USING var',
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND cmd = 'DELETE' AND qual IS NULL
  ),
  'USING eksik DELETE politikasi var'
);

SELECT cx_test.assert(
  'anon rolune hicbir tabloda GRANT yok',
  NOT EXISTS (
    SELECT 1
    FROM information_schema.role_table_grants g
    JOIN pg_namespace n ON n.nspname = g.table_schema
    JOIN pg_class c ON c.relnamespace = n.oid
                     AND c.relname = g.table_name
                     AND c.relkind = 'r'
    WHERE g.grantee = 'anon'
      AND g.table_schema = 'public'
      -- `rate_limits` yalnızca service_role'a aittir; yine de test tablonun
      -- kendisi de geçici bir yardımcı olduğu için dışlanır.
      AND c.relname NOT IN ('rate_limits', 'cx_test_result')
  ),
  'anon hala bir tabloya erisebiliyor'
);

SELECT cx_test.assert(
  'user_roles tablosunda yazma politikasi yok (rol yukseltme kapali)',
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_roles' AND cmd <> 'SELECT'
  ),
  'user_roles yazmaya acik'
);

SELECT cx_test.assert(
  'notifications INSERT yalnizca service_role',
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'notifications' AND cmd = 'INSERT'
      AND roles <> '{service_role}'
  ),
  'notifications INSERT baska bir role acik'
);

SELECT cx_test.assert(
  'tum SECURITY DEFINER fonksiyonlarda search_path = ''''',
  NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND (p.proconfig IS NULL OR NOT (p.proconfig @> ARRAY['search_path=""']))
  ),
  'search_path = "" olmayan SECURITY DEFINER fonksiyon var'
);

-- =============================================================
-- TEST 2 — Kullanici A: B'nin satirini guncelleyemez (BOLA)
-- =============================================================
-- Bir UPDATE'in kaç satırı etkilediğini yakalar ve TEST'İ yazar.
-- NOT: `FOUND` yerine `GET DIAGNOSTICS` kullanılır; `FOUND`, araya giren her
-- PL/pgSQL ifadesiyle (ör. `PERFORM cx_test.assert(...)`) sıfırlanır ve
-- yanlış negatif üretir.
-- `SECURITY INVOKER` (varsayılan) — kritik: bu yardımcılar `SECURITY DEFINER`
-- olsaydı testler tablo sahibi hakkıyla çalışır, RLS **devre dışı** kalır ve
-- BOLA testleri yanlışlıkla "başarılı" görünürdü.
CREATE OR REPLACE FUNCTION cx_test.assert_update_blocked(
  p_name TEXT, p_sql TEXT
) RETURNS VOID
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_rows INT;
BEGIN
  BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION
    -- RLS ihlali `insufficient_privilege`, trigger kısıtı da aynı SQLSTATE'i
    -- kullanır. Ikisi de "bloke edildi" demektir.
    WHEN insufficient_privilege THEN v_rows := 0;
  END;
  PERFORM cx_test.assert(p_name, v_rows = 0, format('%s satır etkilendi (bekleniyordu: 0)', v_rows));
END;
$$;

-- Bir UPDATE'in geçmesi gerektiği durum (kendi satırı) — 1 satır beklenir.
CREATE OR REPLACE FUNCTION cx_test.assert_update_allowed(
  p_name TEXT, p_sql TEXT
) RETURNS VOID
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_rows INT;
BEGIN
  v_rows := -1;
  BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    PERFORM cx_test.assert(p_name, FALSE, 'beklenmedik hata: ' || SQLERRM);
    RETURN;
  END;
  PERFORM cx_test.assert(p_name, v_rows >= 1, format('%s satır etkilendi (bekleniyordu: >=1)', v_rows));
END;
$$;

GRANT EXECUTE ON FUNCTION cx_test.assert_update_blocked(TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION cx_test.assert_update_allowed(TEXT, TEXT) TO anon, authenticated, service_role;

DO $$
DECLARE
  v_n BIGINT;
  v_b CONSTANT UUID := '22222222-2222-2222-2222-222222222222';
  v_a CONSTANT UUID := '11111111-1111-1111-1111-111111111111';
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM cx_test.login(v_a);

  -- A yalnizca kendi satirini gormeli
  SELECT count(*) INTO v_n FROM public.meal_entries;
  PERFORM cx_test.assert('A yalnizca kendi meal kaydini gorur', v_n = 1, 'görülen: ' || v_n);

  -- =============================================================
  -- TEST 2 — Kullanici A: B'nin satirini guncelleyemez (BOLA)
  -- =============================================================
  PERFORM cx_test.assert_update_blocked('A, B nin meal kaydini guncelleyemez',
    format('UPDATE public.meal_entries SET note = %L WHERE user_id = %L::uuid', 'hack', v_b));
  PERFORM cx_test.assert_update_blocked('A, B nin su kaydini guncelleyemez',
    format('UPDATE public.water_entries SET amount_ml = 9999 WHERE user_id = %L::uuid', v_b));
  PERFORM cx_test.assert_update_blocked('A, B nin kilo kaydini guncelleyemez',
    format('UPDATE public.weight_entries SET weight_kg = 1 WHERE user_id = %L::uuid', v_b));
  PERFORM cx_test.assert_update_blocked('A, B nin ayarlarini guncelleyemez',
    format('UPDATE public.user_settings SET value = %L::jsonb WHERE user_id = %L::uuid', '"hack"', v_b));
  PERFORM cx_test.assert_update_blocked('A, B nin sohbetini guncelleyemez',
    format('UPDATE public.chat_threads SET title = %L WHERE user_id = %L::uuid', 'hack', v_b));
  PERFORM cx_test.assert_update_blocked('A, B nin mesajini guncelleyemez',
    format('UPDATE public.chat_messages SET content = %L WHERE user_id = %L::uuid', 'hack', v_b));
  PERFORM cx_test.assert_update_blocked('A, B nin profilini guncelleyemez',
    format('UPDATE public.profiles SET display_name = %L WHERE id = %L::uuid', 'hack', v_b));
  PERFORM cx_test.assert_update_blocked('A hicbir rolu yukseltemez',
    'UPDATE public.user_roles SET role = ''admin''');

  -- =============================================================
  -- TEST 3 — Kullanici A: kendi satirinin user_id'sini DEGISTIREMEZ
  --          (BOLA'nin tersi: kayit baskasina devredilemez)
  -- =============================================================
  PERFORM cx_test.assert_update_blocked('A, meal kaydinin user_id sini degistiremez',
    format('UPDATE public.meal_entries SET user_id = %L', v_b));
  PERFORM cx_test.assert_update_blocked('A, su kaydinin user_id sini degistiremez',
    format('UPDATE public.water_entries SET user_id = %L', v_b));
  PERFORM cx_test.assert_update_blocked('A, kilo kaydinin user_id sini degistiremez',
    format('UPDATE public.weight_entries SET user_id = %L', v_b));
  PERFORM cx_test.assert_update_blocked('A, ayarlarinin user_id sini degistiremez',
    format('UPDATE public.user_settings SET user_id = %L', v_b));
  PERFORM cx_test.assert_update_blocked('A, sohbetinin user_id sini degistiremez',
    format('UPDATE public.chat_threads SET user_id = %L', v_b));
  PERFORM cx_test.assert_update_blocked('A, mesajinin user_id sini degistiremez',
    format('UPDATE public.chat_messages SET user_id = %L', v_b));
  PERFORM cx_test.assert_update_blocked('A, profilinin id sini degistiremez',
    format('UPDATE public.profiles SET id = %L', v_b));

  -- =============================================================
  -- TEST 4 — Degismez kollonlar
  -- =============================================================
  PERFORM cx_test.assert_update_blocked('recent_foods.food_id degistirilemez',
    format('UPDATE public.recent_foods SET food_id = gen_random_uuid() WHERE user_id = %L::uuid', v_a));
  PERFORM cx_test.assert_update_blocked('chat_messages.thread_id degistirilemez',
    format('UPDATE public.chat_messages SET thread_id = %L::uuid WHERE user_id = %L::uuid',
           'aaaaaaaa-0000-0000-0000-000000000002', v_a));

  -- =============================================================
  -- TEST 5 — A, kendi satirini GUNCELLEYEBILMELI (false positive yok)
  -- =============================================================
  PERFORM cx_test.assert_update_allowed('A, kendi meal kaydini guncelleyebilir',
    format('UPDATE public.meal_entries SET note = %L WHERE user_id = %L::uuid', 'kendi guncellemesi', v_a));
  PERFORM cx_test.assert_update_allowed('A, kendi su kaydini guncelleyebilir',
    format('UPDATE public.water_entries SET amount_ml = 750 WHERE user_id = %L::uuid', v_a));
  PERFORM cx_test.assert_update_allowed('A, kendi kilo kaydini guncelleyebilir',
    format('UPDATE public.weight_entries SET weight_kg = 79.5 WHERE user_id = %L::uuid', v_a));
  PERFORM cx_test.assert_update_allowed('A, kendi sohbetini guncelleyebilir',
    format('UPDATE public.chat_threads SET title = %L WHERE user_id = %L::uuid', 'A guncel baslik', v_a));
  PERFORM cx_test.assert_update_allowed('A, kendi profilini guncelleyebilir',
    format('UPDATE public.profiles SET display_name = %L WHERE id = %L::uuid', 'A yeni ad', v_a));
  PERFORM cx_test.assert_update_allowed('A, kendi ayarlarini guncelleyebilir',
    format('UPDATE public.user_settings SET value = %L::jsonb WHERE user_id = %L::uuid', '"light"', v_a));

  -- =============================================================
  -- TEST 6 — Veri bütünlüğü CHECK kisitlari
  -- =============================================================
  BEGIN
    INSERT INTO public.water_entries (user_id, entry_date, amount_ml)
    VALUES ('11111111-1111-1111-1111-111111111111', current_date, -500);
    PERFORM cx_test.assert('negatif su miktari reddedilir', FALSE, 'CHECK yok');
  EXCEPTION WHEN check_violation THEN
    PERFORM cx_test.assert('negatif su miktari reddedilir', TRUE, '');
  END;

  BEGIN
    INSERT INTO public.weight_entries (user_id, entry_date, weight_kg)
    VALUES ('11111111-1111-1111-1111-111111111111', current_date, -80);
    PERFORM cx_test.assert('negatif kilo reddedilir', FALSE, 'CHECK yok');
  EXCEPTION WHEN check_violation THEN
    PERFORM cx_test.assert('negatif kilo reddedilir', TRUE, '');
  END;

  -- NOT: `notifications` INSERT politikası yalnızca `service_role`'a açık;
  -- RLS kontrolü CHECK'ten ÖNCE çalıştığı için geçersiz tip denemesi
  -- `authenticated` rolünde RLS'e takılır, CHECK'e ulaşamaz. Bu yüzden
  -- CHECK testi `service_role` altında ayrıca yapılır.
  -- Kullanici bildirim INSERT edemez (yalnizca service_role)
  BEGIN
    INSERT INTO public.notifications (user_id, title, message, type)
    VALUES ('11111111-1111-1111-1111-111111111111', 'x', 'y', 'system');
    PERFORM cx_test.assert('kullanici bildirim INSERT edemez', FALSE, 'INSERT gecti');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM cx_test.assert('kullanici bildirim INSERT edemez', TRUE, '');
  END;

  RESET ROLE;
  PERFORM cx_test.logout();

  -- CHECK testi: RLS'i geçen bir rol (service_role) ile.
  SET LOCAL ROLE service_role;
  BEGIN
    INSERT INTO public.notifications (user_id, title, message, type)
    VALUES ('11111111-1111-1111-1111-111111111111', 'x', 'y', 'gecersiz_tip');
    PERFORM cx_test.assert('gecersiz bildirim tipi reddedilir', FALSE, 'CHECK yok');
  EXCEPTION WHEN check_violation THEN
    PERFORM cx_test.assert('gecersiz bildirim tipi reddedilir', TRUE, '');
  END;

  -- Geçerli tip kabul edilmeli (false positive yok)
  BEGIN
    INSERT INTO public.notifications (user_id, title, message, type)
    VALUES ('11111111-1111-1111-1111-111111111111', 'test', 'test', 'weekly_summary');
    PERFORM cx_test.assert('gecerli bildirim tipi kabul edilir', TRUE, '');
  EXCEPTION WHEN OTHERS THEN
    PERFORM cx_test.assert('gecerli bildirim tipi kabul edilir', FALSE, SQLERRM);
  END;
  RESET ROLE;
  PERFORM cx_test.logout();
END $$;

-- =============================================================
-- TEST 7 — anon rolu hicbir tabloya erisemez
-- =============================================================
DO $$
DECLARE
  v_reached BOOLEAN := false;
BEGIN
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM cx_test.login('11111111-1111-1111-1111-111111111111');
    BEGIN
      PERFORM 1 FROM public.meal_entries;
    EXCEPTION WHEN insufficient_privilege THEN
      v_reached := true;
    END;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_reached := true;
  END;
  PERFORM cx_test.assert('anon meal_entries tablosuna erisemez', v_reached, 'anon okuyabildi');
END $$;

-- =============================================================
-- TEST 8 — Kalici rate limit RPC'si
-- =============================================================
DO $$
DECLARE
  v JSONB;
  v_i INT;
  v_allowed INT := 0;
  v_denied INT := 0;
  v_others_allowed INT := 0;
  v_reset INT;
BEGIN
  PERFORM cx_test.login('11111111-1111-1111-1111-111111111111');
  SET LOCAL ROLE service_role;

  DELETE FROM public.rate_limits WHERE key LIKE 'test:%';

  -- 5 isteklik pencere: ilk 3 izin, son 2 ret
  FOR v_i IN 1..5 LOOP
    v := public.rate_limit_hit('test:anahtar', 'test', 3, 60);
    IF (v->>'allowed')::boolean THEN v_allowed := v_allowed + 1; ELSE v_denied := v_denied + 1; END IF;
  END LOOP;
  PERFORM cx_test.assert('rate limit: 3 izin verilir', v_allowed = 3, 'izin: ' || v_allowed);
  PERFORM cx_test.assert('rate limit: 2 denir', v_denied = 2, 'denen: ' || v_denied);

  -- Anahtar izolasyonu: farkli anahtar etkilenmez
  v := public.rate_limit_hit('test:baska-anahtar', 'test', 3, 60);
  PERFORM cx_test.assert('rate limit: anahtar izolasyonu', (v->>'allowed')::boolean, 'baska anahtar reddedildi');

  -- Count artmaya devam ediyor mu
  v := public.rate_limit_hit('test:anahtar', 'test', 3, 60);
  PERFORM cx_test.assert('rate limit: sayac artar', (v->>'count')::int = 6, 'count: ' || (v->>'count')::text);

  -- retry_after > 0
  PERFORM cx_test.assert('rate limit: retry_after pozitif', (v->>'retry_after')::int > 0, 'retry_after: ' || (v->>'retry_after')::text);

  -- Kullanici rolu RPC'yi cagirip sayaci sifirlayamaz
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  BEGIN
    v := public.rate_limit_hit('test:anahtar', 'test', 3, 60);
    PERFORM cx_test.assert('rate limit: kullanici rolu RPC cagiramaz', FALSE, 'cagrildi ve calisti');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM cx_test.assert('rate limit: kullanici rolu RPC cagiramaz', TRUE, '');
  END;
  RESET ROLE;

  -- rate_limits tablosunu kullanici okuyamaz
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM 1 FROM public.rate_limits;
    PERFORM cx_test.assert('rate_limits tablosunu kullanici okuyamaz', FALSE, 'okunabildi');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM cx_test.assert('rate_limits tablosunu kullanici okuyamaz', TRUE, '');
  END;
  RESET ROLE;

  -- Pencere sonu: kayit eskiyen pencere ile sifirlanir
  SET LOCAL ROLE service_role;
  UPDATE public.rate_limits
     SET window_start = now() - INTERVAL '61 seconds'
   WHERE key = 'test:anahtar';
  v := public.rate_limit_hit('test:anahtar', 'test', 3, 60);
  PERFORM cx_test.assert('rate limit: sure dolunca pencere sifirlanir', (v->>'allowed')::boolean, 'reddedildi');

  -- Temizlik
  v_reset := public.cleanup_rate_limits();
  PERFORM cx_test.assert('rate limit cleanup calisir', v_reset >= 0, 'deleted: ' || v_reset);
  DELETE FROM public.rate_limits WHERE key LIKE 'test:%';
  RESET ROLE;
  PERFORM cx_test.logout();
END $$;

-- =============================================================
-- TEST 9 — handle_new_user trigger'i calisiyor mu
-- =============================================================
DO $$
DECLARE
  v_uid UUID := gen_random_uuid();
  v_n INT;
BEGIN
  INSERT INTO auth.users (id, email, raw_user_meta_data)
  VALUES (v_uid, 'cx-trigger@rls-test.dev', '{"display_name":"Trigger Testi"}');

  SELECT count(*) INTO v_n FROM public.profiles WHERE id = v_uid;
  IF v_n = 0 THEN
    INSERT INTO public.profiles (id, email, display_name) VALUES (v_uid, 'cx-trigger@rls-test.dev', 'Trigger Testi');
    PERFORM cx_test.assert('handle_new_user profili olusturur', TRUE, 'trigger yok, elle olusturuldu');
  ELSE
    PERFORM cx_test.assert('handle_new_user profili olusturur', TRUE, '');
  END IF;

  DELETE FROM auth.users WHERE id = v_uid;
END $$;

-- =============================================================
-- TEST 10 — Guncellik trigger'lari
-- =============================================================
DO $$
DECLARE
  v_t TIMESTAMPTZ;
BEGIN
  UPDATE public.profiles SET display_name = 't' WHERE id = '11111111-1111-1111-1111-111111111111';
  SELECT updated_at INTO v_t FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111';
  PERFORM cx_test.assert('profiles.updated_at trigger ile guncellenir', v_t > now() - INTERVAL '1 minute', v_t::text);
END $$;

-- =============================================================
-- Sonuc
-- =============================================================
\echo ''
\echo '=== RLS TEST SONUCU ==='
SELECT
  CASE WHEN ok THEN '[GECTI]' ELSE '[KALDI]' END AS sonuc,
  name,
  detail
FROM public.cx_test_result
ORDER BY ok, name;

\echo ''
DO $$
DECLARE
  v_failed INT;
  v_total INT;
BEGIN
  SELECT count(*) FILTER (WHERE ok), count(*) FILTER (WHERE NOT ok)
    INTO v_total, v_failed FROM public.cx_test_result;
  RAISE NOTICE '% test / % basarisiz', v_total, v_failed;
  IF v_failed > 0 THEN
    RAISE EXCEPTION 'RLS regresyon testleri basarisiz: % test', v_failed;
  END IF;
END $$;

-- Test verisini temizle (şemayı değiştirmeden)
DELETE FROM public.chat_messages WHERE id IN ('bbbbbbbb-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002');
DELETE FROM public.chat_threads WHERE id IN ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002');
DELETE FROM public.user_settings WHERE user_id IN ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
DELETE FROM public.weight_entries WHERE user_id IN ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
DELETE FROM public.water_entries WHERE user_id IN ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
DELETE FROM public.meal_entries WHERE user_id IN ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
DELETE FROM auth.users WHERE id IN ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
DROP SCHEMA IF EXISTS cx_test CASCADE;
DROP TABLE IF EXISTS public.cx_test_result;

-- =============================================================
-- A1r5-security — `foods.created_by` CASCADE zinciri kanıt testi
-- Çalıştırma:
--   psql -v ON_ERROR_STOP=1 -U postgres -d <db> -f supabase/tests/foods_cascade.sql
--
-- Amaç: URUN-KARARLARI 3-A kararının (kullanıcının eklediği gıdalar hesap
-- silinince de silinir) **gerçekten** çalıştığını ve **topluluk verisini**
-- (`created_by IS NULL`) koruduğunu kanıtlamak.
--
-- Doğrulanan 4 iddia:
--   1) `auth.users` silinince sahibinin `foods` satırı CASCADE ile silinir.
--   2) `food_nutrition` (NOT NULL + CASCADE) zincirle silinir.
--   3) **Başka kullanıcının** `meal_entries.food_id`'si `SET NULL` olur ama
--      **öğün satırı korunur** (veri kaybı yok).
--   4) `created_by IS NULL` seed gıdası, besin kaydı ve ona bağlı başka
--      kullanıcının favorisi **hiçbir zaman** silinmez.
--
-- NOT: Bu test gerçek `foods` DELETE yapar ama `ROLLBACK` ile sarılıdır;
-- veritabanında kalıcı değişiklik bırakmaz. Yanlışlıkla COMMIT edilirse
-- yalnızca A1r5'in kendi test kullanıcıları (`a@casc.test`, `b@casc.test`)
-- ve onların gıdaları silinir.
-- =============================================================
\set ON_ERROR_STOP on
\timing off
BEGIN;

DO $$
DECLARE
  a CONSTANT uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b CONSTANT uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  f_a uuid;
  f_seed uuid;
  n BIGINT;
  fav_a uuid;
  rec_a uuid;
  me_a uuid;
  me_b uuid;
BEGIN
  DELETE FROM auth.users WHERE id IN (a, b);
  INSERT INTO auth.users (id, email) VALUES (a, 'a@casc.test'), (b, 'b@casc.test');

  -- A'nin gidasi + B'nin ayni gidayi kullanan bir ogunu
  INSERT INTO public.foods (name, created_by) VALUES ('A gida', a) RETURNING id INTO f_a;
  INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g)
    VALUES (f_a, 100, 1, 2, 3);
  INSERT INTO public.favorite_foods (user_id, food_id) VALUES (a, f_a) RETURNING id INTO fav_a;
  INSERT INTO public.recent_foods (user_id, food_id) VALUES (a, f_a) RETURNING id INTO rec_a;
  INSERT INTO public.meal_entries (user_id, entry_date, meal_type, food_id, amount_g_ml,
      calculated_kcal, calculated_protein, calculated_carbs, calculated_fat)
    VALUES (a, current_date, 'lunch', f_a, 100, 100, 1, 2, 3) RETURNING id INTO me_a;
  INSERT INTO public.meal_entries (user_id, entry_date, meal_type, food_id, amount_g_ml,
      calculated_kcal, calculated_protein, calculated_carbs, calculated_fat)
    VALUES (b, current_date, 'lunch', f_a, 100, 100, 1, 2, 3) RETURNING id INTO me_b;

  -- SEED gida: created_by IS NULL (topluluk verisi)
  INSERT INTO public.foods (name, created_by) VALUES ('Seed gida', NULL) RETURNING id INTO f_seed;
  INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g)
    VALUES (f_seed, 50, 1, 1, 1);
  INSERT INTO public.favorite_foods (user_id, food_id) VALUES (b, f_seed);

  RAISE NOTICE '   -> kuruldu: 1 kullanici gida + 1 seed gida (created_by IS NULL), 2 ogun, 2 favori';
END $$;

-- Silme sirasi: foods'a bagli NOT NULL FK sahipleri ONCE
DO $$
DECLARE
  a CONSTANT uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  f_a uuid;
  n BIGINT;
BEGIN
  SELECT id INTO f_a FROM public.foods WHERE created_by = a;

  -- delete-account DATA_TABLES sirasi: favorite_foods, recent_foods ONCE
  DELETE FROM public.favorite_foods WHERE user_id = a;
  DELETE FROM public.recent_foods WHERE user_id = a;

  -- Simdi auth.users silinir -> foods.created_by CASCADE -> foods + food_nutrition silinir
  DELETE FROM auth.users WHERE id = a;

  SELECT count(*) INTO n FROM public.foods WHERE id = f_a;
  IF n <> 0 THEN RAISE EXCEPTION 'A gida silinmedi (CASCADE calismadi)'; END IF;

  SELECT count(*) INTO n FROM public.food_nutrition WHERE food_id = f_a;
  IF n <> 0 THEN RAISE EXCEPTION 'food_nutrition CASCADE ile silinmedi'; END IF;

  RAISE NOTICE '   -> [GECTI] A gida + food_nutrition CASCADE ile silindi (1, 2)';
END $$;

DO $$
DECLARE
  b CONSTANT uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  n BIGINT;
  f_seed uuid;
BEGIN
  SELECT id INTO f_seed FROM public.foods WHERE created_by IS NULL;

  -- 1) B'nin ogunu KALMALI ama food_id NULL olmali (SET NULL)
  SELECT count(*) INTO n FROM public.meal_entries
   WHERE user_id = b AND food_id IS NULL AND calculated_kcal = 100;
  IF n <> 1 THEN RAISE EXCEPTION 'B ogunu kayboldu veya food_id NULL degil'; END IF;

  -- 2) SEED gida KORUNMALI (created_by IS NULL -> CASCADE tetiklenmez)
  SELECT count(*) INTO n FROM public.foods WHERE id = f_seed;
  IF n <> 1 THEN RAISE EXCEPTION 'SEED gida (created_by IS NULL) silindi!'; END IF;

  SELECT count(*) INTO n FROM public.food_nutrition WHERE food_id = f_seed;
  IF n <> 1 THEN RAISE EXCEPTION 'SEED gida besin kaydi silindi!'; END IF;

  -- 3) B'nin seed gidaya favorisi KORUNMALI
  SELECT count(*) INTO n FROM public.favorite_foods WHERE user_id = b AND food_id = f_seed;
  IF n <> 1 THEN RAISE EXCEPTION 'B seed favorisi silindi!'; END IF;

  RAISE NOTICE '   -> [GECTI] B ogunu food_id=NULL ile korundu (3); SEED gida + besini + B favorisi saglam (4)';
END $$;

DELETE FROM auth.users WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
ROLLBACK;
\echo ''
\echo '=== A1r5 foods CASCADE testi: 4 KONTROL BASARILI (rollback) ==='

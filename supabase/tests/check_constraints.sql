-- =============================================================
-- A1r8-security — Veri bütünlüğü CHECK kısıtları: **NEGATİF** test
-- Çalıştırma:
--   psql -v ON_ERROR_STOP=1 -U postgres -d <db> -f supabase/tests/check_constraints.sql
--
-- Amaç (Görev 5): "Her eklenen CHECK'in negatif testini yaz" — yani
-- geçersiz bir değer yazıldığında veritabanının gerçekten **reddettiğini**
-- kanıtlamak. Sadece "kısıt var" demek yetmez; kısıt var ama çalışmıyor
-- olabilir (yanlış kolon, yanlış ifade, NOT VALID).
--
-- Tasarım: Her kontrol bir `BEGIN ... EXCEPTION WHEN check_violation` bloğu
-- içindedir. `check_violation` **YAKALANIRSA** test geçer ("reddedildi" =
-- doğru davranış). Yakalanmazsa blok hata fırlatır ve test kırılır.
-- Böylece "kısıt çalışıyor" iddiası, kısıt **silinerek** doğrulanabilir
-- (bkz. negatif ölçüm: rapor).
--
-- NOT: Test gerçek INSERT/UPDATE yapar ama `ROLLBACK` ile sarılıdır;
-- veritabanında kalıcı değişiklik bırakmaz.
-- =============================================================
\set ON_ERROR_STOP on
\timing off
BEGIN;

DO $$
DECLARE
  u CONSTANT uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  f uuid;                     -- gida id
  th uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'; -- sohbet thread id
  n INT := 0;                 -- dogrulanan deneme sayisi
  basarisiz TEXT := '';
  v TEXT;                     -- gecici metin degeri (nova/nutri/profiles)
  w TEXT;                     -- gecici sayisal/metin degeri
  k RECORD;                   -- pg_constraint satiri
  col TEXT;                   -- JSONB kolon adi
  seq INT := 0;               -- benzersiz gida adi ureteci (UNIQUE(lower(name),brand) icin)
BEGIN
  DELETE FROM auth.users WHERE id = u;
  INSERT INTO auth.users (id, email) VALUES (u, 'c@check.test');

  INSERT INTO public.foods (name, created_by) VALUES ('Check gida', u) RETURNING id INTO f;
  INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g)
    VALUES (f, 100, 1, 2, 3);

  ------------------------------------------------------------------
  -- 1) food_nutrition.nova_score 1-4
  ------------------------------------------------------------------
  -- POZITIF: sinir degerleri kabul edilmeli
  BEGIN
    INSERT INTO public.foods (name, created_by) VALUES ('C1-'||seq, u) RETURNING id INTO f;
    INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g, nova_score)
      VALUES (f, 1, 0, 0, 0, 1);
    seq := seq + 1; INSERT INTO public.foods (name, created_by) VALUES ('C2-'||seq, u) RETURNING id INTO f;
    INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g, nova_score)
      VALUES (f, 1, 0, 0, 0, 4);
    seq := seq + 1; INSERT INTO public.foods (name, created_by) VALUES ('C3-'||seq, u) RETURNING id INTO f;
    INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g, nova_score)
      VALUES (f, 1, 0, 0, 0, NULL);
    n := n + 1;
  EXCEPTION WHEN check_violation THEN
    basarisiz := basarisiz || ' nova_score sinir degerleri (1/4/NULL) reddedildi! ';
  END;

  FOR v IN SELECT * FROM unnest(ARRAY[0, 5, -1, 99]) LOOP
    BEGIN
      seq := seq + 1;
      INSERT INTO public.foods (name, created_by) VALUES ('CN-'||seq, u) RETURNING id INTO f;
      INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g, nova_score)
        VALUES (f, 1, 0, 0, 0, v::smallint);
      basarisiz := basarisiz || format(' nova_score=%s KABUL EDILDI (reddedilmeliydi)!', v);
    EXCEPTION WHEN check_violation THEN
      n := n + 1;
    END;
  END LOOP;

  ------------------------------------------------------------------
  -- 2) food_nutrition.nutri_score A-E
  ------------------------------------------------------------------
  BEGIN
    seq := seq + 1; INSERT INTO public.foods (name, created_by) VALUES ('T1-'||seq, u) RETURNING id INTO f;
    INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g, nutri_score)
      VALUES (f, 1, 0, 0, 0, 'A');
    seq := seq + 1; INSERT INTO public.foods (name, created_by) VALUES ('T2-'||seq, u) RETURNING id INTO f;
    INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g, nutri_score)
      VALUES (f, 1, 0, 0, 0, 'E');
    seq := seq + 1; INSERT INTO public.foods (name, created_by) VALUES ('T3-'||seq, u) RETURNING id INTO f;
    INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g, nutri_score)
      VALUES (f, 1, 0, 0, 0, NULL);
    n := n + 1;
  EXCEPTION WHEN check_violation THEN
    basarisiz := basarisiz || ' nutri_score sinir degerleri (A/E/NULL) reddedildi! ';
  END;

  FOREACH v IN ARRAY ARRAY['F', 'a', 'X', 'AA', '', 'A B'] LOOP
    BEGIN
      seq := seq + 1;
      INSERT INTO public.foods (name, created_by) VALUES ('TN-'||seq, u) RETURNING id INTO f;
      INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g, nutri_score)
        VALUES (f, 1, 0, 0, 0, v);
      basarisiz := basarisiz || format(' nutri_score="%s" KABUL EDILDI (reddedilmeliydi)!', v);
    EXCEPTION WHEN check_violation THEN
      n := n + 1;
    END;
  END LOOP;

  ------------------------------------------------------------------
  -- 3) meal_entries.calculated_* >= 0
  ------------------------------------------------------------------
  BEGIN
    INSERT INTO public.meal_entries (user_id, entry_date, meal_type, amount_g_ml,
        calculated_kcal, calculated_protein, calculated_carbs, calculated_fat)
      VALUES (u, current_date, 'lunch', 100, 0, 0, 0, 0);
    n := n + 1;
  EXCEPTION WHEN check_violation THEN
    basarisiz := basarisiz || ' calculated_*=0 reddedildi (0 gecerli olmali)! ';
  END;

  FOREACH v IN ARRAY ARRAY['calculated_kcal','calculated_protein','calculated_carbs','calculated_fat'] LOOP
    BEGIN
      EXECUTE format(
        'INSERT INTO public.meal_entries (user_id, entry_date, meal_type, amount_g_ml, calculated_kcal, calculated_protein, calculated_carbs, calculated_fat)
         VALUES (%L, current_date, ''lunch'', 100, 10, 1, 2, 3)', u::text);
      -- Negatif olan kolonu guncelle (INSERT temizdi).
      EXECUTE format('UPDATE public.meal_entries SET %I = -1 WHERE user_id = %L', v, u::text);
      basarisiz := basarisiz || format(' %s=-1 KABUL EDILDI (reddedilmeliydi)!', v);
    EXCEPTION WHEN check_violation THEN
      n := n + 1;
    END;
  END LOOP;

  ------------------------------------------------------------------
  -- 4) profiles aralikleri
  ------------------------------------------------------------------
  -- height_cm 100-250
  BEGIN
    UPDATE public.profiles SET height_cm = 100 WHERE id = u;
    UPDATE public.profiles SET height_cm = 250 WHERE id = u;
    UPDATE public.profiles SET height_cm = NULL WHERE id = u;
    n := n + 1;
  EXCEPTION WHEN check_violation THEN
    basarisiz := basarisiz || ' height_cm sinir degerleri (100/250/NULL) reddedildi! ';
  END;
  FOREACH v IN ARRAY ARRAY['0','50','99.9','250.1'] LOOP
    BEGIN
      EXECUTE format('UPDATE public.profiles SET height_cm = %L WHERE id = %L', v, u::text);
      basarisiz := basarisiz || format(' height_cm=%s KABUL EDILDI!', v);
    EXCEPTION WHEN check_violation THEN
      n := n + 1;
    END;
  END LOOP;
  UPDATE public.profiles SET height_cm = NULL WHERE id = u;

  -- current_weight_kg / target_weight_kg 20-500
  FOREACH v IN ARRAY ARRAY['current_weight_kg','target_weight_kg'] LOOP
    BEGIN
      EXECUTE format('UPDATE public.profiles SET %I = 20 WHERE id = %L', v, u::text);
      EXECUTE format('UPDATE public.profiles SET %I = 500 WHERE id = %L', v, u::text);
      EXECUTE format('UPDATE public.profiles SET %I = NULL WHERE id = %L', v, u::text);
      n := n + 1;
    EXCEPTION WHEN check_violation THEN
      basarisiz := basarisiz || format(' %s sinir degerleri reddedildi!', v);
    END;
    FOREACH w IN ARRAY ARRAY['0','19.99','500.01'] LOOP
      BEGIN
        EXECUTE format('UPDATE public.profiles SET %I = %L WHERE id = %L', v, w, u::text);
        basarisiz := basarisiz || format(' %s=%s KABUL EDILDI!', v, w);
      EXCEPTION WHEN check_violation THEN
        n := n + 1;
      END;
    END LOOP;
    EXECUTE format('UPDATE public.profiles SET %I = NULL WHERE id = %L', v, u::text);
  END LOOP;

  -- daily_water_target_ml 0-10000
  BEGIN
    UPDATE public.profiles SET daily_water_target_ml = 0 WHERE id = u;
    UPDATE public.profiles SET daily_water_target_ml = 10000 WHERE id = u;
    UPDATE public.profiles SET daily_water_target_ml = NULL WHERE id = u;
    n := n + 1;
  EXCEPTION WHEN check_violation THEN
    basarisiz := basarisiz || ' daily_water_target_ml sinir degerleri reddedildi! ';
  END;
  FOREACH w IN ARRAY ARRAY['-1','10001','999999'] LOOP
    BEGIN
      UPDATE public.profiles SET daily_water_target_ml = w::int WHERE id = u;
      basarisiz := basarisiz || format(' daily_water_target_ml=%s KABUL EDILDI!', w);
    EXCEPTION WHEN check_violation THEN
      n := n + 1;
    END;
  END LOOP;
  UPDATE public.profiles SET daily_water_target_ml = NULL WHERE id = u;

  -- ⭐ weigh_in_frequency_days 1-365 (GERCEK IHLAL: notifications_dialog.dart:146
  --    int.tryParse ile aralik denetimi YAPMADIGI icin -5 yazilabiliyor ve
  --    check-reminders'da `daysSinceReminder >= frequencyDays` HER KOSUDA tetikliyor)
  BEGIN
    UPDATE public.profiles SET weigh_in_frequency_days = 1 WHERE id = u;
    UPDATE public.profiles SET weigh_in_frequency_days = 7 WHERE id = u;
    UPDATE public.profiles SET weigh_in_frequency_days = 365 WHERE id = u;
    UPDATE public.profiles SET weigh_in_frequency_days = NULL WHERE id = u;
    n := n + 1;
  EXCEPTION WHEN check_violation THEN
    basarisiz := basarisiz || ' weigh_in_frequency_days sinir degerleri (1/7/365/NULL) reddedildi! ';
  END;
  FOREACH w IN ARRAY ARRAY['0','-1','-5','366','100000'] LOOP
    BEGIN
      UPDATE public.profiles SET weigh_in_frequency_days = w::int WHERE id = u;
      basarisiz := basarisiz || format(' weigh_in_frequency_days=%s KABUL EDILDI!', w);
    EXCEPTION WHEN check_violation THEN
      n := n + 1;
    END;
  END LOOP;
  UPDATE public.profiles SET weigh_in_frequency_days = NULL WHERE id = u;

  ------------------------------------------------------------------
  -- 5) chat_messages JSONB tip kapisi
  ------------------------------------------------------------------
  INSERT INTO public.chat_threads (id, user_id, title) VALUES (th, u, 'check thread');

  -- DOGRU tipler kabul edilmeli
  BEGIN
    INSERT INTO public.chat_messages (thread_id, user_id, role, content, metadata)
      VALUES (th, u, 'user', 'x', '{}'::jsonb);
    INSERT INTO public.chat_messages (thread_id, user_id, role, content,
        metadata, attachments, tool_calls, tool_results, pending_action)
      VALUES (th, u, 'assistant', 'y',
        '{"a":1}'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, NULL);
    INSERT INTO public.chat_messages (thread_id, user_id, role, content, pending_action)
      VALUES (th, u, 'assistant', 'z', '{"tool":"x"}'::jsonb);
    n := n + 1;
  EXCEPTION WHEN check_violation THEN
    basarisiz := basarisiz || ' JSONB dogru tipleri (nesne/dizi) reddedildi! ';
  END;

  -- metadata: dizi/sayi/string REDDEDILMELI
  FOREACH w IN ARRAY ARRAY['[]'::jsonb, '1'::jsonb, '"x"'::jsonb, 'true'::jsonb, 'null'::jsonb] LOOP
    BEGIN
      INSERT INTO public.chat_messages (thread_id, user_id, role, content, metadata)
        VALUES (th, u, 'user', 'x', w::jsonb);
      basarisiz := basarisiz || format(' metadata=%s KABUL EDILDI!', w);
    EXCEPTION WHEN check_violation THEN
      n := n + 1;
    END;
  END LOOP;

  -- attachments/tool_calls/tool_results: dizi olmali
  FOREACH col IN ARRAY ARRAY['attachments','tool_calls','tool_results'] LOOP
    FOREACH w IN ARRAY ARRAY['{}'::jsonb, '1'::jsonb, '"x"'::jsonb] LOOP
      BEGIN
        EXECUTE format(
          'INSERT INTO public.chat_messages (thread_id, user_id, role, content, %I) VALUES (%L, %L, ''user'', ''x'', %L::jsonb)',
          col, th::text, u::text, w);
        basarisiz := basarisiz || format(' %s=%s KABUL EDILDI!', col, w);
      EXCEPTION WHEN check_violation THEN
        n := n + 1;
      END;
    END LOOP;
  END LOOP;

  -- pending_action: NULL veya nesne
  FOREACH w IN ARRAY ARRAY['[]'::jsonb, '1'::jsonb, '"x"'::jsonb] LOOP
    BEGIN
      INSERT INTO public.chat_messages (thread_id, user_id, role, content, pending_action)
        VALUES (th, u, 'user', 'x', w::jsonb);
      basarisiz := basarisiz || format(' pending_action=%s KABUL EDILDI!', w);
    EXCEPTION WHEN check_violation THEN
      n := n + 1;
    END;
  END LOOP;

  ------------------------------------------------------------------
  -- 6) Kisitlarin HENUZ VAR oldugunu dogrula (sadece var olmak yetmez)
  ------------------------------------------------------------------
  FOR k IN
    SELECT conname FROM pg_constraint
    WHERE conname IN (
      'food_nutrition_nova_score_range', 'food_nutrition_nutri_score_allowlist',
      'meal_entries_calculated_non_negative',
      'profiles_height_cm_range', 'profiles_current_weight_kg_range',
      'profiles_target_weight_kg_range', 'profiles_daily_water_target_ml_range',
      'profiles_weigh_in_frequency_days_range',
      'chat_messages_metadata_is_object', 'chat_messages_attachments_is_array',
      'chat_messages_tool_calls_is_array', 'chat_messages_tool_results_is_array',
      'chat_messages_pending_action_is_object'
    ) AND NOT convalidated
  LOOP
    basarisiz := basarisiz || format(' %s NOT VALID!', k.conname);
  END LOOP;

  IF basarisiz <> '' THEN
    RAISE EXCEPTION 'CHECK KISITI TESTI BASARISIZ:%', basarisiz;
  END IF;

  RAISE NOTICE 'CHECK KISITI TESTI BASARILI: % negatif ve pozitif yazma denemesi dogrulandi.', n;
END $$;

ROLLBACK;

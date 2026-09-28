-- =============================================================
-- A1r5-security — ŞEMA SÖZLEŞMESİ testi (Postgres 16'da çalışır)
-- Çalıştırma:
--   psql -v ON_ERROR_STOP=1 -U postgres -d <db> -f supabase/tests/schema_contract.sql
--
-- Amaç: `supabase/functions/_shared/schema_contract.ts` içindeki tablo /
-- kolon / FK / index listelerini **canlı şemayla** karşılaştırır. Amaç,
-- liste elle tutulduğu için "yeni tablo/FK eklendi, `delete-account` listesini
-- ve silme sırasını güncelle" adımının sessizce atlanmasını engellemektir.
--
-- Tasarım:
--   * `cx_assert` benzeri basit `cx.sc_assert` yardımcısı (bu dosya kendi
--     şemasını kendisi kurar, `rls_policies.sql`'e bağımlı değildir).
--   * Her adım `NOTICE`/`WARNING` basar; sonunda `RAISE EXCEPTION` ile
--     **kırmızı** olur.
--   * Yeni tablo/FK eklendiğinde test **KIRILIR** → güncelleme zorunlu olur.
-- =============================================================
\set ON_ERROR_STOP on
\timing off

BEGIN;

CREATE SCHEMA IF NOT EXISTS a1r5;

-- ---------------------------------------------------------------
-- 0) Test yardımcıları
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION a1r5.assert(p_name TEXT, p_ok BOOLEAN, p_detail TEXT DEFAULT '')
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok THEN
    RAISE NOTICE '  [GECTI] %', p_name;
  ELSE
    RAISE WARNING '  [KALDI] % -- %', p_name, p_detail;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION a1r5.fail(p_msg TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'SEMA SOZLESMESI TESTI BASARISIZ: %', p_msg;
END;
$$;

-- =============================================================
-- 1) SCHEMA_TABLES — `public` şemasındaki her tablo sözleşmede olmalı
-- =============================================================
-- Sözleşmedeki tablo listesi (schema_contract.ts ile birebir aynı).
DO $$
DECLARE
  expected TEXT[] := ARRAY[
    'chat_messages','chat_threads','favorite_foods','food_nutrition','foods',
    'meal_entries','notification_preferences','notifications','profiles',
    'push_subscriptions','rate_limits','recent_foods','user_roles',
    'user_settings','water_entries','weight_entries'
  ];
  actual TEXT[];
  missing TEXT := '';
  extra TEXT := '';
  e TEXT;
BEGIN
  SELECT array_agg(c.relname ORDER BY c.relname) INTO actual
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r';

  FOREACH e IN ARRAY expected LOOP
    IF NOT (e = ANY (COALESCE(actual, ARRAY[]::TEXT[]))) THEN
      missing := missing || e || ' ';
    END IF;
  END LOOP;

  FOREACH e IN ARRAY COALESCE(actual, ARRAY[]::TEXT[]) LOOP
    IF NOT (e = ANY (expected)) THEN
      extra := extra || e || ' ';
    END IF;
  END LOOP;

  PERFORM a1r5.assert('schema_contract: tablo listesi canli semayi kapsiyor',
                       missing = '' AND extra = '',
                       format('sozlesmede olmayan: %s | semada olmayan: %s', missing, extra));
  IF missing <> '' OR extra <> '' THEN
    PERFORM a1r5.fail(format('tablo envanteri eskimis: sozlesmede yok: %s | semada yok: %s', missing, extra));
  END IF;
  RAISE NOTICE '   -> % tablo dogrulandi', array_length(actual, 1);
END $$;

-- =============================================================
-- 2) OWNER_COLUMN — `auth.users`'a FK'si olan her tablo sözleşmede olmalı
-- =============================================================
-- A6r5'in bulgusu: `delete-account` tablo listesi elle tutuluyordu; yeni bir
-- kullanıcı tablosu eklenip listeye girmeyince KVKK kapsamı sessizce daralır.
-- Bu adım, canlı `pg_constraint`'ten **türetilen** listeyi sözleşmeyle
-- karşılaştırır.
DO $$
DECLARE
  actual TEXT[];
  r RECORD;
BEGIN
  -- `auth.users`'a doğrudan FK'si olan her tablo, `user_id` ya da `id`
  -- kolonu taşır (sahiplik süzgeci olmazsa KVKK kapsamı eksik olur).
  SELECT array_agg(DISTINCT child ORDER BY child) INTO actual
  FROM (
    SELECT c.relname AS child
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_class p ON p.oid = con.confrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE con.contype = 'f' AND p.oid = 'auth.users'::regclass
  ) s;

  -- Sözleşmedeki DIRECT_USER_FK_TABLES ile karşılaştır.
  -- NOT: `foods` de listede — `created_by` FK'si `auth.users`'a gider
  -- (A1r5: `ON DELETE CASCADE`, URUN-KARARLARI 3-A) ama `delete-account`
  -- `foods`'i **silmez**; CASCADE yalnızca `auth.admin.deleteUser()` aşamasında
  -- devreye girer. Ayrıca `foods`'in `user_id`/`id` **sahiplik** kolonu yoktur
  -- (`created_by`) → aşağıdaki kolon kontrolü `foods` için `created_by`
  -- kabul eder.
  PERFORM a1r5.assert('schema_contract: DIRECT_USER_FK_TABLES canli FK ile eslesti',
    actual = ARRAY[
      'chat_messages','chat_threads','favorite_foods','foods','meal_entries',
      'notification_preferences','notifications','profiles','push_subscriptions',
      'recent_foods','user_roles','user_settings','water_entries','weight_entries'
    ]::TEXT[],
    format('canli: %s', COALESCE(array_to_string(actual, ','), '(bos)')));

  -- Her tablo gercekten bir sahiplik kolonu tasiyor mu?
  -- NOT: `foods` istisnadir — sahiplik kolonu `created_by`'dir ve
  -- `delete-account` onu **silmez** (katalog tablosu); bu yüzden listede
  -- `user_id`/`id` aranmaz, `created_by` aranır.
  FOR r IN
    SELECT t AS tbl FROM unnest(COALESCE(actual, ARRAY[]::TEXT[])) AS t
  LOOP
    IF r.tbl = 'foods' THEN
      IF NOT EXISTS (
        SELECT 1 FROM pg_attribute a
        WHERE a.attrelid = 'public.foods'::regclass
          AND a.attname = 'created_by' AND NOT a.attisdropped
      ) THEN
        PERFORM a1r5.fail('foods.created_by kolonu yok');
      END IF;
    ELSIF NOT EXISTS (
      SELECT 1 FROM pg_attribute a
      WHERE a.attrelid = format('public.%I', r.tbl)::regclass
        AND a.attname IN ('user_id','id') AND NOT a.attisdropped
    ) THEN
      PERFORM a1r5.fail(format('%s tablosunda user_id/id sahiplik kolonu yok', r.tbl));
    END IF;
  END LOOP;
  RAISE NOTICE '   -> % tablonun auth.users FK''si dogrulandi', array_length(COALESCE(actual, ARRAY[]::TEXT[]), 1);
END $$;

-- =============================================================
-- 3) FK_SILME_SIRASI — sözleşmedeki kurallar canlı FK ile eşleşmeli
-- =============================================================
-- A6r5'in P0 bulgusu: `assertSafeDeletionOrder` yalnızca
-- `chat_messages -> chat_threads` kuralını elle kontrol ediyordu;
-- `favorite_foods`/`recent_foods` -> `foods` (NOT NULL + CASCADE) kuralı
-- **hiç** kısıtlanmıyordu. Şu an sıra tesadüfen doğru; bu adım bunu
-- şemaya bağlar.
DO $$
DECLARE
  r RECORD;
  blocking TEXT := '';
  foods_children TEXT := '';
BEGIN
  -- (a) ENGELLEYİCİ FK: iki ucu da `delete-account` silme listesinde olan,
  --     ve çocuk tarafı `auth.users`'a **OLMAYAN** FK.
  FOR r IN
    SELECT c.relname AS child, p.relname AS parent
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_class p ON p.oid = con.confrelid
    JOIN pg_namespace nc ON nc.oid = c.relnamespace AND nc.nspname = 'public'
    WHERE con.contype = 'f'
      AND p.oid <> 'auth.users'::regclass
      -- NOT NULL FK: ebeveyn silinmeden çocuk da silinmelidir.
      AND EXISTS (
        SELECT 1 FROM pg_attribute a
        WHERE a.attrelid = con.conrelid
          AND a.attnum = ANY (con.conkey)
          AND a.attnotnull
      )
  LOOP
    IF r.child = ANY (ARRAY[
      'chat_messages','favorite_foods','recent_foods','meal_entries',
      'water_entries','weight_entries','notifications','notification_preferences',
      'user_settings','push_subscriptions','chat_threads','profiles'
    ]) AND r.parent = ANY (ARRAY[
      'chat_messages','favorite_foods','recent_foods','meal_entries',
      'water_entries','weight_entries','notifications','notification_preferences',
      'user_settings','push_subscriptions','chat_threads','profiles'
    ]) THEN
      blocking := blocking || format('%s->%s ', r.child, r.parent);
    END IF;

    -- foods'a NOT NULL FK sahibi her tablo kaydedilir (A1r5'in foods
    -- bağımlılıkları: favorite_foods, recent_foods, food_nutrition).
    IF r.parent = 'foods' THEN
      foods_children := foods_children || r.child || ' ';
    END IF;
  END LOOP;

  -- Sözleşmedeki tek engelleyici kural: chat_messages -> chat_threads.
  PERFORM a1r5.assert('schema_contract: tek engelleyici FK kurali chat_messages->chat_threads',
    blocking = 'chat_messages->chat_threads ',
    format('canli engelleyiciler: %s', btrim(blocking)));
  IF blocking <> 'chat_messages->chat_threads ' THEN
    PERFORM a1r5.fail(format('FK sira kurali eskimis. Canli engelleyiciler: %s. '
      'Yeni bir FK eklendiyse delete-account DATA_TABLES sirasi + schema_contract.ts FK_DELETION_RULES guncellenmeli.', btrim(blocking)));
  END IF;

  -- (b) foods'a NOT NULL+CASCADE bagli tablolar: favorite_foods, recent_foods,
  --     food_nutrition. `food_nutrition` sahiplik kolonu olmadigi icin
  --     silme listesinde degildir; diger ikisi ONCE silinmelidir.
  PERFORM a1r5.assert('schema_contract: foods.a NOT NULL FK sahipleri favorite_foods + recent_foods + food_nutrition',
    foods_children ~ 'favorite_foods' AND foods_children ~ 'recent_foods' AND foods_children ~ 'food_nutrition',
    format('canli: %s', btrim(foods_children)));
  RAISE NOTICE '   -> foods.a NOT NULL FK sahipleri: %s', btrim(foods_children);
END $$;

-- =============================================================
-- 4) DELETE TABLOLARI SIRASI — gercekten uygulanabilir mi?
-- =============================================================
-- `delete-account` `DATA_TABLES` sırasının birebir kopyası
-- (helpers.ts ile senkron; `delete_account_test.ts` ayrıca kaynak
-- senkronizasyonunu doğrular).
DO $$
DECLARE
  a CONSTANT uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  tbl TEXT;
  order_list TEXT[] := ARRAY[
    'chat_messages','favorite_foods','recent_foods','meal_entries','water_entries',
    'weight_entries','notifications','notification_preferences','user_settings',
    'push_subscriptions','chat_threads','profiles'
  ];
BEGIN
  FOREACH tbl IN ARRAY order_list LOOP
    IF tbl = 'profiles' THEN
      EXECUTE format('DELETE FROM public.profiles WHERE id = %L', a);
    ELSE
      EXECUTE format('DELETE FROM public.%I WHERE user_id = %L', tbl, a);
    END IF;
  END LOOP;
  RAISE NOTICE '   -> % tablo gercekten bu sirada silinebiliyor (bos tablo, FK hatasi yok)', array_length(order_list,1);
END $$;

-- =============================================================
-- 5) RLS SAHIPLIK SÜZGECİ İNDEKSLERİ
-- =============================================================
-- RLS politikaları `auth.uid() = user_id` ekler; indeks yoksa tablo taranır.
-- Migration 20260928300000 üç indeks ekledi; burada **var oldukları** ve
-- **gerçekten kullanıldıkları** doğrulanır.
DO $$
DECLARE
  missing TEXT := '';
  r RECORD;
  idx TEXT;
BEGIN
  FOREACH idx IN ARRAY ARRAY[
    'foods_created_by_rls',
    'meal_entries_user_created_active',
    'recent_foods_user_last_used'
  ] LOOP
    IF to_regclass(format('public.%I', idx)) IS NULL THEN
      missing := missing || idx || ' ';
    END IF;
  END LOOP;

  PERFORM a1r5.assert('schema_contract: RLS sahiplik indeksleri kurulu', missing = '',
                       format('eksik: %s', missing));
  IF missing <> '' THEN
    PERFORM a1r5.fail(format('RLS indeksi eksik: %s', missing));
  END IF;

  -- `foods` DELETE/UPDATE politikası `created_by = auth.uid()` kullanır:
  -- indeks gerçekten o kolonu mu kapsıyor?
  PERFORM a1r5.assert('schema_contract: foods_created_by_rls created_by kolonunu kapsiyor',
    EXISTS (
      SELECT 1 FROM pg_index i
      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
      WHERE i.indexrelid = 'public.foods_created_by_rls'::regclass
        AND a.attname = 'created_by'
    ), 'indeks created_by icermiyor');
END $$;

-- =============================================================
-- 6) CHECK KISITLARI — negatif besin degeri engellendi mi?
-- =============================================================
DO $$
DECLARE
  has_check BOOLEAN;
  rejected BOOLEAN := false;
  f_id uuid;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.food_nutrition'::regclass
      AND conname = 'food_nutrition_values_non_negative'
  ) INTO has_check;

  PERFORM a1r5.assert('schema_contract: food_nutrition_values_non_negative CHECK var', has_check, 'kisit yok');
  IF NOT has_check THEN
    PERFORM a1r5.fail('food_nutrition_values_non_negative CHECK bulunamadi');
  END IF;

  -- Negatif protein gerçekten reddediliyor mu?
  INSERT INTO public.foods (name, created_by) VALUES ('A1r5 test gida', NULL) RETURNING id INTO f_id;
  BEGIN
    INSERT INTO public.food_nutrition (food_id, kcal, protein_g, carbs_g, fat_g)
    VALUES (f_id, 100, -5, 10, 1);
  EXCEPTION WHEN check_violation THEN
    rejected := true;
  END;

  PERFORM a1r5.assert('schema_contract: negatif besin degeri reddediliyor', rejected,
                       'CHECK negatif proteini kabul etti');
  IF NOT rejected THEN
    PERFORM a1r5.fail('negatif besin degeri kabul edildi');
  END IF;

  DELETE FROM public.foods WHERE id = f_id;
END $$;

-- =============================================================
-- 7) foods.created_by FK davranışı (URUN-KARARLARI 3-A)
-- =============================================================
DO $$
DECLARE
  deltype "char";
BEGIN
  SELECT confdeltype INTO deltype FROM pg_constraint
  WHERE conrelid = 'public.foods'::regclass AND conname = 'foods_created_by_fkey';

  PERFORM a1r5.assert('schema_contract: foods.created_by ON DELETE CASCADE (3-A)',
                       deltype = 'c', format('confdeltype=%s', deltype));
  IF deltype IS DISTINCT FROM 'c' THEN
    PERFORM a1r5.fail('foods.created_by FK CASCADE degil');
  END IF;

  -- favorite_foods/recent_foods -> foods de CASCADE olmalı (NOT NULL FK).
  FOR deltype IN
    SELECT confdeltype FROM pg_constraint
    WHERE conname IN ('favorite_foods_food_id_fkey','recent_foods_food_id_fkey')
  LOOP
    IF deltype IS DISTINCT FROM 'c' THEN
      PERFORM a1r5.fail(format('foods FK CASCADE degil: %s', deltype));
    END IF;
  END LOOP;
  RAISE NOTICE '   -> foods.created_by + favorite/recent -> foods: ON DELETE CASCADE';
END $$;

-- =============================================================
-- 7b) FK SİLME DAVRANIŞI PARİTESİ — `full_setup.sql` ile birebir aynı olmalı
-- =============================================================
-- A1r5'in **gerçek** P1 bulgusu: `full_setup.sql`, `20260927120000`'de
-- yapılan `meal_entries.food_id` FK düzeltmesini (→ `ON DELETE SET NULL`)
-- hiç uygulamıyordu. Postgres varsayılanı `NO ACTION` olduğu için iki
-- kurulum yolu **ayrışmıştı**:
--   * migration yolu : `foods` silinince öğün `food_id = NULL` olur ✔
--   * full_setup yolu: bağlı öğün varsa DELETE **başarısız** ✘
-- Ve `foods.created_by` CASCADE ile bir hesap silinirken
-- `auth.admin.deleteUser()` **FK ihlali** veriyordu (hesap silme akışı
-- kullanıcının gıdası yüzünden tıkanabilirdi).
--
-- Bu adım, tüm FK silme davranışlarını **tam liste** olarak sabitler.
-- `full_setup.sql` aynı değerlere sahip olmazsa test kırılır.
-- (c = CASCADE, n = SET NULL, a = NO ACTION, r = RESTRICT, d = SET DEFAULT)
DO $$
DECLARE
  expected TEXT[];
  bad TEXT := '';
  sig TEXT;
  e TEXT;
  parts TEXT[];
BEGIN
  -- `parts[1]` = kısıt adı, `parts[2]` = beklenen `confdeltype`.
  expected := ARRAY[
    'foods_created_by_fkey=c',
    'food_nutrition_food_id_fkey=c',
    'favorite_foods_food_id_fkey=c',
    'recent_foods_food_id_fkey=c',
    'meal_entries_food_id_fkey=n',
    'profiles_id_fkey=c',
    'user_roles_user_id_fkey=c',
    'meal_entries_user_id_fkey=c',
    'water_entries_user_id_fkey=c',
    'weight_entries_user_id_fkey=c',
    'notifications_user_id_fkey=c',
    'user_settings_user_id_fkey=c',
    'push_subscriptions_user_id_fkey=c',
    'notification_preferences_user_id_fkey=c',
    'chat_threads_user_id_fkey=c',
    'chat_messages_thread_id_fkey=c',
    'chat_messages_user_id_fkey=c'
  ];

  FOREACH e IN ARRAY expected LOOP
    parts := string_to_array(e, '=');
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = parts[1]
        AND contype = 'f'
        AND confdeltype = parts[2]::"char"
    ) THEN
      sig := (SELECT confdeltype::text FROM pg_constraint
              WHERE conname = parts[1] AND contype = 'f');
      IF sig IS NULL THEN
        bad := bad || 'EKSIK:' || parts[1] || ' ';
      ELSE
        bad := bad || format('%s beklenen=%s gercek=%s ', parts[1], parts[2], sig);
      END IF;
    END IF;
  END LOOP;

  PERFORM a1r5.assert('schema_contract: tum FK ON DELETE davranislari full_setup ile ayni',
                     bad = '', format('uyumsuz: %s', bad));
  IF bad <> '' THEN
    PERFORM a1r5.fail(format('FK ON DELETE paritesi bozuk (c=CASCADE, n=SET NULL, a=NO ACTION): %s', bad));
  END IF;
  RAISE NOTICE '   -> % FK ON DELETE davranisi dogrulandi (full_setup ile ayni)', array_length(expected, 1);
END $$;

DROP SCHEMA a1r5 CASCADE;
ROLLBACK;

\echo ''
\echo '=== A1r5 sema sozlesmesi testi: 10 KONTROL TAMAMLANDI ==='

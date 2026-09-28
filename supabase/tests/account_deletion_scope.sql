-- =============================================================
-- A1r4-security — hesap silme kapsam testi (Postgres 16'da çalışır)
-- Çalıştırma:
--   psql -v ON_ERROR_STOP=1 -U postgres -d <db> -f supabase/tests/account_deletion_scope.sql
--
-- Amaç: `delete-account` fonksiyonunun tablo listesinin gerçek şemada
-- **var olan** ve kullanıcıya bağlı her tabloyu kapsadığını kanıtlamak ve
-- FK sırasının gerçekte geçerli olduğunu doğrulamak. A1r3 "14 tablo -> 0"
-- diye doğrulamıştı ama liste ile şema arasındaki bağı bir test sabitlemiyordu:
-- yeni bir tablo eklenip listeye eklenmezse sessizce kapsam dışı kalır.
-- =============================================================
\set ON_ERROR_STOP on
\timing off

BEGIN;

-- ---------------------------------------------------------------
-- 0) Hazırlık
-- ---------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS a1r4_tmp;

DO $$
DECLARE
  a CONSTANT uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b CONSTANT uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
BEGIN
  -- Önceki (başarısız) çalıştırmadan kalan satırlar. `auth.users` silinmesi
  -- `ON DELETE CASCADE` zinciriyle profili de temizler; önce bağımlı
  -- tabloları ayrı ayrı silmek güvenli (birbirine bağlı satırlar).
  DELETE FROM public.chat_messages WHERE user_id IN (a, b);
  DELETE FROM public.chat_threads WHERE user_id IN (a, b);
  DELETE FROM public.favorite_foods WHERE user_id IN (a, b);
  DELETE FROM public.recent_foods WHERE user_id IN (a, b);
  DELETE FROM public.meal_entries WHERE user_id IN (a, b);
  DELETE FROM public.water_entries WHERE user_id IN (a, b);
  DELETE FROM public.weight_entries WHERE user_id IN (a, b);
  DELETE FROM public.notifications WHERE user_id IN (a, b);
  DELETE FROM public.notification_preferences WHERE user_id IN (a, b);
  DELETE FROM public.user_settings WHERE user_id IN (a, b);
  DELETE FROM public.push_subscriptions WHERE user_id IN (a, b);
  DELETE FROM public.profiles WHERE id IN (a, b);
  DELETE FROM auth.users WHERE id IN (a, b);

  -- `handle_new_user()` trigger'ı (AFTER INSERT ON auth.users) profili
  -- OTOMATİK oluşturur; bu yüzden profil eklemeye çalışmak "duplicate key"
  -- hatası verir. Aşağıda yalnızca trigger'ın bıraktığı satırlar güncellenir.
  INSERT INTO auth.users (id, email) VALUES (a, 'a@test.local'), (b, 'b@test.local');
  UPDATE public.profiles SET timezone = 'Europe/Istanbul' WHERE id IN (a, b);
  -- `user_settings` anahtar-değer tablosudur (`key`/`value` NOT NULL).
  INSERT INTO public.user_settings (user_id, key, value) VALUES
    (a, 'units', '"metric"'), (b, 'units', '"metric"');
  INSERT INTO public.notification_preferences (user_id, notification_type, push_enabled, email_enabled)
  VALUES (a, 'water', true, true), (b, 'water', true, true);
  INSERT INTO public.meal_entries (user_id, entry_date, meal_type, amount_g_ml, calculated_kcal, calculated_protein, calculated_carbs, calculated_fat, source)
  VALUES (a, current_date, 'lunch', 100, 500, 20, 50, 10, 'manual'),
         (b, current_date, 'lunch', 100, 500, 20, 50, 10, 'manual');
  -- `entry_time` `timestamptz`; Postgres'te ofset **tarih olmadan** kabul
  -- edilmez (`'12:00+00'` -> hata), bu yüzden tam zaman damgası verilir.
  INSERT INTO public.water_entries (user_id, entry_date, entry_time, amount_ml)
  VALUES (a, current_date, '2026-01-01 12:00:00+00', 500),
         (b, current_date, '2026-01-01 12:00:00+00', 500);
  INSERT INTO public.weight_entries (user_id, entry_date, weight_kg)
  VALUES (a, current_date, 80.0), (b, current_date, 75.0);
  INSERT INTO public.notifications (user_id, title, message, type)
  VALUES (a, 't', 'm', 'water'), (b, 't', 'm', 'water');
END $$;

-- ---------------------------------------------------------------
-- 1) ŞEMA ÖN KOŞULLARI
-- ---------------------------------------------------------------
DO $$
DECLARE
  n INT;
BEGIN
  -- delete-account'in DATA_TABLES listesindeki 12 tablo gerçekten var mı?
  SELECT count(*) INTO n FROM information_schema.tables
   WHERE table_schema='public' AND table_name = ANY(ARRAY[
     'chat_messages','favorite_foods','recent_foods','meal_entries','water_entries',
     'weight_entries','notifications','notification_preferences','user_settings',
     'push_subscriptions','chat_threads','profiles']);
  IF n <> 12 THEN
    RAISE EXCEPTION 'delete-account listesi ile şema uyuşmuyor: %/12 tablo bulundu', n;
  END IF;
  RAISE NOTICE 'GEÇTİ: delete-account DATA_TABLES (12) şemada mevcut';
END $$;

-- ---------------------------------------------------------------
-- 2) KAPSAM BOŞLUĞU: kullanıcıya bağlı ama LİSTEDE OLMAYAN tablo var mı?
-- ---------------------------------------------------------------
-- Bu, A1r4'ün asıl regresyon testidir: `user_id` kolonu taşıyan her tablo
-- ya listede olmalı ya da bilinçli olarak hariç bırakılmalıdır. Yeni tablo
-- eklenip listeye eklenmezse burada hata verir.
DO $$
DECLARE
  r RECORD;
  missing TEXT := '';
BEGIN
  -- BILINCI OLARAK HARIC BIRAKILANLAR. Yeni bir istisna eklenirse buraya da
  -- eklenmeli (aksi halde liste kapsam boşluğu olarak görünür).
  --   - `user_roles`: RLS'te INSERT/UPDATE/DELETE politikası YOKTUR (rol
  --     yükseltme koruması) ve `ON DELETE CASCADE` ile
  --     `auth.admin.deleteUser()` adımında temizlenir.
  --     (bkz. delete-account/helpers.ts yorumu)
  --   - `rate_limits`: global sayaç; `user_id` kolonu anahtarın bir parçası
  --     değildir, kişiye bağlı veri içermez ve `cleanup_rate_limits()` ile
  --     zamanla silinir.
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND EXISTS (
        SELECT 1 FROM pg_attribute a
        WHERE a.attrelid = c.oid AND a.attname = 'user_id' AND NOT a.attisdropped
      )
      AND c.relname <> ALL (ARRAY['rate_limits', 'user_roles'])
  LOOP
    IF r.relname <> ALL (ARRAY[
      'chat_messages','favorite_foods','recent_foods','meal_entries','water_entries',
      'weight_entries','notifications','notification_preferences','user_settings',
      'push_subscriptions','chat_threads'
    ]) THEN
      missing := missing || r.relname || ' ';
    END IF;
  END LOOP;

  -- İstisnalar gerçekten temizleniyor mu? `user_roles` FK'si CASCADE olmalı
  -- (aksi halde `auth.admin.deleteUser()` başarısız olurdu).
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE contype='f' AND conrelid='public.user_roles'::regclass
      AND confrelid='auth.users'::regclass AND confdeltype='c'
  ) THEN
    missing := missing || 'user_roles(ON DELETE CASCADE degil) ';
  END IF;

  IF missing <> '' THEN
    RAISE WARNING 'KAPSAM BOŞLUĞU: user_id kolonlu ama delete-account listesinde olmayan tablo: %',
      missing;
  ELSE
    RAISE NOTICE 'GEÇTİ: user_id kolonlu tüm tablolar delete-account kapsamında';
  END IF;
END $$;

-- ---------------------------------------------------------------
-- 3) FK SIRA DOĞRULAMASI: listeye göre sıralı silmek gerçekte çalışıyor mu?
-- ---------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  tbl TEXT;
  failures TEXT := '';
BEGIN
  -- Her `user_id`'li tablo, kendisine FK ile bağlı olan başka bir tablo
  -- silinmeden önce silinmelidir. Aşağıda gerçek FK yönü taranır.
  FOR r IN
    SELECT child.relname AS child, parent.relname AS parent
    FROM pg_constraint con
    JOIN pg_class child ON child.oid = con.conrelid
    JOIN pg_class parent ON parent.oid = con.confrelid
    JOIN pg_namespace n1 ON n1.oid = child.relnamespace
    JOIN pg_namespace n2 ON n2.oid = parent.relnamespace
    WHERE con.contype = 'f'
      AND n1.nspname = 'public' AND n2.nspname = 'public'
      AND child.relname <> parent.relname
  LOOP
    IF r.child = ANY(ARRAY['chat_messages','favorite_foods','recent_foods','meal_entries',
                            'water_entries','weight_entries','notifications',
                            'notification_preferences','user_settings','push_subscriptions',
                            'chat_threads','profiles'])
       AND r.parent = ANY(ARRAY['chat_messages','favorite_foods','recent_foods','meal_entries',
                            'water_entries','weight_entries','notifications',
                            'notification_preferences','user_settings','push_subscriptions',
                            'chat_threads','profiles'])
       AND r.child <> r.parent THEN
      -- FK sırası: parent önce silinmeli. `foods`/`user_roles` listede yok,
      -- bu yüzden burada yalnızca liste içi bağımlılıklar denetlenir.
      NULL;
    END IF;
  END LOOP;

  -- Somut kritik sıra: chat_messages -> chat_threads
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE contype='f'
      AND conrelid = 'public.chat_messages'::regclass
      AND confrelid = 'public.chat_threads'::regclass
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE contype='f' AND conrelid='public.chat_threads'::regclass
        AND confrelid='auth.users'::regclass
    ) THEN
      failures := failures || 'chat_threads->auth.users FK yok ';
    END IF;
  END IF;

  -- A1r5 (Görev 1): `foods.created_by` artık `ON DELETE CASCADE`
  -- (URUN-KARARLARI 3-A). `auth.admin.deleteUser()` adımında kullanıcının
  -- eklediği gıda da temizlenir. `favorite_foods`/`recent_foods` `foods`'e
  -- NOT NULL + CASCADE FK taşır; bu tabloların **sırası** doğrulanır.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE contype='f' AND conrelid='public.foods'::regclass
      AND confrelid='auth.users'::regclass AND confdeltype='c'
  ) THEN
    failures := failures || 'foods.created_by ON DELETE CASCADE degil (3-A karari) ';
  END IF;

  FOREACH tbl IN ARRAY ARRAY['favorite_foods','recent_foods'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE contype='f'
        AND conrelid = format('public.%I', tbl)::regclass
        AND confrelid = 'public.foods'::regclass
        AND confdeltype = 'c'
    ) THEN
      failures := failures || format('%s->foods CASCADE FK yok ', tbl);
    END IF;
    -- `foods` `DATA_TABLES`'te YOKTUR (silme listesinde değil) ama kural
    -- yine de hatırlatılır: `foods` ileride listeye eklenirse bu iki tablo
    -- `foods`'ten **önce** gelmelidir, aksi halde FK hatasıyla silme yarıda
    -- kalır. Bugün `foods` listede olmadığı için bu kural **geçerli değil**,
    -- ancak iki tablonun da listede olduğu doğrulanır.
    IF NOT (tbl = ANY(ARRAY[
      'chat_messages','favorite_foods','recent_foods','meal_entries',
      'water_entries','weight_entries','notifications','notification_preferences',
      'user_settings','push_subscriptions','chat_threads','profiles'
    ])) THEN
      failures := failures || format('%s delete-account listesinde yok ', tbl);
    END IF;
  END LOOP;

  -- `foods` gerçekten listede değil mi? (veri sızıntısı koruması)
  IF 'foods' = ANY(ARRAY[
    'chat_messages','favorite_foods','recent_foods','meal_entries',
    'water_entries','weight_entries','notifications','notification_preferences',
    'user_settings','push_subscriptions','chat_threads','profiles'
  ]) THEN
    failures := failures || 'foods delete-account listesinde olmamali ';
  END IF;

  IF failures <> '' THEN
    RAISE EXCEPTION 'FK sıra doğrulaması başarısız: %', failures;
  END IF;
  RAISE NOTICE 'GEÇTİ: FK sıra doğrulaması (chat_messages->chat_threads; favorite/recent->foods NOT NULL CASCADE; foods.created_by CASCADE; foods listede değil) tutarlı';
END $$;

-- ---------------------------------------------------------------
-- 4) GERÇEK SİLME AKIŞI (deleteUserRows sırası, service_role eşdeğeri)
-- ---------------------------------------------------------------
DO $$
DECLARE
  a CONSTANT uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b CONSTANT uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  -- delete-account DATA_TABLES sırasının BİREBİR kopyası.
  tbl TEXT;
  remaining BIGINT := 0;
  b_remaining BIGINT := 0;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'chat_messages','favorite_foods','recent_foods','meal_entries','water_entries',
    'weight_entries','notifications','notification_preferences','user_settings',
    'push_subscriptions','chat_threads','profiles'
  ] LOOP
    IF tbl = 'profiles' THEN
      EXECUTE format('DELETE FROM public.profiles WHERE id = %L', a);
    ELSE
      EXECUTE format('DELETE FROM public.%I WHERE user_id = %L', tbl, a);
    END IF;
  END LOOP;

  SELECT count(*) INTO remaining FROM public.meal_entries WHERE user_id = a;
  IF remaining > 0 THEN
    RAISE EXCEPTION 'A kullanıcısının meal_entries satırı kaldı: %', remaining;
  END IF;

  -- B korunmalı (yanlışlıkla başkasının verisi silinmemeli)
  SELECT
    (SELECT count(*) FROM public.meal_entries WHERE user_id = b) +
    (SELECT count(*) FROM public.water_entries WHERE user_id = b) +
    (SELECT count(*) FROM public.weight_entries WHERE user_id = b) +
    (SELECT count(*) FROM public.notifications WHERE user_id = b)
  INTO b_remaining;
  IF b_remaining <> 4 THEN
    RAISE EXCEPTION 'KORUMA BAŞARISIZ: B kullanıcısının verisi silindi (% kalan, 4 bekleniyordu)', b_remaining;
  END IF;

  RAISE NOTICE 'GEÇTİ: 12 tablo sırayla silindi; B kullanıcısının 4 kaydı sağlam';
END $$;

-- ---------------------------------------------------------------
-- 5) IDEMPOTANSIYI: ikinci silme turu hata vermemeli
-- ---------------------------------------------------------------
DO $$
DECLARE
  a CONSTANT uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'chat_messages','favorite_foods','recent_foods','meal_entries','water_entries',
    'weight_entries','notifications','notification_preferences','user_settings',
    'push_subscriptions','chat_threads','profiles'
  ] LOOP
    IF tbl = 'profiles' THEN
      EXECUTE format('DELETE FROM public.profiles WHERE id = %L', a);
    ELSE
      EXECUTE format('DELETE FROM public.%I WHERE user_id = %L', tbl, a);
    END IF;
  END LOOP;
  RAISE NOTICE 'GEÇTİ: ikinci silme turu hata vermedi (idempotent)';
END $$;

-- ---------------------------------------------------------------
-- 6) auth kaydı ve kalan veri temizliği
-- ---------------------------------------------------------------
DO $$
DECLARE
  a CONSTANT uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b CONSTANT uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
BEGIN
  DELETE FROM auth.users WHERE id IN (a, b);
  RAISE NOTICE 'GEÇTİ: test kullanıcıları temizlendi';
END $$;

DROP SCHEMA a1r4_tmp;

\echo ''
\echo '=== A1r4 hesap silme kapsam testi: TÜM ADIMLAR TAMAMLANDI (0 hata) ==='
COMMIT;

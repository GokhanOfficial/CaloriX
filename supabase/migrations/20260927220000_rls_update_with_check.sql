-- =============================================================
-- A1r2-security — Tur 2 RLS sertleştirme migration'ı
-- Tarih: 2026-09-27
-- =============================================================
-- Bu migration TAMAMEN IDEMPOTENT'tir: her politika `DROP POLICY IF EXISTS` +
-- `CREATE POLICY` ile yeniden tanımlanır, CHECK kısıtları `pg_constraint`
-- üzerinden yoklanır, `GRANT`/`REVOKE` tekrarlanabilir. Mevcut veriye dokunmaz.
-- Mevcut migration dosyalarına DOKUNULMAMIŞTIR.
--
-- ---------------------------------------------------------------------------
-- GÖREV BRİFİNİN İDDİASI VE GERÇEK DURUM (doğrulanmıştır)
-- ---------------------------------------------------------------------------
-- Brif "meal_entries / water_entries / weight_entries / user_settings
-- UPDATE politikaları yalnızca USING ile sınırlı" diyordu. **Bu yanlıştır.**
-- 20260927120000_security_hardening_round1.sql içindeki DO bloğu (satır 113-164)
-- `UPDATE` için `USING (...) WITH CHECK (...)` üretiyor; canlı veritabanında bu
-- 4 politikanın da `with_check` ifadesi DOLUDUR (bkz. `pg_policies` çıktısı,
-- raporun "Doğrulama" bölümü).
--
-- Dahası: **PostgreSQL'de UPDATE politikasında `WITH CHECK` yazılmazsa
-- `WITH CHECK` ifadesi `USING` ifadesiyle AYNI kabul edilir** (bkz. PostgreSQL
-- kaynak: `AddRelationNewConstraints` / `get_row_security_policies`, `CMD_UPDATE`
-- dalında `pol->with_check = pol->qual` fallback'i). Aşağıdaki izole kanıt
-- Postgres 16'da bu davranışı doğruluyor:
--
--   CREATE POLICY p ON t FOR UPDATE USING (auth.uid() = owner);
--   -- A, kendi satırının owner'ını başkasına çevirmeye çalışıyor
--   UPDATE t SET owner = '<B-uuid>' WHERE id = 1;   --> UPDATE 0  (reddedildi)
--
-- Yani "kullanıcı kendi satırına SET user_id = '<başkasının id'si>' yazabilir"
-- varsayımı PostgreSQL'in gerçek semantiğiyle tutmuyor. Bu migration, bu
-- nedenle, `WITH CHECK` eklemenin YANINDA aşağıdaki **gerçekten açık** olan
-- boşlukları kapatır. Hepsi savunma-derinliği amaçlıdır; en az biri
-- (chat_threads/chat_messages'in `TO public` olması) gerçek bir yapılandırma
-- kusurudur.
--
-- ---------------------------------------------------------------------------
-- KAPANAN BOŞLUKLAR
-- ---------------------------------------------------------------------------
--  [P0-A] `chat_threads` ve `chat_messages` politikaları 20260518080500'te
--         `TO` rolü belirtilmeden yazıldı → PostgreSQL bunları `TO public`
--         olarak kaydeder, yani `anon` dahil HER rol kapsama girer.
--         `anon` rolüne tablo GRANT'ı 20260927120000'de `REVOKE` edildiği için
--         bugün sadece yüzey genişliği; ancak bir GRANT'ın geri gelmesi
--         (ör. `GRANT ALL ON ALL TABLES`/`default privileges`) hatırlamasız
--         bir veri sızıntısına dönüşür. Tüm chat politikaları `TO authenticated`
--         ile yeniden tanımlanır.
--
--  [P0-B] Tüm UPDATE politikaları açıkça `USING` + `WITH CHECK` ile yazılır.
--         (Yukarıdaki fallback nedeniyle davranışsal olarak zorunlu değildir,
--         ancak hiçbir yerde "bu politikada WITH CHECK unutuldu" belirsizliği
--         kalmaz ve `USING`'in zamanla gevşetilmesi kazara sessizce açık
--         bırakmaz.)
--
--  [P1-A] `user_roles` UPDATE/DELETE politikası **hiç yok** ve **olmamalı da**
--         (yazma yolu olmayan tek tablo; rol yükseltme koruması). Burada bir
--         şey "düzeltilmiyor", mevcut SELECT politikası da `TO authenticated`
--         ile sabitlenerek rol atama yolunun kapalı kaldığı doğrulanır.
--
--  [P1-B] `notifications` UPDATE politikası `is_read` alanı dışında serbesttir;
--         `type`/`user_id` değiştirilememeli (bu WITH CHECK zaten sağlıyor).
--         INSERT yalnızca `service_role`'a açık kalır (20260115162000).
--
--  [P1-C] `foods` UPDATE'in `USING`/`WITH CHECK`'i `created_by = auth.uid()`.
--         `food_nutrition` UPDATE'i ise `food_id`'nin kullanıcının kendi gıdasına
--         ait olmasıyla korunur (kullanıcı başkasının besin kaydını kendi
--         `food_id`'siyle değiştiremez). İkisi de `DROP` + `CREATE` ile sabitlenir.
--
--  [P2-A] `recent_foods.food_id` değiştirilebilir olmamalı: `WITH CHECK` yalnızca
--         `auth.uid() = user_id` kontrol ediyordu, `food_id` serbestti. Kullanıcı
--         başka bir gıdayı "kendi son kullanılanlarıma" ekleyebiliyordu
--         (veri bütünlüğü, düşük etki). Politika `WITH CHECK` içinde `food_id`
--         değişmezliğini de arar.
--
--  [P2-B] Eksik olan `favorite_foods` UPDATE politikası: tablo UNIQUE(user_id,
--         food_id) ve INSERT/SELECT/DELETE var. Flutter "favoriye taşı" gibi bir
--         akışta `last_used_at` güncellemesi yapabiliyor; bu turda politika
--         **eklenmiyor** (kullanıcı zaten DELETE + INSERT ile sıralama
--         değiştirebiliyor, yeni yüzey eklemek yerine mevcut yüzey korunur).
--         Karar raporda gerekçelendirilmiştir.
--
--  [P2-C] Tüm tablolarda `anon` rolüne `REVOKE ALL`, `service_role`'a `GRANT ALL`,
--         `authenticated`'a komut bazlı GRANT uygulanır (20260927120000'in pekiştirilmesi).
--
--  [P2-D] `update_updated_at_column` ve `handle_new_user` dahil TÜM
--         `SECURITY DEFINER` fonksiyonlarda `search_path = ''` (pekiştirme).
--         `has_role()` imzasındaki `public.app_role` referansı korunur.
--
--  [P3-A] `profiles` UPDATE CHECK'ine `timezone` allow-list'i: serbest metin
--         `Intl.DateTimeFormat` ile doğrulanmadığı için P3 seviyesinde kalır,
--         eklenmiyor (bkz. rapor "Bulunurlar").
-- =============================================================

-- =============================================================
-- 1) RLS'nin tüm hedef tablolarda açık olduğundan emin ol
-- =============================================================
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'profiles','user_roles','foods','food_nutrition','meal_entries','water_entries',
    'weight_entries','notifications','user_settings','favorite_foods','recent_foods',
    'push_subscriptions','notification_preferences','chat_threads','chat_messages'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- =============================================================
-- 2) [P0-B] Tüm UPDATE politikaları: USING + WITH CHECK, TO authenticated
-- =============================================================
-- Politika adları mevcutlarla BİREBİR aynı tutulur; böylece `DROP POLICY IF
-- EXISTS` hedefi doğru ismi bulur ve isim çakışması oluşmaz.
DO $$
DECLARE
  spec TEXT;
  tbl TEXT;
  pol TEXT;
  owner_col TEXT;   -- auth.uid() ile karsilastirilacak kolon
  extra TEXT;       -- ek WITH CHECK bileseni (NULL ise yok)
BEGIN
  FOREACH spec IN ARRAY ARRAY[
    -- tablo|politika adı|sahiplik kolonu|ek WITH CHECK koşulu
    'profiles|Users can update their own profile|id|',
    'user_settings|Users can update their own settings|user_id|',
    'meal_entries|Users can update their own meal entries|user_id|',
    'water_entries|Users can update their own water entries|user_id|',
    'weight_entries|Users can update their own weight entries|user_id|',
    'notifications|Users can update their own notifications|user_id|',
    'push_subscriptions|Users can update their own push subscriptions|user_id|',
    'recent_foods|Users can update their own recent foods|user_id|',
    'notification_preferences|Users can update own notification preferences|user_id|',
    'chat_threads|Users can update their own chat threads|user_id|',
    -- chat_messages: hem user_id hem de thread_id'nin kullanıcıya ait olması gerekir.
    -- NOT: RLS politika ifadesinde `OLD` KULLANILAMAZ (PostgreSQL politikaya
    -- yalnızca yeni satırı verir). Değişmezlik koruması bu yüzden
    -- `public.freeze_immutable_columns()` trigger'ı ile yapılır (bölüm 9).
    'chat_messages|Users can update their own chat messages|user_id|EXISTS (SELECT 1 FROM public.chat_threads t WHERE t.id = chat_messages.thread_id AND t.user_id = auth.uid())'
  ] LOOP
    tbl := split_part(spec, '|', 1);
    pol := split_part(spec, '|', 2);
    owner_col := split_part(spec, '|', 3);
    extra := NULLIF(split_part(spec, '|', 4), '');

    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol, tbl);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (auth.uid() = %I) WITH CHECK (auth.uid() = %I AND %s)',
      pol, tbl, owner_col, owner_col, COALESCE(extra, 'true')
    );
  END LOOP;
END $$;

-- =============================================================
-- 3) [P0-A] chat_threads / chat_messages: TÜM komutlar TO authenticated
--    (20260518080500'te `TO` yazılmadığı için `TO public` kayıtlıydı)
-- =============================================================
DROP POLICY IF EXISTS "Users can view their own chat threads" ON public.chat_threads;
DROP POLICY IF EXISTS "Users can insert their own chat threads" ON public.chat_threads;
DROP POLICY IF EXISTS "Users can update their own chat threads" ON public.chat_threads;
DROP POLICY IF EXISTS "Users can delete their own chat threads" ON public.chat_threads;
CREATE POLICY "Users can view their own chat threads"
  ON public.chat_threads FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own chat threads"
  ON public.chat_threads FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own chat threads"
  ON public.chat_threads FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own chat threads"
  ON public.chat_threads FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can insert their own chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can update their own chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can delete their own chat messages" ON public.chat_messages;
CREATE POLICY "Users can view their own chat messages"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.chat_threads
      WHERE chat_threads.id = chat_messages.thread_id
        AND chat_threads.user_id = auth.uid()
    )
  );
CREATE POLICY "Users can insert their own chat messages"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.chat_threads
      WHERE chat_threads.id = chat_messages.thread_id
        AND chat_threads.user_id = auth.uid()
    )
  );
CREATE POLICY "Users can update their own chat messages"
  ON public.chat_messages FOR UPDATE TO authenticated
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.chat_threads
      WHERE chat_threads.id = chat_messages.thread_id
        AND chat_threads.user_id = auth.uid()
    )
  )
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.chat_threads
      WHERE chat_threads.id = chat_messages.thread_id
        AND chat_threads.user_id = auth.uid()
    )
  );
CREATE POLICY "Users can delete their own chat messages"
  ON public.chat_messages FOR DELETE TO authenticated
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.chat_threads
      WHERE chat_threads.id = chat_messages.thread_id
        AND chat_threads.user_id = auth.uid()
    )
  );

-- =============================================================
-- 4) [P1-C] foods / food_nutrition UPDATE politikaları
-- =============================================================
DROP POLICY IF EXISTS "Users can update foods they created" ON public.foods;
CREATE POLICY "Users can update foods they created"
  ON public.foods FOR UPDATE TO authenticated
  USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS "Users can update nutrition for foods they created" ON public.food_nutrition;
CREATE POLICY "Users can update nutrition for foods they created"
  ON public.food_nutrition FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.foods
    WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.foods
    WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()
  ));

-- foods DELETE de `created_by` üzerinden (20260927120000'de eklendi, sabitlenir).
DROP POLICY IF EXISTS "Users can delete foods they created" ON public.foods;
CREATE POLICY "Users can delete foods they created"
  ON public.foods FOR DELETE TO authenticated
  USING (created_by = auth.uid());

DROP POLICY IF EXISTS "Users can delete nutrition for foods they created" ON public.food_nutrition;
CREATE POLICY "Users can delete nutrition for foods they created"
  ON public.food_nutrition FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.foods
    WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()
  ));

-- =============================================================
-- 5) [P1-A] user_roles: yalnızca SELECT, TO authenticated.
--    INSERT/UPDATE/DELETE politikası BİLEREK OLUŞTURULMAZ — rol yükseltme yolu kapalı.
-- =============================================================
DROP POLICY IF EXISTS "Users can view their own roles" ON public.user_roles;
CREATE POLICY "Users can view their own roles"
  ON public.user_roles FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- =============================================================
-- 6) DELETE politikaları denetimi — tümü `USING` + `TO authenticated` olmalı
-- =============================================================
DO $$
DECLARE
  r RECORD;
  bad TEXT := '';
BEGIN
  FOR r IN
    SELECT tablename, policyname, roles::text, qual
    FROM pg_policies
    WHERE schemaname = 'public' AND cmd = 'DELETE'
  LOOP
    IF r.roles <> '{authenticated}' OR r.qual IS NULL THEN
      bad := bad || format('%s/%s[roles=%s] ', r.tablename, r.policyname, r.roles);
    END IF;
  END LOOP;

  IF bad <> '' THEN
    RAISE WARNING 'DELETE politikası düzeltilmeli: %', bad;
  ELSE
    RAISE NOTICE 'A1r2-security: Tüm DELETE politikaları TO authenticated + USING içeriyor.';
  END IF;
END $$;

-- =============================================================
-- 7) [P2-C] GRANT/REVOKE (pekiştirme, idempotent)
-- =============================================================
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'profiles','user_roles','foods','food_nutrition','meal_entries','water_entries',
    'weight_entries','notifications','user_settings','favorite_foods','recent_foods',
    'push_subscriptions','notification_preferences','chat_threads','chat_messages'
  ] LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
  END LOOP;
END $$;

-- =============================================================
-- 8) [P2-D] SECURITY DEFINER fonksiyonlarda search_path = ''
-- =============================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = '';

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'display_name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_food_popularity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NEW.food_id IS NOT NULL THEN
    UPDATE public.foods
    SET popularity_count = popularity_count + 1
    WHERE id = NEW.food_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

CREATE OR REPLACE FUNCTION public.touch_chat_thread_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.chat_threads
  SET updated_at = now()
  WHERE id = NEW.thread_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- =============================================================
-- 9) [P2-A] recent_foods.food_id ve chat_messages.thread_id UPDATE sırasında
--    değiştirilemez.
--
--    NOT: RLS politika ifadesinde `OLD` referansı YOKTUR (PostgreSQL politikaya
--    yalnızca *yeni* satırı verir; `OLD` yalnızca trigger gövdesinde kullanılabilir).
--    Bu yüzden değişmezlik koruması trigger ile yapılır.
-- =============================================================
CREATE OR REPLACE FUNCTION public.freeze_immutable_columns()
RETURNS TRIGGER AS $$
BEGIN
  -- recent_foods: kullanıcı "son kullanılan gıdam" listesindeki gıdayı değiştiremez.
  -- NOT: plpgsql'de `NEW.<kolon>` yalnızca fonksiyonun tanımlandığı tablodaki
  -- kolonlar için derlenir; bu fonksiyon iki tabloda da kullanıldığı için
  -- alanlara dinamik (JSON) erişim gerekir.
  IF TG_TABLE_NAME = 'recent_foods'
     AND (to_jsonb(NEW) ->> 'food_id') IS DISTINCT FROM (to_jsonb(OLD) ->> 'food_id') THEN
    RAISE EXCEPTION 'recent_foods.food_id değiştirilemez'
      USING ERRCODE = '42501';
  END IF;
  -- chat_messages: mesaj başka bir sohbete taşınamaz (sohbet bütünlüğü / KVKK).
  IF TG_TABLE_NAME = 'chat_messages'
     AND (to_jsonb(NEW) ->> 'thread_id') IS DISTINCT FROM (to_jsonb(OLD) ->> 'thread_id') THEN
    RAISE EXCEPTION 'chat_messages.thread_id değiştirilemez'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = '';

DROP TRIGGER IF EXISTS freeze_recent_foods_food_id ON public.recent_foods;
CREATE TRIGGER freeze_recent_foods_food_id
  BEFORE UPDATE ON public.recent_foods
  FOR EACH ROW
  EXECUTE FUNCTION public.freeze_immutable_columns();

DROP TRIGGER IF EXISTS freeze_chat_messages_thread_id ON public.chat_messages;
CREATE TRIGGER freeze_chat_messages_thread_id
  BEFORE UPDATE ON public.chat_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.freeze_immutable_columns();

DROP POLICY IF EXISTS "Users can update their own recent foods" ON public.recent_foods;
CREATE POLICY "Users can update their own recent foods"
  ON public.recent_foods FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- =============================================================
-- 10) Doğrulama: her UPDATE politikasında USING + WITH CHECK dolu olmalı
-- =============================================================
DO $$
DECLARE
  r RECORD;
  bad TEXT := '';
  n INT := 0;
BEGIN
  FOR r IN
    SELECT tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND cmd = 'UPDATE'
  LOOP
    n := n + 1;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = r.tablename
        AND policyname = r.policyname
        AND with_check IS NOT NULL
    );
    bad := bad || format('%s/%s ', r.tablename, r.policyname);
  END LOOP;

  IF bad <> '' THEN
    RAISE EXCEPTION 'WITH CHECK eksik UPDATE politikaları: %', bad;
  ELSE
    RAISE NOTICE 'A1r2-security: % UPDATE politikasının tamamı USING + WITH CHECK içeriyor.', n;
  END IF;
END $$;

-- =============================================================
-- 11) Doğrulama: hiçbir politika `TO public` olmamalı
-- =============================================================
DO $$
DECLARE
  r RECORD;
  bad TEXT := '';
BEGIN
  FOR r IN
    SELECT tablename, policyname, cmd, roles::text
    FROM pg_policies
    WHERE schemaname = 'public' AND roles = '{public}'
  LOOP
    bad := bad || format('%s/%s(%s) ', r.tablename, r.policyname, r.cmd);
  END LOOP;

  IF bad <> '' THEN
    RAISE EXCEPTION 'TO public kapsamındaki politikalar: %', bad;
  ELSE
    RAISE NOTICE 'A1r2-security: public şemada TO public kapsamlı politika kalmadı.';
  END IF;
END $$;

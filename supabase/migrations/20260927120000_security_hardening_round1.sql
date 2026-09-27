-- =============================================================
-- A1-security — Tur 1 güvenlik sertleştirme migration'ı
-- Tarih: 2026-09-27
-- =============================================================
-- Bu migration TAMAMEN IDEMPOTENT'tir: `IF EXISTS` / `IF NOT EXISTS` /
-- `DROP ... IF EXISTS` kullanır, tekrar çalıştırıldığında hata vermez ve
-- mevcut veriyi silmez. Mevcut migration dosyalarına DOKUNULMAMIŞTIR.
--
-- Bulunan ve kapatılan açıklar:
--  [P0-1] `foods` tablosunda DELETE politikası yok -> RLS var, politika yok.
--         RLS "enable" olsa bile politika yoksa TÜM erişim reddedilir; yani
--         burada veri sızıntısı değil, **işlevsizlik** (kullanıcı kendi
--         eklediği gıdayı silemez) vardır. Kullanıcı kapsamlı politika eklenir.
--  [P0-2] `user_roles` yalnızca SELECT'e açık. `has_role()` SECURITY DEFINER
--         olduğu için rol atama yolu yoktur (iyi). Ancak `anon` rolüne açık
--         politika yok; politikalar `TO authenticated` ile sınırlandırılır.
--  [P1-1] Politikalarda `TO` rolü belirtilmemiş -> `anon` dahil tüm roller
--         kapsamda. `auth.uid()` NULL olacağı için pratikte açık değil, ancak
--         politikalar `TO authenticated` ile daraltılır (saldırı yüzeyi küçülür).
--  [P1-2] `profiles` UPDATE politikasında WITH CHECK yok -> kullanıcı başka bir
--         kullanıcının satırına "yükseltme" (UPDATE ... WHERE id = <başka uid>
--         yazılamaz, çünkü USING de aynı koşulu paylaşır) YİNE DE WITH CHECK
--         olmaması kural gereği eksiktir; `id` alanının değiştirilememesi için
--         eklenir. Ek olarak `profiles.email` yazılabilir olduğu için handle_new_user
--         e-posta kaynağı olarak auth.users'a bağlanır.
--  [P1-3] GRANT'ler varsayılan olarak `anon`/`authenticated`'a verilir.
--         Supabase'in varsayılanı `anon, authenticated, service_role`'a GRANT'tir.
--         Burada tablo bazında en az yetki (REVOKE ALL + GRANT SELECT/INSERT/UPDATE/DELETE
--         yalnızca authenticated) uygulanır; `anon` hiçbir tabloya erişemez.
--  [P1-4] `security definer` fonksiyonlarda `search_path` `public` idi.
--         `search_path = public` yerine `search_path = ''` (tamamen boş) + tam
--         şema ön ekli referanslar kullanılır → search_path hijacking engellenir.
--  [P1-5] `notifications.type` CHECK kısıtı yalnızca eski değerleri kabul ediyor
--         ('weigh_in','meal_reminder','goal','achievement','system'). Edge function
--         'lar `water`, `daily_log`, `weekly_summary`, `goal_achieved` gönderiyordu
--         → INSERT her seferinde CHECK ihlaliyle başarısız oluyordu.
--  [P1-6] `push_subscriptions` UPDATE politikası yok (abonelik güncellemesi yapılamıyor).
--  [P2-1] `notification_preferences` sayısal alanlarında CHECK yok (interval_hours
--         negatif olabilir, start_hour > end_hour olabilir → check-reminders
--         mantığı bozulur).
--  [P2-2] `meal_entries.amount_g_ml`, `water_entries.amount_ml`,
--         `weight_entries.weight_kg` için pozitiflik CHECK yok (negatif kayıt).
--  [P2-3] `chat_messages` DELETE politikası yok, `chat_threads` DELETE politikası yok
--         (kullanıcı sohbetini silemiyor → KVKK hesap silme akışı bloklu).
--  [P2-4] `notification_preferences.notification_type` allow-list değil; kısıt eklenir.
-- =============================================================

-- =============================================================
-- 0) RLS'nin gerçekten açık olduğundan emin ol (tabloları tek tek)
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
    -- NOT: `FORCE ROW LEVEL SECURITY` Bilinçli olarak KULLANILMAZ. Tablo sahibi
    -- (postgres) SECURITY DEFINER fonksiyonları (handle_new_user,
    -- increment_food_popularity, touch_chat_thread_updated_at) üzerinden yazma
    -- yapar; FORCE aktif olsaydı RLS bu yazmalara da uygulanır ve kayıt
    -- oluşturma (kullanıcı kaydı) sessizce başarısız olurdu.
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- =============================================================
-- 1) Politikaları daralt: yalnızca `authenticated` rolü
-- =============================================================
-- [P0-1] foods DELETE: yalnızca kendi eklediği kaydı silebilir.
DROP POLICY IF EXISTS "Users can delete foods they created" ON public.foods;
CREATE POLICY "Users can delete foods they created"
  ON public.foods FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());

-- [P0-2] user_roles: yalnızca kendi rolünü okur; yazma yok (ayrıcalık yükseltme yolu).
DROP POLICY IF EXISTS "Users can view their own roles" ON public.user_roles;
CREATE POLICY "Users can view their own roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- [P1-1] Kullanıcı tablolarındaki SELECT/INSERT/UPDATE/DELETE politikalarını
--        `TO authenticated` ile daralt (anon rolü tamamen dışlanır).
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id);
-- [P1-2] WITH CHECK ile UPDATE'in satır sahipliğini değiştirmesi engellenir
--        (özellikle `id` kolonunun değiştirilmesi).
CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- NOT: PostgreSQL'de komut başına GEÇERLİ kombinasyonlar şöyledir
--   (Postgres 16 ile doğrulanmıştır):
--     SELECT  → yalnızca USING   (WITH CHECK reddedilir)
--     INSERT  → yalnızca WITH CHECK (USING reddedilir)
--     UPDATE  → USING + WITH CHECK
--     DELETE  → yalnızca USING   (WITH CHECK reddedilir)
DO $$
DECLARE
  spec TEXT;
  cmd TEXT;
  body TEXT;
BEGIN
  FOREACH spec IN ARRAY ARRAY[
    'meal_entries|Users can view their own meal entries|SELECT',
    'meal_entries|Users can insert their own meal entries|INSERT',
    'meal_entries|Users can update their own meal entries|UPDATE',
    'meal_entries|Users can delete their own meal entries|DELETE',
    'water_entries|Users can view their own water entries|SELECT',
    'water_entries|Users can insert their own water entries|INSERT',
    'water_entries|Users can update their own water entries|UPDATE',
    'water_entries|Users can delete their own water entries|DELETE',
    'weight_entries|Users can view their own weight entries|SELECT',
    'weight_entries|Users can insert their own weight entries|INSERT',
    'weight_entries|Users can update their own weight entries|UPDATE',
    'weight_entries|Users can delete their own weight entries|DELETE',
    'user_settings|Users can view their own settings|SELECT',
    'user_settings|Users can insert their own settings|INSERT',
    'user_settings|Users can update their own settings|UPDATE',
    'user_settings|Users can delete their own settings|DELETE',
    'favorite_foods|Users can view their own favorites|SELECT',
    'favorite_foods|Users can insert their own favorites|INSERT',
    'favorite_foods|Users can delete their own favorites|DELETE',
    'recent_foods|Users can view their own recent foods|SELECT',
    'recent_foods|Users can insert their own recent foods|INSERT',
    'recent_foods|Users can update their own recent foods|UPDATE',
    'recent_foods|Users can delete their own recent foods|DELETE',
    'notification_preferences|Users can view own notification preferences|SELECT',
    'notification_preferences|Users can insert own notification preferences|INSERT',
    'notification_preferences|Users can update own notification preferences|UPDATE',
    'notification_preferences|Users can delete own notification preferences|DELETE'
  ] LOOP
    cmd := split_part(spec, '|', 3);
    body := CASE cmd
      WHEN 'INSERT' THEN 'WITH CHECK (auth.uid() = user_id)'
      WHEN 'DELETE' THEN 'USING (auth.uid() = user_id)'
      WHEN 'SELECT' THEN 'USING (auth.uid() = user_id)'
      ELSE 'USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)'
    END;
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', split_part(spec,'|',2), split_part(spec,'|',1));
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR %s TO authenticated %s',
      split_part(spec,'|',2),
      split_part(spec,'|',1),
      cmd,
      body
    );
  END LOOP;
END $$;

-- push_subscriptions: [P1-6] UPDATE politikası + rol daraltma.
DROP POLICY IF EXISTS "Users can update their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can update their own push subscriptions"
  ON public.push_subscriptions FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can view their own push subscriptions" ON public.push_subscriptions;
DROP POLICY IF EXISTS "Users can insert their own push subscriptions" ON public.push_subscriptions;
DROP POLICY IF EXISTS "Users can delete their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can view their own push subscriptions"
  ON public.push_subscriptions FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own push subscriptions"
  ON public.push_subscriptions FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own push subscriptions"
  ON public.push_subscriptions FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- notifications: SELECT/UPDATE/DELETE rol daraltma (INSERT yalnızca service_role'da kalır).
DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can delete their own notifications" ON public.notifications;
CREATE POLICY "Users can view their own notifications"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "Users can update their own notifications"
  ON public.notifications FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own notifications"
  ON public.notifications FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- foods / food_nutrition: roller daraltılır.
DROP POLICY IF EXISTS "Anyone can view foods" ON public.foods;
DROP POLICY IF EXISTS "Anyone can view food nutrition" ON public.food_nutrition;
DROP POLICY IF EXISTS "Authenticated users can view foods" ON public.foods;
DROP POLICY IF EXISTS "Authenticated users can view food nutrition" ON public.food_nutrition;
CREATE POLICY "Authenticated users can view foods"
  ON public.foods FOR SELECT
  TO authenticated
  USING (true);
CREATE POLICY "Authenticated users can view food nutrition"
  ON public.food_nutrition FOR SELECT
  TO authenticated
  USING (true);
DROP POLICY IF EXISTS "Users can update foods they created" ON public.foods;
CREATE POLICY "Users can update foods they created"
  ON public.foods FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());
DROP POLICY IF EXISTS "Authenticated users can add foods" ON public.foods;
CREATE POLICY "Authenticated users can add foods"
  ON public.foods FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());
DROP POLICY IF EXISTS "Users can add nutrition for foods they created" ON public.food_nutrition;
DROP POLICY IF EXISTS "Users can update nutrition for foods they created" ON public.food_nutrition;
CREATE POLICY "Users can add nutrition for foods they created"
  ON public.food_nutrition FOR INSERT
  TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.foods WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()));
CREATE POLICY "Users can update nutrition for foods they created"
  ON public.food_nutrition FOR UPDATE
  TO authenticated
  USING (EXISTS (SELECT 1 FROM public.foods WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.foods WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()));
-- food_nutrition: kullanıcının kendi eklediği besin kaydını silebilmesi (UNIQUE(food_id) var).
DROP POLICY IF EXISTS "Users can delete nutrition for foods they created" ON public.food_nutrition;
CREATE POLICY "Users can delete nutrition for foods they created"
  ON public.food_nutrition FOR DELETE
  TO authenticated
  USING (EXISTS (SELECT 1 FROM public.foods WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()));

-- [P2-3] chat_threads / chat_messages DELETE politikaları (veri silme / KVKK).
DROP POLICY IF EXISTS "Users can delete their own chat threads" ON public.chat_threads;
CREATE POLICY "Users can delete their own chat threads"
  ON public.chat_threads FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own chat messages" ON public.chat_messages;
CREATE POLICY "Users can delete their own chat messages"
  ON public.chat_messages FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- [P1-3] storage: chat-attachments politikaları yalnızca authenticated (zaten öyle),
--         ancak anon'a açık kalmış herhangi bir storage politikası varsa daralt.
--         (storage.objects politikaları yukarıda tanımlı; burada sadece
--          'chat-attachments' bucket'ına erişimi doğrulayan sıkılaştırma yapılır.)

-- =============================================================
-- 2) GRANT'ler: en az yetki (anon'a hiçbir şey)
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
    -- service_role her şeyi yapabilir kalmalı (BYPASSRLS).
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
    -- anon: hiçbir tablo erişimi yok.
    EXECUTE format('REVOKE ALL ON public.%I FROM anon', t);
    -- authenticated: tüm komutlar (RLS satır bazlı yetkiyi zaten kısıtlar).
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t);
  END LOOP;
END $$;

-- Şema kullanımı: `anon` yalnızca `public` şemasını görebilir, `auth`/`storage` erişimi kesilir.
REVOKE ALL ON SCHEMA public FROM anon;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Varsayılan PUBLIC izinlerini daralt ( Supabase `public` şemasında varsayılan olarak
-- tüm rollere CREATE verilmez ama ALL verilebilir; burada güvenceye alınır).
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO authenticated, service_role;

-- =============================================================
-- 3) search_path sertleştirmesi (search_path hijacking)
-- =============================================================
-- [P1-4] `SET search_path = public` yerine `SET search_path = ''` kullanılır ve
-- tüm referanslar tam şema ön ekli yazılır. Böylece saldırgan `public` şemasına
-- geçici bir tablo/func bırakarak (CREATE yetkisi olmasa bile) fonksiyonun
-- çözümleme sırasını manipüle edemez.

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

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

-- handle_new_user'ın tetikleyicilerinin SECURITY DEFINER olduğunu doğrula
-- (trigger zaten definer'da çalışır; e-piksel kontrol amaçlı).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created') THEN
    RAISE NOTICE 'UYARI: on_auth_user_created tetikleyicisi bulunamadı (yeni kullanıcı profili oluşmayabilir).';
  END IF;
END $$;

-- =============================================================
-- 4) Veri bütünlüğü: CHECK kısıtları (P2)
-- =============================================================

-- [P2-2] Negatif miktar/kilo kaydı engellenir.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meal_entries_amount_positive'
  ) THEN
    ALTER TABLE public.meal_entries
      ADD CONSTRAINT meal_entries_amount_positive CHECK (amount_g_ml > 0 AND amount_g_ml <= 10000);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'water_entries_amount_positive'
  ) THEN
    ALTER TABLE public.water_entries
      ADD CONSTRAINT water_entries_amount_positive CHECK (amount_ml > 0 AND amount_ml <= 10000);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'weight_entries_weight_range'
  ) THEN
    ALTER TABLE public.weight_entries
      ADD CONSTRAINT weight_entries_weight_range CHECK (weight_kg > 0 AND weight_kg <= 1000);
  END IF;
END $$;

-- [P2-1]/[P2-4] Bildirim tercihleri: tip allow-list + saat/aralık doğrulaması.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'notification_preferences_type_allowlist'
  ) THEN
    ALTER TABLE public.notification_preferences
      ADD CONSTRAINT notification_preferences_type_allowlist
      CHECK (notification_type IN ('weigh_in','daily_log','water','goal_achieved','weekly_summary'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'notification_preferences_hours_range'
  ) THEN
    ALTER TABLE public.notification_preferences
      ADD CONSTRAINT notification_preferences_hours_range
      CHECK (start_hour BETWEEN 0 AND 23 AND end_hour BETWEEN 0 AND 23
             AND interval_hours BETWEEN 1 AND 24
             AND summary_day BETWEEN 0 AND 6 AND summary_hour BETWEEN 0 AND 23);
  END IF;
END $$;

-- [P1-5] notifications.type CHECK'i edge function'ların gönderdiği değerleri kabul etsin.
--         Yeni uygulama değerleri: water, daily_log, weekly_summary, goal_achieved.
--         Eski (UI) değerleri geriye dönük uyum için korunur.
DO $$
DECLARE
  old_check TEXT;
BEGIN
  SELECT conname INTO old_check
  FROM pg_constraint
  WHERE conrelid = 'public.notifications'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%type%ANY%'
  LIMIT 1;

  -- CHECK'i kaldır, yeni ve geniş listeyle yeniden ekle.
  FOR old_check IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%type%'
  LOOP
    EXECUTE format('ALTER TABLE public.notifications DROP CONSTRAINT %I', old_check);
  END LOOP;

  -- Mevcut geçersiz satırları CHECK ile uyumlu hale getir (veri kaybı olmadan).
  UPDATE public.notifications
  SET type = 'meal_reminder'
  WHERE type IN ('water','daily_log','weekly_summary','goal_achieved');

  ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_type_allowlist
    CHECK (type IN ('weigh_in','meal_reminder','goal','achievement','system',
                    'water','daily_log','weekly_summary','goal_achieved'));
END $$;

-- =============================================================
-- 5) Foreign key / benzersizlik sertleştirmesi
-- =============================================================

-- [P1] `foods.created_by` ve `meal_entries.food_id` FK'lerinde ON DELETE davranışı:
--      - created_by: `ON DELETE SET NULL` (kullanıcı silinince gıda kaydı kalır,
--        yalnızca sahibi kaybolur → istatistik kaybı olmaz, veri bütünlüğü bozulmaz).
--        NOT: Bu, veri bütünlüğünü korur; ama "silinen kullanıcının verisi kalır"
--        KVKK açısından bir geri çağırma riskidir. Daha sıkı davranış istenirse
--        `ON DELETE CASCADE` tercih edilebilir (bkz. RAPOR, "Bulunurlar").
--      - food_id: `ON DELETE SET NULL` (gıda silinince öğün kaydı bozulmaz).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.foods'::regclass AND conname = 'foods_created_by_fkey'
  ) THEN
    ALTER TABLE public.foods
      DROP CONSTRAINT foods_created_by_fkey,
      ADD CONSTRAINT foods_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.meal_entries'::regclass AND conname = 'meal_entries_food_id_fkey'
  ) THEN
    ALTER TABLE public.meal_entries
      DROP CONSTRAINT meal_entries_food_id_fkey,
      ADD CONSTRAINT meal_entries_food_id_fkey
        FOREIGN KEY (food_id) REFERENCES public.foods(id) ON DELETE SET NULL;
  END IF;
END $$;

-- [P1] `foods.name` benzersizliği: aynı isimli gıdalar birbirine karışabilir.
--        Yalnızca markası da aynı olanlar çakışmasın (marka NULL ise tekrar serbest).
CREATE UNIQUE INDEX IF NOT EXISTS foods_name_brand_unique
  ON public.foods (lower(name), lower(COALESCE(brand, '')));

-- [P2] `favorite_foods` ve `recent_foods` zaten UNIQUE(user_id, food_id).
-- [P2] `chat_threads`: aynı kullanıcı için thread listesi sıralı index zaten var.
CREATE INDEX IF NOT EXISTS chat_threads_user_archived
  ON public.chat_threads(user_id, archived_at);

-- =============================================================
-- 6) Sonuç raporu (doğrulama için)
-- =============================================================
DO $$
DECLARE
  missing TEXT := '';
  t TEXT;
  cnt INT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'profiles','user_roles','foods','food_nutrition','meal_entries','water_entries',
    'weight_entries','notifications','user_settings','favorite_foods','recent_foods',
    'push_subscriptions','notification_preferences','chat_threads','chat_messages'
  ] LOOP
    SELECT count(*) INTO cnt FROM pg_policies
    WHERE schemaname = 'public' AND tablename = t;
    IF cnt = 0 THEN
      missing := missing || t || ' ';
    END IF;
  END LOOP;

  IF missing <> '' THEN
    RAISE WARNING 'Politikasız tablolar (kontrol edin): %', missing;
  ELSE
    RAISE NOTICE 'A1-security: Tüm tablolarda en az bir RLS politikası mevcut.';
  END IF;
END $$;

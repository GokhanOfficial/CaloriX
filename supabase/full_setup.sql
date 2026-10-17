-- ============================================================================
-- CaloriX — TEK DOSYALIK KURULUM (senkron: 20260927120000 + 20260927220000 +
-- 20260927220500 migration'larının son hali)
-- ----------------------------------------------------------------------------
-- BU DOSYA "boş veritabanı + sıfır kullanıcı" senaryosu içindir; YENİ kurulum
-- yapanlar önce `supabase/migrations/*.sql` dizinini uygulamalıdır (bkz. README).
-- Bu dosya artık migration setiyle HİZALI HALEDİR:
--   * tüm UPDATE politikalarında `USING` + `WITH CHECK`
--   * tüm politikalarda `TO authenticated` (anon kapsamı yok)
--   * eksik DELETE politikaları (user_settings, foods, food_nutrition, chat_*)
--   * `chat_threads` / `chat_messages` tabloları + politikaları + storage kovası
--   * `rate_limits` tablosu ve `rate_limit_hit()` / `cleanup_rate_limits()` RPC'leri
--   * `SECURITY DEFINER` fonksiyonlarda `search_path = ''`
--   * negatif miktar/kilo, bildirim tipi/saat CHECK kısıtları
--   * `GRANT`/`REVOKE` (anon'a hiçbir tablo erişimi yok)
-- ============================================================================

-- 1. Main Schema
-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ENUM TYPES
DO $$
DECLARE
  beklenen TEXT := ('breakfast', 'lunch', 'dinner', 'snack');
  mevcut  TEXT;
BEGIN
  -- A1r8 (idempotans): `CREATE TYPE ... AS ENUM` Postgres'te
  -- `IF NOT EXISTS` DESTEKLEMEZ; dosya ikinci kez calistirilirsa
  -- `type ... already exists` (42P07) hatasini verir. Burada olasi hata
  -- YAKALANIR ve etiket dizisi karsilastirilir: ayniyse sessizce gecilir,
  -- FARKLIYSA WARNING basilir (sessizce farkli bir enum ile devam etmek
  -- semayi sessizce degistirmek olurdu).
  BEGIN
    CREATE TYPE public.meal_type AS ENUM ('breakfast', 'lunch', 'dinner', 'snack');
  EXCEPTION WHEN duplicate_object THEN
    SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
      INTO mevcut
      FROM pg_catalog.pg_type t
      JOIN pg_catalog.pg_enum e ON e.enumtypid = t.oid
     WHERE t.typname = 'meal_type';
    IF mevcut IS DISTINCT FROM beklenen THEN
      RAISE WARNING
        'A1r8: public.meal_type etiketleri FARKLI (mevcut=%, beklenen=%). Enum degistirilemez; elle inceleyin.',
        mevcut, beklenen;
    ELSE
      RAISE NOTICE 'A1r8: public.meal_type zaten var (etiketler ayni), atlaniyor.';
    END IF;
  END;
END $$;
DO $$
DECLARE
  beklenen TEXT := ('photo', 'text', 'manual');
  mevcut  TEXT;
BEGIN
  -- A1r8 (idempotans): `CREATE TYPE ... AS ENUM` Postgres'te
  -- `IF NOT EXISTS` DESTEKLEMEZ; dosya ikinci kez calistirilirsa
  -- `type ... already exists` (42P07) hatasini verir. Burada olasi hata
  -- YAKALANIR ve etiket dizisi karsilastirilir: ayniyse sessizce gecilir,
  -- FARKLIYSA WARNING basilir (sessizce farkli bir enum ile devam etmek
  -- semayi sessizce degistirmek olurdu).
  BEGIN
    CREATE TYPE public.food_source AS ENUM ('photo', 'text', 'manual');
  EXCEPTION WHEN duplicate_object THEN
    SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
      INTO mevcut
      FROM pg_catalog.pg_type t
      JOIN pg_catalog.pg_enum e ON e.enumtypid = t.oid
     WHERE t.typname = 'food_source';
    IF mevcut IS DISTINCT FROM beklenen THEN
      RAISE WARNING
        'A1r8: public.food_source etiketleri FARKLI (mevcut=%, beklenen=%). Enum degistirilemez; elle inceleyin.',
        mevcut, beklenen;
    ELSE
      RAISE NOTICE 'A1r8: public.food_source zaten var (etiketler ayni), atlaniyor.';
    END IF;
  END;
END $$;
DO $$
DECLARE
  beklenen TEXT := ('admin', 'moderator', 'user');
  mevcut  TEXT;
BEGIN
  -- A1r8 (idempotans): `CREATE TYPE ... AS ENUM` Postgres'te
  -- `IF NOT EXISTS` DESTEKLEMEZ; dosya ikinci kez calistirilirsa
  -- `type ... already exists` (42P07) hatasini verir. Burada olasi hata
  -- YAKALANIR ve etiket dizisi karsilastirilir: ayniyse sessizce gecilir,
  -- FARKLIYSA WARNING basilir (sessizce farkli bir enum ile devam etmek
  -- semayi sessizce degistirmek olurdu).
  BEGIN
    CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');
  EXCEPTION WHEN duplicate_object THEN
    SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
      INTO mevcut
      FROM pg_catalog.pg_type t
      JOIN pg_catalog.pg_enum e ON e.enumtypid = t.oid
     WHERE t.typname = 'app_role';
    IF mevcut IS DISTINCT FROM beklenen THEN
      RAISE WARNING
        'A1r8: public.app_role etiketleri FARKLI (mevcut=%, beklenen=%). Enum degistirilemez; elle inceleyin.',
        mevcut, beklenen;
    ELSE
      RAISE NOTICE 'A1r8: public.app_role zaten var (etiketler ayni), atlaniyor.';
    END IF;
  END;
END $$;

-- PROFILES TABLE
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  display_name TEXT,
  email TEXT,
  avatar_url TEXT,
  birth_date DATE,
  gender TEXT CHECK (gender IN ('male', 'female', 'other')),
  height_cm NUMERIC(5,1),
  current_weight_kg NUMERIC(5,2),
  target_weight_kg NUMERIC(5,2),
  activity_level TEXT CHECK (activity_level IN ('sedentary', 'light', 'moderate', 'active', 'very_active')),
  goal TEXT CHECK (goal IN ('lose', 'maintain', 'gain')),
  bmr NUMERIC(6,1),
  tdee NUMERIC(6,1),
  daily_calorie_target INTEGER,
  protein_target_g INTEGER,
  carbs_target_g INTEGER,
  fat_target_g INTEGER,
  daily_water_target_ml INTEGER DEFAULT 2500,
  weigh_in_frequency_days INTEGER DEFAULT 7,
  last_weigh_in_reminder TIMESTAMPTZ,
  push_notifications_enabled BOOLEAN DEFAULT true,
  email_notifications_enabled BOOLEAN DEFAULT true,
  onboarding_completed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- USER ROLES TABLE
CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- FOODS TABLE
CREATE TABLE IF NOT EXISTS public.foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  brand TEXT,
  serving_size_g NUMERIC(8,2) DEFAULT 100,
  serving_description TEXT,
  source food_source NOT NULL DEFAULT 'manual',
  image_url TEXT,
  popularity_count INTEGER DEFAULT 0,
  verified BOOLEAN DEFAULT false,
  created_by UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.foods ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_foods_name ON public.foods USING gin(to_tsvector('turkish', name));
CREATE INDEX IF NOT EXISTS idx_foods_popularity ON public.foods(popularity_count DESC);
-- Ayni isim + marka tekrarini engeller (20260927120000 ile hizalandi).
-- Marka NULL ise bos string'e cozumlenir, boylece "ayni isim, markasiz"
-- gidalar da carpismaz.
CREATE UNIQUE INDEX IF NOT EXISTS foods_name_brand_unique
  ON public.foods (lower(name), lower(COALESCE(brand, '')));
-- RLS süzgeci indeksi (20260928300000 ile hizalandi): `foods` DELETE/UPDATE
-- politikalari `created_by = auth.uid()` kullanir; indeks yoksa tablo taranir.
CREATE INDEX IF NOT EXISTS foods_created_by_rls ON public.foods(created_by);
COMMENT ON COLUMN public.foods.created_by IS
  'Ekleyen kullanici. URUN-KARARLARI 3-A: hesap silinince bu gida da silinir (ON DELETE CASCADE, 20260928300000). NULL olan satirlar (seed/admin) CASCADE ile TETIKLENMEZ ve korunur.';

-- FOOD NUTRITION TABLE
CREATE TABLE IF NOT EXISTS public.food_nutrition (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  food_id UUID REFERENCES public.foods(id) ON DELETE CASCADE NOT NULL,
  per_100_g_ml BOOLEAN DEFAULT true,
  kcal NUMERIC(7,2) NOT NULL,
  protein_g NUMERIC(6,2) NOT NULL,
  carbs_g NUMERIC(6,2) NOT NULL,
  fat_g NUMERIC(6,2) NOT NULL,
  fiber_g NUMERIC(6,2),
  sugar_g NUMERIC(6,2),
  salt_g NUMERIC(6,3),
  saturated_fat_g NUMERIC(6,2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(food_id)
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.food_nutrition ENABLE ROW LEVEL SECURITY;

-- MEAL ENTRIES TABLE
-- NOT: `food_id` FK'si `ON DELETE SET NULL` olmalıdır (20260927120000 ile
-- hizalandi). `full_setup.sql` bu değişikliği daha önce **yapmıyordu** ve
-- Postgres varsayılanı `NO ACTION` ile bir tablo üretiyordu → sonuç: bir
-- gıda silinmek istendiğinde ona bağlı öğün kaydı varsa DELETE **başarısız**
-- oluyordu (kullanıcı "kendi eklediği gıdayı" silemiyordu), hem de
-- `foods.created_by` CASCADE ile bir hesap silinirken `auth.admin.deleteUser()`
-- FK ihlali veriyordu. A1r5'in CASCADE testi bu farkı yakaladı.
CREATE TABLE IF NOT EXISTS public.meal_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  entry_date DATE NOT NULL,
  meal_type meal_type NOT NULL,
  food_id UUID REFERENCES public.foods(id) ON DELETE SET NULL,
  custom_name TEXT,
  amount_g_ml NUMERIC(8,2) NOT NULL,
  calculated_kcal NUMERIC(7,2) NOT NULL,
  calculated_protein NUMERIC(6,2) NOT NULL,
  calculated_carbs NUMERIC(6,2) NOT NULL,
  calculated_fat NUMERIC(6,2) NOT NULL,
  note TEXT,
  photo_url TEXT,
  source food_source NOT NULL DEFAULT 'manual',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.meal_entries ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_meal_entries_user_date ON public.meal_entries(user_id, entry_date);
-- Favoriler / son kullanilanlar turetimi (20260928300000 ile hizalandi).
-- Her iki istemci bu deseni kullanir: user_id + deleted_at IS NULL +
-- created_at DESC + LIMIT 200/50. Indekssiz Seq Scan + Top-N Sort
-- (olculdu: 20.000 ogun, 7.49 ms); indekli Index Scan (0.06 ms).
CREATE INDEX IF NOT EXISTS meal_entries_user_created_active ON public.meal_entries(user_id, created_at DESC) WHERE deleted_at IS NULL;
COMMENT ON INDEX public.meal_entries_user_created_active IS
  'Favoriler/son kullanilanlar turetimi: user_id + created_at DESC + deleted_at IS NULL (her iki istemci). A1r5-security.';

-- WATER ENTRIES TABLE
CREATE TABLE IF NOT EXISTS public.water_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  entry_date DATE NOT NULL,
  entry_time TIMESTAMPTZ NOT NULL DEFAULT now(),
  amount_ml INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.water_entries ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_water_entries_user_date ON public.water_entries(user_id, entry_date);

-- WEIGHT ENTRIES TABLE
CREATE TABLE IF NOT EXISTS public.weight_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  entry_date DATE NOT NULL,
  weight_kg NUMERIC(5,2) NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.weight_entries ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_weight_entries_user_date ON public.weight_entries(user_id, entry_date);

-- NOTIFICATIONS TABLE
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('weigh_in', 'meal_reminder', 'goal', 'achievement', 'system')),
  is_read BOOLEAN DEFAULT false,
  push_sent BOOLEAN DEFAULT false,
  email_sent BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.notifications(user_id, is_read) WHERE is_read = false;

-- USER SETTINGS TABLE
CREATE TABLE IF NOT EXISTS public.user_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  key TEXT NOT NULL,
  value JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, key)
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- FAVORITE FOODS TABLE
CREATE TABLE IF NOT EXISTS public.favorite_foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  food_id UUID REFERENCES public.foods(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, food_id)
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.favorite_foods ENABLE ROW LEVEL SECURITY;

-- RECENT FOODS TABLE
CREATE TABLE IF NOT EXISTS public.recent_foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  food_id UUID REFERENCES public.foods(id) ON DELETE CASCADE NOT NULL,
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  use_count INTEGER DEFAULT 1,
  UNIQUE(user_id, food_id)
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.recent_foods ENABLE ROW LEVEL SECURITY;
-- Siralama indeksi (20260928300000 ile hizalandi): UNIQUE(user_id, food_id)
-- user_id'yi zaten indeksliyor ama `last_used_at` HICBIR indekste degildi.
CREATE INDEX IF NOT EXISTS recent_foods_user_last_used ON public.recent_foods(user_id, last_used_at DESC);
COMMENT ON INDEX public.recent_foods_user_last_used IS
  'recent_foods siralamasi: last_used_at hicbir indekste degildi. A1r5-security.';

-- PUSH SUBSCRIPTIONS TABLE
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  endpoint TEXT NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, endpoint)
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

-- CHAT THREADS TABLE (AI sohbet geçmişi — 20260518080500 ile eklendi)
CREATE TABLE IF NOT EXISTS public.chat_threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title TEXT,
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.chat_threads ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_chat_threads_user_updated ON public.chat_threads(user_id, updated_at DESC);
-- Arsivlenmemis thread listesi her istemcide `archived_at IS NULL` ile
-- sorgulanir (Flutter `chat_repository.dart:65`, web `ChatPage.tsx:160`).
-- (20260927120000 ile hizalandi; migration yolunda `chat_threads_user_archived`.)
CREATE INDEX IF NOT EXISTS chat_threads_user_archived ON public.chat_threads(user_id, archived_at);

-- CHAT MESSAGES TABLE
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id UUID REFERENCES public.chat_threads(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system', 'tool')),
  content TEXT,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  tool_calls JSONB NOT NULL DEFAULT '[]'::jsonb,
  tool_results JSONB NOT NULL DEFAULT '[]'::jsonb,
  pending_action JSONB,
  action_status TEXT CHECK (action_status IN ('pending', 'approved', 'rejected', 'executed', 'failed')),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_chat_messages_thread_created ON public.chat_messages(thread_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_user_created ON public.chat_messages(user_id, created_at DESC);

-- RATE LIMITS TABLE (kalıcı hız sınırı sayacı — 20260927220500 ile eklendi)
CREATE TABLE IF NOT EXISTS public.rate_limits (
  key TEXT PRIMARY KEY,
  bucket TEXT NOT NULL,
  max_count INTEGER NOT NULL,
  window_seconds INTEGER NOT NULL,
  window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  request_count INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT rate_limits_positive_check CHECK (max_count > 0 AND window_seconds > 0 AND request_count >= 0)
);
-- A1r8: `CREATE TABLE` -> `CREATE TABLE IF NOT EXISTS` (idempotans).
CREATE INDEX IF NOT EXISTS rate_limits_window_start_idx ON public.rate_limits (window_start);
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES
-- ----------------------------------------------------------------------------
-- Kurallar (20260927220000 ile hizalandi):
--   1) Her politika `TO authenticated` — `anon` hicbir tabloya erisemez.
--   2) UPDATE politikalarinda MUTLAKA `USING` **ve** `WITH CHECK` birlikte.
--      (PostgreSQL'de WITH CHECK yazilmazsa USING ile ayni kabul edilir; yine de
--       her yerde acikca yazilir, bkz. migration basligindaki kanit.)
--   3) Politika adlari migration setiyle BIREBIR ayni (DROP/CREATE uyumlu).
-- ============================================================================

-- PROFILES POLICIES
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
CREATE POLICY "Users can view their own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

-- USER ROLES POLICIES
-- NOT: INSERT/UPDATE/DELETE politikasi BILEREK YOKTUR — rol atama yolu kapalı.
DROP POLICY IF EXISTS "Users can view their own roles" ON public.user_roles;
CREATE POLICY "Users can view their own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- FOODS POLICIES
DROP POLICY IF EXISTS "Authenticated users can view foods" ON public.foods;
CREATE POLICY "Authenticated users can view foods" ON public.foods FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Authenticated users can add foods" ON public.foods;
CREATE POLICY "Authenticated users can add foods" ON public.foods FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());
DROP POLICY IF EXISTS "Users can update foods they created" ON public.foods;
CREATE POLICY "Users can update foods they created" ON public.foods FOR UPDATE TO authenticated USING (created_by = auth.uid()) WITH CHECK (created_by = auth.uid());
DROP POLICY IF EXISTS "Users can delete foods they created" ON public.foods;
CREATE POLICY "Users can delete foods they created" ON public.foods FOR DELETE TO authenticated USING (created_by = auth.uid());

-- FOOD NUTRITION POLICIES
DROP POLICY IF EXISTS "Authenticated users can view food nutrition" ON public.food_nutrition;
CREATE POLICY "Authenticated users can view food nutrition" ON public.food_nutrition FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Users can add nutrition for foods they created" ON public.food_nutrition;
CREATE POLICY "Users can add nutrition for foods they created" ON public.food_nutrition FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.foods WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()));
DROP POLICY IF EXISTS "Users can update nutrition for foods they created" ON public.food_nutrition;
CREATE POLICY "Users can update nutrition for foods they created" ON public.food_nutrition FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.foods WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.foods WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()));
DROP POLICY IF EXISTS "Users can delete nutrition for foods they created" ON public.food_nutrition;
CREATE POLICY "Users can delete nutrition for foods they created" ON public.food_nutrition FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.foods WHERE foods.id = food_nutrition.food_id AND foods.created_by = auth.uid()));

-- MEAL ENTRIES POLICIES
DROP POLICY IF EXISTS "Users can view their own meal entries" ON public.meal_entries;
CREATE POLICY "Users can view their own meal entries" ON public.meal_entries FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own meal entries" ON public.meal_entries;
CREATE POLICY "Users can insert their own meal entries" ON public.meal_entries FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own meal entries" ON public.meal_entries;
CREATE POLICY "Users can update their own meal entries" ON public.meal_entries FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own meal entries" ON public.meal_entries;
CREATE POLICY "Users can delete their own meal entries" ON public.meal_entries FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- WATER ENTRIES POLICIES
DROP POLICY IF EXISTS "Users can view their own water entries" ON public.water_entries;
CREATE POLICY "Users can view their own water entries" ON public.water_entries FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own water entries" ON public.water_entries;
CREATE POLICY "Users can insert their own water entries" ON public.water_entries FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own water entries" ON public.water_entries;
CREATE POLICY "Users can update their own water entries" ON public.water_entries FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own water entries" ON public.water_entries;
CREATE POLICY "Users can delete their own water entries" ON public.water_entries FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- WEIGHT ENTRIES POLICIES
DROP POLICY IF EXISTS "Users can view their own weight entries" ON public.weight_entries;
CREATE POLICY "Users can view their own weight entries" ON public.weight_entries FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own weight entries" ON public.weight_entries;
CREATE POLICY "Users can insert their own weight entries" ON public.weight_entries FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own weight entries" ON public.weight_entries;
CREATE POLICY "Users can update their own weight entries" ON public.weight_entries FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own weight entries" ON public.weight_entries;
CREATE POLICY "Users can delete their own weight entries" ON public.weight_entries FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- NOTIFICATIONS POLICIES
-- INSERT yalnizca service_role'a acik (kullanicilar sahte bildirim uretemez).
DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
CREATE POLICY "Users can view their own notifications" ON public.notifications FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;
CREATE POLICY "Users can update their own notifications" ON public.notifications FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own notifications" ON public.notifications;
CREATE POLICY "Users can delete their own notifications" ON public.notifications FOR DELETE TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Service role can insert notifications" ON public.notifications;
CREATE POLICY "Service role can insert notifications" ON public.notifications FOR INSERT TO service_role WITH CHECK (true);

-- USER SETTINGS POLICIES
DROP POLICY IF EXISTS "Users can view their own settings" ON public.user_settings;
CREATE POLICY "Users can view their own settings" ON public.user_settings FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own settings" ON public.user_settings;
CREATE POLICY "Users can insert their own settings" ON public.user_settings FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own settings" ON public.user_settings;
CREATE POLICY "Users can update their own settings" ON public.user_settings FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own settings" ON public.user_settings;
CREATE POLICY "Users can delete their own settings" ON public.user_settings FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- FAVORITE FOODS POLICIES
DROP POLICY IF EXISTS "Users can view their own favorites" ON public.favorite_foods;
CREATE POLICY "Users can view their own favorites" ON public.favorite_foods FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own favorites" ON public.favorite_foods;
CREATE POLICY "Users can insert their own favorites" ON public.favorite_foods FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own favorites" ON public.favorite_foods;
CREATE POLICY "Users can delete their own favorites" ON public.favorite_foods FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- RECENT FOODS POLICIES
DROP POLICY IF EXISTS "Users can view their own recent foods" ON public.recent_foods;
CREATE POLICY "Users can view their own recent foods" ON public.recent_foods FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own recent foods" ON public.recent_foods;
CREATE POLICY "Users can insert their own recent foods" ON public.recent_foods FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own recent foods" ON public.recent_foods;
CREATE POLICY "Users can update their own recent foods" ON public.recent_foods FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own recent foods" ON public.recent_foods;
CREATE POLICY "Users can delete their own recent foods" ON public.recent_foods FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- PUSH SUBSCRIPTIONS POLICIES
DROP POLICY IF EXISTS "Users can view their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can view their own push subscriptions" ON public.push_subscriptions FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can insert their own push subscriptions" ON public.push_subscriptions FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can update their own push subscriptions" ON public.push_subscriptions FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can delete their own push subscriptions" ON public.push_subscriptions FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- NOTIFICATION PREFERENCES TABLE
-- NOT: Dosyanın orijinalinde bu tablo bölüm 4'te, yani bu politika
-- bloklarından SONRA oluşturuluyordu. Politikaların tanımlanabilmesi için
-- tablo buraya taşındı (şema aynıdır, yalnızca sıra değişmiştir).
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notification_type text NOT NULL,
  push_enabled boolean DEFAULT true,
  email_enabled boolean DEFAULT true,
  start_hour integer DEFAULT 9,
  end_hour integer DEFAULT 21,
  interval_hours integer DEFAULT 3,
  summary_day integer DEFAULT 1,
  summary_hour integer DEFAULT 9,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, notification_type)
);
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- NOTIFICATION PREFERENCES POLICIES
DROP POLICY IF EXISTS "Users can view own notification preferences" ON public.notification_preferences;
CREATE POLICY "Users can view own notification preferences" ON public.notification_preferences FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert own notification preferences" ON public.notification_preferences;
CREATE POLICY "Users can insert own notification preferences" ON public.notification_preferences FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update own notification preferences" ON public.notification_preferences;
CREATE POLICY "Users can update own notification preferences" ON public.notification_preferences FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete own notification preferences" ON public.notification_preferences;
CREATE POLICY "Users can delete own notification preferences" ON public.notification_preferences FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- CHAT THREADS POLICIES
DROP POLICY IF EXISTS "Users can view their own chat threads" ON public.chat_threads;
CREATE POLICY "Users can view their own chat threads" ON public.chat_threads FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own chat threads" ON public.chat_threads;
CREATE POLICY "Users can insert their own chat threads" ON public.chat_threads FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own chat threads" ON public.chat_threads;
CREATE POLICY "Users can update their own chat threads" ON public.chat_threads FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own chat threads" ON public.chat_threads;
CREATE POLICY "Users can delete their own chat threads" ON public.chat_threads FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- CHAT MESSAGES POLICIES
-- Mesaj yalnizca kullaniciya ait bir sohbete aitse gorulur/yazilir.
DROP POLICY IF EXISTS "Users can view their own chat messages" ON public.chat_messages;
CREATE POLICY "Users can view their own chat messages" ON public.chat_messages FOR SELECT TO authenticated
  USING (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.chat_threads WHERE chat_threads.id = chat_messages.thread_id AND chat_threads.user_id = auth.uid()));
DROP POLICY IF EXISTS "Users can insert their own chat messages" ON public.chat_messages;
CREATE POLICY "Users can insert their own chat messages" ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.chat_threads WHERE chat_threads.id = chat_messages.thread_id AND chat_threads.user_id = auth.uid()));
DROP POLICY IF EXISTS "Users can update their own chat messages" ON public.chat_messages;
CREATE POLICY "Users can update their own chat messages" ON public.chat_messages FOR UPDATE TO authenticated
  USING (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.chat_threads WHERE chat_threads.id = chat_messages.thread_id AND chat_threads.user_id = auth.uid()))
  WITH CHECK (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.chat_threads WHERE chat_threads.id = chat_messages.thread_id AND chat_threads.user_id = auth.uid()));
DROP POLICY IF EXISTS "Users can delete their own chat messages" ON public.chat_messages;
CREATE POLICY "Users can delete their own chat messages" ON public.chat_messages FOR DELETE TO authenticated
  USING (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.chat_threads WHERE chat_threads.id = chat_messages.thread_id AND chat_threads.user_id = auth.uid()));

-- ============================================================================
-- RLS GRANT'LERI — en az yetki (anon hicbir tabloya erisemez)
-- ----------------------------------------------------------------------------
-- NOT: Bu blok, `notification_preferences` dahil TUM tablolar olustuktan sonra
-- calisir; bu yuzden dosyanin SONUNDA tekrar yer alir (bkz. "7. Grants" bolumu).
-- Burada yalnizca sema izinleri verilir.
-- ============================================================================
REVOKE ALL ON SCHEMA public FROM anon;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO authenticated, service_role;

-- HELPER FUNCTIONS
-- NOT: `SECURITY DEFINER` fonksiyonlarda `search_path = ''` kullanilir
-- (search_path hijacking korumasi). Tum referanslar sema on eklidir.
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = '';

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
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
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.food_id IS NOT NULL THEN
    UPDATE public.foods SET popularity_count = popularity_count + 1 WHERE id = NEW.food_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Chat sohbetinin `updated_at` damgasini yeniler.
CREATE OR REPLACE FUNCTION public.touch_chat_thread_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.chat_threads SET updated_at = now() WHERE id = NEW.thread_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Degismez kolon korumasi: RLS politika ifadesinde `OLD` kullanilamaz
-- (PostgreSQL politikaya yalnizca yeni satiri verir), bu yuzden trigger gerekir.
CREATE OR REPLACE FUNCTION public.freeze_immutable_columns()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_TABLE_NAME = 'recent_foods'
     AND (to_jsonb(NEW) ->> 'food_id') IS DISTINCT FROM (to_jsonb(OLD) ->> 'food_id') THEN
    RAISE EXCEPTION 'recent_foods.food_id değiştirilemez' USING ERRCODE = '42501';
  END IF;
  IF TG_TABLE_NAME = 'chat_messages'
     AND (to_jsonb(NEW) ->> 'thread_id') IS DISTINCT FROM (to_jsonb(OLD) ->> 'thread_id') THEN
    RAISE EXCEPTION 'chat_messages.thread_id değiştirilemez' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = '';

-- KALICI RATE LIMIT — atomik sayaç artırma (bkz. 20260927220500).
-- Donus: { allowed, count, max, retry_after }
CREATE OR REPLACE FUNCTION public.rate_limit_hit(
  p_key TEXT, p_bucket TEXT, p_max_count INTEGER, p_window_seconds INTEGER
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_count INTEGER;
  v_window_start TIMESTAMPTZ;
  v_effective_window INTEGER;
  v_reset_at TIMESTAMPTZ;
BEGIN
  IF p_key IS NULL OR length(p_key) = 0 OR length(p_key) > 512 THEN
    RAISE EXCEPTION 'rate_limit_hit: gecersiz anahtar';
  END IF;
  IF p_max_count <= 0 OR p_window_seconds <= 0 OR p_window_seconds > 86400 THEN
    RAISE EXCEPTION 'rate_limit_hit: gecersiz kova tanimi';
  END IF;

  INSERT INTO public.rate_limits AS rl
    (key, bucket, max_count, window_seconds, window_start, request_count, updated_at)
  VALUES (p_key, p_bucket, p_max_count, p_window_seconds, v_now, 1, v_now)
  ON CONFLICT (key) DO UPDATE
    SET request_count = CASE
          WHEN rl.window_start + make_interval(secs => rl.window_seconds) <= v_now THEN 1
          ELSE rl.request_count + 1
        END,
        window_start = CASE
          WHEN rl.window_start + make_interval(secs => rl.window_seconds) <= v_now THEN v_now
          ELSE rl.window_start
        END,
        max_count = EXCLUDED.max_count,
        window_seconds = EXCLUDED.window_seconds,
        bucket = EXCLUDED.bucket,
        updated_at = v_now
  RETURNING rl.request_count, rl.window_start, rl.window_seconds
  INTO v_count, v_window_start, v_effective_window;

  v_reset_at := v_window_start + make_interval(secs => v_effective_window);

  RETURN jsonb_build_object(
    'allowed', v_count <= p_max_count,
    'count', v_count,
    'max', p_max_count,
    'retry_after', GREATEST(0, CEIL(EXTRACT(EPOCH FROM (v_reset_at - v_now)))::INTEGER)
  );
END;
$$;

-- Suresi dolmus sayaç kayitlarini temizler.
CREATE OR REPLACE FUNCTION public.cleanup_rate_limits()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.rate_limits
  WHERE window_start + make_interval(secs => window_seconds) < now() - INTERVAL '1 hour';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

-- Rate limit RPC'leri yalnizca edge function'lar (service_role) cagirabilir.
REVOKE ALL ON FUNCTION public.rate_limit_hit(TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rate_limit_hit(TEXT, TEXT, INTEGER, INTEGER) TO service_role;
REVOKE ALL ON FUNCTION public.cleanup_rate_limits() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_rate_limits() TO service_role;

-- TRIGGERS
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;  -- A1r8: idempotans
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;  -- A1r8: idempotans
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_foods_updated_at ON public.foods;  -- A1r8: idempotans
CREATE TRIGGER update_foods_updated_at BEFORE UPDATE ON public.foods FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_food_nutrition_updated_at ON public.food_nutrition;  -- A1r8: idempotans
CREATE TRIGGER update_food_nutrition_updated_at BEFORE UPDATE ON public.food_nutrition FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_meal_entries_updated_at ON public.meal_entries;  -- A1r8: idempotans
CREATE TRIGGER update_meal_entries_updated_at BEFORE UPDATE ON public.meal_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_water_entries_updated_at ON public.water_entries;  -- A1r8: idempotans
CREATE TRIGGER update_water_entries_updated_at BEFORE UPDATE ON public.water_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_weight_entries_updated_at ON public.weight_entries;  -- A1r8: idempotans
CREATE TRIGGER update_weight_entries_updated_at BEFORE UPDATE ON public.weight_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_user_settings_updated_at ON public.user_settings;  -- A1r8: idempotans
CREATE TRIGGER update_user_settings_updated_at BEFORE UPDATE ON public.user_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS on_meal_entry_created ON public.meal_entries;  -- A1r8: idempotans
CREATE TRIGGER on_meal_entry_created AFTER INSERT ON public.meal_entries FOR EACH ROW EXECUTE FUNCTION public.increment_food_popularity();
DROP TRIGGER IF EXISTS trg_touch_chat_thread_updated_at ON public.chat_messages;  -- A1r8: idempotans
CREATE TRIGGER trg_touch_chat_thread_updated_at AFTER INSERT OR UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION public.touch_chat_thread_updated_at();
DROP TRIGGER IF EXISTS freeze_recent_foods_food_id ON public.recent_foods;  -- A1r8: idempotans
CREATE TRIGGER freeze_recent_foods_food_id BEFORE UPDATE ON public.recent_foods FOR EACH ROW EXECUTE FUNCTION public.freeze_immutable_columns();
DROP TRIGGER IF EXISTS freeze_chat_messages_thread_id ON public.chat_messages;  -- A1r8: idempotans
CREATE TRIGGER freeze_chat_messages_thread_id BEFORE UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION public.freeze_immutable_columns();

-- PUSH ABONELIK ADET SINIRI (20260928120000 ile hizalandi)
-- Kullanici basina en fazla 7 push aboneligi. RLS satir guvenligi tek basina
-- yeterli degildir: kotu niyetli istemci sınırsiz abonelik kaydedip her
-- bildirimde yuzlerce fetch tetikleyebilirdi. Trigger INSERT'te calisir; ayni
-- endpoint'e yapilan UPDATE (upsert) siniri tetiklemez.
CREATE OR REPLACE FUNCTION public.limit_push_subscriptions_per_user()
RETURNS TRIGGER AS $$
DECLARE
  v_max CONSTANT INTEGER := 7;
  v_count INTEGER;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT count(*) INTO v_count
    FROM public.push_subscriptions
    WHERE user_id = NEW.user_id;

    IF v_count >= v_max THEN
      -- Mesaj SABIT ve semasiz: istemciye tablo adi/kolon sizmaz.
      RAISE EXCEPTION 'Cihaz siniri asildi, daha fazla push aboneliği eklenemiyor'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = '';

DROP TRIGGER IF EXISTS limit_push_subscriptions ON public.push_subscriptions;
CREATE TRIGGER limit_push_subscriptions
  BEFORE INSERT ON public.push_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.limit_push_subscriptions_per_user();

-- 2. RLS Improvements
-- NOT: foods/food_nutrition INSERT+UPDATE politikaları yukarıdaki "RLS POLICIES"
-- bölümünde tanımlandı; burada tekrar tanımlanmaz (isim çakışması hatası).

-- 3. Profile Updates
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS auto_recalculate_macros BOOLEAN DEFAULT true;

-- 4. Notification Preferences
-- NOT: Tablo yukarıda ("RLS POLICIES" bölümünden hemen önce) oluşturuldu;
-- burada yalnızca `updated_at` trigger'ı tanımlanır.
DROP TRIGGER IF EXISTS update_notification_preferences_updated_at ON public.notification_preferences;  -- A1r8: idempotans
CREATE TRIGGER update_notification_preferences_updated_at BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'Europe/Istanbul';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_water_reminder timestamptz;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_daily_log_reminder timestamptz;
-- Haftalik ozet idempotency damgasi (20260928120000 ile hizalandi).
-- Bu kolon olmadan `check-reminders` haftalik ozeti her kosuda yeniden gonderir.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_weekly_summary timestamptz;
COMMENT ON COLUMN public.profiles.last_weekly_summary IS 'Son gonderilen haftalik ozet hatirlatmasi (idempotency). NULL = hic gonderilmedi.';

-- ============================================================================
-- 4b. VERI BÜTÜNLÜĞÜ — CHECK kisitlari (20260927120000 ile hizalandi)
-- ----------------------------------------------------------------------------
-- Negatif miktar/kilo kaydi engellenir; ust sinirlar ile absurd degerler de.
-- Bildirim tipi allow-list'i edge function'larin gonderdigi degerleri kapsar.
-- Bildirim tercihlerinde saat/aralik degerleri dogrulanir.
-- Besin degerleri negatif olamaz (20260928300000 ile hizalandi).
-- ============================================================================
ALTER TABLE public.meal_entries DROP CONSTRAINT IF EXISTS meal_entries_amount_positive;
ALTER TABLE public.meal_entries
  ADD CONSTRAINT meal_entries_amount_positive CHECK (amount_g_ml > 0 AND amount_g_ml <= 10000);
ALTER TABLE public.water_entries DROP CONSTRAINT IF EXISTS water_entries_amount_positive;
ALTER TABLE public.water_entries
  ADD CONSTRAINT water_entries_amount_positive CHECK (amount_ml > 0 AND amount_ml <= 10000);
ALTER TABLE public.weight_entries DROP CONSTRAINT IF EXISTS weight_entries_weight_range;
ALTER TABLE public.weight_entries
  ADD CONSTRAINT weight_entries_weight_range CHECK (weight_kg > 0 AND weight_kg <= 1000);
ALTER TABLE public.notification_preferences DROP CONSTRAINT IF EXISTS notification_preferences_type_allowlist;
ALTER TABLE public.notification_preferences
  ADD CONSTRAINT notification_preferences_type_allowlist
  CHECK (notification_type IN ('weigh_in','daily_log','water','goal_achieved','weekly_summary'));
ALTER TABLE public.notification_preferences DROP CONSTRAINT IF EXISTS notification_preferences_hours_range;
ALTER TABLE public.notification_preferences
  ADD CONSTRAINT notification_preferences_hours_range
  CHECK (start_hour BETWEEN 0 AND 23 AND end_hour BETWEEN 0 AND 23
         AND interval_hours BETWEEN 1 AND 24
         AND summary_day BETWEEN 0 AND 6 AND summary_hour BETWEEN 0 AND 23);
-- Negatif besin degeri engellenir (kcal/protein/carbs/fat + opsiyonel
-- fiber/sugar/salt/saturated_fat). `trans_fat_g` kolonu bu dosyanin
-- "6. Nutrition Updates" bolumunde eklendigi icin CHECK **orada** kurulur
-- (asagida bkz. "6. Nutrition Updates"). A1r5-security (Tur 7).

-- notifications.type CHECK'i: eski UI degerleri + edge function degerleri.
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_allowlist;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_allowlist
  CHECK (type IN ('weigh_in','meal_reminder','goal','achievement','system',
                  'water','daily_log','weekly_summary','goal_achieved'));

-- profiles.timezone artık SERBEST METIN DEGIL: gercek bir IANA dilimi
-- olmali (20260928200000 ile hizalandi). Gerekce: kolon `text` ve RLS
-- `Users can update their own profile` oldugu icin kullanici bos/curp bir
-- deger yazabiliyordu; `check-reminders` bu kolonu okudugu icin (eski kodda
-- sabit UTC+3 idi) bozuk deger sessizce yanlis saate dusuyordu.
CREATE OR REPLACE FUNCTION public.is_valid_timezone(_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT _value IS NOT NULL
     AND btrim(_value) <> ''
     AND EXISTS (
       SELECT 1
       FROM pg_catalog.pg_timezone_names() z
       WHERE z.name = btrim(_value)
     )
$$;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_timezone_is_valid_iana;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_timezone_is_valid_iana
  CHECK (public.is_valid_timezone(timezone));
COMMENT ON FUNCTION public.is_valid_timezone(TEXT) IS
  'TRUE iff _value bos degil ve pg_timezone_names() icinde bir IANA adidir. profiles_timezone_is_valid_iana CHECK kisitinin arkasindaki fonksiyon.';
COMMENT ON COLUMN public.profiles.timezone IS
  'IANA saat dilimi (orn. Europe/Istanbul). NULL/'' yazilamaz; kontrol: profiles_timezone_is_valid_iana. check-reminders bu kolonu okur (eski kodda sabit UTC+3 idi).';

-- ============================================================================
-- 4c. STORAGE — chat-attachments kovasi (20260518080500 ile hizalandi)
-- ----------------------------------------------------------------------------
-- Kova gizlidir (public = false), dosya boyutu 10 MB ile sinirlidir ve
-- politikalar yalnizca `authenticated` icindir; her obje kullanici klasorunde
-- olmak zorundadir: <user_id>/<dosya>
-- ============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-attachments', 'chat-attachments', false, 10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Users can upload their own chat attachments" ON storage.objects;
CREATE POLICY "Users can upload their own chat attachments" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'chat-attachments' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Users can view their own chat attachments" ON storage.objects;
CREATE POLICY "Users can view their own chat attachments" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'chat-attachments' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Users can update their own chat attachments" ON storage.objects;
CREATE POLICY "Users can update their own chat attachments" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'chat-attachments' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'chat-attachments' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Users can delete their own chat attachments" ON storage.objects;
CREATE POLICY "Users can delete their own chat attachments" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'chat-attachments' AND (storage.foldername(name))[1] = auth.uid()::text);

-- 5. Cron Jobs
-- A1r10 (Tur 11): `CREATE EXTENSION IF NOT EXISTS` kurulu olmayan eklenti
-- için "extension is not available" HATASI verir. Stock `postgres:16-alpine`
-- imajında ikisi de yok → bu blok hatayı `NOTICE`'e çevirir (idempotans:
-- aynı blok 1/2/3. kez çalıştırılabilir, 0 gerçek hata).
DO $$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'full_setup: pg_cron kurulamadı/kapalı (%)', SQLERRM;
  END;
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'full_setup: pg_net kurulamadı/kapalı (%)', SQLERRM;
  END;
END $$;
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;

-- A1r10 (Tur 11): `check-reminders` cron job'ı.
--
-- ⭐ P0: Bu dosya daha önce **hiçbir job tanımlamıyordu**; sunucu tarafı
-- hatırlatıcıları (`water`, `daily_log`, `weekly_summary`, `weigh_in`)
-- elle tetikleniyordu, yani hiç gidiyordu. Migration karşılığı:
-- `20260929010000_check_reminders_cron_job.sql` (parite).
--
-- Sıklık `7-59/7 * * * *` (saatte 7-8 kez). Gerekçe migration dosyasında;
-- özet: dakikada bir `checkRateLimit` 2/300 kovası yüzünden anlamsız,
-- saatte bir ise 09:00 (`weigh_in`) ve 18:00 (`daily_log`) saatlerinde
-- tetiklenen bildirimler 1/24 ihtimalle **kaçar**.
--
-- Yetkilendirme `x-calorix-internal-token` başlığı ile
-- (`check-reminders/index.ts` `isAuthorizedCall`). Token Vault'ta:
--   SELECT vault.create_secret('<token>', 'calorix_internal_function_token');
-- Token'ı migration'a düz yazmak repoya sır giriyor; bu yüzden Vault.
DO $$
DECLARE
  v_job_id BIGINT;
BEGIN
  IF to_regprocedure('cron.schedule(text, text, text)') IS NULL THEN
    RAISE NOTICE 'full_setup: pg_cron yok, check-reminders job''ı kurulmadı.';
    RETURN;
  END IF;
  -- `to_regprocedure` imzayı birebir arar; `pg_net`'in belgelenen imzası beş
  -- argümanlıdır ama dört argümanlı kurulumlar da vardır. Üçünü de kabul et
  -- (A1r10 ölçümü: yalnız beş argümanlı arama, dört argümanlı bir kurulumda
  -- job'u sessizce kurmadan geçiyordu).
  IF (to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)') IS NULL
      AND to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb)') IS NULL
      AND to_regprocedure('net.http_post(text, jsonb)') IS NULL)
     OR to_regclass('vault.decrypted_secrets') IS NULL THEN
    RAISE WARNING 'full_setup: pg_net veya vault yok, check-reminders job''ı kurulmadı.';
    RETURN;
  END IF;

  -- Çift kayıt koruması: aynı adlı her job'ı düşür, sonra bir tane kur.
  FOR v_job_id IN SELECT jobid FROM cron.job WHERE jobname = 'check-reminders' LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'check-reminders',
    '7-59/7 * * * *',
    $cron$
      SELECT net.http_post(
        url := 'https://bzfnncensolirkqdohpq.supabase.co/functions/v1/check-reminders',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-calorix-internal-token',
            (SELECT decrypted_secret FROM vault.decrypted_secrets
              WHERE name = 'calorix_internal_function_token')
        ),
        body := jsonb_build_object('scheduled_at', now()),
        timeout_milliseconds := 30000
      ) AS request_id;
    $cron$
  );
  RAISE NOTICE 'full_setup: check-reminders job''ı kuruldu (saatte 7 kez).';
END $$;

-- 6. Nutrition Updates
ALTER TABLE public.food_nutrition ADD COLUMN IF NOT EXISTS trans_fat_g numeric NULL;
ALTER TABLE public.food_nutrition ADD COLUMN IF NOT EXISTS nova_score smallint NULL;
ALTER TABLE public.food_nutrition ADD COLUMN IF NOT EXISTS nutri_score text NULL;
COMMENT ON COLUMN public.food_nutrition.trans_fat_g IS 'Trans fat content per 100g/ml';
COMMENT ON COLUMN public.food_nutrition.nova_score IS 'NOVA food classification: 1=Unprocessed, 2=Processed culinary ingredients, 3=Processed foods, 4=Ultra-processed';
COMMENT ON COLUMN public.food_nutrition.nutri_score IS 'Nutri-Score grade: A (best) to E (worst)';
-- Negatif besin degeri engellenir (20260928300000 ile hizalandi). CHECK
-- `trans_fat_g` kolonundan SONRA kurulur (kolon yukarida eklendi).
ALTER TABLE public.food_nutrition DROP CONSTRAINT IF EXISTS food_nutrition_values_non_negative;
ALTER TABLE public.food_nutrition
  ADD CONSTRAINT food_nutrition_values_non_negative
  CHECK (
    kcal >= 0 AND protein_g >= 0 AND carbs_g >= 0 AND fat_g >= 0
    AND COALESCE(fiber_g, 0) >= 0 AND COALESCE(sugar_g, 0) >= 0
    AND COALESCE(salt_g, 0) >= 0 AND COALESCE(saturated_fat_g, 0) >= 0
    AND COALESCE(trans_fat_g, 0) >= 0
  );
COMMENT ON CONSTRAINT food_nutrition_values_non_negative ON public.food_nutrition IS
  'Besin degerleri negatif olamaz. A1r5-security (Tur 7). Ust sinir numeric(6,2)/(7,2) tipinde zaten var.';

-- ============================================================================
-- 7. Grants — en az yetki (tüm tablolar olustuktan SONRA calisir)
-- ----------------------------------------------------------------------------
-- `anon` hicbir tabloya erisemez. `authenticated` komut bazli GRANT alir ve
-- satir bazli yetkiyi RLS belirler. `service_role` BYPASSRLS ile her seye
-- erisir (edge function'lar bunu kullanir).
-- ============================================================================
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'profiles','user_roles','foods','food_nutrition','meal_entries','water_entries',
    'weight_entries','notifications','user_settings','favorite_foods','recent_foods',
    'push_subscriptions','notification_preferences','chat_threads','chat_messages'
  ] LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN
      RAISE WARNING 'Tablo bulunamadi, GRANT atlaniyor: %', t;
      CONTINUE;
    END IF;
    EXECUTE format('REVOKE ALL ON public.%I FROM anon', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
  END LOOP;
END $$;

-- rate_limits: yalnizca servis rolu (kullanici sayacini okuyamaz/sifirlayamaz)
REVOKE ALL ON public.rate_limits FROM anon, authenticated, PUBLIC;
GRANT ALL ON public.rate_limits TO service_role;

-- ============================================================================
-- 8. VERI BÜTÜNLÜĞÜ — 13 CHECK kisiti (20260928400000 ile hizalandi, A1r8)
-- ----------------------------------------------------------------------------
-- Bu dosya "bos veritabani + sifir kullanici" senaryosu icindir, dolayisiyla
-- asagidaki kisitlar hicbir mevcut satiri dogrulamak zorunda degildir.
-- Migration yolu (`20260928400000`) ise canli veri olabilecegi icin once
-- dogrular ve ihlal varsa HATA verir; burada ayni kisit ifadeleri kullanilir
-- (parite `diff` = bos).
-- Hepsinde once `DROP CONSTRAINT IF EXISTS` -> `ADD CONSTRAINT` deseni
-- kullanilir: dosya ikinci kez calistirilirsa hata vermez (idempotans).
-- ============================================================================

-- --- 8.1 NOVA (1-4) / Nutri-Score (A-E) -------------------------------------
ALTER TABLE public.food_nutrition DROP CONSTRAINT IF EXISTS food_nutrition_nova_score_range;
ALTER TABLE public.food_nutrition
  ADD CONSTRAINT food_nutrition_nova_score_range
  CHECK (nova_score IS NULL OR nova_score BETWEEN 1 AND 4);
ALTER TABLE public.food_nutrition DROP CONSTRAINT IF EXISTS food_nutrition_nutri_score_allowlist;
ALTER TABLE public.food_nutrition
  ADD CONSTRAINT food_nutrition_nutri_score_allowlist
  CHECK (nutri_score IS NULL OR nutri_score IN ('A','B','C','D','E'));

-- --- 8.2 meal_entries.calculated_* >= 0 -------------------------------------
ALTER TABLE public.meal_entries DROP CONSTRAINT IF EXISTS meal_entries_calculated_non_negative;
ALTER TABLE public.meal_entries
  ADD CONSTRAINT meal_entries_calculated_non_negative
  CHECK (calculated_kcal >= 0 AND calculated_protein >= 0
         AND calculated_carbs >= 0 AND calculated_fat >= 0);

-- --- 8.3 profiles aralikleri ------------------------------------------------
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_height_cm_range;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_height_cm_range
  CHECK (height_cm IS NULL OR height_cm BETWEEN 100 AND 250);
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_current_weight_kg_range;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_current_weight_kg_range
  CHECK (current_weight_kg IS NULL OR current_weight_kg BETWEEN 20 AND 500);
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_target_weight_kg_range;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_target_weight_kg_range
  CHECK (target_weight_kg IS NULL OR target_weight_kg BETWEEN 20 AND 500);
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_daily_water_target_ml_range;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_daily_water_target_ml_range
  CHECK (daily_water_target_ml IS NULL OR daily_water_target_ml BETWEEN 0 AND 10000);
-- ⭐ `weigh_in_frequency_days`: negatif deger `check-reminders`'ta
-- `daysSinceReminder >= frequencyDays` karsilastirmasini HER KOSUDA saglayip
-- tartilma hatirlatmasini surekli gonderir. `notifications_dialog.dart:146`
-- `int.tryParse(...)` ile aralik denetimi YAPMADIĞI icin bu bir gercek
-- istemci hatasidir, varsayim degil.
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_weigh_in_frequency_days_range;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_weigh_in_frequency_days_range
  CHECK (weigh_in_frequency_days IS NULL OR weigh_in_frequency_days BETWEEN 1 AND 365);

-- --- 8.4 chat_messages JSONB tip kapisi -------------------------------------
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_metadata_is_object;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_metadata_is_object
  CHECK (jsonb_typeof(metadata) = 'object');
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_attachments_is_array;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_attachments_is_array
  CHECK (jsonb_typeof(attachments) = 'array');
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_tool_calls_is_array;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_tool_calls_is_array
  CHECK (jsonb_typeof(tool_calls) = 'array');
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_tool_results_is_array;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_tool_results_is_array
  CHECK (jsonb_typeof(tool_results) = 'array');
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_pending_action_is_object;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_pending_action_is_object
  CHECK (pending_action IS NULL OR jsonb_typeof(pending_action) = 'object');

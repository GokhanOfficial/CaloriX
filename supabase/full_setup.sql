-- 1. Main Schema
-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ENUM TYPES
CREATE TYPE public.meal_type AS ENUM ('breakfast', 'lunch', 'dinner', 'snack');
CREATE TYPE public.food_source AS ENUM ('barcode', 'photo', 'text', 'manual');
CREATE TYPE public.sync_state AS ENUM ('pending', 'synced', 'conflict', 'failed');
CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');

-- PROFILES TABLE
CREATE TABLE public.profiles (
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
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- USER ROLES TABLE
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- FOODS TABLE
CREATE TABLE public.foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode TEXT UNIQUE,
  name TEXT NOT NULL,
  brand TEXT,
  serving_size_g NUMERIC(8,2) DEFAULT 100,
  serving_description TEXT,
  source food_source NOT NULL DEFAULT 'manual',
  image_url TEXT,
  popularity_count INTEGER DEFAULT 0,
  verified BOOLEAN DEFAULT false,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_synced_at TIMESTAMPTZ
);
ALTER TABLE public.foods ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_foods_barcode ON public.foods(barcode);
CREATE INDEX idx_foods_name ON public.foods USING gin(to_tsvector('turkish', name));
CREATE INDEX idx_foods_popularity ON public.foods(popularity_count DESC);

-- FOOD NUTRITION TABLE
CREATE TABLE public.food_nutrition (
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
ALTER TABLE public.food_nutrition ENABLE ROW LEVEL SECURITY;

-- MEAL ENTRIES TABLE
CREATE TABLE public.meal_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  entry_date DATE NOT NULL,
  meal_type meal_type NOT NULL,
  food_id UUID REFERENCES public.foods(id),
  custom_name TEXT,
  amount_g_ml NUMERIC(8,2) NOT NULL,
  calculated_kcal NUMERIC(7,2) NOT NULL,
  calculated_protein NUMERIC(6,2) NOT NULL,
  calculated_carbs NUMERIC(6,2) NOT NULL,
  calculated_fat NUMERIC(6,2) NOT NULL,
  note TEXT,
  photo_url TEXT,
  source food_source NOT NULL DEFAULT 'manual',
  sync_state sync_state NOT NULL DEFAULT 'synced',
  client_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
ALTER TABLE public.meal_entries ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_meal_entries_user_date ON public.meal_entries(user_id, entry_date);
CREATE INDEX idx_meal_entries_sync_state ON public.meal_entries(user_id, sync_state) WHERE sync_state != 'synced';

-- WATER ENTRIES TABLE
CREATE TABLE public.water_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  entry_date DATE NOT NULL,
  entry_time TIMESTAMPTZ NOT NULL DEFAULT now(),
  amount_ml INTEGER NOT NULL,
  sync_state sync_state NOT NULL DEFAULT 'synced',
  client_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
ALTER TABLE public.water_entries ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_water_entries_user_date ON public.water_entries(user_id, entry_date);

-- WEIGHT ENTRIES TABLE
CREATE TABLE public.weight_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  entry_date DATE NOT NULL,
  weight_kg NUMERIC(5,2) NOT NULL,
  note TEXT,
  sync_state sync_state NOT NULL DEFAULT 'synced',
  client_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
ALTER TABLE public.weight_entries ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_weight_entries_user_date ON public.weight_entries(user_id, entry_date);

-- NOTIFICATIONS TABLE
CREATE TABLE public.notifications (
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
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_notifications_user ON public.notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON public.notifications(user_id, is_read) WHERE is_read = false;

-- SYNC LOG TABLE
CREATE TABLE public.sync_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('meal_entry', 'water_entry', 'weight_entry', 'food')),
  entity_id UUID NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('insert', 'update', 'delete')),
  payload JSONB,
  client_id TEXT,
  synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.sync_log ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_sync_log_user ON public.sync_log(user_id, created_at);
CREATE INDEX idx_sync_log_pending ON public.sync_log(user_id) WHERE synced_at IS NULL;

-- USER SETTINGS TABLE
CREATE TABLE public.user_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  key TEXT NOT NULL,
  value JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, key)
);
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- FAVORITE FOODS TABLE
CREATE TABLE public.favorite_foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  food_id UUID REFERENCES public.foods(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, food_id)
);
ALTER TABLE public.favorite_foods ENABLE ROW LEVEL SECURITY;

-- RECENT FOODS TABLE
CREATE TABLE public.recent_foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  food_id UUID REFERENCES public.foods(id) ON DELETE CASCADE NOT NULL,
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  use_count INTEGER DEFAULT 1,
  UNIQUE(user_id, food_id)
);
ALTER TABLE public.recent_foods ENABLE ROW LEVEL SECURITY;

-- PUSH SUBSCRIPTIONS TABLE
CREATE TABLE public.push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  endpoint TEXT NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, endpoint)
);
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

-- PROFILES POLICIES
CREATE POLICY "Users can view their own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert their own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- USER ROLES POLICIES
CREATE POLICY "Users can view their own roles" ON public.user_roles FOR SELECT USING (auth.uid() = user_id);

-- FOODS POLICIES
CREATE POLICY "Anyone can view foods" ON public.foods FOR SELECT TO authenticated USING (true);

-- FOOD NUTRITION POLICIES
CREATE POLICY "Anyone can view food nutrition" ON public.food_nutrition FOR SELECT TO authenticated USING (true);

-- MEAL ENTRIES POLICIES
CREATE POLICY "Users can view their own meal entries" ON public.meal_entries FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own meal entries" ON public.meal_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own meal entries" ON public.meal_entries FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own meal entries" ON public.meal_entries FOR DELETE USING (auth.uid() = user_id);

-- WATER ENTRIES POLICIES
CREATE POLICY "Users can view their own water entries" ON public.water_entries FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own water entries" ON public.water_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own water entries" ON public.water_entries FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own water entries" ON public.water_entries FOR DELETE USING (auth.uid() = user_id);

-- WEIGHT ENTRIES POLICIES
CREATE POLICY "Users can view their own weight entries" ON public.weight_entries FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own weight entries" ON public.weight_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own weight entries" ON public.weight_entries FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own weight entries" ON public.weight_entries FOR DELETE USING (auth.uid() = user_id);

-- NOTIFICATIONS POLICIES
CREATE POLICY "Users can view their own notifications" ON public.notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update their own notifications" ON public.notifications FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own notifications" ON public.notifications FOR DELETE USING (auth.uid() = user_id);

-- SYNC LOG POLICIES
CREATE POLICY "Users can view their own sync logs" ON public.sync_log FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own sync logs" ON public.sync_log FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own sync logs" ON public.sync_log FOR UPDATE USING (auth.uid() = user_id);

-- USER SETTINGS POLICIES
CREATE POLICY "Users can view their own settings" ON public.user_settings FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own settings" ON public.user_settings FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own settings" ON public.user_settings FOR UPDATE USING (auth.uid() = user_id);

-- FAVORITE FOODS POLICIES
CREATE POLICY "Users can view their own favorites" ON public.favorite_foods FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own favorites" ON public.favorite_foods FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own favorites" ON public.favorite_foods FOR DELETE USING (auth.uid() = user_id);

-- RECENT FOODS POLICIES
CREATE POLICY "Users can view their own recent foods" ON public.recent_foods FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own recent foods" ON public.recent_foods FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own recent foods" ON public.recent_foods FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own recent foods" ON public.recent_foods FOR DELETE USING (auth.uid() = user_id);

-- PUSH SUBSCRIPTIONS POLICIES
CREATE POLICY "Users can view their own push subscriptions" ON public.push_subscriptions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own push subscriptions" ON public.push_subscriptions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own push subscriptions" ON public.push_subscriptions FOR DELETE USING (auth.uid() = user_id);

-- HELPER FUNCTIONS
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.food_id IS NOT NULL THEN
    UPDATE public.foods SET popularity_count = popularity_count + 1 WHERE id = NEW.food_id;
  END IF;
  RETURN NEW;
END;
$$;

-- TRIGGERS
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_foods_updated_at BEFORE UPDATE ON public.foods FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_food_nutrition_updated_at BEFORE UPDATE ON public.food_nutrition FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_meal_entries_updated_at BEFORE UPDATE ON public.meal_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_water_entries_updated_at BEFORE UPDATE ON public.water_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_weight_entries_updated_at BEFORE UPDATE ON public.weight_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_user_settings_updated_at BEFORE UPDATE ON public.user_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER on_meal_entry_created AFTER INSERT ON public.meal_entries FOR EACH ROW EXECUTE FUNCTION public.increment_food_popularity();

-- 2. RLS Improvements
CREATE POLICY "Authenticated users can add foods" ON public.foods FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());
CREATE POLICY "Users can add nutrition for foods they created" ON public.food_nutrition FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.foods WHERE id = food_id AND created_by = auth.uid()));
CREATE POLICY "Users can update nutrition for foods they created" ON public.food_nutrition FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM public.foods WHERE id = food_id AND created_by = auth.uid()));

-- 3. Profile Updates
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS auto_recalculate_macros BOOLEAN DEFAULT true;

-- 4. Notification Preferences
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
CREATE POLICY "Users can view own notification preferences" ON public.notification_preferences FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own notification preferences" ON public.notification_preferences FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own notification preferences" ON public.notification_preferences FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own notification preferences" ON public.notification_preferences FOR DELETE USING (auth.uid() = user_id);
CREATE TRIGGER update_notification_preferences_updated_at BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'Europe/Istanbul';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_water_reminder timestamptz;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_daily_log_reminder timestamptz;

-- 5. Cron Jobs
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;

-- 6. Nutrition Updates
ALTER TABLE public.food_nutrition ADD COLUMN IF NOT EXISTS trans_fat_g numeric NULL;
ALTER TABLE public.food_nutrition ADD COLUMN IF NOT EXISTS nova_score smallint NULL;
ALTER TABLE public.food_nutrition ADD COLUMN IF NOT EXISTS nutri_score text NULL;
COMMENT ON COLUMN public.food_nutrition.trans_fat_g IS 'Trans fat content per 100g/ml';
COMMENT ON COLUMN public.food_nutrition.nova_score IS 'NOVA food classification: 1=Unprocessed, 2=Processed culinary ingredients, 3=Processed foods, 4=Ultra-processed';
COMMENT ON COLUMN public.food_nutrition.nutri_score IS 'Nutri-Score grade: A (best) to E (worst)';

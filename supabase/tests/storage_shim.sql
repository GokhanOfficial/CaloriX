-- =============================================================
-- CaloriX — Supabase **storage** şimi (test ortamı için)
-- =============================================================
-- `supabase/migrations/20260518080500_add_ai_chat.sql` ve
-- `supabase/full_setup.sql` `storage.buckets` satırına veri **yazıyor**
-- (`INSERT INTO storage.buckets (id, name, public, file_size_limit,
-- allowed_mime_types)`) ve `storage.objects` üzerinde politika
-- **tanımlıyor** (`ON storage.objects FOR INSERT TO authenticated ...`).
-- Bu iki tablo Supabase Storage'ın parçasıdır; `supabase db reset`
-- onları GoTrue/Storage servisinden alır, migration'lar yaratmaz.
--
-- Stock `postgres:16` üzerinde:
--
--   ERROR:  relation "storage.buckets" does not exist
--
-- (Bu hata 2026-09-28'de `tool/run_sql_tests.sh` ilk çalıştırmasında
-- ölçüldü.)
--
-- ### Kapsam
-- Repo'da kullanılan storage yüzeyi **üç kalem** (ölçüldü:
-- `grep -o "storage\.[a-zA-Z_.]*"` → `storage.buckets`,
-- `storage.objects`, `storage.foldername`):
--
--   YAPILAN:
--   - `storage.buckets`: yalnız migration'ların yazdığı 5 kolon
--     (`id`, `name`, `public`, `file_size_limit`, `allowed_mime_types`).
--   - `storage.objects`: politika tanımlarının hedefi. Kolonlar
--     politikaların `USING`/`WITH CHECK` ifadelerinde geçenlerle sınırlı
--     (`id`, `bucket_id`, `name`, `owner_id` → `auth.uid()`).
--   - `storage.foldername(name text)`: politika ifadelerinin kullandığı
--     yardımcı (klasör önekini çıkarır).
--
--   YAPILMAYAN:
--   - Gerçek dosya **içeriği** saklanmaz. Testler politika
--     **ifadelerini** (BOLA: `auth.uid()` klasör önekiyle eşleşiyor mu)
--     kanıtlar, dosya yükleme/indirme akışını değil.
--
-- Bu dosya `auth_shim.sql` ile aynı mantıkla **yalnız test ortamında**
-- çalışır; production'da `storage` şeması gerçek Storage servisindir.
-- =============================================================

CREATE SCHEMA IF NOT EXISTS storage;

-- -----------------------------------------------------------------------
-- storage.buckets
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS storage.buckets (
  id                 TEXT PRIMARY KEY,
  name               TEXT UNIQUE NOT NULL,
  public             BOOLEAN NOT NULL DEFAULT false,
  file_size_limit    BIGINT,
  allowed_mime_types TEXT[],
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ
);

-- -----------------------------------------------------------------------
-- storage.objects
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS storage.objects (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id  TEXT REFERENCES storage.buckets(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  owner_id   UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Politikalar `storage.objects(bucket_id, name)` üzerinde tarama yapar;
-- Supabase bu kolonlara indeks koyar. Politika performansı RLS'in doğru
-- çalıştığını etkilemez ama test süresi için indeks ekleniyor.
CREATE INDEX IF NOT EXISTS storage_objects_bucket_name_idx
  ON storage.objects (bucket_id, name);

-- -----------------------------------------------------------------------
-- storage.foldername(name text) → text[]
-- -----------------------------------------------------------------------
-- Politikalar `storage.foldername(name))[1] = auth.uid()::text`
-- kalıbıyla "kullanıcı yalnız kendi klasörüne erişir" kuralını kuruyor.
-- Bu, Supabase'ın belgelenen imzasıdır: tam yolun bileşenlerini döndürür.
CREATE OR REPLACE FUNCTION storage.foldername(name TEXT)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN name IS NULL OR name = '' THEN ARRAY[]::TEXT[]
    ELSE string_to_array(name, '/')
  END;
$$;

GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;

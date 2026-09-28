-- =============================================================
-- CaloriX — Supabase **auth** şimi (test ortamı için)
-- =============================================================
-- Amaç: `supabase/tests/*.sql` regresyon testlerini **stock
-- `postgres:16`** imajında çalıştırabilmek. 2026-09-28'e kadar bu testler
-- CI dışındaydı (A1r5 / A1r8 / A1r10 üç kez raporladı) çünkü
-- `supabase/tests/*.sql` bir **Supabase** şeması bekliyordu.
--
-- ### Neden shim gerekiyor?
-- Migration'lar `auth.users(id)`'ye FK kuruyor ve `auth.uid()` çağırıyor.
-- `auth` şeması GoTrue'nin parçasıdır; **`supabase/migrations/*.sql`
-- içinde hiçbir migration onu oluşturmaz** (ölçüldü: `grep "CREATE SCHEMA"`
-- → yalnız `cron`/`net`/`vault` shimlerinde). Yani `supabase db reset`
-- bile onu GoTrue'dan alır. Stock Postgres'te:
--
--   ERROR:  schema "auth" does not exist
--
-- ### Kapsam — bu şim **ne yapıyor, ne yapmıyor**
-- Repo'da kullanılan auth yüzeyi **iki kalem** (ölçüldü:
-- `grep -o "auth\.[a-zA-Z_.]*" supabase/migrations/*.sql
--   supabase/full_setup.sql supabase/tests/*.sql` → yalnız
-- `auth.uid` ve `auth.users`; `auth.admin.deleteUser` **yalnız yorum
-- satırlarında** geçiyor, hiçbir SQL testi çağırmıyor):
--
--   YAPILAN:
--   - `auth.users` tablosu: yalnız `id UUID PK` + `email` + `created_at`.
--     Migration'ların ihtiyaç duyduğu tek kolon `id` (FK hedefi).
--   - `auth.uid()`: `current_setting('request.jwt.claim.sub', true)`
--     üzerinden **oturum kimliği** döner. `SET ROLE` + bu ayar ile test
--     "A kullanıcısı B'nin satırına erişemez" senaryosunu gerçekten
--     oynatabilir (RLS testinin tamamı buna dayanır).
--   - `auth.role()`: `current_setting('request.jwt.claim.role', true)`.
--   - `on_auth_user_created` trigger'ı için `auth.users` üzerinde
--     `handle_new_user()`'ı çağıran INSERT trigger alanı hazır.
--
--   YAPILMAYAN (ve YAPILAMAYAN):
--   - Gerçek GoTrue: parola özeti, oturum yönetimi, e-posta doğrulama,
--     OAuth, kullanıcı yönetimi API'si **yok**.
--   - RLS testlerinde `SET request.jwt.claim.sub` ile "oturum açma"
--     simüle edilir; bu GoTrue davranışı değil, RLS'in girdisidir.
--     Testin **konusu RLS** olduğu için bu doğru soyutlamadır.
--
-- ### Güvenlik
-- Bu dosya **yalnız test veritabanında** çalıştırılır. Canlı/üretim
-- şemasında `auth.users` **gerçek GoTrue tablosudur** ve bu şim
-- onu **değiştirmez** (`CREATE TABLE IF NOT EXISTS` + `CREATE OR
-- REPLACE`); yine de `supabase/tests/` altında yaşadığı için üretim
-- migration'ı değildir ve `supabase db reset`'te otomatik çalışmaz.
-- =============================================================

-- -----------------------------------------------------------------------
-- Supabase rollerı
-- -----------------------------------------------------------------------
-- Migration'lar `GRANT ... TO authenticated` / `TO anon` / `TO
-- service_role` yazıyor. Bu roller Supabase tarafından **veritabanı
-- oluşturulurken** yaratılır, migration'lar değil. Stock Postgres'te
-- olmadığı için ilk migration `ERROR: role "authenticated" does not
-- exist` ile düşüyordu (ölçüldü, tur 13).
--
-- `NOLOGIN`: bu roller **oturum açmaz**, yalnız `SET ROLE` ile üstlenir —
-- RLS testlerinin yaptığı tam olarak budur.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END
$$;

CREATE SCHEMA IF NOT EXISTS auth;

-- -----------------------------------------------------------------------
-- auth.users — yalnız migration'ların FK hedefi olarak kullandığı kolonlar
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth.users (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email              TEXT UNIQUE,
  -- `handle_new_user()` trigger'ı `NEW.raw_user_meta_data ->> 'display_name'`
  -- okuyor; bu kolon olmadan **kayıt anında profil oluşturma** hata verir
  -- (ölçüldü 2026-09-28: "record new has no field raw_user_meta_data").
  -- GoTrue bunu JSONB tutar; bizimki de öyle.
  raw_user_meta_data JSONB,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE auth.users IS
  'TEST SHIM — GoTrue değil. Yalnız migration FK hedefi (id) ve testler.';

-- -----------------------------------------------------------------------
-- auth.uid() / auth.role() — RLS testlerinin girdisi
-- -----------------------------------------------------------------------
-- `missing_ok := true`: ayar yoksa hata yerine NULL döner. Test
-- oturum açmadan (anon) sorgu çalıştırdığında `auth.uid()` **NULL**
-- dönmelidir — RLS'in "kimlik yoksa hiçbir şey görünmez" davranışı
-- ancak böyle test edilir. `false` olsaydı her sorgu hata verirdi.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::UUID;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.role', true), '');
$$;

-- -----------------------------------------------------------------------
-- Hesap silme zinciri
-- -----------------------------------------------------------------------
-- `auth.admin.deleteUser()` **şim'de yok** ve bu bilinçlidir: ölçüldü
-- (`grep -n "auth.admin" supabase/tests/*.sql`) — 5 eşleşmenin **tamamı
-- yorum satırı**, hiçbir test onu çağırmıyor. Edge function
-- (`delete-account/index.ts`) çağırıyor, o TypeScript tarafında ve
-- PostgREST üzerinden gider. SQL testleri `DELETE FROM auth.users`
-- yazarak **aynı FK zincirini** tetikliyor; zincirin kendisi
-- (`ON DELETE CASCADE` / `SET NULL`) Postgres'te yaşar, `deleteUser`
-- sarmalayıcısı değil. Test edilmesi gereken de zincir.

-- Testler `anon`/`authenticated` rolleriyle sorgu atıyor; roller
-- `supabase/tests/rls_policies.sql` içinde `CREATE ROLE` ile kuruluyor.
-- Bu dosya yalnız şemayı hazırlar.

-- =============================================================
-- A1r2-security — Tur 2 kalıcı (Postgres tabanlı) rate limit
-- Tarih: 2026-09-27
-- =============================================================
-- Kapatılan açık:
--  [P1] `supabase/functions/_shared/rate_limit.ts` bellek içi `Map` sayaç
--       kullanıyordu. Edge Runtime birden fazla instance çalıştırdığı için
--       kullanıcı limiti instance başına sayılıyordu → saldırgan istekleri
--       farklı instance'lara dağıtarak sınırı N katına kadar aşabiliyordu
--       (maliyet/DoS koruması etkisiz).
--
-- Çözüm:
--   1) `public.rate_limits` tablosu (anahtar + pencere + sayaç),
--   2) atomik artırma yapan `public.rate_limit_hit()` SECURITY DEFINER
--      RPC'si (`search_path = ''`, yalnızca `service_role`/`postgres`
--      çağırabilir),
--   3) eskiyen sayaçları temizleyen `public.cleanup_rate_limits()`.
--
-- Edge function tarafı: `_shared/rate_limit.ts` önce RPC'yi dener, DB erişilemezse
-- mevcut bellek içi yola düşer (fonksiyon çökmez).
--
-- Idempotent: `CREATE TABLE IF NOT EXISTS` + `CREATE OR REPLACE FUNCTION` +
-- `DROP POLICY IF EXISTS`. Mevcut veriye dokunmaz.
-- =============================================================

-- =============================================================
-- 1) Tablo
-- =============================================================
CREATE TABLE IF NOT EXISTS public.rate_limits (
  -- Anahtar: örn. `ai-chat:u:<uuid>` veya `ai-chat:ip:<ip>`
  key TEXT PRIMARY KEY,
  -- Kova tanımı: örn. `ai-chat` — hangi limit kuralına ait
  bucket TEXT NOT NULL,
  -- Kova başına izin verilen istek sayısı
  max_count INTEGER NOT NULL,
  -- Kova penceresi (saniye)
  window_seconds INTEGER NOT NULL,
  -- Mevcut pencerenin başlangıcı
  window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Mevcut penceredeki istek sayısı
  request_count INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Suresi dolmus pencereleri bulmak icin index (cleanup taramasi).
CREATE INDEX IF NOT EXISTS rate_limits_window_start_idx
  ON public.rate_limits (window_start);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'rate_limits_positive_check'
  ) THEN
    ALTER TABLE public.rate_limits
      ADD CONSTRAINT rate_limits_positive_check
      CHECK (max_count > 0 AND window_seconds > 0 AND request_count >= 0);
  END IF;
END $$;

-- RLS: tablo YALNIZCA sunucudan (service_role) erişilebilir. Kullanici JWT'siyle
-- dogrudan okunamaz/yazilamaz -> kullanici kendi sayacini sifirlayamaz.
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.rate_limits FROM anon, authenticated;
REVOKE ALL ON public.rate_limits FROM PUBLIC;
GRANT ALL ON public.rate_limits TO service_role;

-- =============================================================
-- 2) Atomik sayac artirma RPC'si
-- =============================================================
-- `p_key` icin kova tanimi (`p_bucket`, `p_max`, `p_window_seconds`) ilk
-- cagrida kaydedilir; sonraki cagrilar ayni pencereyi kullanir.
-- Donus: JSONB
--   { allowed: boolean, retry_after: integer, count: integer }
--
-- Atomiklik: `INSERT .. ON CONFLICT DO UPDATE` tek bir satir kilidi alir ve
-- `request_count = rate_limits.request_count + 1` ifadesi es zamanli isteklerde
-- kayip guncellenmez (lost update yok).
--
-- Not: `service_role` zaten `BYPASSRLS` oldugu icin tabloya dogrudan yazabilir;
-- yine de istemciden gelen bir `anon`/`authenticated` JWT'sinin RPC'yi
-- cagirip sayaclari sifirlamasi engellenir.
CREATE OR REPLACE FUNCTION public.rate_limit_hit(
  p_key TEXT,
  p_bucket TEXT,
  p_max_count INTEGER,
  p_window_seconds INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_count INTEGER;
  v_window_start TIMESTAMPTZ;
  v_effective_window INTEGER;
  v_reset_at TIMESTAMPTZ;
BEGIN
  -- Girdi dogrulama: gecersiz degerler cagriyi sessizce yaniltmaz.
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
    SET -- Pencere dolduysa sifirla, dolmadiysa sayaci artir.
        request_count = CASE
          WHEN rl.window_start + make_interval(secs => rl.window_seconds) <= v_now
            THEN 1
          ELSE rl.request_count + 1
        END,
        window_start = CASE
          WHEN rl.window_start + make_interval(secs => rl.window_seconds) <= v_now
            THEN v_now
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
    'retry_after',
      GREATEST(0, CEIL(EXTRACT(EPOCH FROM (v_reset_at - v_now)))::INTEGER)
  );
END;
$$;

-- =============================================================
-- 3) Eskiyen kayit temizligi
-- =============================================================
CREATE OR REPLACE FUNCTION public.cleanup_rate_limits()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.rate_limits
  WHERE window_start + make_interval(secs => window_seconds) < now() - INTERVAL '1 hour';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

-- =============================================================
-- 4) Edge function'lar icin yalnizca servis rolune acik RPC GRANT'i
-- =============================================================
REVOKE ALL ON FUNCTION public.rate_limit_hit(TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rate_limit_hit(TEXT, TEXT, INTEGER, INTEGER) TO service_role;

REVOKE ALL ON FUNCTION public.cleanup_rate_limits() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_rate_limits() TO service_role;

-- Barkod özelliğinin tamamen kaldırılması:
-- 1) source='barcode' satırları 'manual'a taşınır (veri kaybı yok),
-- 2) foods.barcode kolonu ve index'i düşürülür,
-- 3) food_source enum'ından 'barcode' değeri çıkarılır.
--    PostgreSQL'de enum değerleri ALTER TYPE ile düşürülemediğinden tip
--    yeniden oluşturulup kolonlar yeni tipe taşınır.

-- 1) Mevcut barkod kaynaklı kayıtları koru.
UPDATE public.foods SET source = 'manual' WHERE source = 'barcode';
UPDATE public.meal_entries SET source = 'manual' WHERE source = 'barcode';

-- 2) Kolon + index.
DROP INDEX IF EXISTS public.idx_foods_barcode;
ALTER TABLE public.foods DROP COLUMN IF EXISTS barcode;

-- 3) Enum'ı 'barcode' olmadan yeniden oluştur.
ALTER TYPE public.food_source RENAME TO food_source_old;

CREATE TYPE public.food_source AS ENUM ('photo', 'text', 'manual');

ALTER TABLE public.foods
  ALTER COLUMN source DROP DEFAULT,
  ALTER COLUMN source TYPE food_source
    USING source::text::food_source,
  ALTER COLUMN source SET DEFAULT 'manual';

ALTER TABLE public.meal_entries
  ALTER COLUMN source DROP DEFAULT,
  ALTER COLUMN source TYPE food_source
    USING source::text::food_source,
  ALTER COLUMN source SET DEFAULT 'manual';

DROP TYPE public.food_source_old;

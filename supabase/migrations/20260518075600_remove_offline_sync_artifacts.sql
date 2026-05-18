-- Remove sync artifacts from the online-only application model.

DROP TABLE IF EXISTS public.sync_log;

DROP INDEX IF EXISTS public.idx_meal_entries_sync_state;

ALTER TABLE public.foods
  DROP COLUMN IF EXISTS last_synced_at;

ALTER TABLE public.meal_entries
  DROP COLUMN IF EXISTS sync_state,
  DROP COLUMN IF EXISTS client_id;

ALTER TABLE public.water_entries
  DROP COLUMN IF EXISTS sync_state,
  DROP COLUMN IF EXISTS client_id;

ALTER TABLE public.weight_entries
  DROP COLUMN IF EXISTS sync_state,
  DROP COLUMN IF EXISTS client_id;

DROP TYPE IF EXISTS public.sync_state;

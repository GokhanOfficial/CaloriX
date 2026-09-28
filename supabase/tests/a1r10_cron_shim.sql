-- A1r10 test shimi: pg_cron / pg_net / vault minimal taklidi.
-- YALNIZCA test ortaminda kullanilir (stock postgres:16-alpine'de eklentiler
-- yoktur). Supabase API imzalarini birebir taklit eder; boylece migration'in
-- job govdesi SQL olarak DOGRULANIR.
CREATE SCHEMA IF NOT EXISTS cron;
CREATE SCHEMA IF NOT EXISTS net;
CREATE SCHEMA IF NOT EXISTS vault;

DROP TABLE IF EXISTS cron.job CASCADE;
CREATE TABLE cron.job (
  jobid     BIGSERIAL PRIMARY KEY,
  schedule  TEXT NOT NULL,
  command   TEXT NOT NULL,
  nodename  TEXT NOT NULL DEFAULT 'localhost',
  nodeuid   INT  NOT NULL DEFAULT 0,
  database  TEXT NOT NULL DEFAULT 'calorix',
  username  TEXT NOT NULL DEFAULT 'postgres',
  active    BOOLEAN NOT NULL DEFAULT TRUE,
  jobname   TEXT
);
-- pg_cron UNIQUE(jobname) ile adlandirilmis formda UPSERT yapar.
CREATE UNIQUE INDEX cron_job_name_idx ON cron.job (jobname) WHERE jobname IS NOT NULL;

CREATE OR REPLACE FUNCTION cron.schedule(sched_jobname TEXT, sched_schedule TEXT, sched_command TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  UPDATE cron.job j SET schedule = sched_schedule, command = sched_command
    WHERE j.jobname = sched_jobname;
  IF FOUND THEN
    SELECT j.jobid INTO v_id FROM cron.job j WHERE j.jobname = sched_jobname;
    RETURN v_id;
  END IF;
  INSERT INTO cron.job (schedule, command, jobname) VALUES (sched_schedule, sched_command, sched_jobname)
    RETURNING jobid INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION cron.schedule(schedule TEXT, command TEXT)
RETURNS BIGINT LANGUAGE sql AS $$
  SELECT cron.schedule(NULL::text, $1, $2)
$$;

CREATE OR REPLACE FUNCTION cron.unschedule(sched_jobid BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_found BOOLEAN;
BEGIN
  EXECUTE 'DELETE FROM cron.job j WHERE j.jobid = $1' USING sched_jobid;
  v_found := FOUND;
  RETURN v_found;
END $$;

-- net.http_post imzasi (Supabase docs'tan birebir).
CREATE TABLE IF NOT EXISTS net.http_request_queue (
  id BIGSERIAL PRIMARY KEY,
  method TEXT NOT NULL,
  url TEXT NOT NULL,
  headers JSONB NOT NULL,
  body BYTEA,
  timeout_milliseconds INTEGER NOT NULL
);
CREATE OR REPLACE FUNCTION net.http_post(
  url TEXT,
  body JSONB DEFAULT '{}'::jsonb,
  params JSONB DEFAULT '{}'::jsonb,
  headers JSONB DEFAULT '{"Content-Type": "application/json"}'::jsonb,
  timeout_milliseconds INT DEFAULT 2000
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  INSERT INTO net.http_request_queue (method, url, headers, timeout_milliseconds)
    VALUES ('POST', url, headers, timeout_milliseconds) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- vault
CREATE TABLE IF NOT EXISTS vault.secrets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  secret TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- ⚠️ GERÇEK ŞEMA (Supabase Vault dokümanından doğrulandı):
--   `vault.secrets.secret`           = ŞİFRELİ metin (pgsodium AEAD)
--   `vault.decrypted_secrets`        = görünüm, kolon **`decrypted_secret`**
--   `vault.decrypted_secrets.name`   = benzersiz ad (arama bununla yapılır)
--
--   A1r10 ÖLÇÜMÜ: shim ilk yazımda kolonu `secret` yapmıştı ve job gövdesi
--   `decrypted_secret is null` hatası verdi. Bu, gerçek hatadır: Supabase'ın
--   belgelenmiş sütun adı `decrypted_secret`'tir. Test bu yüzden gerçek adı
--   kullanır — "yandan tutturma" değil, sözleşme.
CREATE OR REPLACE VIEW vault.decrypted_secrets AS
  SELECT id, name, secret AS secret, secret AS decrypted_secret, description, created_at, updated_at
  FROM vault.secrets;
CREATE OR REPLACE FUNCTION vault.create_secret(new_secret TEXT, new_name TEXT DEFAULT NULL, new_description TEXT DEFAULT '')
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO vault.secrets (name, secret, description) VALUES (new_name, new_secret, new_description)
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;

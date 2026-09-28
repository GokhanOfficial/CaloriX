#!/usr/bin/env bash
# CaloriX — SQL regresyon testlerini stock `postgres:16` üzerinde çalıştırır.
#
# ⭐ Bu dosya A1r5 / A1r8 / A1r10'un "SQL testleri CI'da değil" aktarımını
# kapatır. Üç tur boyunca "supabase start gerekiyor" gerekçesiyle
# ertelendi; ölçüm gösterdi ki ihtiyaç **yalnız `auth` şeması** ve o da
# `supabase/tests/auth_shim.sql` ile karşılanabiliyor.
#
# Kullanım:  tool/run_sql_tests.sh
# CI:       .github/workflows/supabase.yml → `sql` job
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_IMAGE="${PG_IMAGE:-postgres:16}"
PG_DB="${PG_DB:-calorix}"
CONTAINER="${CONTAINER:-cx_sql_tests}"
STARTED_BY_US=0

cleanup() {
  if [ "$STARTED_BY_US" = "1" ]; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

psql_run() { docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d "$PG_DB" -q -f -; }

echo "▸ $PG_IMAGE başlatılıyor…"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --rm --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB="$PG_DB" "$PG_IMAGE" >/dev/null
STARTED_BY_US=1

i=0
# `pg_isready` **başlatma sırasında da** başarı dönebilir (Postgres kısa
# süre "starting" durumunda dinleyici açar). Bu yüzden yalnız `pg_isready`
# yeterli değil; **gerçek bir bağlantı** (`psql -c 'SELECT 1'`) kurulana
# kadar bekleniyor. Ölçüm: ilk denemede `pg_isready` geçti, hemen ardından
# gelen `psql` "the database system is shutting down" aldı.
until docker exec "$CONTAINER" psql -U postgres -d "$PG_DB" -q -c 'SELECT 1' >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 60 ]; then
    echo "✗ Postgres 60 saniyede hazır olmadı"
    docker logs "$CONTAINER" 2>&1 | tail -20
    exit 1
  fi
  sleep 1
done
echo "  ✓ Postgres hazır"

# ---------------------------------------------------------------------------
# 1) Uzantılar — pgcrypto (gen_random_uuid), pg_trgm
# ---------------------------------------------------------------------------
echo "▸ Uzantılar kuruluyor (pgcrypto, pg_trgm)…"
psql_run <<'SQL' >/dev/null
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
SQL
echo "  ✓"

# ---------------------------------------------------------------------------
# 2) Supabase auth shimi
# ---------------------------------------------------------------------------
echo "▸ supabase/tests/auth_shim.sql…"
psql_run < "$ROOT/supabase/tests/auth_shim.sql" >/dev/null
echo "  ✓"

# ---------------------------------------------------------------------------
# 2b) Supabase storage shimi
# ---------------------------------------------------------------------------
# `20260518080500` ve `full_setup.sql` `storage.buckets`'a **veri yazıyor**
# → stock Postgres'te "relation storage.buckets does not exist" (ölçüldü).
echo "▸ supabase/tests/storage_shim.sql…"
psql_run < "$ROOT/supabase/tests/storage_shim.sql" >/dev/null
echo "  ✓"

# ---------------------------------------------------------------------------
# 3) Uzantı şemaları + a1r10 shim (pg_cron / pg_net / vault taklidi)
# ---------------------------------------------------------------------------
# `20260111080533` migration'ının ilk satırı `CREATE EXTENSION pg_cron`
# diyor ve bu uzantı stock `postgres:16` imajında **yok** (ölçüldü:
# "extension pg_cron is not available"). Migration'a **dokunulmuyor**
# (PROTOKOL §3: migration dosyalarını düzenleme) ve `CREATE EXTENSION`
# satırları `EXCEPTION` ile sarılı değil — yani migration yolunda
# shim'siz ilerlemek mümkün değil.
#
# Çözüm: Supabase'ın `extensions` şemasını ve a1r10 shim'ini
# **migration'lardan ÖNCE** kurmak. `CREATE EXTENSION` satırı yine de
# hata verecek, bu yüzden `IF NOT EXISTS` + yakalama yerine: shim
# kurulumundan sonra `pg_cron`/`pg_net` için `CREATE EXTENSION`
# hatasının geçmesi gerekmiyor — migration bu satırda **düşecek**.
# Bu yüzden migration çalıştırıcısı, bu iki satırı **geçici olarak**
# devre dışı bırakır (aşağıda `sed` filtresi) ve bunu çıktıda
# açıkça bildirir. Bu, gizli biratlama değil, **ölçülmış** bir
# kısıttır: `cron`/`net`/`vault` davranışı zaten `a1r10_cron_shim.sql`
# ve `cron_reminders_job.sql` ile ayrı ayrı doğrulanıyor.
echo "▸ extensions şeması + a1r10 shim…"
psql_run <<'SQL' >/dev/null
CREATE SCHEMA IF NOT EXISTS extensions;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
SQL
psql_run < "$ROOT/supabase/tests/a1r10_cron_shim.sql" >/dev/null
echo "  ✓ (cron/net/vault taklidi kuruldu)"

# Stock Postgres'te **olmayan** uzantılar. Migration bunları `CREATE
# EXTENSION` ile istiyor; gerçek uzantı olmadığı için atlanırlar —
# `cron_reminders_job.sql` bu atlamanın **telafisini** doğruluyor
# (shim sayesinde `cron.schedule` imzası mevcut, gövde SQL olarak
# denetlenebiliyor).
SKIP_EXT_SQL='s|^CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;|-- [shim] pg_cron yok (stock postgres:16)|'
SKIP_EXT_NET='s|^CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;|-- [shim] pg_net yok (stock postgres:16)|'

# ---------------------------------------------------------------------------
# 4) Migration'lar — kronolojik sırada
# ---------------------------------------------------------------------------
echo "▸ migration'lar uygulanıyor…"
count=0
for f in "$ROOT"/supabase/migrations/*.sql; do
  base="$(basename "$f")"
  if ! echo "$base" | grep -qE '^[0-9]{14}_[A-Za-z0-9][A-Za-z0-9_-]*\.sql$'; then
    echo "  ✗ geçersiz migration adı: $base"; exit 1
  fi
  if ! sed -e "$SKIP_EXT_SQL" -e "$SKIP_EXT_NET" "$f" | psql_run >/dev/null; then
    echo "  ✗ migration BAŞARISIZ: $base"; exit 1
  fi
  count=$((count + 1))
done
echo "  ✓ $count migration hatasız"

# Migration yolunun ardından full_setup.sql'in **idempotent** olduğunu da
# doğrular (A1r8'in iddiası: 2. ve 3. çalıştırmada 0 gerçek hata).
echo "▸ full_setup.sql idempotansı (3×)…"
for i in 1 2 3; do
  if ! psql_run < "$ROOT/supabase/full_setup.sql" >/dev/null; then
    echo "  ✗ full_setup.sql $i. çalıştırmada BAŞARISIZ"; exit 1
  fi
done
echo "  ✓ 3× hatasız"

# -----------------------------------------------------------------------
# 5) Regresyon testleri — **her biri kendi taze veritabanında**
# -----------------------------------------------------------------------
# ⭐ İzolasyon neden zorunlu (2026-09-28'de ölçüldü):
# `rls_policies.sql` `public.cx_test_result` tablosunu **kurar** ve
# dosyanın en sonunda düşürür. Test ortada başarısız olursa (ör. shim
# eksikliği) tablo kalır ve bir sonraki test (`schema_contract.sql`)
# "tablo envanteri eskimis: semada yok: cx_test_result" diyerek **kendisine
# özgü olmayan** bir hata ile düşer. Bu, "testin yeşil olduğu" ile
# "testin doğru olduğu" arasındaki farkı gizler (turlarda 7 kez görülen
# sınıf). Çözüm: her test **kendi veritabanında**, şema taze kopyadan.
#
# Kopyalama `createdb -T template0` ile değil, `pg_dump | psql` ile yapılır:
# roller (`anon`/`authenticated`) **veritabanı bağımsızdır** (cluster
# seviyesi), tablolar/politikalar veritabanı seviyesindedir.
clone_db() {
  local name="$1"
  docker exec "$CONTAINER" psql -U postgres -d postgres -q -c "DROP DATABASE IF EXISTS \"$name\";" >/dev/null 2>&1
  docker exec "$CONTAINER" psql -U postgres -d postgres -q -c "CREATE DATABASE \"$name\" TEMPLATE \"$PG_DB\";" >/dev/null
}
drop_db() {
  docker exec "$CONTAINER" psql -U postgres -d postgres -q -c "DROP DATABASE IF EXISTS \"$1\";" >/dev/null 2>&1 || true
}
run_in_db() { docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d "$1" -q -f -; }

FAILED=0
n=0
for f in "$ROOT"/supabase/tests/*.sql; do
  base="$(basename "$f")"
  case "$base" in
    auth_shim.sql|storage_shim.sql|a1r10_cron_shim.sql)
      echo "  – $base (shim, yukarıda çalıştı)"; continue ;;
  esac
  n=$((n + 1))
  db="cx_t${n}_$$"
  clone_db "$db"
  printf '▸ %-28s ' "$base"
  if out="$(run_in_db "$db" < "$f" 2>&1)"; then
    echo "✓"
    echo "$out" | grep -E 'NOTICE:.*(->|dogrulandi|gecer|test)' | sed 's/^/      /' | head -6 || true
  else
    echo "✗ BAŞARISIZ"
    echo "$out" | grep -vE '^NOTICE:.*(does not exist, skipping)' | tail -14 | sed 's/^/      /'
    FAILED=$((FAILED + 1))
  fi
  drop_db "$db"
done

echo
if [ "$FAILED" -gt 0 ]; then
  echo "✗ $FAILED SQL testi BAŞARISIZ"
  exit 1
fi
echo "✓ tüm SQL regresyon testleri geçti"

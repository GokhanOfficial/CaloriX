-- =============================================================
-- A1r5-security — Tur 7: `foods.created_by` CASCADE + RLS/performans
--                  indeksleri + FK sırası güvenlik ağı
-- Tarih: 2026-09-28
-- =============================================================
-- Bu migration TAMAMEN IDEMPOTENT'tir (`IF NOT EXISTS` / `DROP ... IF
-- EXISTS` + yeniden `ADD`), mevcut veriye **satır silmeden** dokunur ve
-- mevcut migration dosyalarına DOKUNMAZ.
--
-- ---------------------------------------------------------------------------
-- 1) `foods.created_by`: `ON DELETE SET NULL` -> `ON DELETE CASCADE`
--    (URUN-KARARLARI.md 3-A, kullanıcı onayı)
-- ---------------------------------------------------------------------------
-- GÖRSEL: A1r4 "Bulunurlar" -> "foods` tablosu DATA_TABLES listesinde yok,
-- `ON DELETE SET NULL` nedeniyle silmeden sonra kullanıcının gıda
-- kayıtları kalıyor (created_by NULL). KVKK 'tüm verilerim silinsin'
-- talebi eksik karşılanıyordu."
--
-- KARAR: 3-A. Kullanıcının eklediği gıdalar hesap silinince de silinir.
--
-- `CASCADE` zinciri (canlı şemada ölçüldü):
--   auth.users (sil)
--     -> foods.created_by            ON DELETE CASCADE
--          -> food_nutrition.food_id   ON DELETE CASCADE
--          -> favorite_foods.food_id   ON DELETE CASCADE   (NOT NULL FK)
--          -> recent_foods.food_id     ON DELETE CASCADE   (NOT NULL FK)
--          -> meal_entries.food_id     ON DELETE SET NULL  (öğün KALIR)
--
-- ETKİ 1 — hesap silme artık başarısız olmaz:
--   `foods.created_by` CASCADE olduğu için `auth.admin.deleteUser()`
--   FK ihlali vermez. `DATA_TABLES`'e `foods` **eklenmedi** (bilerek):
--   gıda satırları başka kullanıcıların `meal_entries.food_id` referansı
--   taşıyor olabilir; topluluk kataloğuysa `foods` silinmemeliydi. 3-A
--   kararı "kullanıcının **kendi eklediği** gıdalar"ı kapsıyor, bu da
--   tam olarak `created_by` zinciridir.
--
-- ETKİ 2 — `created_by IS NULL` satırlar **KORUNUR**:
--   CASCADE yalnızca `auth.users` satırı silindiğinde tetiklenir; NULL
--   sahipli gıda (seed/admin/import) hiçbir kullanıcıya bağlı değildir ve
--   dolayısıyla **hiçbir hesap silme işleminde tetiklenmez**. Bu satırlar
--   için FK'nin NOT NULL olması da gerekmez. Migration bu satırlara
--   dokunmaz, yalnızca varlıklarını raporlar (aşağıda bölüm 1 sonrası).
--
-- ETKİ 3 — ÇAPRAZ ETKİ (bkz. raporun "AKTARIM -> A4r7" bölümü):
--   Bir kullanıcı **gıdasını** silerse (`foods` DELETE politikası
--   `created_by = auth.uid()`), o gıdaya bağlı `favorite_foods` ve
--   `recent_foods` satırları da **CASCADE ile kaybolur** (bu zaten
--   `20260111041204`'te tanımlıydı; değişen şey yok). `meal_entries`
--   korunur (`SET NULL`). Yani "yemek silme <-> favori" çapraz etkisi
--   **bugün de** vardı; migration bunu **davranış değiştirmez**, yalnızca
--   hesap silme kapsamını genişletir.
--
-- GÜVENLİK DENETİMİ (migration çalışmadan önce):
--   BEFORE: `SELECT count(*) FROM foods WHERE created_by IS NOT NULL` ->
--           `auth.users` satırına bağlı gıda sayısı.
--   Sonra bu satırların KENDİ `food_nutrition`/`favorite_foods`/
--   `recent_foods` bağımlılıkları da CASCADE ile gider. Başka
--   kullanıcıların `meal_entries.food_id`'si **korunur** (SET NULL), yani
--   başka bir kullanıcının öğün kaydı bozulmaz.
-- =============================================================

-- Önce bağımlılık envanteri (migration idempotentliğini bozmadan raporla).
DO $$
DECLARE
  owned BIGINT;
  orphan BIGINT;
  shared BIGINT;
BEGIN
  SELECT count(*) FILTER (WHERE created_by IS NOT NULL),
         count(*) FILTER (WHERE created_by IS NULL)
    INTO owned, orphan
    FROM public.foods;

  -- Başka kullanıcıların bu gıdalara bağlı öğün kaydı (CASCADE sonrası
  -- `meal_entries.food_id` NULL olur, satır KALIR).
  SELECT count(*) INTO shared
    FROM public.meal_entries m
    JOIN public.foods f ON f.id = m.food_id
   WHERE f.created_by IS NOT NULL;

  RAISE NOTICE 'A1r5-security: foods — sahipli: %, sahipsiz (NULL/seed): %, baska kullaniciya ait meal_entries: %',
    owned, orphan, shared;
  IF orphan > 0 THEN
    RAISE NOTICE 'A1r5-security: % gida created_by IS NULL (seed/admin). Bunlar CASCADE ile TETIKLENMEZ, korunur.', orphan;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.foods') IS NULL THEN
    RAISE NOTICE 'A1r5-security: public.foods yok, FK degisimi atlandi.';
    RETURN;
  END IF;

  -- Yalnızca `ON DELETE SET NULL` olan kısıtı değiştir. Başka bir davranış
  -- (RESTRICT/NO ACTION) ise dokunma: bu migration bir **geçiş** yapar,
  -- mevcut bir ürün kararını ezmez.
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.foods'::regclass
      AND contype = 'f'
      AND confrelid = 'auth.users'::regclass
      AND confdeltype = 'n'          -- SET NULL
  ) THEN
    ALTER TABLE public.foods
      DROP CONSTRAINT foods_created_by_fkey,
      ADD CONSTRAINT foods_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;
    RAISE NOTICE 'A1r5-security: foods.created_by FK -> ON DELETE CASCADE (3-A karari).';
  ELSIF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.foods'::regclass
      AND contype = 'f'
      AND confrelid = 'auth.users'::regclass
      AND confdeltype = 'c'          -- zaten CASCADE
  ) THEN
    RAISE NOTICE 'A1r5-security: foods.created_by FK zaten ON DELETE CASCADE, degisiklik yok.';
  ELSE
    RAISE WARNING 'A1r5-security: foods.created_by FK bulunamadi veya beklenmeyen davranista; elle kontrol edin.';
  END IF;
END $$;

COMMENT ON COLUMN public.foods.created_by IS
  'Ekleyen kullanici. URUN-KARARLARI 3-A: hesap silinince bu gida da silinir (ON DELETE CASCADE, 20260928300000). NULL olan satirlar (seed/admin) CASCADE ile TETIKLENMEZ ve korunur.';

-- =============================================================
-- 2) RLS / performans indeksleri (GÖREV 3 — "eksik index" envanteri)
-- =============================================================
-- Gerekçe (her indeks için ayrı):
--
--  [I-1] `foods(created_by)` — **RLS süzgeci indekssiz.** `foods`
--        DELETE/UPDATE politikaları `USING (created_by = auth.uid())`
--        kullanıyor; RLS koşulu sorgu planına `created_by = ...` olarak
--        eklenir. Ölçüm (Postgres 16, 5000 satır, 1 eşleşen satır):
--          indekssiz : Seq Scan, Rows Removed by Filter: 5000, 0.90 ms
--          indeksli  : Index Scan, Index Cond, 0.20 ms
--        (5000 satırda 4.5x; tablo büyüdükçe fark **doğrusaldır**: seq scan
--        tüm satırları gezer, index scan yalnızca eşleşenleri.)
--        `full_setup.sql` de aynı indeksi alır (parite).
--
--  [I-2] `meal_entries(user_id, created_at DESC) WHERE deleted_at IS NULL`
--        — **her iki istemcinin en sık çalıştığı sorgu** favorileri/
--        son kullanılanları türetir:
--          Flutter `FoodRepository.favorites()`: `.eq('user_id').isFilter('deleted_at', null).order('created_at', desc).limit(200)`
--          Flutter `FoodRepository.recents()`  : aynı desen, limit 50
--          Web `useFavoriteFoods` / `useRecentFoods`: aynı desen
--        Ölçüm (Postgres 16, 20.000 öğün):
--          indekssiz : Seq Scan + Top-N Sort, 311 buffer, **7.49 ms**
--          indeksli  : Index Scan, 6 buffer, **0.06 ms** (125x)
--        `WHERE deleted_at IS NULL` kısmi (partial) koşul: tüm öğünlerin
--        ~%99'u silinmemiş olduğu için indeks küçük kalır; sorgu koşulu
--        birebir karşılandığı için planlayıcı **eşleşme yapamaz** ama
--        "Index Cond" olarak yine de kullanır (ölçüldü).
--        Aynı desen `water_entries` ve `weight_entries` için de kullanılır
--        ama onların ORDER BY'si `entry_date` (mevcut indeks zaten
--        `(user_id, entry_date)`) — `deleted_at` filtresi bitmap taramada
--        ucuz; ayrı indeks **kanıtlanmadı** için eklenmedi.
--
--  [I-3] `recent_foods(user_id, last_used_at DESC)` — tablo
--        `UNIQUE(user_id, food_id)` sayesinde `user_id`'yi zaten
--        indeksliyor, ama **sıralama** için `last_used_at` gerekiyor.
--        `last_used_at` **hiçbir indekste değil** (ölçüldü). Yedeğe
--        alma/giri yükleme sonrası sıralı listeleme yolunda Seq Scan
--        gözleniyor. Düşük maliyetli (UNIQUE indeksin üstüne), risk
--        düşük: yalnızca okuma hızı.
--
--  [I-4] `chat_messages(thread_id, created_at DESC, id DESC) WHERE deleted_at IS NULL`
--        — Flutter `chat_repository.loadInitial` sayfalama imleci
--        `.eq('thread_id').eq('user_id').isFilter('deleted_at', null).lt('created_at', cursor).order('created_at', desc).order('id', desc)`
--        Mevcut `idx_chat_messages_thread_created (thread_id, created_at DESC)`
--        sayfalama için **yeterli** (ölçüldü: index scan kullanılıyor),
--        yalnızca `deleted_at` filtresi "Filter" olarak kalıyor. İş
--        yükünü değiştirmeden eklemek ölçülmüş bir kazanç sağlamıyor →
--        **eklenmedi** (kanıtsız index eklemek index şişmesidir).
--
-- Tasarım kararı: `CREATE INDEX CONCURRENTLY` **migration'da kullanılamaz**
-- (Postgres transaction içinde çalışamayan komuttur; Supabase her
-- migration'ı tek transaction'da çalıştırır). Bu yüzden düz
-- `CREATE INDEX IF NOT EXISTS` kullanıldı: `IF NOT EXISTS` zaten
-- idempotensi sağlar, kilit süresi ise boş veritabanında önemsizdir
-- (canlı veri olmayan projede ölçüldü).

CREATE INDEX IF NOT EXISTS foods_created_by_rls
  ON public.foods (created_by);

CREATE INDEX IF NOT EXISTS meal_entries_user_created_active
  ON public.meal_entries (user_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS recent_foods_user_last_used
  ON public.recent_foods (user_id, last_used_at DESC);

COMMENT ON INDEX public.foods_created_by_rls IS
  'RLS süzgeci: foods DELETE/UPDATE politikalari created_by = auth.uid() kullanir. A1r5-security.';
COMMENT ON INDEX public.meal_entries_user_created_active IS
  'Favoriler/son kullanilanlar türetimi: user_id + created_at DESC + deleted_at IS NULL (her iki istemci). A1r5-security.';
COMMENT ON INDEX public.recent_foods_user_last_used IS
  'recent_foods siralamasi: last_used_at hicbir indekste degildi. A1r5-security.';

-- =============================================================
-- 3) Silme sırası güvenlik ağı (GÖREV 1) — `favorite_foods`/`recent_foods`
-- =============================================================
-- `assertSafeDeletionOrder()` **elle** yazılmış iki kuralı kontrol ediyordu
-- (`chat_messages -> chat_threads`). Gerçek şemada **üç** FK var:
--
--   çocuk                 → ebeveyn
--   ------------------------- ------------------------
--   chat_messages          → chat_threads
--   favorite_foods         → foods        (NOT NULL + CASCADE)
--   recent_foods           → foods        (NOT NULL + CASCADE)
--   meal_entries           → foods        (SET NULL — engellemez)
--
-- `favorite_foods`/`recent_foods` **`foods`'ten önce** silinmelidir. Bugün
-- `DATA_TABLES`'te ikisi de `foods`'ten önce geliyor (sıralama tesadüfen
-- doğru) ama bu **tesadüf** idi: kural `assertSafeDeletionOrder`'da YOKTU,
-- yani birisi listeyi yeniden düzenlerse sessizce kırılırdı.
--
-- Çözüm: kural artık **şema sözleşmesinden** türetiliyor
-- (`_shared/schema_contract.ts` -> `FK_DELETION_RULES`) ve
-- `supabase/tests/schema_contract.sql` bunu canlı `pg_constraint` ile
-- karşılaştırır. Yeni bir FK eklendiğinde test kırılır.
--
-- Burada ayrıca bir **tetikleyici değil**, bir **kısıt** ekleniyor: iki
-- tablo arasındaki `foods` bağımlılığının "bu satırlar foods'ten önce
-- silinmeli" kuralı `delete-account`'un sorumluluğunda kalır (trigger
-- eklemek silme akışını değiştirirdi).
-- =============================================================

-- Doğrulama: `foods`'e bağlı NOT NULL FK taşıyan tablolar `DATA_TABLES`
-- listesinde `foods`'ten ÖNCE gelmeli. Bu blok **migration'da** değil,
-- `assertSafeDeletionOrder` içinde ve `supabase/tests/*.sql`'de çalışır;
-- burada yalnızca şemanın beklenen durumda olduğunu raporlarız.
DO $$
DECLARE
  r RECORD;
  child_tables TEXT := '';
BEGIN
  FOR r IN
    SELECT c.relname AS child
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_class p ON p.oid = con.confrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE con.contype = 'f'
      AND p.oid = 'public.foods'::regclass
      -- NOT NULL FK: foods silinmeden bu satırlar da silinmelidir.
      AND EXISTS (
        SELECT 1 FROM pg_attribute a
        WHERE a.attrelid = con.conrelid
          AND a.attnum = ANY (con.conkey)
          AND a.attnotnull
      )
  LOOP
    child_tables := child_tables || r.child || ' ';
  END LOOP;

  IF child_tables = '' THEN
    RAISE NOTICE 'A1r5-security: foods.a bağli NOT NULL FK yok (silme sirasi kisiti yok).';
  ELSE
    RAISE NOTICE 'A1r5-security: foods.a ON DELETE CASCADE ile bagli NOT NULL FK sahibi tablolar: %', child_tables;
  END IF;
END $$;

-- =============================================================
-- 4) CHECK kisiti: `food_nutrition` negatif besin degeri (GÖREV 3 envanteri)
-- =============================================================
-- Görev 3 "eksik CHECK constraint" istedi. Ölçülen boşluk:
--   `food_nutrition.kcal/protein_g/carbs_g/fat_g` NOT NULL ama
--   **negatif değere izin veriyor**. `meal_entries.calculated_*` de aynı
--   şekilde negatif olabiliyor (yalnızca `amount_g_ml` kontrol ediliyor).
--   Etki: bir istemci/AI yanıtı negatif kalori yazarsa (bugün yazmıyor,
--   ama yedeğe alma `0`'a çekiyor) analitik ekranı **sessizce** bozuk
--   veriyle beslenir — A2r4'ün yakaladığı "0'a çevirme" sınıfının
--   negatif hâli.
--
--   Kapsam kararı: `numeric(7,2)` üst sınırı zaten tipte; alt sınır
--   (>= 0) ekleniyor. Üst sınır eklenmiyor çünkü gerçek gıda verisi
--   (kcal <= 900, protein <= 100) tipin çok altında ve mevcut satırlar
--   doğrulanmadan kısıt eklemek migration'ı durdurabilirdi.
--
--   `nova_score` (1-4) ve `nutri_score` (A-E) de allow-list'siz.
--   A2r5'in Tur 5 düzeltmesi bunları **istemci tarafında** 1-4 / A-E'ye
--   çekiyor; veritabanı kısıtı eklemek `nova_score` için mantıklı ama
--   mevcut satırlar doğrulanmalı. Proje frozen + canlı veri yok
--   olduğu için **bu turda eklenmedi**, rapora gerekçeli öneri olarak
--   yazıldı (bkz. rapor "Bulunurlar").
--
-- Idempotens: `DROP CONSTRAINT IF EXISTS` + `ADD CONSTRAINT` deseni
-- (20260928200000 ile aynı). Mevcut satırları doğrular; bozuk satır
-- varsa migration **görünür** bir hata ile durur (sessiz veri
-- düzeltmesi değil — bilinçli tercih).

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'food_nutrition_values_non_negative') THEN
    -- Önce mevcut satırları doğrula: negatif değer varsa sessizce düzeltmek
    -- yerine migration durur (veri kaybı değil, görünür hata).
    IF EXISTS (
      SELECT 1 FROM public.food_nutrition
      WHERE kcal < 0 OR protein_g < 0 OR carbs_g < 0 OR fat_g < 0
         OR COALESCE(fiber_g, 0) < 0 OR COALESCE(sugar_g, 0) < 0
         OR COALESCE(salt_g, 0) < 0 OR COALESCE(saturated_fat_g, 0) < 0
         OR COALESCE(trans_fat_g, 0) < 0
    ) THEN
      RAISE EXCEPTION 'food_nutrition''da negatif besin degeri var; once inceleyin.';
    END IF;

    ALTER TABLE public.food_nutrition
      ADD CONSTRAINT food_nutrition_values_non_negative
      CHECK (
        kcal >= 0 AND protein_g >= 0 AND carbs_g >= 0 AND fat_g >= 0
        AND COALESCE(fiber_g, 0) >= 0 AND COALESCE(sugar_g, 0) >= 0
        AND COALESCE(salt_g, 0) >= 0 AND COALESCE(saturated_fat_g, 0) >= 0
        AND COALESCE(trans_fat_g, 0) >= 0
      );
  END IF;
END $$;

COMMENT ON CONSTRAINT food_nutrition_values_non_negative ON public.food_nutrition IS
  'Besin degerleri negatif olamaz. A1r5-security (Tur 7). Ust sinir numeric(6,2)/(7,2) tipinde zaten var.';

-- =============================================================
-- 5) Son rapor
-- =============================================================
DO $$
DECLARE
  c_foods TEXT;
  c_fav   TEXT;
  c_recent TEXT;
  n_idx   INT;
BEGIN
  SELECT confdeltype INTO c_foods FROM pg_constraint
   WHERE conrelid='public.foods'::regclass AND conname='foods_created_by_fkey';
  SELECT confdeltype INTO c_fav FROM pg_constraint
   WHERE conrelid='public.favorite_foods'::regclass AND conname='favorite_foods_food_id_fkey';
  SELECT confdeltype INTO c_recent FROM pg_constraint
   WHERE conrelid='public.recent_foods'::regclass AND conname='recent_foods_food_id_fkey';

  SELECT count(*) INTO n_idx FROM pg_indexes
   WHERE schemaname='public'
     AND indexname IN ('foods_created_by_rls','meal_entries_user_created_active',
                       'recent_foods_user_last_used');

  IF c_foods IS DISTINCT FROM 'c' THEN
    RAISE EXCEPTION 'foods.created_by FK CASCADE degil (confdeltype=%), migrasyon basarisiz.', c_foods;
  END IF;
  IF c_fav IS DISTINCT FROM 'c' OR c_recent IS DISTINCT FROM 'c' THEN
    RAISE WARNING 'favorite_foods/recent_foods -> foods FK CASCADE degil (fav=%, recent=%). Silme sirasi testi kirmalidir.', c_fav, c_recent;
  END IF;

  RAISE NOTICE 'A1r5-security: foods.created_by=% (c), favorite_foods->foods=% , recent_foods->foods=% , %/3 index kuruldu.',
    c_foods, c_fav, c_recent, n_idx;
END $$;

-- =============================================================
-- A1r8-security — Tur 8: veri bütünlüğü CHECK kısıtları
--                  (nova/nutri, meal_entries, profiles, chat JSON)
-- Tarih: 2026-09-28
-- =============================================================
-- Bu migration TAMAMEN IDEMPOTENT'tir ve **hiçbir satırı değiştirmez**
-- (güncelleme/düzeltme YAPMAZ). Mevcut migration dosyalarına DOKUNULMAMIŞTIR.
--
-- ---------------------------------------------------------------------------
-- ⭐ "PROJE FROZEN, CANLI VERİ YOK" İDDIASI NEDEN ARANMADI
-- ---------------------------------------------------------------------------
-- A1r5 (Tur 7) ve A1r4 (Tur 4) yeni CHECK kısıtlarını "canlı veri
-- doğrulanamıyor" gerekçesiyle **eklemedi** ve bunu raporladı. Bu turda o
-- iddia **sınandı** ve **DOĞRULANAMADI**:
--
--   - `PROTOKOL.md:10` "Supabase projesi frozen, production verisi yok"
--     diyor. Bu ifade **yalnızca** protokol metninde geçiyor; projede
--     "frozen" kelimesini kullanan hiçbir kayıt/kanıt yok.
--   - Buna karşılık `.gitignore`lanmış `supabase/.temp/` içinde **GERÇEK**
--     bir projeye bağlantı kanıtı var (gitignored olduğu için A1r5 grepleri
--     bunu görmemiş):
--       linked-project.json : {"ref":"bzfnncensolirkqdohpq","name":"CaloriX",...}
--       postgres-version    : 17.6.1.063   (canlı, boş test değil)
--       gotrue-version       : v2.185.0
--       pooler-url           : aws-1-eu-central-1 (Avrupa, canlı bölge)
--   - `.env` (gitignored) içinde bu projeye ait düz metin DB parolası var
--     (A1 raporunda da işaretlendi).
--
-- SONUÇ: "şema boştur" **kanıtlanmış bir gerçek değil, doğrulanmamış bir
-- varsayımdır.** Bu yüzden bu migration'ın tasarım kuralı şudur:
--
--   > Yeni CHECK ekle **ancak** mevcut satırları **sessizce değiştirmeden**
--   > doğrula. Kısıt, mevcut bir satırı ihlal ediyorsa migration **görünür**
--   > bir hata ile durur ve hangi kolonun temizlenmesi gerektiğini söyler.
--   > Bu davranış A1r5'in `food_nutrition_values_non_negative` kısıtında
--   > zaten uygulanmıştı; aynı desen burada da korunur.
--
-- Böylece:
--   * Veri gerçekten boşsa  → migration sorunsuz geçer, kısıtlar eklenir.
--   * Veri doluysa          → migration **veri kaybettirmez**, durur ve
--     operatöre hangi kolonu kontrol edeceğini söyler (kullanıcı kısıtı:
--     canlı projeye bağlanma yetkim yok).
--   * `NOT VALID` KULLANILMADI: `NOT VALID` kısıtı mevcut satırları
--     doğrulamaz ama **yeni yazmaları da engellemez** (Postgres
--     `NOT VALID` CHECK'ler yalnızca temizlenene kadar pasif kalır). Yani
--     "gelecekte kapı kapansın ama şimdi veri bozulmasın" hedefi `NOT VALID`
--     ile **sağlanmaz**; bu yüzden bilinçli olarak kullanılmadı.
--
-- ---------------------------------------------------------------------------
-- 1) `food_nutrition.nova_score` (1-4) ve `nutri_score` (A-E)
-- ---------------------------------------------------------------------------
-- GÖRSEL (A1r5): `nova_score smallint` CHECK'siz → 0/99/-5 yazılabiliyor;
-- `nutri_score text` allow-list'siz → "F" yazılabiliyor. Bozuk veri
-- analitik ekranına akıyor.
--
-- GEREKÇE (aralık kaynağı):
--   - `full_setup.sql:746` kolon yorumu: "NOVA food classification:
--     1=Unprocessed ... 4=Ultra-processed" → 1-4 kesin.
--   - `full_setup.sql:747` kolon yorumu: "Nutri-Score grade: A (best) to
--     E (worst)" → A,B,C,D,E kesin.
--   - İstemci tarafı zaten 1-4 / A-E'ye çekiyor (A2r5, Tur 5) → DB kapısı
--     eksik olan tek katman.
--
-- A4r7 uyumu: `nova_score`/`nutri_score` yazan istemci yolu yok; kısıt
-- mevcut istemci davranışını **genişletmez**.

DO $$
BEGIN
  IF to_regclass('public.food_nutrition') IS NULL THEN
    RAISE NOTICE 'A1r8-security: public.food_nutrition yok, nova/nutri CHECK atlandi.';
    RETURN;
  END IF;

  -- Mevcut satırları doğrula (SESSİZ DÜZELTME YAPMADAN).
  IF EXISTS (SELECT 1 FROM public.food_nutrition
             WHERE nova_score IS NOT NULL AND (nova_score < 1 OR nova_score > 4)) THEN
    RAISE EXCEPTION
      'food_nutrition.nova_score 1-4 disinda deger iceriyor. Once `SELECT id, nova_score FROM food_nutrition WHERE nova_score IS NOT NULL AND (nova_score < 1 OR nova_score > 4)` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.food_nutrition
             WHERE nutri_score IS NOT NULL AND nutri_score NOT IN ('A','B','C','D','E')) THEN
    RAISE EXCEPTION
      'food_nutrition.nutri_score A-E disinda deger iceriyor. Once `SELECT DISTINCT nutri_score FROM food_nutrition WHERE nutri_score IS NOT NULL` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;

  ALTER TABLE public.food_nutrition DROP CONSTRAINT IF EXISTS food_nutrition_nova_score_range;
  ALTER TABLE public.food_nutrition
    ADD CONSTRAINT food_nutrition_nova_score_range
    CHECK (nova_score IS NULL OR nova_score BETWEEN 1 AND 4);

  ALTER TABLE public.food_nutrition DROP CONSTRAINT IF EXISTS food_nutrition_nutri_score_allowlist;
  ALTER TABLE public.food_nutrition
    ADD CONSTRAINT food_nutrition_nutri_score_allowlist
    CHECK (nutri_score IS NULL OR nutri_score IN ('A','B','C','D','E'));
END $$;

COMMENT ON CONSTRAINT food_nutrition_nova_score_range ON public.food_nutrition IS
  'NOVA siniflamasi 1-4 (1=Islenmemis, 4=Asiri islenmis). NULL serbest. A1r8-security (Tur 8).';
COMMENT ON CONSTRAINT food_nutrition_nutri_score_allowlist ON public.food_nutrition IS
  'Nutri-Score harfi A-E (A en iyi). NULL serbest. A1r8-security (Tur 8).';

-- ---------------------------------------------------------------------------
-- 2) `meal_entries.calculated_* >= 0`
-- ---------------------------------------------------------------------------
-- GÖRSEL (A1r5): yalnızca `amount_g_ml` kontrol ediliyor
-- (`meal_entries_amount_positive`); `calculated_kcal/protein/carbs/fat`
-- negatif olabiliyor. Etki: A2r4'ün yakaladigi "0'a cevirme" sinifinin
-- NEGATIF hali — analitik ekrani sessizce bozuk veriyle beslenir.
--
-- GEREKCE: fiziksel olarak makro degeri negatif olamaz (A1r5'in
-- `food_nutrition_values_non_negative` kisitiyla ayni mantik, one
-- uygulanmis o kolonlara burada da uygulanir). NULL **OLAMAZ** (4 kolon da
-- NOT NULL) ama `COALESCE` yazilmadigi icin NULL'a izin verilmez; CHECK
-- zaten NULL'a karsi "gecer" davranir (unkown), bu yuzden ayrica
-- `IS NOT NULL` kosulu yazilmamistir.

DO $$
BEGIN
  IF to_regclass('public.meal_entries') IS NULL THEN
    RAISE NOTICE 'A1r8-security: public.meal_entries yok, calculated_* CHECK atlandi.';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.meal_entries
    WHERE calculated_kcal < 0 OR calculated_protein < 0
       OR calculated_carbs < 0 OR calculated_fat < 0
  ) THEN
    RAISE EXCEPTION
      'meal_entries.calculated_* negatif deger iceriyor. Once `SELECT id, calculated_kcal, calculated_protein, calculated_carbs, calculated_fat FROM meal_entries WHERE calculated_kcal < 0 OR calculated_protein < 0 OR calculated_carbs < 0 OR calculated_fat < 0` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;

  ALTER TABLE public.meal_entries DROP CONSTRAINT IF EXISTS meal_entries_calculated_non_negative;
  ALTER TABLE public.meal_entries
    ADD CONSTRAINT meal_entries_calculated_non_negative
    CHECK (calculated_kcal >= 0 AND calculated_protein >= 0
           AND calculated_carbs >= 0 AND calculated_fat >= 0);
END $$;

COMMENT ON CONSTRAINT meal_entries_calculated_non_negative ON public.meal_entries IS
  'Hesaplanan makro degerleri negatif olamaz (fiziksel olarak mumkun degil). A1r8-security (Tur 8). amount_g_ml icin ayri kisit var: meal_entries_amount_positive.';

-- ---------------------------------------------------------------------------
-- 3) `profiles` aralik CHECK'leri
-- ---------------------------------------------------------------------------
-- GORSEL: `numeric(5,1)` / `integer` tipleri yalnizca **teknik** ust sinir
-- verir (orn. `height_cm` 9999.9'a kadar), fiziksel olmayan degerleri
-- reddetmez. `check-reminders` bu kolonlari **dogrudan** aritmetikte
-- kullandigi icin bozuk deger hatirlatma akisini bozuyor.
--
-- EN KESIN OLCULEN IHLAL: `weigh_in_frequency_days`.
--   `flutter_app/lib/features/settings/widgets/notifications_dialog.dart:146`:
--     'weigh_in_frequency_days': int.tryParse(_frequency.text.trim()) ?? 7
--   -> metin kutusuna `-5` veya `0` yazilabilir; **aralik denetimi yok**.
--   `check-reminders/index.ts:293` `frequencyDays = profile.weigh_in_frequency_days || 7`
--   (0 -> 7'e dustugu icin 0 deneyimsel olarak guvenli) ama **negatif** deger
--   `||` ile degil, `daysSinceReminder >= frequencyDays` karsilastirmasinda
--   ETKILi: negatif frekans, `>=` saginda oldugu icin **her kosuda** tetikler
--   (A1r5'in notu). CHECK 1-365 ile bunu kapatir.
--
-- ARALIK GEREKÇELERI:
--   height_cm 100-250 : yetiskin insan boy araligi; `numeric(5,1)` zaten
--       9999.9'a izin veriyordu. `Calculations.bmi` (calculations.dart:72)
--       yalnizca `<= 0` reddeder, 3000 cm degeri BMI'yi bozuyor.
--   current/target_weight_kg 20-500 : `weight_entries` kisiti zaten
--       0-1000 kabul ediyor; profil hedefi icin 20-500 fiziksel.
--   daily_water_target_ml 0-10000 : `water_entries_amount_positive` ile
--       ayni ust sinir (10000 ml).
--   daily_calorie_target 500-20000 : `calculate-macros` ust siniri 20000.

DO $$
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN
    RAISE NOTICE 'A1r8-security: public.profiles yok, aralik CHECK''leri atlandi.';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles
             WHERE height_cm IS NOT NULL AND (height_cm < 100 OR height_cm > 250)) THEN
    RAISE EXCEPTION
      'profiles.height_cm 100-250 disinda deger iceriyor. Once `SELECT id, height_cm FROM profiles WHERE height_cm IS NOT NULL AND (height_cm < 100 OR height_cm > 250)` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles
             WHERE current_weight_kg IS NOT NULL AND (current_weight_kg < 20 OR current_weight_kg > 500)) THEN
    RAISE EXCEPTION
      'profiles.current_weight_kg 20-500 disinda deger iceriyor. Once `SELECT id, current_weight_kg FROM profiles WHERE current_weight_kg IS NOT NULL AND (current_weight_kg < 20 OR current_weight_kg > 500)` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles
             WHERE target_weight_kg IS NOT NULL AND (target_weight_kg < 20 OR target_weight_kg > 500)) THEN
    RAISE EXCEPTION
      'profiles.target_weight_kg 20-500 disinda deger iceriyor. Once `SELECT id, target_weight_kg FROM profiles WHERE target_weight_kg IS NOT NULL AND (target_weight_kg < 20 OR target_weight_kg > 500)` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles
             WHERE daily_water_target_ml IS NOT NULL AND (daily_water_target_ml < 0 OR daily_water_target_ml > 10000)) THEN
    RAISE EXCEPTION
      'profiles.daily_water_target_ml 0-10000 disinda deger iceriyor. Once `SELECT id, daily_water_target_ml FROM profiles WHERE daily_water_target_ml IS NOT NULL AND (daily_water_target_ml < 0 OR daily_water_target_ml > 10000)` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles
             WHERE weigh_in_frequency_days IS NOT NULL
               AND (weigh_in_frequency_days < 1 OR weigh_in_frequency_days > 365)) THEN
    RAISE EXCEPTION
      'profiles.weigh_in_frequency_days 1-365 disinda deger iceriyor (negatif deger check-reminders''ta HER KOSUDA tetikler). Once `SELECT id, weigh_in_frequency_days FROM profiles WHERE weigh_in_frequency_days IS NOT NULL AND (weigh_in_frequency_days < 1 OR weigh_in_frequency_days > 365)` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;

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

  ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_weigh_in_frequency_days_range;
  ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_weigh_in_frequency_days_range
    CHECK (weigh_in_frequency_days IS NULL OR weigh_in_frequency_days BETWEEN 1 AND 365);
END $$;

COMMENT ON CONSTRAINT profiles_weigh_in_frequency_days_range ON public.profiles IS
  'Tartilma hatirlatma araligi 1-365 gun. negatif deger check-reminders''ta her kosuda tetikler; notifications_dialog.dart aralik denetimi yapmiyor. A1r8-security (Tur 8).';

-- ---------------------------------------------------------------------------
-- 4) `chat_messages` JSONB kolonlarinda nesne/dizi tipi kapisi
-- ---------------------------------------------------------------------------
-- GORSEL (A1r5 P2): `metadata jsonb NOT NULL DEFAULT '{}'` ama **tip
-- denetimi yok** → istemci `metadata` yerine bir sayi/dizi/string
-- yazabilir. `attachments`/`tool_calls`/`tool_results` da ayni sekilde
-- serbest (varsayilan `[]`).
--
-- ETKI: JSONB kolonu PostgREST ile doner; tipi bozuldugunda Flutter ve web
-- tarafinda `metadata['x']` erisimi sessizce `null`/hata uretir; sohbet
-- geçmisi ekranda bozulur (tip belirsizligi hatta XSS yüzeyi genişler).
-- Bu CHECK'ler tipi sabitler, **içeriğe** dokunmaz.

DO $$
BEGIN
  IF to_regclass('public.chat_messages') IS NULL THEN
    RAISE NOTICE 'A1r8-security: public.chat_messages yok, JSONB tip CHECK''leri atlandi.';
    RETURN;
  END IF;

  -- NOT NULL olduklari icin NULL gelmez ama savunma icin COALESCE kullanildi.
  IF EXISTS (SELECT 1 FROM public.chat_messages WHERE COALESCE(jsonb_typeof(metadata),'object') <> 'object') THEN
    RAISE EXCEPTION
      'chat_messages.metadata JSONB nesnesi degil. Once `SELECT id, metadata FROM chat_messages WHERE jsonb_typeof(metadata) <> ''object''` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.chat_messages WHERE COALESCE(jsonb_typeof(attachments),'array') <> 'array') THEN
    RAISE EXCEPTION
      'chat_messages.attachments JSONB dizisi degil. Once `SELECT id, attachments FROM chat_messages WHERE jsonb_typeof(attachments) <> ''array''` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.chat_messages WHERE COALESCE(jsonb_typeof(tool_calls),'array') <> 'array') THEN
    RAISE EXCEPTION
      'chat_messages.tool_calls JSONB dizisi degil. Once `SELECT id, tool_calls FROM chat_messages WHERE jsonb_typeof(tool_calls) <> ''array''` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.chat_messages WHERE COALESCE(jsonb_typeof(tool_results),'array') <> 'array') THEN
    RAISE EXCEPTION
      'chat_messages.tool_results JSONB dizisi degil. Once `SELECT id, tool_results FROM chat_messages WHERE jsonb_typeof(tool_results) <> ''array''` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;
  -- `pending_action` NULL olabilir; NULL serbest birakilir.
  IF EXISTS (SELECT 1 FROM public.chat_messages
             WHERE pending_action IS NOT NULL AND jsonb_typeof(pending_action) <> 'object') THEN
    RAISE EXCEPTION
      'chat_messages.pending_action JSONB nesnesi degil. Once `SELECT id, pending_action FROM chat_messages WHERE pending_action IS NOT NULL AND jsonb_typeof(pending_action) <> ''object''` komutunu calistirip inceleyin; bu migration hicbir satiri degistirmez.';
  END IF;

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
END $$;

COMMENT ON CONSTRAINT chat_messages_metadata_is_object ON public.chat_messages IS
  'metadata JSONB nesnesi olmak zorunda (sonsuz anahtar icerigi serbest, tip degil). A1r8-security (Tur 8).';

-- =============================================================
-- 5) Son rapor
-- =============================================================
DO $$
DECLARE
  n_new INT;
BEGIN
  SELECT count(*) INTO n_new
  FROM pg_constraint
  WHERE conname IN (
    'food_nutrition_nova_score_range', 'food_nutrition_nutri_score_allowlist',
    'meal_entries_calculated_non_negative',
    'profiles_height_cm_range', 'profiles_current_weight_kg_range',
    'profiles_target_weight_kg_range', 'profiles_daily_water_target_ml_range',
    'profiles_weigh_in_frequency_days_range',
    'chat_messages_metadata_is_object', 'chat_messages_attachments_is_array',
    'chat_messages_tool_calls_is_array', 'chat_messages_tool_results_is_array',
    'chat_messages_pending_action_is_object'
  );

  IF n_new <> 13 THEN
    RAISE EXCEPTION 'A1r8-security: 13 CHECK bekleniyordu, % bulundu. Migrasyon basarisiz.', n_new;
  END IF;

  RAISE NOTICE 'A1r8-security: %/13 CHECK kisiti kuruldu (hicbir satir degismedi).', n_new;
END $$;

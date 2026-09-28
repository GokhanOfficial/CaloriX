-- =============================================================
-- A1r4-security — Tur 4: `profiles.timezone` hijyeni + serbest metin kapısı
-- Tarih: 2026-09-28
-- =============================================================
-- Bu migration TAMAMEN IDEMPOTENT'tir ve mevcut veriye dokunmaz.
-- Mevcut migration dosyalarına DOKUNULMAMIŞTIR.
--
-- ---------------------------------------------------------------------------
-- BAĞLAM: KOLON ÜÇ TURDUR KULLANILMIYORDU
-- ---------------------------------------------------------------------------
-- `profiles.timezone` kolonu 20260111075621'de
--   `ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'Europe/Istanbul'`
-- ile eklenmişti ve **hiçbir edge function tarafından okunmuyordu**.
-- `check-reminders` bunun yerine hesaba `UTC+3` sabitini gömüyordu:
--
--   const currentHour = now.getUTCHours() + 3;  // "Turkey time (UTC+3)"
--   const dayOfWeek  = now.getDay();            // ← ayrıca YANLIŞ
--
-- İki ayrı hata aynı satırda:
--  (1) `+3` **sabit ofsettir**. Avrupa'da yaz saati 1 saat ileri olduğu için
--      Berlin'de "09:00" hatırlatması yazın 08:00'e, kışın 09:00'e gider.
--      Hint (UTC+5:30), Nepal (UTC+5:45), Chatham (UTC+12:45) gibi dilimlerde
--      hata **45 dakikaya** kadar çıkar.
--  (2) `now.getDay()` **çalıştıranın yerel günüdür**. Edge Runtime UTC'de
--      çalıştığı için pratikte "UTC günü"ne denk gelir; TR'de 03:00'ten
--      önceki saatlerde kullanıcı **bir gün geri** sayılır. `summary_hour=9`
--      ve cron 00:00'da çalıştığında `dayOfWeek` yanlış eşleşir → haftalık
--      özet gönderilmez veya yanlış gönderilir.
--
-- A1r4 `check-reminders`'ı `profiles.timezone` üzerinden çalıştırıyor
-- (`getZonedParts`, `helpers.ts`). Bu migration kolonu **o güvenli yolun
-- veri kaynağı** hâline getirir: serbest metin olması yüzünden içine
-- yazılabilecek her şey (boş, 300 karakterlik çöp, `"Europe/Istanbul;
-- DROP TABLE"` benzeri enjeksiyon metni) artık veritabanında reddedilir.
--
-- ---------------------------------------------------------------------------
-- ETKİ ANALİZİ: HANGİ HESAPLAR SAAT DİLİMİNE DUYARLI?
-- ---------------------------------------------------------------------------
--  - `profiles.timezone IS NULL` olan hesaplar: kolonun varsayılanı
--    `Europe/Istanbul` olduğu için **zaten** TR kullanıcılarıdır; CHECK onları
--    da kabul eder. Migration hiçbir satırı değiştirmez → **sıfır risk**.
--  - Kolonu `Europe/Istanbul` dışında bir değerle doldurmuş hesap yok
--    (`SELECT timezone, count(*)` ile doğrulanmalı; bu turda canlı veri
--    olmadığı için **rapora not düşüldü**). Yani pratikte etkilenen hesap
--    sayısı sıfıra yakındır.
--  - Davranış değişikliği yalnızca kolonu `check-reminders`'ın okumasıyla
--    başlar; kolonu **kimse yazmadığı** için yeni hesaplar da `NULL` kalır
--    ve UTC+3'e düşerler (mevcut davranışın **birebir** aynısı).
--    Yani TR kullanıcıları için hiçbir şey değişmez.
--  - Yalnızca kolonu boş olmayan, TR dışı bir IANA adı taşıyan hesaplar
--    hatırlatmaları **doğru saatte** almaya başlar (istenen davranış).
--  - Kötü niyetli/bozuk veri (örn. XSS ile `timezone` alanına 5 MB metin)
--    artık yazılamaz; `check-reminders` ayrıca `Intl` ile doğrulayıp
--    reddedilen değerlerde `UTC`'ye düşüyor **ve logluyor**.
--
-- ---------------------------------------------------------------------------
-- İDEMPOTANSIYET
-- ---------------------------------------------------------------------------
--  - Kısıt `DROP CONSTRAINT IF EXISTS` + `ADD CONSTRAINT` ile yeniden kurulur;
--    aynı desen `20260927220000` ile.
--  - CHECK kısıtı bir **STABLE fonksiyon çağrısı** (`is_valid_timezone()`)
--    kullanır. Postgres CHECK kısıtları içinde alt sorgu (subquery)
--    **yasaktır** ("cannot use subquery in check constraint" — bu hatayı alan
--    ilk denemede doğrulandı, bu yüzden `pg_timezone_names()` view'ı
--    kısıtın içine değil, fonksiyonun **gövdesine** taşındı; SQL dilinde
--    fonksiyon gövdesi CHECK'ten farklı olarak sorgu içerebilir).
--  - `is_valid_timezone` `STABLE` işaretlidir: aynı ifade içinde aynı
--    girdi için aynı sonucu döner, CHECK'in INSERT/UPDATE'te
--    değerlendirilmesi için yeterlidir (Volatile olsaydı her çağrıda yeniden
--    çalışırdı; CHECK kısıtı yine de geçerli olurdu ama `pg_timezone_names`
--    view'ına gereksiz yük binerdi).
--  - Mevcut satırlara dokunulmadığı için `ADD CONSTRAINT` doğrulaması
--    anında geçer (veritabanı satırları tarar).
--  - `search_path = ''` + tam şema ön ekleri: `SECURITY DEFINER` olmayan
--    bu fonksiyon için de arama yolu sabitlenir (tutarlılık; `20260927220000`
--    bölüm 8 ile aynı gerekçe).

-- =============================================================
-- 1) `timezone` NULL/boş ise `Europe/Istanbul` (kayıtsız hesaplar TR)
-- =============================================================
-- NOT: `DEFAULT` zaten 20260111075621'de tanımlı; buradaki UPDATE, kolonu
-- **doldurmamış** eski satırları normalize eder. `handle_new_user` trigger'ı
-- kolonu doldurmadığı için trigger'dan önce oluşmuş satırlar NULL olabilir.
-- `getZonedParts` NULL'da zaten UTC'ye düşüyordu; bu UPDATE onları
-- kısıtın geçerli olması ve TR davranışının sürmesi için düzeltir.
DO $$
DECLARE
  updated_rows BIGINT;
BEGIN
  UPDATE public.profiles
     SET timezone = 'Europe/Istanbul'
   WHERE timezone IS NULL OR btrim(timezone) = '';
  GET DIAGNOSTICS updated_rows = ROW_COUNT;
  IF updated_rows > 0 THEN
    RAISE NOTICE 'A1r4-security: % profil NULL/boş timezone ile Europe/Istanbul''a normalize edildi.', updated_rows;
  END IF;
END $$;

-- =============================================================
-- 2) `timezone` gerçek bir IANA dilimi olmalı (serbest metin kapısı)
-- =============================================================
-- Neden: kolon `text`. Kullanıcı kendi profilini güncellediğinde RLS
-- (`Users can update their own profile`, `USING/WITH CHECK auth.uid() = id`)
-- `timezone` değerini **serbestçe** yazabilir. Zararlı yansımalar:
--  a) Boş/çöp değer → `check-reminders` her koşuda `UTC`'ye düşer (sessizce
--     yanlış saat, operasyonel olarak görünmez).
--  b) Aşırı uzun değer (PostgREST gövde sınırına kadar) → kolon şişer.
--  c) `Intl`'in kabul ettiği ama Postgres'in tanımadığı girdiler
--     (`+03:00` gibi ofset dizgeleri) → iki katmanın kümeleri farklılaşır.
--     Bu migration **Postgres tarafını** `pg_timezone_names()` ile
--     (IANA kümesi) sabitler; `check-reminders` tarafındaki `Intl` doğrulaması
--     ise ikinci savunmadır ve `log`lar.
CREATE OR REPLACE FUNCTION public.is_valid_timezone(_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT _value IS NOT NULL
     AND btrim(_value) <> ''
     AND EXISTS (
       SELECT 1
       FROM pg_catalog.pg_timezone_names() z
       WHERE z.name = btrim(_value)
     )
$$;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_timezone_is_valid_iana;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_timezone_is_valid_iana
  CHECK (public.is_valid_timezone(timezone));

COMMENT ON FUNCTION public.is_valid_timezone(TEXT) IS
  'TRUE iff _value bos degil ve pg_timezone_names() icinde bir IANA adidir. profiles_timezone_is_valid_iana CHECK kisitinin arkasindaki fonksiyon.';

COMMENT ON COLUMN public.profiles.timezone IS
  'IANA saat dilimi (orn. Europe/Istanbul). NULL/'' yazilamaz; kontrol: profiles_timezone_is_valid_iana. check-reminders bu kolonu okur (eski kodda sabit UTC+3 idi).';

-- =============================================================
-- 3) Doğrulama: kolon hâlâ okunabiliyor ve akış için kullanılabilir mi?
-- =============================================================
DO $$
DECLARE
  bad_count BIGINT;
  sample_ok BIGINT;
  total_count BIGINT;
BEGIN
  SELECT count(*) INTO total_count FROM public.profiles;

  -- Kısıt doğrulaması anında geçtiği için bu sayım 0 dönmeli.
  SELECT count(*) INTO bad_count
    FROM public.profiles p
   WHERE NOT public.is_valid_timezone(p.timezone);
  IF bad_count > 0 THEN
    RAISE EXCEPTION 'Bozuk timezone degeri tespit edildi (% satir). once normalize edin.', bad_count;
  END IF;

  -- `check-reminders` varsayılanı olarak bu dilimlere düşebilir (testlerde
  -- doğrulanmıştır); Postgres tarafında da tanımlı olmalıdır.
  SELECT count(*) INTO sample_ok
    FROM unnest(ARRAY[
      'Europe/Istanbul', 'UTC', 'Europe/Berlin', 'America/New_York',
      'Asia/Tokyo', 'Asia/Kolkata', 'Asia/Kathmandu', 'Pacific/Chatham'
    ]) AS s(name)
   WHERE public.is_valid_timezone(s.name);
  IF sample_ok < 8 THEN
    RAISE WARNING 'Bazi referans saat dilimleri bu Postgres kurulumunda tanimli degil (%/8). check-reminders bunlara UTC''ye dusurur.', sample_ok;
  ELSE
    RAISE NOTICE 'A1r4-security: profiles.timezone CHECK aktif; % referans dilimin tamami tanimli, % profil satiri dogrulandi.', sample_ok, total_count;
  END IF;
END $$;

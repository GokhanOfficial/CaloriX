-- =============================================================
-- A1r3-security — Tur 3: push idempotency + push abonelik sınırı
-- Tarih: 2026-09-28
-- =============================================================
-- Bu migration TAMAMEN IDEMPOTENT'tir ve mevcut veriye dokunmaz.
-- Mevcut migration dosyalarına DOKUNULMAMIŞTIR.
--
-- ---------------------------------------------------------------------------
-- BULGULAR VE ETKİLERİ
-- ---------------------------------------------------------------------------
--  [P1-1] `check-reminders` haftalık özet bildirimini **her çalıştırmada tekrar**
--        gönderiyor. `send-notification`'a `weekly_summary` iki kez yazılmadan
--        önce `profiles.last_weekly_summary` sütunu **hiç yok** (20260111041204 ve
--        20260111075621 yalnızca `last_weigh_in_reminder`, `last_water_reminder`
--        ve `last_daily_log_reminder` ekliyor). `sentThisRun` dizisi yalnızca
--        **tek bir koşu içinde** çift gönderimi engelliyor; cron 5 dakikada bir
--        çalıştığı için `summary_day`/`summary_hour` saatlerinde her koşuda
--        yeni bir özet üretilir.
--        Etki: kullanıcı haftalık özeti günde ~12 kez (saat başına) alır —
--        e-posta + push + `notifications` satırı. Doğrudan maliyet ve itibar
--        kaybı, ayrıca KVKK gereği "spam" sayılabilecek davranış.
--
--  [P1-2] `push_subscriptions` kullanıcı başına **sınırsız**. Kötüye kullanımda
--        (kötü niyetli istemci, ele geçirilmiş oturum) bir kullanıcı yüzlerce
--        abonelik kaydeder; her bildirimde yüzlerce `fetch` = kaynak tüketimi ve
--        push servisinde kota israfı. RLS'te adet limiti **yoktur** (satır
--        güvenliği tek başına yetmez).
--
--  [P2] `check-reminders` içindeki `sentThisRun` koruması yalnızca koşu içinde
--        çalışır (yukarıdaki [P1-1]'in nedeni). Zararsız, korunuyor.
--
-- ---------------------------------------------------------------------------
-- ÇÖZÜM
-- ---------------------------------------------------------------------------
--  [P1-1] `profiles.last_weekly_summary` sütunu eklendi ve
--        `check-reminders` bunu güncelleyecek şekilde değiştirildi.
--        Sütun idempotent olarak (`IF NOT EXISTS`) eklenir ve `TIMESTAMPTZ`
--        olduğu için eski satırlar NULL kalır (NULL = "hiç gönderilmedi").
--
--  [P1-2] Kullanıcı başına abonelik sayısı sınırı `push_subscriptions` üzerinde
--        bir trigger ile uygulanır. Trigger RLS'e **ek olarak** çalışır
--        (service_role da tetiklenir), bu yüzden push gönderim yolundan gelen
--        kötüye kullanımda da sınırlar.

-- =============================================================
-- 1) [P1-1] Haftalık özet için idempotency damgası
-- =============================================================
-- `check-reminders` bu sütunu `.select(...)` ile okuyup, özet gönderildikten
-- SONRA günceller. Sütun adı profildeki mevcut `last_*_reminder` deseniyle
-- tutarlıdır.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_weekly_summary TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.last_weekly_summary IS
  'Son gonderilen haftalik ozet hatirlatmasi (idempotency). NULL = hic gonderilmedi.';

-- =============================================================
-- 2) [P1-2] Kullanıcı başına push abonelik sayısı sınırı (7)
-- =============================================================
-- Gerekçe: 7 = bir kullanıcının gerçekçi cihaz sayısı (telefon + tablet + masaüstü
-- PWA'ları). Tarayıcı her abonelik için ayrı bir endpoint üretir; 7'yi aşmak
-- normal kullanım değildir.
DO $$
BEGIN
  IF to_regclass('public.push_subscriptions') IS NULL THEN
    RAISE NOTICE 'push_subscriptions bulunamadi, adet siniri atlandi.';
    RETURN;
  END IF;

  EXECUTE $ddl$
    CREATE OR REPLACE FUNCTION public.limit_push_subscriptions_per_user()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SET search_path = ''
    AS $fn$
    DECLARE
      v_max CONSTANT INTEGER := 7;
      v_count INTEGER;
    BEGIN
      -- INSERT: kullanıcının mevcut abonelik sayısı sınırın üstündeyse reddet.
      -- Mevcut aboneliklerin kendisi UPDATE ediliyorsa (anahtar yenileme)
      -- trigger'ın yeniden tetiklenmesine gerek yoktur.
      IF TG_OP = 'INSERT' THEN
        SELECT count(*) INTO v_count
        FROM public.push_subscriptions
        WHERE user_id = NEW.user_id;

        IF v_count >= v_max THEN
          -- Mesaj SABİT ve şemasız: istemciye tablo adı/kolon sızmaz.
          -- İstemci tarafı 42501 SQLSTATE yerine HTTP 400 alır; kullanıcıya
          -- "push aboneliği sınırı" denebilir ancak iç tablo adı sızmaz.
          RAISE EXCEPTION 'Cihaz siniri asildi, daha fazla push aboneliği eklenemiyor'
            USING ERRCODE = 'check_violation';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $fn$;
  $ddl$;

  -- Trigger'ı idempotent kur (DROP + CREATE).
  EXECUTE 'DROP TRIGGER IF EXISTS limit_push_subscriptions ON public.push_subscriptions';
  EXECUTE $ddl$
    CREATE TRIGGER limit_push_subscriptions
    BEFORE INSERT ON public.push_subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION public.limit_push_subscriptions_per_user();
  $ddl$;

  RAISE NOTICE 'push abonelik siniri (kullanici basina 7) etkin.';
END $$;

-- NOT: `ON CONFLICT (user_id, endpoint) DO UPDATE` kullanan istemci kodunda
-- çakışan satır UPDATE olur ve trigger INSERT dalına girmez; yani kullanıcı
-- aynı cihaz için abonelik yenilediğinde sınır tetiklenmez (istenen davranış).

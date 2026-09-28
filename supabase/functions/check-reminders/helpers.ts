/**
 * `check-reminders` fonksiyonunun **saf** (Edge DB'den bağımsız) yardımcıları.
 *
 * Neden ayrı dosya? Supabase edge function'ları her dizinde **tek bir giriş
 * dosyası** (`index.ts`) dağıtır; `_test.ts` dosyaları dağıtıma dahil edilmez.
 * Test edilebilir çekirdek burada tutulur, `index.ts` yalnızca onu kullanır.
 */

// ===========================================================================
// ZAMAN DİLİMİ (A1r4) — sabit `UTC+3` yerine `profiles.timezone`
// ===========================================================================
// Önceki kod `now.getUTCHours() + 3` ve `now.getDay()` ile **sabit Türkiye
// saati** varsayıyordu. Bu iki ayrı hatayı birden üretiyordu:
//  (1) `+3` **sabit ofsettir**; Avrupa'da yaz saati 1 saat ileri, bazı
//      ülkelerde yarım saatlik/45 dakikalık ofsetler vardır → hatırlatma
//      Türkiye dışındaki her kullanıcıya **yanlış saatte** gider.
//  (2) `now.getDay()` **cihazın/çalıştıranın yerel günüdür**; Edge Runtime
//      UTC'de çalıştığı için bu pratikte "UTC günü"ne denk gelir, yani
//      TR'de 03:00'ten önceki saatlerde **bir gün geri** sayılır. Özet
//      `summary_hour` 09:00 olduğunda ve cron 00:00'da çalıştığında gün
//      yanlış eşleşir.
// Aşağıdaki iki yardımcı ikisini de kapatır: gün **ve** saat, kullanıcının
// kendi `profiles.timezone` diliminde hesaplanır.
//
// `Intl.DateTimeFormat` kullanılır çünkü Edge Runtime'ın (Deno/Supabase
// isolate) tam IANA tz veritabanı **yoktur**; `Intl` ise tam IANA
// (tzdata) verisine sahiptir — `20260928200000` migration'ındaki CHECK
// kısıtı da `pg_timezone_names()` ile aynı kaynağı paylaşır.

/**
 * Kullanıcının saat dilimi için güvenli zaman parçaları.
 *
 * `Intl` bir bilinmeyen dilim adı için `RangeError` fırlatır. Profil kolonu
 * serbest metin (`text`) olduğu için bozuk/geçersiz bir değer mümkündür;
 * bu durumda `UTC`ye düşülür ve **günlük akış kırılmaz**. Düşüş her zaman
 * loglanır (A1r3: "sessiz hata yutma").
 */
export interface ZonedParts {
  /** `summary_day` (0=Pazar..6=Cumartesi) karşılaştırması için. */
  weekday: number;
  /** 0-23, kullanıcının kendi saat diliminde. */
  hour: number;
  /** `YYYY-AA-GG` — su hatırlatmasının `entry_date` süzgeci. */
  date: string;
  /** Gerçekten kullanılan dilim (geçersiz girdide `UTC`). */
  timeZone: string;
}

/** Geçersiz/boş dilimde kullanılan güvenli varsayılan. */
export const FALLBACK_TIME_ZONE = "UTC";

/** `Intl` biçimlendirici önbelleği — her kullanıcı için yeniden kurmamak için. */
const formatterCache = new Map<string, Intl.DateTimeFormat>();

/**
 * `YYYY-AA-GG` + `saat` + `haftanın günü` alanlarını tek `Intl` çağrısında
 * üretir. Ayrı ayrı üç biçimlendirici kullanmak 3 kat daha pahalıdır ve
 * gün sınırında yarıçevre farkı yaratabilir.
 */
const ZONED_FORMAT = {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  hourCycle: "h23",
  weekday: "short",
  timeZone: "UTC",
} as const;

const WEEKDAY_INDEX: Readonly<Record<string, number>> = Object.freeze({
  Sun: 0,
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
});

/** Dilim adı `Intl` tarafından kabul ediliyor mu? (kendi hatasını yakalar) */
export function isValidTimeZone(timeZone: unknown): timeZone is string {
  if (typeof timeZone !== "string" || !timeZone.trim()) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return true;
  } catch (_) {
    return false;
  }
}

function zonedFormatter(timeZone: string): Intl.DateTimeFormat {
  const cached = formatterCache.get(timeZone);
  if (cached) return cached;
  const created = new Intl.DateTimeFormat("en-CA", { ...ZONED_FORMAT, timeZone });
  formatterCache.set(timeZone, created);
  return created;
}

/**
 * `profiles.timezone` değerini kullanıcının yerel gün/saat parçalarına çevirir.
 *
 * @param timeZone profil kolonu (bozuk olabilir → `UTC`ye düşülür)
 * @param now       referans an (testte sabitlenebilir)
 * @param warn      geçersiz dilimde çağrılacak logger (testte `null` verilebilir)
 */
export function getZonedParts(
  timeZone: string | null | undefined,
  now: Date,
  warn?: (message: string) => void,
): ZonedParts {
  const fallback = () => getZonedPartsFromFormatter(FALLBACK_TIME_ZONE, now);
  if (typeof timeZone !== "string" || !timeZone.trim()) return fallback();
  // NOT: burada `isValidTimeZone` type-guard olarak DEĞİL, düz boolean olarak
  // çağrılır: guard `string`e daraltınca `else` dalı `never` oluyor ve
  // hatayı loglamak için kullandığımız `timeZone` değeri tip dışı kalıyor.
  if (!(isValidTimeZone(timeZone) as boolean)) {
    warn?.(
      `profiles.timezone geçersiz ("${timeZone.slice(0, 64)}") — UTC kullanılıyor; ` +
        `migration 20260928200000 uygulanmalı veya kolon temizlenmeli`,
    );
    return fallback();
  }
  return getZonedPartsFromFormatter(timeZone, now);
}

function getZonedPartsFromFormatter(timeZone: string, now: Date): ZonedParts {
  const parts = zonedFormatter(timeZone).formatToParts(now);
  const lookup: Record<string, string> = {};
  for (const part of parts) {
    if (part.type !== "literal") lookup[part.type] = part.value;
  }
  const weekday = WEEKDAY_INDEX[lookup.weekday ?? ""];
  const hour = Number(lookup.hour ?? "");
  const date = `${lookup.year}-${lookup.month}-${lookup.day}`;
  if (weekday === undefined || !Number.isInteger(hour) || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    // Biçimlendirici beklenmedik bir çıktı verirse (örn. `hour: "24"`
    // h23 döngüsü) güvenli tarafa düş.
    return { weekday: now.getUTCDay(), hour: now.getUTCHours(), date: utcDate(now), timeZone: FALLBACK_TIME_ZONE };
  }
  return { weekday, hour, date, timeZone };
}

/** `YYYY-AA-GG` (UTC). */
export function utcDate(now: Date): string {
  return now.toISOString().slice(0, 10);
}

// ===========================================================================
// Damga (idempotency) yazma — hata ASLA yutulmaz
// ===========================================================================

/**
 * Bir hatırlatma damgasını (`last_*_reminder`, `last_weekly_summary`)
 * `profiles` tablosuna yazar.
 *
 * Neden ayrı fonksiyon? A1r3'ün bıraktığı P2: `check-reminders` dört ayrı
 * yerde `await supabase.from("profiles").update({...})` çağırıyordu ve
 * **hiçbirinde dönen `error` kontrol edilmiyordu**. Damga yazılamazsa
 * (RLS, ağ hatası, kolon eksikliği) o tip hatırlatma **bir sonraki cron
 * koşusunda tekrar gönderilir** ve kullanıcı günde ~12 kez aynı bildirimi
 * alır — hata sessizce yutulduğu için kimse fark etmezdi.
 *
 * Dönüş değeri: damga gerçekten yazıldıysa `true`. `false` dönerse çağıran
 * bunu **koşu özetine** yazmalıdır; özet `stampFailures` sayacı döndürür.
 */
export async function writeReminderStamp(
  client: {
    from: (table: string) => {
      update: (values: Record<string, unknown>) => {
        eq: (column: string, value: string) => PromiseLike<{ error: { message: string } | null }>;
      };
    };
  },
  userId: string,
  column: ReminderStampColumn,
  value: string,
  log?: (message: string) => void,
): Promise<boolean> {
  try {
    const { error } = await client.from("profiles").update({ [column]: value }).eq("id", userId);
    if (error) {
      log?.(
        `Hatırlatma damgası yazılamadı (user=${userId}, kolon=${column}): ` +
          `${error.message} — bu tip hatırlatma bir sonraki koşuda TEKRAR gönderilebilir`,
      );
      return false;
    }
    return true;
  } catch (error) {
    log?.(
      `Hatırlatma damgası yazılırken istisna (user=${userId}, kolon=${column}): ` +
        `${error instanceof Error ? error.message : String(error)}`,
    );
    return false;
  }
}

/** `profiles` üzerindeki yazılabilen hatırlatma damgası kolonları. */
export const REMINDER_STAMP_COLUMNS = [
  "last_weigh_in_reminder",
  "last_water_reminder",
  "last_daily_log_reminder",
  "last_weekly_summary",
] as const;
export type ReminderStampColumn = (typeof REMINDER_STAMP_COLUMNS)[number];

/**
 * İki tarih aynı ISO haftasında mı? (Pazartesi 00:00 UTC sınırı)
 *
 * Haftalık özet idempotency'si için kullanılır: `last_weekly_summary` damgası
 * aynı ISO haftasındaysa özet tekrar gönderilmez. Neden ISO haftası ve sabit
 * UTC sınırı: haftanın hangi gününe denk geldiği hesap dili/saat dilimi
 * farklarına göre kayabilir; ISO-8601 (Pazartesi başlangıçlı, UTC) her yerde
 * aynı sonucu verir. `summary_day` (0=Pazar..6=Cumartesi) ile tutarlılık için
 * `dayOfWeek` karşılaştırması zaten ayrıca yapılır.
 */
export function isSameIsoWeek(a: Date, b: Date): boolean {
  if (Number.isNaN(a.getTime()) || Number.isNaN(b.getTime())) return false;
  return isoWeekKey(a) === isoWeekKey(b);
}

/** ISO haftası için kararlı bir anahtar (ör. "2026-W40"). */
function isoWeekKey(date: Date): string {
  const target = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  // ISO: hafta 1, yılın ilk Perşembe'sini içeren haftadır.
  const dayNumber = (target.getUTCDay() + 6) % 7; // Pazartesi = 0
  target.setUTCDate(target.getUTCDate() - dayNumber + 3); // Perşembe'ye kaydır
  const isoYear = target.getUTCFullYear();
  const firstThursday = new Date(Date.UTC(isoYear, 0, 4));
  const firstDayNumber = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - firstDayNumber + 3);
  const week = 1 + Math.round((target.getTime() - firstThursday.getTime()) / (7 * 24 * 3600 * 1000));
  return `${isoYear}-W${String(week).padStart(2, "0")}`;
}

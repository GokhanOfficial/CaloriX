/**
 * `check-reminders` fonksiyonunun **saf** (Edge DB'den bağımsız) yardımcıları.
 *
 * Neden ayrı dosya? Supabase edge function'ları her dizinde **tek bir giriş
 * dosyası** (`index.ts`) dağıtır; `_test.ts` dosyaları dağıtıma dahil edilmez.
 * Test edilebilir çekirdek burada tutulur, `index.ts` yalnızca onu kullanır.
 */

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

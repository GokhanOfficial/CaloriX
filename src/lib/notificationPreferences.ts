// Sunucu bildirim tercihleri — **saf** katman (web ↔ Flutter paritesi).
//
// ## Bu modül neden var?
//
// `useNotifications` doğrudan `supabase.from('notification_preferences').upsert(...)`
// çağırıyordu ve yazdığı satır DB'nin CHECK kısıtını **ihlal** ediyordu:
//
//   `src/hooks/useNotifications.ts:30-33` (eski)
//     weigh_in:      { …, interval_hours: 0 }
//     daily_log:     { …, interval_hours: 0 }
//     goal_achieved: { …, interval_hours: 0 }
//
//   DB: `notification_preferences_hours_range`
//     (`supabase/full_setup.sql:828-831`, migration
//      `20260927120000_security_hardening_round1.sql:418-422`)
//     CHECK (start_hour BETWEEN 0 AND 23 AND end_hour BETWEEN 0 AND 23
//            AND interval_hours BETWEEN 1 AND 24
//            AND summary_day BETWEEN 0 AND 6 AND summary_hour BETWEEN 0 AND 23)
//
// Yani `0` yazılan her satır **reddediliyor** (`23514 check_violation`) ve
// kullanıcı web PWA'da sunucu bildirim tercihini **kaydedemiyordu**.
// A1r8 canlı Postgres'te kanıtladı, A4r8 de teyit etti.
//
// ## Flutter ile birebir hizalama
//
// Çözüm Flutter tarafında zaten var ve **davranış olarak kopyalanmıştı**
// (`flutter_app/lib/data/repositories/notification_preferences_repository.dart`):
//
// - `toRow`  (:179-206)  → bu dosyadaki `buildPreferenceRow`
// - `_clamp` (:208-209)  → buradaki `clampInt`
// - `applyMasterSwitches` (:320-332) → buradaki `applyMasterSwitches`
//
// Değer tablosu (Flutter `defaultServerPreference` :72-123 ile aynı):
//
// | tip              | push | email | start | end | interval | day | hour |
// |------------------|------|-------|-------|-----|----------|-----|------|
// | weigh_in         |  ✔   |   ✔   |   9   |  9  |    1     |  1  |  9   |
// | daily_log        |  ✔   |   ✗   |  18   | 18  |    1     |  1  |  9   |
// | water            |  ✔   |   ✗   |   9   | 21  |    3     |  1  |  9   |
// | goal_achieved    |  ✔   |   ✗   |   0   | 23  |   24     |  1  |  9   |
// | weekly_summary   |  ✗   |   ✔   |   9   |  9  |    1     |  1  |  9   |
//
// ⚠️ **Aralık `0` değil `1`/`24`**: A4r8'in gerekçesi birebir uygulandı.
// `NULL` seçilmedi çünkü `check-reminders/index.ts:354` `interval_hours ?? 3`
// diyor — `NULL` gönderirsen sunucu sessizce `3` kullanır ve kullanıcı
// "kapalı" yerine "yazılmamış" olur. `1` anlamlı: tek seferlik tiplerde
// (`weigh_in` `=== 9`, `daily_log` `=== 18` sabit saat denetimi) aralık
// zaten kullanılmaz, `water`'da ise gerçekten saatte bir kez demektir.
//
// ## `summary_day` 0 = Pazar
//
// Sunucunun hafta günü dizini **üç yerden teyitli**:
//   - `supabase/functions/check-reminders/helpers.ts:70-78` `WEEKDAY_INDEX`
//     → `{Sun: 0, Mon: 1, …, Sat: 6}`
//   - `supabase/functions/check-reminders/index.ts:484` `dayOfWeek === summaryDay`
//   - migration yorumu: `summary_day` 0..6 CHECK'i
//
// Dart'ın `DateTime.weekday` dizini **ters** yönde olduğu için
// (`1 = Pazartesi, 7 = Pazar`) iki istemci arasında gün kayması yaşandı
// (A4r7b, 12 dilde ölçüldü). Web tarafında gün **üretilmiyor** — yalnızca
// kullanıcının seçimi `{value, label}` tablosundan geliyor ve bu tablo
// `WEEKDAY_INDEX` ile birebir hizalı (bkz. `WEEKDAY_OPTIONS`).
//
// ## Master anahtar gölgelenmesi (P1-2)
//
// `supabase/functions/send-notification/index.ts:423-424`
//   `preference?.push_enabled ?? profile.push_notifications_enabled ?? true`
//
// `??` **yalnız `NULL` üstüne düşer**. "Her tip için satır yaz" davranışı
// devreye girdiğinden `push_enabled` **dolu** olur ve **profil master
// anahtarı hiç okunmaz**: kullanıcı üstteki "Push Bildirimleri" anahtarını
// kapatır, tip bazlı `true` satırı yazılır, bildirim **yine gider**.
// Flutter bu hatanın karşılığını `applyMasterSwitches` ile (AND mantığı)
// çözdü; burada da **aynı** bileşim uygulanır.

export type NotificationType =
  | 'weigh_in'
  | 'daily_log'
  | 'water'
  | 'goal_achieved'
  | 'weekly_summary';

/** Sunucunun kabul ettiği tip sırası (DB CHECK allow-list, `full_setup.sql:824`). */
export const NOTIFICATION_TYPES: readonly NotificationType[] = [
  'weigh_in',
  'daily_log',
  'water',
  'goal_achieved',
  'weekly_summary',
];

/** Bir tipin sunucu tarafı ayar gövdesi. */
export interface PreferenceDraft {
  push_enabled: boolean;
  email_enabled: boolean;
  start_hour: number;
  end_hour: number;
  interval_hours: number;
  summary_day: number;
  summary_hour: number;
}

/** DB'ye yazılacak satır (PostgREST `Insert` ile uyumlu). */
export interface PreferenceRow extends PreferenceDraft {
  user_id: string;
  notification_type: NotificationType;
}

/** DB CHECK'i `notification_preferences_hours_range` (birebir). */
export const HOUR_MIN = 0;
export const HOUR_MAX = 23;
export const INTERVAL_MIN = 1;
export const INTERVAL_MAX = 24;
export const SUMMARY_DAY_MIN = 0; // 0 = Pazar
export const SUMMARY_DAY_MAX = 6; // 6 = Cumartesi

/**
 * Flutter `_clamp` (:208-209) ile birebir: aralık içindeyse değer,
 * dışındaysa `fallback`.
 *
 * `NaN` de "aralık dışı"dır (`v >= min` `NaN` üretir) → sessizce `NaN`
 * yazılmaz.
 */
export function clampInt(value: unknown, min: number, max: number, fallback: number): number {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n) || n < min || n > max) return fallback;
  // CHECK `BETWEEN` tam sayı arar; PostgREST `2.5` gönderirse CHECK reddeder.
  return Math.trunc(n);
}

/**
 * DB'ye yazılacak satırı üretir.
 *
 * A4r4b'nin Flutter'da bulduğu ikinci hata burada da birebir kapatılır:
 * `check-reminders/index.ts:356` koşulu
 * `normalizedHour >= startHour && normalizedHour <= endHour`;
 * `start > end` ise **hiçbir saatte** sağlanmaz → hatırlatma sessizce hiç
 * gönderilmez. DB CHECK'i iki saati de 0..23 olduğu için bunu reddetmez,
 * yani istemci tarafında düzeltilir. **Gece aralığı desteklenmez.**
 */
export function buildPreferenceRow(
  userId: string,
  type: NotificationType,
  draft: Partial<PreferenceDraft> | null | undefined,
): PreferenceRow {
  return { user_id: userId, notification_type: type, ...normalizePreference(type, draft) };
}

/**
 * Taslağı DB'nin kabul ettiği aralıklara normalize eder.
 *
 * ⭐ Neden `normalizePreference` gerekiyor: kolonlar **nullable**
 * (`full_setup.sql:527-533`) ve `null` bir değer CHECK'i geçer ama
 * `check-reminders` sessizce sunucu varsayılanına düşer. Ayrıca PostgREST
 * `int` kolonu JSON'a sayı olarak yazar; kolon `numeric` olsaydı metin
 * (`"3"`) olarak dönerdi — Flutter'da aynı tuzak
 * `NotificationPreference._asInt` (:220-228) ile kapatıldı, `clampInt`
 * `Number(value)` ile ikisini de kabul eder.
 *
 * `start > end` de burada düzeltilir ki **okuma** ve **yazma** tarafı
 * aynı satırı üretsin (`check-reminders:356` ters aralıkta hiçbir saatte
 * sağlanmaz).
 */
export function normalizePreference(
  type: NotificationType,
  draft: Partial<PreferenceDraft> | null | undefined,
): PreferenceDraft {
  const d = draft ?? {};
  const start = clampInt(d.start_hour, HOUR_MIN, HOUR_MAX, 9);
  const endRaw = clampInt(d.end_hour, HOUR_MIN, HOUR_MAX, 23);
  return {
    // `push_enabled`/`email_enabled` nullable kolonlar. `null` **"sunucu
    // varsayılanını kullan"** demek (yani profil master anahtarı okunur),
    // bu yüzden `null`ı yanlışlıkla `false`a çevirmiyoruz: tip dışı ya da
    // `null` girdide `NOTIFICATION_DEFAULTS` mantığı `true`/`false`
    // sabitlerine düşer (`buildPreferenceRow` çağırıcısı ekliyor).
    push_enabled: typeof d.push_enabled === 'boolean' ? d.push_enabled : true,
    email_enabled: typeof d.email_enabled === 'boolean' ? d.email_enabled : false,
    start_hour: start,
    end_hour: endRaw >= start ? endRaw : 23,
    interval_hours: clampInt(d.interval_hours, INTERVAL_MIN, INTERVAL_MAX, 3),
    summary_day: clampInt(d.summary_day, SUMMARY_DAY_MIN, SUMMARY_DAY_MAX, 1),
    summary_hour: clampInt(d.summary_hour, HOUR_MIN, HOUR_MAX, 9),
  };
}

/**
 * `summary_day` (0 = Pazar) seçenekleri.
 *
 * Değerler `WEEKDAY_INDEX` (`check-reminders/helpers.ts:70-78`) ile
 * **birebir** aynıdır. Sıralama Pazar'dan başlar çünkü `0 = Pazar`;
 * "Pazartesi = 1" çıkarımı yapılmamalıdır (A4r7b tuzağı).
 *
 * ⚠️ Etiketler Flutter'ın `DateFormat.E`'si gibi **yerelleştirilmiş** değil,
 * web PWA'nın bugünkü sabit Türkçe etiketlerinin aynısıdır. Değer↔etiket
 * eşleşmesi doğrudur; etiket çevirisi ayrı bir iş (P3, raporda bırakıldı).
 */
export const WEEKDAY_OPTIONS: ReadonlyArray<{ value: number; label: string }> = [
  { value: 0, label: 'Pazar' },
  { value: 1, label: 'Pazartesi' },
  { value: 2, label: 'Salı' },
  { value: 3, label: 'Çarşamba' },
  { value: 4, label: 'Perşembe' },
  { value: 5, label: 'Cuma' },
  { value: 6, label: 'Cumartesi' },
];

/**
 * Bir tarihin `summary_day` karşılığı (`0 = Pazar`).
 *
 * JS `Date#getDay()` zaten `0 = Pazar` verir, yani **kayma yok**; bu
 * yardımcı yalnızca "hangi dizin?" sorusunun tek yerde cevaplanması için
 * var (üç yerden teyitli kaynak: `WEEKDAY_INDEX`, `check-reminders:484`,
 * migration yorumu).
 */
export function weekdayIndexFor(date: Date): number {
  return date.getDay();
}

/**
 * ⭐ Profil seviyesi **master** anahtarlarla tip tercihlerini birleştirir.
 *
 * Flutter: `NotificationPreferencesRepository.applyMasterSwitches`
 * (`notification_preferences_repository.dart:320-332`).
 *
 * Bileşim **AND**'dir: master kapandıysa hiçbir kanal açılamaz. Master
 * kapandığında hangi satırın "kapatıldığı" bilgisi kaybolduğu için master
 * tekrar açıldığında **tüm** satırlar yazılır.
 */
export function applyMasterSwitches<T extends PreferenceDraft>(
  preferences: readonly T[],
  master: { push: boolean; email: boolean },
): T[] {
  return preferences.map((p) => ({
    ...p,
    push_enabled: master.push && p.push_enabled,
    email_enabled: master.email && p.email_enabled,
  }));
}

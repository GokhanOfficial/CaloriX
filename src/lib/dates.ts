// CaloriX tarih yardımcıları — web tarafının **yerel gün** sözleşmesi.
//
// ## Neden ayrı bir modül
//
// DB'de `entry_date` bir `DATE` kolonu, yani `tarih-saat` **değil**.
// Supabase/PostgREST bunu `"2026-03-01"` dizesi olarak döner. Bu dizeyi
// `new Date(...)` ile ayrıştırmak **UTC gece yarısı** üretir; ardından
// `toISOString().slice(0,10)` ile geri alındığında **UTC günü** elde edilir.
// Türkiye'de (UTC+03:00, yıl boyu sabit) bu, saat 03:00'ten sonra
// **bir gün ileri** bir tarih demektir:
//
//   1 Mart 2026, 10:00 (UTC+03:00) → new Date().toISOString().slice(0,10)
//   → "2026-03-01"  ✓ (UTC 07:00, aynı gün)
//   2 Mart 2026, 01:00 (UTC+03:00) → "2026-03-01"  ✗ (UTC 22:00 **1 Mart**)
//                                              → kullanıcı "1 Mart" görüyor
//
// Yani 03:00–24:00 arasındaki **tüm** kayıtlar bir gün geri etiketleniyordu.
// Batı yarımkürede ise tersi: gece yarısından sonraki kayıtlar **bir gün
// ileri** gösteriliyordu. Bu PWA'nın ana günlük ekranı (`Index`), analitik
// ekranı (`AnalyticsPage`) ve dışa aktarım dosya adı bu desenin üç ayrı
// kopyasını taşıyordu; A6r3 yalnız `useDataExport` içindeki bir yeri
// düzeltmişti (`localDateFromIso`).
//
// ## Sözleşme
//
// Her yere **bu modülün** fonksiyonları yazılır:
//
// - `todayLocalDateString()` — "bugün" (yerel takvim günü).
// - `formatLocalDate(date)`    — `Date` → `yyyy-MM-dd` (yerel).
// - `parseDateOnly(value)`     — `yyyy-MM-dd` → **yerel** `Date`.
// - `dayDiff(from, to)`        — iki yerel takvim günü arası **gün** farkı
//   (duvar saati farkına duyarsız — `add(Duration(days:1))` deseni yerine).
//
// Flutter tarafındaki karşılık: `DiaryRepository` / `AnalyticsRepository`
// (`entryDate` üretimi) ve `core/utils/date_utils.dart`.

import { format, isValid, parse } from 'date-fns';

/** `yyyy-MM-dd` regex'i. */
const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})$/;

/**
 * `Date` → `yyyy-MM-dd` (**yerel** takvim günü).
 *
 * `toISOString().slice(0, 10)` bunun **UTC** karşılığıdır ve doğru
 * günü vermez; bkz. modül yorumu.
 */
export function formatLocalDate(date: Date): string {
  if (!(date instanceof Date) || !isValid(date)) {
    throw new RangeError('formatLocalDate: geçersiz Date');
  }
  return format(date, 'yyyy-MM-dd');
}

/**
 * **Yerel** bugünün `yyyy-MM-dd` karşılığı.
 *
 * `new Date().toISOString().split('T')[0]` yerine kullanılır. Bugün tarih
 * alanı `max` değeri olarak da kullanılıldığı için (doğum tarihi seçici,
 * onboarding) hataya **gün** kayması doğrudan kullanıcıya yansır.
 */
export function todayLocalDateString(now: Date = new Date()): string {
  return formatLocalDate(now);
}

/**
 * `yyyy-MM-dd` dizesini **yerel** `Date`'e çevirir (UTC gece yarısı değil).
 *
 *Saat içeren ISO dize dokunulmadan ayrıştırılır (gerçek zaman damgası).
 * Ayırt edilemeyen girdide (`new Date` de string kabul ediyor) yerel
 * ayrıştırma denenir, o da başarısızsa `null` döner.
 */
export function parseDateOnly(value: string | null | undefined): Date | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  const match = DATE_ONLY.exec(trimmed);
  if (!match) {
    // Tarih-saat veya serbest biçim — `date-fns` yerel ayrıştırıcı.
    const parsed = parse(trimmed, 'yyyy-MM-dd HH:mm:ss', new Date());
    return isValid(parsed) ? parsed : null;
  }
  const [, y, m, d] = match;
  const year = Number(y);
  const month = Number(m);
  const day = Number(d);
  const date = new Date(year, month - 1, day);
  // `new Date(2026, 1, 30)` 1 Mart'a kayar (taşma) → o gün yok demektir.
  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    return null;
  }
  return date;
}

/**
 * İki **yerel takvim günü** arasındaki gün farkı (`to - from`).
 *
 * `Math.floor((t1 - t0) / 864e5)` **DST'de yanlış sonuç verir**: 23 saatlik
 * bir gün 0.9583 gün sayılır (→ 0) veya 25 saatlik gün 1.0417 (→ 1, ama
 * saat dilimi ötelemesi 2 saatse 1'e düşer). Burada iki `Date` de **yerel
 * gece yarısına** sabitlenir (`setHours(0,0,0,0)`) ve yıl/ay/gün alanları
 * üzerinden `Date.UTC` ile fark alınır → saat dilimi ve DST tamamen dışarı
 * çıkar. Flutter'daki `DateUtils.daysBetween` sözleşmesinin aynısı.
 */
export function dayDiff(from: Date, to: Date): number {
  if (!(from instanceof Date) || !(to instanceof Date)) {
    throw new TypeError('dayDiff: Date bekleniyor');
  }
  if (!isValid(from) || !isValid(to)) return 0;
  const fromUtc = Date.UTC(from.getFullYear(), from.getMonth(), from.getDate());
  const toUtc = Date.UTC(to.getFullYear(), to.getMonth(), to.getDate());
  return Math.round((toUtc - fromUtc) / 86_400_000);
}

/**
 * `date`'e `n` **takvim günü** ekler/çıkarır.
 *
 * `add(Duration(days: 1))` (Dart) yerine: `setDate(getDate() + n)`
 * kullanılır. `ms + 864e5` deseni DST'de günü atlar/geri alır
 * (Türkiye'de yıl boyu sabit olduğu için sorun görünmez, ama
 * `DateSelector` saat dilimini değiştiren bir kullanıcıda bozulur).
 * Dart tarafında A2r3'ün bu sınıf hatayı düzelttiği yer de
 * `date_utils.dart`.
 */
export function addLocalDays(date: Date, n: number): Date {
  if (!(date instanceof Date) || !isValid(date)) {
    throw new RangeError('addLocalDays: geçersiz Date');
  }
  if (n === 0) return new Date(date.getTime());
  const out = new Date(date.getTime());
  out.setDate(out.getDate() + n);
  return out;
}

/** `date`'i **yerel** gece yarısına sabitler (saat/dakika/saniye/ms = 0). */
export function startOfLocalDay(date: Date = new Date()): Date {
  if (!(date instanceof Date) || !isValid(date)) {
    throw new RangeError('startOfLocalDay: geçersiz Date');
  }
  const out = new Date(date.getTime());
  out.setHours(0, 0, 0, 0);
  return out;
}

/**
 * `start`..`end` (her ikisi de **takvim gününe** kırpılmış) arasındaki
 * her günü yerel gece yarısıyla üretir — **dahil**.
 *
 * `date-fns` `eachDayOfInterval` yerine kullanılır çünkü o fonksiyon
 * ters aralıkta `RangeError` fırlatır ve aralığı `+864e5 ms` adımıyla
 * ilerlettiği için 23/25 saatlik DST günlerinde **gün kaçırabilir**.
 * Flutter'ın `analytics_repository.buildDays` sözleşmesinin aynısı.
 */
export function eachLocalDay(start: Date, end: Date): Date[] {
  // Doğrulama **önce**: `startOfLocalDay` sözleşmesi gereği `RangeError`
  // fırlatır, ama bu bir *veri* fonksiyonu — çağıran
  // (`useAnalyticsData`) bozuk veride ekranı düşürmek istemiyor.
  if (
    !(start instanceof Date) || !(end instanceof Date) ||
    Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())
  ) {
    return [];
  }
  const from = startOfLocalDay(start);
  const to = startOfLocalDay(end);
  const out: Date[] = [];
  for (let d = from; dayDiff(d, to) >= 0; d = addLocalDays(d, 1)) {
    out.push(d);
  }
  return out;
}

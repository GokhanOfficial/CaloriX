/**
 * `check-reminders` idempotency yardımcıları için Deno testleri.
 *
 * Çalıştırma:
 *   deno test --allow-env supabase/functions/check-reminders/check_reminders_test.ts
 *
 * Kapsam: haftalık özet çift gönderimini engelleyen ISO haftası karşılaştırması.
 * Edge DB'ye bağımlı değildir.
 *
 * NOT: `index.ts` `serve()` çağırdığı için doğrudan import edilmez; saf
 * yardımcının **aynı kaynağı** `helpers.ts` üzerinden paylaşılır ve
 * senkronluk son test ile doğrulanır.
 */

import { isSameIsoWeek } from "./helpers.ts";

// Harici test kütüphanesi kullanılmaz (bkz. `_shared/vapid_test.ts`).
function assert(condition: unknown, message = "assertion başarısız"): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(message ?? `beklenen ${b}, alınan ${a}`);
}

const at = (iso: string) => new Date(iso);

Deno.test("aynı ISO haftasındaki iki tarih eşleşir (haftalık özet tekrarı engellenir)", () => {
  // 2026-09-28 bir Pazartesi.
  assert(isSameIsoWeek(at("2026-09-28T09:00:00Z"), at("2026-09-28T18:00:00Z")));
  // Pazartesi -> Pazar aynı hafta (ISO'da Pazar, başlayan haftanın son günüdür).
  assert(isSameIsoWeek(at("2026-09-28T00:00:00Z"), at("2026-10-04T23:59:59Z")));
  // Hafta içi farklı günler.
  assert(isSameIsoWeek(at("2026-09-28T09:00:00Z"), at("2026-09-30T09:00:00Z")));
});

Deno.test("farklı ISO haftaları eşleşmez (haftalık özet yeniden gönderilir)", () => {
  // Pazartesi -> sonraki Pazartesi.
  assert(!isSameIsoWeek(at("2026-09-28T09:00:00Z"), at("2026-10-05T09:00:00Z")));
  // Yıl sınırı: 2026-W40 -> 2027-W01.
  assert(!isSameIsoWeek(at("2026-12-31T09:00:00Z"), at("2027-01-04T09:00:00Z")));
});

Deno.test("aynı gün farklı saatler eşleşir (cron saatte bir çalışırsa bile tek sefer)", () => {
  // summary_hour = 9 iken cron 09:00 ve 09:59'da çalışırsa tekrar olmamalı.
  assert(isSameIsoWeek(at("2026-09-28T09:00:00Z"), at("2026-09-28T09:59:00Z")));
  assert(isSameIsoWeek(at("2026-09-28T09:00:00Z"), at("2026-09-28T09:00:30Z")));
});

Deno.test("geçersiz tarih eşleşmez (sessiz hata yerine güvenli davranış)", () => {
  const invalid = new Date("gecersiz");
  assert(!isSameIsoWeek(invalid, at("2026-09-28T09:00:00Z")));
  assert(!isSameIsoWeek(at("2026-09-28T09:00:00Z"), invalid));
  assert(!isSameIsoWeek(invalid, invalid));
});

Deno.test("ISO hafta numarası yıl sınırında doğru (2021-W01 = 4-10 Ocak)", () => {
  // 2021 yılının 1. ISO haftası 4 Ocak (Pazartesi) ile başlar.
  assert(isSameIsoWeek(at("2021-01-04T00:00:00Z"), at("2021-01-10T23:59:59Z")));
  // 2020-12-31 2020-W53'e aittir, 2021-W01'e değil.
  assert(!isSameIsoWeek(at("2020-12-31T12:00:00Z"), at("2021-01-04T12:00:00Z")));
});

Deno.test("kritik senaryo: haftalık özet aynı hafta 12 kez çalışsa da 1 kez gönderilir", () => {
  // Cron 5 dakikada bir çalışıyor; summary_hour=9'da 09:00-09:55 arası 12 koşu.
  const firstRun = at("2026-09-28T09:00:00Z");
  let sent = 0;
  for (let i = 0; i < 12; i++) {
    const runAt = at(`2026-09-28T09:${String(i * 5).padStart(2, "0")}:00Z`);
    // Damga yalnızca ilk gönderimden sonra yazılır.
    if (!isSameIsoWeek(firstRun, runAt)) sent++;
  }
  assertEquals(sent, 0, "aynı hafta içinde 0 ek gönderim olmalı");
  // Ertesi hafta yeniden gönderilir.
  assert(!isSameIsoWeek(firstRun, at("2026-10-05T09:00:00Z")));
});

/** Kaynak senkronizasyonu: index.ts saf yardıcıyı helpers.ts'ten almalı. */
Deno.test("index.ts ISO hafta yardımcısını helpers.ts'ten alır (tek kaynak)", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(source.includes('from "./helpers.ts"'), "index.ts helpers.ts'i içe aktarmalı");
  assert(
    !source.includes("export function isSameIsoWeek"),
    "isSameIsoWeek yalnızca helpers.ts'te tanımlanmalı (kopya kaynak = kayma riski)",
  );
  assert(source.includes("isSameIsoWeek("), "index.ts ISO hafta kontrolünü kullanmalı");
  assert(source.includes("last_weekly_summary"), "index.ts damga sütununu okumalı ve yazmalı");
});

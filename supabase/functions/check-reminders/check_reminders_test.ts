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

import {
  FALLBACK_TIME_ZONE,
  getZonedParts,
  isSameIsoWeek,
  isValidTimeZone,
  writeReminderStamp,
} from "./helpers.ts";

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

// ---------------------------------------------------------------------------
// Saat dilimi (A1r4): sabit `UTC+3` yerine `profiles.timezone`
// ---------------------------------------------------------------------------

Deno.test("TR kullanıcısı kendi saat diliminde hesaplanır (09:00 TR = 06:00 UTC)", () => {
  // 2026-09-28 06:00 UTC -> 09:00 Europe/Istanbul, Pazartesi.
  const parts = getZonedParts("Europe/Istanbul", at("2026-09-28T06:00:00Z"));
  assertEquals(parts.hour, 9);
  assertEquals(parts.weekday, 1, "Pazartesi = 1 (summary_day dizini)");
  assertEquals(parts.date, "2026-09-28");
  assertEquals(parts.timeZone, "Europe/Istanbul");
});

Deno.test("farklı saat dilimleri farklı saat/gün verir (sabit UTC+3 değil)", () => {
  const now = at("2026-09-28T23:30:00Z");
  // New York: 19:30, aynı gün.
  const ny = getZonedParts("America/New_York", now);
  assertEquals(ny.hour, 19);
  assertEquals(ny.date, "2026-09-28");
  // Tokyo: 08:30, **ertesi** gün -> gün sınırı eski `now.getDay()` ile kaçıyordu.
  const tokyo = getZonedParts("Asia/Tokyo", now);
  assertEquals(tokyo.hour, 8);
  assertEquals(tokyo.date, "2026-09-29");
  assertEquals(tokyo.weekday, 2, "Salı = 2");
  // Eski davranış (sabit +3) burada 02:30 ve YANLIŞ gün verirdi.
  assertEquals(getZonedParts("Europe/Istanbul", now).hour, 2);
  assertEquals(getZonedParts("Europe/Istanbul", now).date, "2026-09-29");
});

Deno.test("Avrupa yaz saati (CEST) sabit UTC+3'ten farklıdır", () => {
  // Berlin yazın UTC+2, kışın UTC+1. Sabit `+3` yazın 1 saat kaydırırdı.
  const summer = getZonedParts("Europe/Berlin", at("2026-07-01T12:00:00Z"));
  assertEquals(summer.hour, 14, "CEST = UTC+2");
  const winter = getZonedParts("Europe/Berlin", at("2026-01-15T12:00:00Z"));
  assertEquals(winter.hour, 13, "CET = UTC+1");
  // TR yaz saati uygulamıyor: yıl boyunca UTC+3.
  assertEquals(getZonedParts("Europe/Istanbul", at("2026-07-01T12:00:00Z")).hour, 15);
  assertEquals(getZonedParts("Europe/Istanbul", at("2026-01-15T12:00:00Z")).hour, 15);
});

Deno.test("yarım saat ve 45 dakikalık ofsetli dilimler doğru çözülür", () => {
  // Hindistan UTC+5:30, Nepal UTC+5:45, Chatham UTC+12:45/13:45.
  assertEquals(getZonedParts("Asia/Kolkata", at("2026-09-28T18:00:00Z")).hour, 23);
  assertEquals(getZonedParts("Asia/Kathmandu", at("2026-09-28T18:00:00Z")).hour, 23);
  // Chatham: yazın UTC+12:45 -> 18:00 UTC = 06:45, saat 6.
  assertEquals(getZonedParts("Pacific/Chatham", at("2026-01-15T18:00:00Z")).hour, 7);
});

Deno.test("geçersiz/boş/null saat dilimi akışı kırmaz, UTC'ye düşer VE loglar", () => {
  const logged: string[] = [];
  for (const bad of ["Mars/Olympus_Mons", "Not/AZone", "", "   ", null, undefined, 42]) {
    const parts = getZonedParts(bad as string, at("2026-09-28T12:00:00Z"), (m) => logged.push(m));
    assertEquals(parts.timeZone, FALLBACK_TIME_ZONE, `bozuk dilim: ${String(bad)}`);
    assertEquals(parts.hour, 12, "UTC saati dönmeli");
  }
  // Boş/null/uygunsuz tip sessiz geçmez, gerçekten bozuk olanlar loglanır.
  assert(logged.length >= 2, `bozuk dilimler loglanmalıydı, ${logged.length} kayıt`);
  assert(
    logged.some((m) => m.includes("20260928200000")),
    "log, uygulanması gereken migration'ı belirtmeli",
  );
});

Deno.test("isValidTimeZone gerçek IANA adlarını kabul eder, diğerlerini reddeder", () => {
  assert(isValidTimeZone("Europe/Istanbul"));
  assert(isValidTimeZone("UTC"));
  assert(!isValidTimeZone("Europe/Nowhere"));
  assert(!isValidTimeZone(""));
  assert(!isValidTimeZone("GMT+3"), "'GMT+3' IANA dilimi değildir");
  assert(!isValidTimeZone("UTC+3"), "'UTC+3' IANA dilimi değildir");
  assert(!isValidTimeZone(null));
  assert(!isValidTimeZone(7));
});

Deno.test("sabit ofset metinleri (Intl'in kabul ettiği) akışı bozmaz", () => {
  // ÖNEMLİ (ölçülen davranış): `Intl.DateTimeFormat` ISO ofset dizelerini
  // (`+03:00`) de kabul eder; `GMT+3`/`UTC+3`/`+3` etmezler.
  // Migration'daki CHECK kısıtı `pg_timezone_names()` ile doğrular ve
  // `+03:00` O LİSTEDE YOKTUR → yazma engellenir. Yani kanonik girdi
  // daima IANA adıdır; bir ofset dizgesi yine de bir şekilde verilirse
  // `Intl` onu çözer ve akış **kırılmaz** (sessizce UTC'ye de düşmez).
  const parts = getZonedParts("+03:00", at("2026-09-28T18:00:00Z"));
  assertEquals(parts.hour, 21, "ofset dizgesi doğru ofseti uygulanmalı");
  assertEquals(parts.date, "2026-09-28");
  // Etc/GMT-3 POSIX ters işaretlidir ve Türkiye = UTC+3'e karşılık gelir.
  assertEquals(getZonedParts("Etc/GMT-3", at("2026-09-28T18:00:00Z")).hour, 21);
});

Deno.test("saat dilimi mantığı timezone'a bağlı değil (intentional: sabit davranış testi)", () => {
  // `getZonedParts` saf fonksiyondur: aynı girdi → aynı çıktı, önbellek
  // kullanılsa bile (formatterCache) sonuç değişmez.
  const now = at("2026-09-28T06:00:00Z");
  const a = getZonedParts("Asia/Tokyo", now);
  const b = getZonedParts("Asia/Tokyo", now);
  assertEquals(a, b);
});

// ---------------------------------------------------------------------------
// Damga yazma (A1r3'ün bıraktığı P2): hata ASLA yutulmaz
// ---------------------------------------------------------------------------

/** `writeReminderStamp` sözleşmesini karşılayan sahte PostgREST builder. */
function fakeClient(
  behaviour: { error?: { message: string } | null; throws?: Error },
): {
  calls: Array<{ table: string; values: Record<string, unknown>; column: string; value: string }>;
  client: unknown;
} {
  const calls: Array<{ table: string; values: Record<string, unknown>; column: string; value: string }> = [];
  const client = {
    from(table: string) {
      return {
        update(values: Record<string, unknown>) {
          return {
            eq(column: string, value: string) {
              calls.push({ table, values, column, value });
              if (behaviour.throws) return Promise.reject(behaviour.throws);
              return Promise.resolve({ error: behaviour.error ?? null });
            },
          };
        },
      };
    },
  };
  return { calls, client };
}

Deno.test("damga başarıyla yazılırsa true döner ve doğru kolona yazar", async () => {
  const { calls, client } = fakeClient({ error: null });
  const logs: string[] = [];
  const ok = await writeReminderStamp(
    client as never,
    "user-1",
    "last_weekly_summary",
    "2026-09-28T06:00:00.000Z",
    (m) => logs.push(m),
  );
  assert(ok, "başarılı yazma true dönmeli");
  assertEquals(calls.length, 1);
  assertEquals(calls[0].table, "profiles");
  assertEquals(calls[0].column, "id");
  assertEquals(calls[0].values, { last_weekly_summary: "2026-09-28T06:00:00.000Z" });
  assertEquals(logs.length, 0, "başarılı yazmada log üretilmemeli");
});

Deno.test("DB hatası damga yazımında: false döner, hata LOGLANIR (sessiz yutma yok)", async () => {
  // Bu, A1r3'ün bıraktığı asıl senaryo: `.update()` çağrısının hatası
  // kontrol edilmediği için haftalık özet tekrar gönderiliyordu.
  const { client } = fakeClient({ error: { message: 'column "last_weekly_summary" does not exist' } });
  const logs: string[] = [];
  const ok = await writeReminderStamp(
    client as never,
    "user-2",
    "last_weekly_summary",
    "2026-09-28T06:00:00.000Z",
    (m) => logs.push(m),
  );
  assert(!ok, "hatalı yazma false dönmeli");
  assertEquals(logs.length, 1, "hata loglanmalıydı");
  assert(logs[0].includes("last_weekly_summary"), "kolon adı logda olmalı");
  assert(logs[0].includes("user-2"), "kullanıcı id logda olmalı");
  assert(
    logs[0].includes("TEKRAR"),
    "log, tekrar gönderim riskini açıkça belirtmeli (sessiz hataya dönmesin)",
  );
  // Şema ayrıntısı logda kalır ama istemciye dönmez (log-only).
  assert(logs[0].includes("does not exist"), "sunucu logunda tam hata bulunmalı");
});

Deno.test("ağ istisnası yakalanır, fonksiyon çökmez ve loglar", async () => {
  const { client } = fakeClient({ throws: new TypeError("network error") });
  const logs: string[] = [];
  const ok = await writeReminderStamp(
    client as never,
    "user-3",
    "last_water_reminder",
    "2026-09-28T06:00:00.000Z",
    (m) => logs.push(m),
  );
  assert(!ok, "istisnada false dönmeli");
  assertEquals(logs.length, 1);
  assert(logs[0].includes("network error"), "istisna mesajı logda olmalı");
});

Deno.test("damga yazımı opsiyonel logger olmadan da çalışır (undefined koruması)", async () => {
  const { client } = fakeClient({ error: { message: "boom" } });
  // Logger verilmezse istisna atmamalı — `log?.()` kullanılıyor.
  const ok = await writeReminderStamp(client as never, "user-4", "last_weigh_in_reminder", "x");
  assert(!ok);
});

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

/**
 * A1r3'ün bıraktığı P2'nin regresyon testi: damga yazan HER `profiles.update()`
 * çağrısı hatasını kontrol etmeli. `index.ts` kaynağında kontrolsüz
 * `.update(` deseni kalmadığını doğrular.
 */
Deno.test("index.ts'te damga yazan profiles.update() çağrısının hatası yutulmuyor", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(
    !source.includes("getUTCHours() + 3"),
    "sabit UTC+3 hesabı kaldırılmalı (profiles.timezone kullanılmalı)",
  );
  assert(source.includes("getZonedParts("), "index.ts saat dilimi yardımcısını kullanmalı");
  // Damga yazımı tek noktadan (writeReminderStamp) geçmelidir.
  const directUpdates = source.match(/supabase\s*\n?\s*\.from\("profiles"\)\s*\n?\s*\.update\(/g) ?? [];
  assertEquals(directUpdates.length, 0, "doğrudan profiles.update() kalmamalı");
  assertEquals(
    (source.match(/writeReminderStamp\(/g) ?? []).length,
    4,
    "dört damga (weigh_in / water / daily_log / weekly_summary) tek yardımcıdan geçmeli",
  );
  assert(source.includes("stampFailures"), "başarısız damga yazımları izlenebilir olmalı");
  assert(
    source.includes('from("profiles")\n      .select(') ||
      source.includes('"id, display_name, timezone,'),
    "profiles SELECT listesinde timezone bulunmalı",
  );
});

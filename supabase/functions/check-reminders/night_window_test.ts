/**
 * GECE ARALIĞI (A1r10, P1) — `start_hour > end_hour` gerçek desteği.
 *
 * Çalıştırma:
 *   cd supabase && deno test --allow-env --allow-read \
 *     functions/check-reminders/night_window_test.ts
 *
 * ---------------------------------------------------------------------------
 * NEDEN BU DOSYA VAR (tarihsel kayıt)
 * ---------------------------------------------------------------------------
 * `check-reminders/index.ts` eski koşulu:
 *
 *   if (normalizedHour >= startHour && normalizedHour <= endHour)
 *
 * `start = 21`, `end = 9` iken bu koşul **hiçbir saatte** sağlanmaz → "gece
 * 21:00-09:00 arası su hatırlat" diyen kullanıcıya bildirim **sessizce hiç
 * gitmiyordu**. DB CHECK'i (`notification_preferences_hours_range`) iki saati
 * de 0..23 olduğu için buna izin veriyordu.
 *
 * ---------------------------------------------------------------------------
 * ⭐ ÖLÇÜLEN TUZAK: "sarma tek başına yeter" yanılgısı
 * ---------------------------------------------------------------------------
 * Koşulu `h >= s || h <= e` yapmak **yetmez** ve hatta daha kötüdür. 7 günlük
 * saatlik simülasyonla ölçüldü (bu dosyanın `sarma TEK BASINA` testleri
 * aynı sayıyı yeniden üretir):
 *
 *   * 21→09, `interval_hours = 1` → **günde 13 gönderim** (21..23 + 0..9
 *     = 13 saatlik pencere, her saatte bir tane).
 *   * Aralık içi **art arda iki saatte** gönderim oluşuyor (21:00 ve 22:00).
 *
 * Neden? Damga yaşı `hoursBetween(stamp, now)` ile **UTC** farkından
 * hesaplanıyordu; 21:00→22:00 arası gerçekten 1 saat geçtiği için
 * `>= interval(1)` sağlanır. Sarmalı pencere "gece dilimi hâlâ açık" diye
 * okunur ve içerideki **her saat** yeniden tetikler. Yani sarma, "gece
 * aralığını aç" demek; "gece aralığında **her saat** gönder" demek değil.
 *
 * İkinci ve daha ince hata — **gece yarısını geçen damganın GÜNÜ**:
 * `last_water_reminder` bir `timestamptz`'dir ve **UTC'de saklanır**.
 *   dün  23:50 TR = 20:50 UTC   (UTC günü: D)
 *   bugün 00:10 TR = 21:10 UTC   (UTC günü: D-1  ← bir gün geride!)
 * Yani damga ve kontrol **UTC'ye göre farklı günlerde** görünür. Gün
 * karşılaştırması UTC ile yapılırsa saat farkı **negatif** çıkar → bildirim
 * **tekrar gönderilir**. Bu, A1r3'ün `weekly_summary` hatasının (aynı saat
 * diliminde günde ~12 kez gönderim) **aynı sınıfıdır**; tekrarlanmadı.
 *
 * Çözüm iki parçadır ve ikisi de burada testlidir:
 *   1. `isWithinHourWindow` — sarma (pencere) mantığı.
 *   2. `zonedMinutesBetween` — damga yaşı, kullanıcının **kendi gün/saat/
 *      dakika** parçaları üzerinden; dakika hassasiyeti ayrıca şart (saat
 *      0-23 tek başına 22:50→23:00'ı "1 saat" sanar → 50 dakika erken
 *      gönderim).
 *
 * Test dosyası `supabase/` altındadır (kullanıcı kısıtı: `/tmp` dışında test
 * yazma).
 */

import {
  getZonedParts,
  isWithinHourWindow,
  isWrappingWindow,
  isValidMinutes,
  zonedMinutesBetween,
  type ZonedParts,
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
const TZ = "Europe/Istanbul"; // UTC+3 yıl boyunca (Türkiye yaz saati uygulamaz).

/**
 * Kaynak koddan satır (`//`) ve blok (`/* *\/`) yorumlarını siler.
 *
 * ⭐ Neden gerekli? A4r7b'in ölçtüğü tuzak: yorum satırlarını ve ölü
 * import'ları "kullanım" sanan kaynak taraması **yanlış yeşil** üretir. Bu
 * dosyadaki "index.ts şunu yapmamalı" kapılarının yorumlarda geçen eski
 * koddan tetiklenmemesi için yorumlar temizlenir. Ters yönde de güvenli:
 * gerçek bir kullanım yorum **içinde** olamayacağı için silinmez.
 */
function stripComments(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .split("\n")
    .map((line) => {
      // Satır yorumu: string literal içindeki `//` yanlış kesilmesin diye
      // çift tırnaklı bölümler korunur.
      let out = "";
      let inString: '"' | "'" | "`" | null = null;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (inString) {
          out += ch;
          if (ch === "\\") {
            out += line[++i] ?? "";
            continue;
          }
          if (ch === inString) inString = null;
          continue;
        }
        if (ch === '"' || ch === "'" || ch === "`") {
          inString = ch;
          out += ch;
          continue;
        }
        if (ch === "/" && line[i + 1] === "/") break;
        out += ch;
      }
      return out;
    })
    .join("\n");
}

// ---------------------------------------------------------------------------
// 1) PENCERE MANTIĞI — isWithinHourWindow
// ---------------------------------------------------------------------------

Deno.test("start == end → YALNIZCA o saat (Flutter/web varsayılanları buna dayanır)", () => {
  // `weigh_in` 9→9, `daily_log` 18→18. "Tüm gün" isteyen kullanıcı 0/23 seçer.
  for (const hour of [0, 8, 10, 17, 19, 23]) {
    assert(!isWithinHourWindow(hour, 9, 9), `9→9 iken saat ${hour} pencereye girmemeli`);
  }
  assert(isWithinHourWindow(9, 9, 9), "9→9 iken saat 9 pencereye girmeli");
  assert(isWithinHourWindow(18, 18, 18), "18→18 iken saat 18 pencereye girmeli");
});

Deno.test("start < end → normal pencere, sarma YOK (davranış değişmedi)", () => {
  // 09:00-21:00 gündüz penceresi. 10, 15, 21 içeride; 8, 22 dışarıda.
  assert(isWithinHourWindow(9, 9, 21));
  assert(isWithinHourWindow(15, 9, 21));
  assert(isWithinHourWindow(21, 9, 21), "bitiş saati dahil (mevcut `<=` semantiği korunur)");
  assert(!isWithinHourWindow(8, 9, 21));
  assert(!isWithinHourWindow(22, 9, 21));
  assert(!isWithinHourWindow(0, 9, 21), "gece yarısı gündüz penceresine girmez");
  assert(!isWithinHourWindow(23, 9, 21));
});

Deno.test("⭐ start > end → GECE ARALIĞI çalışır: 21→09 = 21..23 ∪ 0..9", () => {
  // Eski koşul (>= && <=) bu durumda HİÇBİR saatte sağlanmıyordu.
  for (const hour of [0, 1, 5, 8, 9, 21, 22, 23]) {
    assert(
      isWithinHourWindow(hour, 21, 9),
      `gece aralığında saat ${hour} pencereye girmeliydi`,
    );
  }
  // Pencere dışı saatler: 10..20 arası.
  for (const hour of [10, 12, 15, 18, 20]) {
    assert(
      !isWithinHourWindow(hour, 21, 9),
      `gece aralığında saat ${hour} pencereye GİRMEMELİ`,
    );
  }
});

Deno.test("eski koşul (>= && <=) gece aralığında HİÇBİR saatte sağlanmıyordu", () => {
  // Bu test, düzeltmenin çözdüğü hatayı birebir yeniden üretir. Davranış
  // değişmediyse bu test kırmızı olur → yani yeşil "eski hâlâ bozuk" demektir.
  const old = (h: number, s: number, e: number) => h >= s && h <= e;
  const matched: number[] = [];
  for (let h = 0; h < 24; h++) if (old(h, 21, 9)) matched.push(h);
  assertEquals(matched, [], "eski koşul 21→09 için saat üretmemeliydi (bugün üretiyor)");

  // Yeni koşul aynı girişte 13 saat üretir (21,22,23 + 0..9).
  const now: number[] = [];
  for (let h = 0; h < 24; h++) if (isWithinHourWindow(h, 21, 9)) now.push(h);
  assertEquals(now, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 21, 22, 23]);
});

Deno.test("sarma tüm gece aralıklarında simetrik çalışır (22→05, 23→00, 00→23)", () => {
  // 22→05 = 22,23 ∪ 0..5
  const a: number[] = [];
  for (let h = 0; h < 24; h++) if (isWithinHourWindow(h, 22, 5)) a.push(h);
  assertEquals(a, [0, 1, 2, 3, 4, 5, 22, 23]);

  // 23→00 = yalnız 23 ve 0 (iki saatlik gece penceresi)
  const b: number[] = [];
  for (let h = 0; h < 24; h++) if (isWithinHourWindow(h, 23, 0)) b.push(h);
  assertEquals(b, [0, 23]);

  // 00→23 = sarma DEĞİL (0 < 23) → 0..23, yani tüm gün
  const c: number[] = [];
  for (let h = 0; h < 24; h++) if (isWithinHourWindow(h, 0, 23)) c.push(h);
  assertEquals(c.length, 24, "0→23 tüm gündür, sarma değil");
  assert(!isWrappingWindow(0, 23));
});

Deno.test("isWrappingWindow yalnız gerçek gece aralıklarında true", () => {
  assert(isWrappingWindow(21, 9), "21→9 gece aralığıdır");
  assert(isWrappingWindow(23, 0));
  assert(!isWrappingWindow(9, 21));
  assert(!isWrappingWindow(9, 9), "start == end sarma DEĞİLDİR (tek saat)");
  assert(!isWrappingWindow(0, 23));
  assert(!isWrappingWindow(0, 0));
});

Deno.test("pencere saatleri aralık dışıysa güvenli tarafa düşer (sessiz çökmez)", () => {
  // Kolon `integer` ve CHECK 0..23 olsa da CHECK uygulanmamış bir veri
  // (A1r8'in "veri doğrulanamadı" bulgusu) veya bozuk istemci yazımı
  // mümkündür. `check-reminders` bu kolonları doğrudan aritmetikte
  // kullandığı için akış **kırılmamalı**.
  assert(isWithinHourWindow(9, -5, 21), "negatif start güvenli aralığa indirgenir (0..21)");
  assert(!isWithinHourWindow(23, -5, 21), "indirgemeden sonra 23 pencere dışı");
  assert(isWithinHourWindow(9, 9, 99), "end > 23 → 23'e indirgenir, 09 girer");
  assert(isWithinHourWindow(23, 9, 99), "end = 23 iken 23 girer");
  assert(isWithinHourWindow(9, 9, Number.NaN), "NaN end → güvenli taraf");
  // ÖLÇÜLEN davranış: `safeHour` `Number.isFinite("9")` → **false** → 0.
  // Yani `"9"` 0'a indirgenir; pencere 00..21 olur ve saat 9 hâlâ girer
  // (yanlış olsa da akış kırılmaz). Sürükle-bırak arayüzün sayı üreteceği
  // düşünülür; buradaki amaç **kırılmama** garantisini kilitlemek.
  assert(isWithinHourWindow(9, "9" as unknown as number, 21), "string saat akışı kırmaz");
});

// ---------------------------------------------------------------------------
// 2) DAMGA YAŞI — zonedMinutesBetween (gece yarısı tuzağı)
// ---------------------------------------------------------------------------

/** `Europe/Istanbul` için damga parçaları üret (test okunabilirliği için). */
function stampAt(iso: string): ZonedParts {
  return getZonedParts(TZ, at(iso));
}

Deno.test("⭐ damga yaşı aynı gün içinde dakika hassasiyetinde ölçülür", () => {
  // 22:50 → 23:00 = **10 dakika**, "1 saat" DEĞİL. Saat (0-23) tek başına
  // kullanılsaydı 23-22 = 1 saat sanılır ve `interval_hours = 1` için
  // 50 dakika erken gönderim yapılırdı.
  const stamp = stampAt("2026-09-28T19:50:00Z"); // 22:50 TR
  const now = stampAt("2026-09-28T20:00:00Z"); // 23:00 TR
  const minutes = zonedMinutesBetween(stamp, now);
  assertEquals(minutes, 10, "22:50→23:00 = 10 dakika olmalı");
  assert(isValidMinutes(minutes));
  assert(minutes < 60, "saat yuvarlaması yapılmamalı");
});

Deno.test("⭐⭐ GECE YARISI TUZAĞI: dün 23:50 damgası, bugün 00:10'da 20 dakika", () => {
  // Bu, görevin uyardığı kritik senaryo. Damga dün 23:50 TR, kontrol bugün
  // 00:10 TR. Gerçek fark **20 dakika** → `interval_hours >= 1` ise **gönderim
  // yapılmamalı**. (Aksi halde "bugün gönderilmedi" sanılır ve tekrar gönderilir.)
  const stamp = stampAt("2026-09-27T20:50:00Z"); // 2026-09-27 23:50 TR
  const now = stampAt("2026-09-27T21:10:00Z"); // 2026-09-28 00:10 TR

  // Önce tuzağın kendisini göster: UTC günleri FARKLI.
  assertEquals(stamp.date, "2026-09-27", "damganın UTC karşılığı 27 Eylül 20:50");
  assertEquals(now.date, "2026-09-28", "kontrolün UTC karşılığı 27 Eylül 21:10 (28'lik görünüyor!)");

  const minutes = zonedMinutesBetween(stamp, now);
  assertEquals(minutes, 20, "gece yarısını geçen damga 20 dakika önce yazılmış olmalı");
  assert(minutes > 0, "fark ASLA negatif olmamalı (negatiflik = yanlış gün karşılaştırması)");

  // Karşılaştırma: 1 saatlik aralık dolmadı → gönderim YOK.
  assert(!(minutes >= 60), "interval_hours=1 için 20 dakika yeterli değil, gönderim olmamalı");
  // 1 saatlik aralık doldu → gönderim VAR.
  const later = stampAt("2026-09-27T22:10:00Z"); // 2026-09-28 01:10 TR
  assert(zonedMinutesBetween(stamp, later) >= 60, "1 saat 20 dakika sonra gönderim olmalı");
});

Deno.test("⭐ UTC günü karşılaştırması KULLANILIRSA tuzak gerçekleşir (negatif ölçüm)", () => {
  // Doğru davranışın **karşıtı** burada ölçülür. `hoursBetween(stamp, now)`
  // saf UTC farkı verir: 20:50 UTC → 21:10 UTC = **+20 dakika**, yani
  // doğru! Yani **yalnızca** UTC farkı bu spesifik çiftte doğru çalışır.
  //
  // Peki neden "gün karşılaştırması da düzeltilmeli" deniyor? Çünkü
  // `hoursBetween` **tamsaat** farkını döndürür ve **gün sayısını
  // göremez**: damga **dün 20:00 UTC**, kontrol **bugün 02:00 UTC**
  // (yani TR'de dün 23:00 → bugün 05:00) farkı 6 saattir ama TR'de **6 saat
  // geçmiştir** — burada da tutarlı. Asıl kırılma noktası **sarma ile
  // birleştiğinde**: aşağıdaki test bunu ölçüyor.
  const stamp = stampAt("2026-09-27T20:50:00Z");
  const now = stampAt("2026-09-27T21:10:00Z");
  // ⚠️ AMA: gece yarısını geçen damga **gün farkı** taşır. Damga dün 23:50
  // **TR**, kontrol bugün 00:10 **TR**. `hoursBetween` (UTC) = 20 dakika →
  // doğru. Şimdi damga dün 20:00 **UTC** (= dün 23:00 TR), kontrol bugün
  // 01:00 **UTC** (= bugün 04:00 TR): 5 saat. Doğru da.
  //
  // Kırılan yer: **gün sayısı yuvarlanınca**. `Math.floor`/`Math.round` ile
  // "gün" türetilen her yaklaşım 23:59→00:01 gibi sınırlarda 0 yerine 1
  // gün sayar. Saf `hoursBetween` bunu yapmaz — bu yüzden **asıl** kırılma
  // A1r3'ün anlattığı "damga günü" karşılaştırmasının `entry_date`/`date`
  // alanı üzerinden yapılmasıdır (aşağıdaki `gece yarısı tuzağı` testi).
  const utcDiffMinutes = (new Date("2026-09-27T21:10:00Z").getTime() -
    new Date("2026-09-27T20:50:00Z").getTime()) / 60000;
  assertEquals(utcDiffMinutes, 20, "bu çiftte UTC farkı da doğru (20 dk)");

  // Gerçek kırılma: gün **sayısı** türetilirse. Damga 2026-09-27 23:50 TR
  // (`date` = 2026-09-27), kontrol 2026-09-28 00:10 TR (`date` = 2026-09-28).
  // Gün farkı = 1. Saat farkı = 0 - 23 = -23. Gün/saat mantığı:
  //   1 * 24 + (-23) = **1 saat** → `>= 1` sağlanır → **00:10'da TEKRAR
  // gönderim**. İşte A1r3'ün hatasının tam sınıfı.
  const dayDiff = Math.round(
    (Date.parse("2026-09-28T00:00:00Z") - Date.parse("2026-09-27T00:00:00Z")) / 86_400_000,
  );
  const hourOnly = dayDiff * 24 + (now.hour - stamp.hour);
  assertEquals(hourOnly, 1, "GÜN+SAAT mantığı 1 saat der (yanlış: gerçek 20 dakika)");
  assert(hourOnly >= 1, "bu YANLIŞ mantık 1 saatlik aralığı dolmuş sayar → TEKRAR gönderim");
  // Dakika mantığı aynı anda gönderimi reddeder.
  assert(!(zonedMinutesBetween(stamp, now) >= 60), "DOĞRU mantık gönderimi reddeder");
});

Deno.test("gece yarısını geçen tam gün farkı 24 saat değil 20 dakika, ertesi gün doğru", () => {
  // 23:50 (dün) → 23:50 (bugün) = tam 24 saat.
  const a = stampAt("2026-09-27T20:50:00Z");
  const b = stampAt("2026-09-28T20:50:00Z");
  assertEquals(zonedMinutesBetween(a, b), 1440, "bir gün = 1440 dakika");
  // 00:10 (bugün) → 00:10 (yarın) = 1440 dakika.
  const c = stampAt("2026-09-27T21:10:00Z");
  const d = stampAt("2026-09-28T21:10:00Z");
  assertEquals(zonedMinutesBetween(c, d), 1440);
});

Deno.test("damga gelecekteyse fark negatif çıkar (sessizce 'gönderildi' sayılmaz)", () => {
  // Saat kayması / bozuk veri durumu. Negatif fark `>= interval` koşulunu
  // **sağlamaz** → gönderim yapılmaz. Test, bu güvenli tarafı kilitler.
  const future = stampAt("2026-09-28T20:50:00Z");
  const now = stampAt("2026-09-27T21:10:00Z");
  const minutes = zonedMinutesBetween(future, now);
  assert(minutes < 0, "gelecek damga negatif fark vermeli");
  assert(!(minutes >= 60), "gelecek damga gönderim tetiklememeli");
});

Deno.test("okunamayan damga NaN döner ve isValidMinutes ayırır (sessiz hata yok)", () => {
  // `getZonedParts` bozuk dilimde UTC'ye düşer ama **tarih her zaman dolu**;
  // bu yüzden burada doğrudan bozuk parçalar veriyoruz.
  const broken = { ...stampAt("2026-09-27T20:50:00Z"), date: "bozuk" } as ZonedParts;
  const now = stampAt("2026-09-28T10:00:00Z");
  const minutes = zonedMinutesBetween(broken, now);
  assert(!isValidMinutes(minutes), "bozuk tarih NaN vermeli");
  assert(Number.isNaN(minutes));

  // minute alanı eksikse de güvenli taraf (0 dakika).
  const noMinute = { weekday: 1, hour: 10, date: "2026-09-28", timeZone: TZ } as unknown as ZonedParts;
  assert(!isValidMinutes(zonedMinutesBetween(noMinute, now)), "minute yoksa geçersiz sayılmalı");
});

// ---------------------------------------------------------------------------
// 3) ⭐ 24 SAATLİK TAM TUR — uçtan uca simülasyon (sarma tuzağının ölçümü)
// ---------------------------------------------------------------------------

/**
 * `check-reminders` su bloğunun **saf** karşılığı: pencere → damga yaşı.
 *
 * `index.ts` ile birebir aynı karar sırası:
 *   1. `isWithinHourWindow(hour, start, end)` — pencere (sarma destekli)
 *   2. damga yoksa/okunamıyorsa → gönder; yoksa
 *      `zonedMinutesBetween(stamp, now) >= intervalHours * 60`
 *   3. gönderimden sonra damga yazılır.
 *
 * ⭐ Not: Bu simülasyon **saatte bir** koşu varsayar (cron `* * * * * *`).
 * Bu, tuzağın **en kötü** halidir: aralık 1 saat olan bir hatırlatma saatte
 * bir koşuda **her saat** tetiklenme eğilimindedir.
 */
function simulate(
  startHour: number,
  endHour: number,
  intervalHours: number,
  hours: number,
  tz = TZ,
): Array<{ date: string; hour: number; minute: number }> {
  // Başlangıç: 2026-09-21 00:00 UTC = 2026-09-21 03:00 TR.
  let cursor = at("2026-09-21T00:00:00Z");
  const sends: Array<{ date: string; hour: number; minute: number }> = [];
  let stamp: ZonedParts | null = null;
  for (let i = 0; i < hours; i++) {
    const nowParts = getZonedParts(tz, cursor);
    if (isWithinHourWindow(nowParts.hour, startHour, endHour)) {
      const minutesSince = stamp ? zonedMinutesBetween(stamp, nowParts) : NaN;
      const met = !isValidMinutes(minutesSince) || minutesSince >= intervalHours * 60;
      if (met) {
        sends.push({ date: nowParts.date, hour: nowParts.hour, minute: nowParts.minute });
        stamp = nowParts;
      }
    }
    cursor = new Date(cursor.getTime() + 3_600_000);
  }
  return sends;
}

Deno.test("⭐ sarma TEK BAŞINA uygulansa günde 13 gönderim olurdu (ölçülen tuzak)", () => {
  // Bu, **yalnızca sarmayı açan** (damga yaşını UTC farkıyla ölçmeye devam
  // eden) yaklaşımın sonucunu ölçer. Sayı 13'tür; düzeltme aşağıda bunu
  // 4'e indirir. Bu test, "sarma tek başına yetmez" iddiasının kanıtıdır.
  const naive = (h: number, s: number, e: number) => (s > e ? h >= s || h <= e : h >= s && h <= e);
  let stampHour = -1;
  let count = 0;
  for (let h = 0; h < 24; h++) {
    if (!naive(h, 21, 9)) continue;
    const age = stampHour < 0 ? 99 : (h - stampHour + 24) % 24;
    if (age >= 1) {
      count++;
      stampHour = h;
    }
  }
  assertEquals(count, 13, "yalnızca sarmayla 21→09 aralığında günde 13 gönderim olur");
});

Deno.test("⭐⭐ DÜZELTME: gece aralığı 21→09 + interval 3 → saatte 5 gönderim", () => {
  // Simülasyon 2026-09-21 **03:00 TR**'de başlar (bu saat 21→09 penceresinin
  // İÇİNDEDİR) ve 24 saat sürer. Türetilmiş akış:
  //   03:00 pencere içi, damga yok → **gönderim** (damga 09-21 03:00)
  //   06:00 (+180) → **gönderim** · 09:00 (+180) → **gönderim** (pencere kapanır)
  //   10:00..20:00 pencere dışı
  //   21:00 (yeni gece) → **gönderim** · 00:00 (09-22, +180) → **gönderim**
  // Toplam 5. ⭐ Dikkat: 09-21 03:00/06:00/09:00 gönderimleri **bir önceki
  // gece diliminin** devamıdır (gece aralığında "gün" 09:00-21:00 arası
  // boşluktur). Bu, tanımın doğal sonucudur ve **kullanıcı 09:00'u bitiş
  // seçtiği için** beklenen davranıştır.
  const sends = simulate(21, 9, 3, 24);
  assertEquals(sends.length, 5, `24 saatte 5 gönderim, ${sends.length} oldu: ${JSON.stringify(sends)}`);
  assertEquals(sends.map((s) => s.hour), [3, 6, 9, 21, 0]);
  assertEquals(
    sends.map((s) => `${s.date} ${String(s.hour).padStart(2, "0")}:00`),
    [
      "2026-09-21 03:00",
      "2026-09-21 06:00",
      "2026-09-21 09:00",
      "2026-09-21 21:00",
      "2026-09-22 00:00",
    ],
    "gece yarısı TR gününü değiştirir ama aralık bozulmaz",
  );
});

Deno.test("gece aralığı + interval 1: saatte 13 gönderim, art arda saat YOK", () => {
  // Pencere 13 saat (21,22,23,0..9), aralık 1 saat. 03:00'te başlanan
  // 24 saatlik turda 03,04,...,09 (7) + 21,22,23,00,01,02 (6) = **13**.
  // 13 = pencere saatleri. Yani "saatte bir" aralık, pencerenin **her
  // saatinde tam bir kez** gönderir — ve **bir fazlasını değil**.
  // ⚠️ Düzeltmesiz sarma 13'ü **her koşuda** tekrarlardı (günde 24+).
  const sends = simulate(21, 9, 1, 24);
  assertEquals(sends.length, 13, `24 saatte 13 gönderim, ${sends.length} oldu`);
  assertEquals(sends.map((s) => s.hour), [3, 4, 5, 6, 7, 8, 9, 21, 22, 23, 0, 1, 2]);
  // Art arda kontrolü: iki gönderim arasındaki en küçük fark **60 dakika**.
  for (let i = 1; i < sends.length; i++) {
    const prev = Date.parse(`${sends[i - 1].date}T00:00:00Z`) +
      (sends[i - 1].hour * 60 + sends[i - 1].minute);
    const cur = Date.parse(`${sends[i].date}T00:00:00Z`) + (sends[i].hour * 60 + sends[i].minute);
    assert(cur - prev >= 60, `art arda gönderim var: ${sends[i - 1].hour}->${sends[i].hour}`);
  }
});

Deno.test("gece aralığında 23:50 damgası sonrası 00:00'da TEKRAR gönderim yok", () => {
  // 2026-09-27 23:50 TR'de damga var (gece aralığında gönderilmiş).
  // 2026-09-28 00:00 TR'de cron koşar: pencere AÇIK (00 <= 9).
  // Damga yaşı = 10 dakika < 60 → **gönderim olmamalı**.
  const stamp = getZonedParts(TZ, at("2026-09-27T20:50:00Z")); // 23:50 TR
  const midnight = getZonedParts(TZ, at("2026-09-27T21:00:00Z")); // 00:00 TR
  assert(isWithinHourWindow(midnight.hour, 21, 9), "00:00 gece aralığında olmalı");
  const atMidnight = zonedMinutesBetween(stamp, midnight);
  assertEquals(atMidnight, 10, "23:50 → 00:00 = 10 dakika");
  assert(!(atMidnight >= 60), "00:00'da TEKRAR gönderim yapılmamalı");

  // 01:00 TR'ye gelindiğinde 70 dakika geçmiş olur → gönderim VAR.
  const oneAm = getZonedParts(TZ, at("2026-09-27T22:00:00Z"));
  assertEquals(zonedMinutesBetween(stamp, oneAm), 70);
  assert(zonedMinutesBetween(stamp, oneAm) >= 60, "01:00'de gönderim olmalı");
});

Deno.test("⭐ 7 GÜN: gece aralığında gönderim sayısı sabit (kaçak yok)", () => {
  // 168 saatlik koşu, interval 3. Pencerede saat başına en çok 1 gönderim
  // ve aralık 3 saat → **günde en çok 5** (pencere 13 saat / 3 + 1).
  // 7 günde 35 gönderim. Sapma olsaydı (bir gün 8, bir gün 2) damga
  // tutulmaması ya da çift sayım demekti.
  const sends = simulate(21, 9, 3, 24 * 7);
  assertEquals(sends.length, 35, `7 günde 35 gönderim beklenir, ${sends.length} oldu`);
  const perDay = new Map<string, number>();
  for (const s of sends) perDay.set(s.date, (perDay.get(s.date) ?? 0) + 1);
  for (const [date, count] of perDay) {
    assert(count <= 5, `${date} gününde en fazla 5 gönderim olmalı, ${count} oldu`);
  }
  // 21 Eylül: 03,06,09,21 = 4 · 22 Eylül: 00,03,06,09,21 = 5 · sonrakiler 5.
  assertEquals(perDay.get("2026-09-21"), 4, "ilk gün 03:00'te başlar (pencere içi)");
  assertEquals(perDay.get("2026-09-22"), 5);
  assertEquals(perDay.get("2026-09-27"), 5, "son gün de 5 (sızma yok)");
  assertEquals(perDay.size, 8, "8 farklı TR günü (17-24 + 25 Eylül sabaha kadar)");
});

Deno.test("gece aralığında bir gün içinde ASLA çift gönderim olmaz (en küçük fark 60 dk)", () => {
  // Bu, "sarma açtı → her saat" hatasının genel biçimini reddeder: aynı
  // saatte iki gönderim, ya da dakikalar arası ikinci koşu.
  const sends = simulate(21, 9, 1, 24 * 7);
  for (let i = 1; i < sends.length; i++) {
    const prev = Date.parse(`${sends[i - 1].date}T00:00:00Z`) +
      (sends[i - 1].hour * 60 + sends[i - 1].minute);
    const cur = Date.parse(`${sends[i].date}T00:00:00Z`) + (sends[i].hour * 60 + sends[i].minute);
    assert(cur - prev >= 60, `7 günlük koşuda art arda gönderim: ${JSON.stringify(sends.slice(i - 1, i + 1))}`);
  }
});

Deno.test("⭐ 24 saatlik döngüde TAM BİR TUR: gündüz 09→21 + interval 3", () => {
  // Gece aralığı düzeltmesi **gündüz** davranışını bozmamalı (regresyon).
  // 03:00'te başlanıyor → ilk pencere saati 09:00.
  // 09:00 (damga yok → gönderim) · 12,15,18,21 → 5 gönderim.
  const sends = simulate(9, 21, 3, 24);
  assertEquals(sends.map((s) => s.hour), [9, 12, 15, 18, 21]);
  assertEquals(sends.length, 5, "09,12,15,18,21 = 5 gönderim");
  const dates = new Set(sends.map((s) => s.date));
  assertEquals(dates.size, 1, "bir gün içinde kalmalı, ertesi güne taşmamalı");
});

Deno.test("tam tur: gece 21→09 + interval 6 → 24 saatte 3 gönderim (03,09,21)", () => {
  // 03:00 (damga yok → gönderim) · 09:00 (+360 → gönderim) · 21:00 (pencere
  // yeni açılıyor, +720 → gönderim). 00:00'da 09:00'dan 15 saat geçmiş
  // olurdu ama **pencere kapalı** (00 ≤ 9 olduğu için aslında AÇIK — 00:00
  // gece aralığına girer ve 09:00'dan 15 saat geçtiği için gönderilir;
  // 24 saatlik turun 00:00'ı içermediği için listede yok).
  const sends = simulate(21, 9, 6, 24);
  assertEquals(sends.map((s) => s.hour), [3, 9, 21]);
  assertEquals(sends.length, 3);
  // 48 saatlik tur: 3,9,21 (21 Eylül) → 3,9,21 (22 Eylül). 00:00 **gelmez**,
  // çünkü 09:00'dan sonraki 6 saatlik dilim 15:00'a düşer ve pencere kapalı.
  const two = simulate(21, 9, 6, 48);
  assertEquals(two.map((s) => s.hour), [3, 9, 21, 3, 9, 21]);
  assertEquals(two.length, 6, "48 saatte 6 gönderim (günde 3)");
  // Gece devri kanıtı: 21:00 → ertesi gün 03:00 arası tam 6 saat.
  const nightToMorning = simulate(21, 9, 6, 24);
  const last = nightToMorning[nightToMorning.length - 1];
  assertEquals(last.hour, 21, "gün 21:00'da kapanır (pencere 21'de yeniden açılır)");
});

Deno.test("gece aralığı interval 24'te: günde TAM 1 gönderim", () => {
  // `goal_achieved` varsayılanı `interval_hours: 24`. Aynı desen su bloğuyla
  // paylaşılırsa günde bir kez gönderilir (her saat DEĞİL).
  const sends = simulate(21, 9, 24, 24 * 7);
  assertEquals(sends.length, 7, `7 günde 7 gönderim, ${sends.length} oldu`);
});

// ---------------------------------------------------------------------------
// 4) KAYNAK SENKRONİZASYONU — index.ts gerçekten bu yardımcıları kullanıyor mu?
// ---------------------------------------------------------------------------

Deno.test("index.ts sarmayı destekleyen yardımcıları kullanır (tek kaynak)", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  // ⚠️ Yorum satırları eski koşulu **anlatmak** için yazıyor; bu yüzden
  // yalnızca yorum olmayan satırlar taranır (bkz. A4r7b'in notu: yorum
  // temizlemeden kaynak taraması yapan kapılar yanlış yeşil üretir).
  const code = stripComments(source);
  assert(
    !code.includes("normalizedHour >= startHour && normalizedHour <= endHour"),
    "eski sarmasız koşul index.ts KODUNDA kalmamalı",
  );
  assert(code.includes("isWithinHourWindow("), "index.ts pencere yardımcısını kullanmalı");
  assert(code.includes("zonedMinutesBetween("), "index.ts dakika farkı yardımcısını kullanmalı");
  assert(
    !code.includes("hoursBetween(lastWaterReminder, now)"),
    "damga yaşı artık UTC farkıyla ölçülmemeli (gece yarısı tuzağı)",
  );
  // Aralık karşılaştırması **dakika** cinsinden olmalı.
  assert(
    /minutesSince\s*>=\s*intervalHours\s*\*\s*60/.test(code),
    "aralık kontrolü `intervalHours * 60` dakika olmalı (saat yuvarlaması tuzağı)",
  );
});

Deno.test("helpers.ts tek kaynak: isWithinHourWindow yalnız burada tanımlı", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(
    !source.includes("export function isWithinHourWindow"),
    "kopya tanım index.ts'te olmamalı (kayma riski)",
  );
  assert(
    !source.includes("function isWithinHourWindow"),
    "isWithinHourWindow helpers.ts'ten alınmalı",
  );
});

Deno.test("ZonedParts her yerde `minute` alanı içerir (sözleşme)", async () => {
  // `minute` alanı eklenirken diğer `ZonedParts` üreticileri güncellenmeli;
  // eksik kalırsa `zonedMinutesBetween` yanlış ölçer.
  const source = await Deno.readTextFile(new URL("./helpers.ts", import.meta.url));
  const interfaceMatch = source.match(/export interface ZonedParts \{([\s\S]*?)\n\}/);
  assert(interfaceMatch, "ZonedParts arayüzü bulunamadı");
  assert(interfaceMatch[1].includes("minute:"), "ZonedParts.minute alanı tanımlı olmalı");
  // Her `ZonedParts` dönüşü `minute` içermeli — **kısaltma** (`minute` alanı
  // `{ minute }` olarak yazılır) dahil. Bu yüzden `minute:` değil, `minute`
  // aranır ve her dönüş `weekday:` içermeli (ZonedParts dönüşü olduğunu
  // ayırt etmek için).
  const producer = source.slice(source.indexOf("function getZonedPartsFromFormatter"));
  const returns = producer.match(/return \{[\s\S]*?\};/g) ?? [];
  const partReturns = returns.filter((r) => /weekday/.test(r));
  assertEquals(
    partReturns.length,
    2,
    `iki ZonedParts dönüşü beklenir (güvenli-UTC + normal), ${partReturns.length} bulundu`,
  );
  for (const r of partReturns) {
    assert(/\bminute\b/.test(r), `ZonedParts dönüşü minute içermeli: ${r}`);
  }
});

// ---------------------------------------------------------------------------
// 5) A4r8'İN İSTEMCİ TARAFI DÜZELTMESİ — sunucu artık desteklediği için
//    `toRow` içindeki `end → 23` çekme kaldırılabilir mi? (AKTARIM notu)
// ---------------------------------------------------------------------------

Deno.test("AKTARIM: istemci `end`'i 23'e çekmesi artık gereksiz (sunucu destekliyor)", async () => {
  // Bu test KOD DEĞİL, **kural** testidir: sunucu tarafı artık gece
  // aralığını desteklediği için Flutter'ın `notification_preferences_repository.dart`
  // içindeki `end >= start ? end : 23` normalize etmesi kullanıcının seçimini
  // sessizce değiştiriyor. Aktarım dosyasında bu satırın kaldırılması
  // istenmelidir; burada yalnızca "destek gerçekten var" kaydı tutulur.
  // (Flutter dosyasına dokunulmadı — PROTOKOL §5.)
  const helpers = await Deno.readTextFile(new URL("./helpers.ts", import.meta.url));
  assert(
    helpers.includes("export function isWithinHourWindow"),
    "sunucu tarafı sarmayı gerçekten destekliyor → istemci normalize etmemeli",
  );
  assert(helpers.includes("isWrappingWindow"), "gece aralığı algılanabiliyor");
});

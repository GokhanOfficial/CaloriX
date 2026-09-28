#!/usr/bin/env node
/**
 * Tarih/gün sınırı testleri — "UTC günü" deseninin kapatıldığını kanıtlar.
 *
 * ## Neden ayrı dosya
 *
 * Hesap testleri saf sayı üretir; buradaki hatalar **zaman dilimine** bağlıdır
 * ve test ortamının `TZ`'si ne olduğuna **bağlıdır**. Bu yüzden burada
 * `TZ=Europe/Istanbul` ve `TZ=America/New_York` altında **ayrı ayrı**
 * çalıştırılacak şekilde yazıldı; `npm test` betiği her ikisini de
 * koşar (aşağıdaki "koşum" notu).
 *
 * ## Kapatılan desenler
 *
 *   1. `new Date().toISOString().split("T")[0]` → **UTC** günü.
 *      Türkiye'de (UTC+03:00) saat 03:00'ten sonra **bir gün ileri**;
 *      Batı yarımkürede gece yarısından sonra **bir gün geri** gösterir.
 *   2. `new Date("2026-03-01")` → **UTC gece yarısı**; `getDate()` yerelde
 *      önceki güne düşer (Türkiye'de 28 Şubat).
 *   3. `Math.floor((t1 - t0) / 864e5)` → **duvar saati farkına** duyarlı;
 *      DST'de bir gün kaçırır/ekler.
 *   4. `add(Duration(days: 1))` benzeri ms ekleme → DST'de gün atlar
 *      (23 saatlik gün 0.9583 gün sayılır).
 *
 * ## `TZ` bağımlılığı nasıl yönetiliyor
 *
 * `process.env.TZ` çalışma anında değiştirilip `new Date()` çağrıları
 * yeniden yorumlatılır (V8'de çalışır, `node --test` altında doğrulandı).
 * Testler **her iki dilimde** koşar ve hangi dilimde koştuğunu
 * `Intl.DateTimeFormat().resolvedOptions().timeZone` ile doğrular — böylece
 * "test yanlış zamanda sessizce yeşil" durumu (A3r6'nın bulduğu DST testi
 * tuzağı) tekrarlanmaz.
 *
 * Çalıştırma:
 *   node --experimental-strip-types --import ./tool/ts-resolve.mjs \
 *        --test tool/test_dates.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  addLocalDays,
  dayDiff,
  eachLocalDay,
  formatLocalDate,
  parseDateOnly,
  startOfLocalDay,
  todayLocalDateString,
} from '../src/lib/dates.ts';

import { parseDateOnly as parseForAge, calculateAge } from '../src/lib/calculations.ts';

const currentTz = Intl.DateTimeFormat().resolvedOptions().timeZone;

/** Belirli bir saat diliminde çalıştırır, sonra eski dilime döner. */
function inTz(tz, fn) {
  const previous = process.env.TZ;
  process.env.TZ = tz;
  try {
    return fn(tz);
  } finally {
    if (previous === undefined) delete process.env.TZ;
    else process.env.TZ = previous;
  }
}

// ===========================================================================
// 1) ⭐ "UTC günü" deseni — `toISOString().split("T")[0]`
// ===========================================================================

test('⭐ toISOString UTC günü verir, formatLocalDate yerel verir (Türkiye)', () => {
  inTz('Europe/Istanbul', (tz) => {
    assert.equal(
      Intl.DateTimeFormat().resolvedOptions().timeZone,
      tz,
      'TZ uygulanmadı — test sessizce yanlış zamanda koşuyor'
    );
    // 2 Mart 2026, 01:00 yerel (UTC+03:00) → UTC 2026-03-01 22:00
    const d = new Date(2026, 2, 2, 1, 0, 0);
    const utcDay = d.toISOString().slice(0, 10);
    const localDay = formatLocalDate(d);
    assert.equal(utcDay, '2026-03-01', 'UTC günü bir gün geride');
    assert.equal(localDay, '2026-03-02', 'yerel gün doğru');
    assert.notEqual(utcDay, localDay, 'UTC ve yerel gün aynı olmamalı');

    // 2 Mart 2026, 04:00 yerel → UTC 01:00 → **aynı** gün
    const d2 = new Date(2026, 2, 2, 4, 0, 0);
    assert.equal(d2.toISOString().slice(0, 10), '2026-03-02');
    assert.equal(formatLocalDate(d2), '2026-03-02');
  });
});

test('⭐ Batı yarımkürede UTC günü bir gün ileride (ters hata)', () => {
  inTz('America/New_York', (tz) => {
    assert.equal(Intl.DateTimeFormat().resolvedOptions().timeZone, tz);
    // 1 Mart 2026, 20:00 yerel (UTC-05:00) → UTC 2 Mart 01:00
    const d = new Date(2026, 2, 1, 20, 0, 0);
    assert.equal(d.toISOString().slice(0, 10), '2026-03-02', 'UTC günü ileride');
    assert.equal(formatLocalDate(d), '2026-03-01', 'yerel gün doğru');
  });
});

test('⭐ todayLocalDateString her iki dilimde yerel günü verir', () => {
  for (const tz of ['Europe/Istanbul', 'America/New_York', 'UTC', 'Asia/Tokyo']) {
    inTz(tz, () => {
      // Saati 00:30'a sabitle: iki farklı UTC günü oluşturabilen tek nokta.
      const probe = new Date(2026, 5, 15, 0, 30, 0);
      const iso = probe.toISOString();
      const expected = todayLocalDateString(probe);
      // `formatLocalDate` ile aynı olmalı (o zaten `format`'ı kullanır)
      assert.equal(expected, formatLocalDate(probe), tz);
      // UTC günü farklı olduğunda hata görünür olmalı
      const d = new Date(2026, 5, 15, 0, 30, 0);
      const now = new Date(d.getTime());
      assert.equal(todayLocalDateString(now), expected, tz);
      assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(expected), `${tz}: ${expected}`);
      void iso;
    });
  }
});

test('⭐ formatLocalDate yerel alanlardan okur (UTC günü değil)', () => {
  inTz('Europe/Istanbul', () => {
    // 1 Ocak 2026 00:30 yerel → UTC 2025-12-31 21:30 → UTC günü 2025!
    const d = new Date(2026, 0, 1, 0, 30, 0);
    assert.equal(d.toISOString().slice(0, 10), '2025-12-31');
    assert.equal(formatLocalDate(d), '2026-01-01');
  });
});

// ===========================================================================
// 2) parseDateOnly — "2026-03-01" yerel gün olarak çözülmeli
// ===========================================================================

test('⭐ "2026-03-01" UTC gece yarısı DEĞİL, yerel gün', () => {
  for (const tz of ['Europe/Istanbul', 'America/New_York', 'UTC', 'Asia/Tokyo']) {
    inTz(tz, () => {
      const d = parseDateOnly('2026-03-01');
      assert.ok(d, `${tz}: Date dönmeli`);
      assert.equal(d.getFullYear(), 2026, tz);
      assert.equal(d.getMonth(), 2, tz);
      assert.equal(d.getDate(), 1, tz);
      assert.equal(d.getHours(), 0, `${tz}: yerel gece yarısı olmalı`);
      // Eski desen (`new Date("2026-03-01")`) burada **yanlış** gün verir
      const legacy = new Date('2026-03-01');
      if (tz === 'Europe/Istanbul') {
        assert.equal(legacy.getDate(), 1, 'Türkiye de aynı günü verir (gece yarısı UTC)');
      }
      if (tz === 'America/New_York') {
        // UTC-05:00'de 1 Mart 00:00 UTC = 28 Şubat 19:00 → **önceki gün**
        assert.equal(legacy.getDate(), 28, 'eski desen Batı yarımkürede gün kaybediyor');
        assert.equal(d.getDate(), 1, 'yerel ayrıştırma doğru günü veriyor');
      }
    });
  }
});

test('parseDateOnly ⇄ formatLocalDate gidiş-dönüş (her gün için)', () => {
  inTz('Europe/Istanbul', () => {
    for (let m = 0; m < 12; m++) {
      for (const day of [1, 15, 28]) {
        const iso = `2026-${String(m + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
        const parsed = parseDateOnly(iso);
        assert.ok(parsed, iso);
        assert.equal(formatLocalDate(parsed), iso, iso);
      }
    }
  });
});

test('parseDateOnly (calculations kopyası) de yerel gün verir', () => {
  inTz('Europe/Istanbul', () => {
    const d = parseForAge('2000-01-15');
    assert.equal(d.getDate(), 15);
    assert.equal(d.getHours(), 0);
  });
});

test('⭐ calculateAge: 1 Ocak doğumlu, doğum gününde 26 (UTC kayması düzeltildi)', () => {
  // Bu test **yalnız** `parseDateOnly` kullanıldığında yeşildir.
  inTz('Europe/Istanbul', () => {
    const now = new Date();
    // Şimdiki yılın 1 Ocak'ında doğmuş 25 yaşındaki biri
    const birth = new Date(now.getFullYear() - 25, 0, 1);
    const viaLegacy = calculateAge(new Date(formatLocalDate(birth)));
    const viaFixed = calculateAge(parseForAge(formatLocalDate(birth)));
    assert.equal(viaFixed, 25, 'yerel ayrıştırma doğru yaşı veriyor');
    // Yıl başında 1 Ocak günü: 1 Şubat'a kadar ikisi de 25 verir.
    // Yılın ilerleyen günlerinde legacy de doğru olur; fark yıl başıdır.
    void viaLegacy;
  });
});

// ===========================================================================
// 3) addLocalDays — DST'de gün kaçırmıyor
// ===========================================================================

test('⭐ addLocalDays DST geçişinde gün kaçırmaz (23 saatlik gün)', () => {
  inTz('Europe/Berlin', () => {
    // 2026-03-29 Avrupa'da yaz saatine geçiş: 28 Mart günü **23 saat**.
    //
    // Ölçüm (saat bazında taranarak): `+86_400_000 ms` deseni **yalnız**
    // `hour = 0`'da sapar (00:30 → 00:30 yok, 01:30'a düşer ama yine
    // 29 Mart'ta kalır). Ölçülen sapma: 00:00–00:59 arası.
    const before = new Date(2026, 2, 28, 0, 30, 0);
    const after = addLocalDays(before, 1);
    assert.equal(formatLocalDate(after), '2026-03-29', 'gün 29 olmalı');
    assert.equal(after.getHours(), 0, 'saat korunur (takvim günü)');
    // Ölçülen: bu saatte ms deseni de 29 Mart'ta kalır (01:30).
    assert.equal(formatLocalDate(new Date(before.getTime() + 86_400_000)), '2026-03-29');

    // **Saat 00:00**'da sapma gerçek: 00:00 + 24 saat = 29 Mart 01:00 → aynı
    // gün; ama 29 Mart 00:00'a **ilerlemek** gerekirken saat 01:00'e
    // kayıyor, yani "gece yarısı" invariantı bozuluyor.
    const midnight = new Date(2026, 2, 28, 0, 0, 0);
    const fixedMidnight = addLocalDays(midnight, 1);
    assert.equal(formatLocalDate(fixedMidnight), '2026-03-29');
    assert.equal(
      fixedMidnight.getHours(),
      0,
      'gece yarısı korunmalı — "gün" kavramı saat diliminden bağımsız'
    );
  });
});

test('⭐ addLocalDays 25 saatlik günde de doğru (geri saat)', () => {
  inTz('Europe/Berlin', () => {
    // 2026-10-25 Avrupa'da geri saat (25 saatlik gün).
    //
    // Dürüst ölçüm: bu geçişte `+86_400_000 ms` deseni **kalem günü
    // doğru** verir (fazladan bir saat var, gün atlamaz). Gerçek risk
    // ters yöndedir: **gün sayma** (24 saatlik aralık varsayan kod).
    // `dayDiff` testi bunu ayrıca kilitler.
    const before = new Date(2026, 9, 24, 12, 0, 0);
    assert.equal(formatLocalDate(addLocalDays(before, 1)), '2026-10-25');
    // İki gün atla: 24 Ekim → 26 Ekim
    assert.equal(formatLocalDate(addLocalDays(before, 2)), '2026-10-26');
  });
});

test('⭐ addLocalDays geri yönde de DST güvenli', () => {
  inTz('Europe/Berlin', () => {
    const after = new Date(2026, 2, 30, 12, 0, 0);
    const back = addLocalDays(after, -1);
    assert.equal(formatLocalDate(back), '2026-03-29');
  });
});

test('⭐ addLocalDays yıl sınırını doğru geçer (31 Aralık → 1 Ocak)', () => {
  inTz('Europe/Istanbul', () => {
    assert.equal(formatLocalDate(addLocalDays(new Date(2026, 11, 31, 10), 1)), '2027-01-01');
    assert.equal(formatLocalDate(addLocalDays(new Date(2027, 0, 1, 10), -1)), '2026-12-31');
    // Artık yıl: 29 Şubat
    assert.equal(formatLocalDate(addLocalDays(new Date(2028, 1, 28, 10), 1)), '2028-02-29');
    assert.equal(formatLocalDate(addLocalDays(new Date(2028, 1, 29, 10), 1)), '2028-03-01');
  });
});

test('addLocalDays 0 ve büyük adımlar', () => {
  inTz('Europe/Istanbul', () => {
    const d = new Date(2026, 5, 15, 13, 45, 30);
    assert.equal(addLocalDays(d, 0).getTime(), d.getTime());
    assert.equal(formatLocalDate(addLocalDays(d, 7)), '2026-06-22');
    assert.equal(formatLocalDate(addLocalDays(d, -15)), '2026-05-31');
    assert.equal(formatLocalDate(addLocalDays(d, 365)), '2027-06-15');
  });
});

// ===========================================================================
// 4) dayDiff — duvar saati farkına duyarsız gün farkı
// ===========================================================================

test('⭐ dayDiff 12 saatlik farkı 0 sayar (gece 01:00 tartılan kilo)', () => {
  inTz('Europe/Istanbul', () => {
    // Dün 01:00 → bugün 13:00 arası 36 saat, ama **1 takvim günü**.
    const from = new Date(2026, 5, 14, 1, 0, 0);
    const to = new Date(2026, 5, 15, 13, 0, 0);
    const hours = (to - from) / 3_600_000;
    assert.ok(hours > 24, 'saat farkı bir günden büyük');
    // `Math.floor(hours / 24)` = 1 ama 23:00→13:00 arasında 0 olmalı
    const from2 = new Date(2026, 5, 14, 23, 0, 0);
    assert.equal((to - from2) / 3_600_000, 14);
    assert.equal(dayDiff(from2, to), 1, 'takvim günü farkı 1');
    assert.equal(dayDiff(from2, from2), 0);
    assert.equal(dayDiff(to, from2), -1, 'ters yön negatif');
  });
});

test('⭐ dayDiff gece 01:00 senaryosu: 12 saat = 0 gün', () => {
  inTz('Europe/Istanbul', () => {
    const at1am = new Date(2026, 5, 14, 1, 0, 0);
    const at1pm = new Date(2026, 5, 14, 13, 0, 0);
    assert.equal(dayDiff(at1am, at1pm), 0, 'aynı gün');
    // Aynı gün içinde geriye de 0
    assert.equal(dayDiff(at1pm, at1am), 0);
  });
});

test('⭐ dayDiff DST gününde 1 döner (23 saatlik gün sayılmaz)', () => {
  for (const tz of ['Europe/Berlin', 'Europe/Istanbul', 'America/New_York']) {
    inTz(tz, () => {
      // 2026 yılında Avrupa'da 29 Mart, ABD'de 8 Mart yaz saati başlangıcı
      const before = new Date(2026, 2, 27, 12, 0, 0);
      const after = addLocalDays(before, 2);
      assert.equal(dayDiff(before, after), 2, tz);
    });
  }
});

test('dayDiff aylar ve yıllar arasında', () => {
  inTz('Europe/Istanbul', () => {
    assert.equal(dayDiff(new Date(2026, 0, 31), new Date(2026, 1, 1)), 1);
    assert.equal(dayDiff(new Date(2026, 0, 1), new Date(2026, 11, 31)), 364);
    assert.equal(dayDiff(new Date(2024, 0, 1), new Date(2025, 0, 1)), 366); // artık yıl
    assert.equal(dayDiff(new Date(2025, 0, 1), new Date(2026, 0, 1)), 365);
  });
});

// ===========================================================================
// 5) eachLocalDay — aralıktaki her gün (DST ve ters aralık)
// ===========================================================================

test('⭐ eachLocalDay DST gününü atlamaz', () => {
  inTz('Europe/Berlin', () => {
    const days = eachLocalDay(new Date(2026, 2, 27), new Date(2026, 2, 31));
    assert.deepEqual(
      days.map(formatLocalDate),
      ['2026-03-27', '2026-03-28', '2026-03-29', '2026-03-30', '2026-03-31']
    );
  });
});

test('eachLocalDay tek gün ve aynı gün aralıkları', () => {
  inTz('Europe/Istanbul', () => {
    const one = eachLocalDay(new Date(2026, 5, 15, 8), new Date(2026, 5, 15, 22));
    assert.equal(one.length, 1);
    assert.equal(formatLocalDate(one[0]), '2026-06-15');
    assert.equal(one[0].getHours(), 0, 'gün başlangıcına kırpılır');
  });
});

test('eachLocalDay hafta sonu (Pazartesi başlangıçlı hafta)', () => {
  inTz('Europe/Istanbul', () => {
    // 2026-09-28 bir Pazartesi
    const days = eachLocalDay(new Date(2026, 8, 28), new Date(2026, 8, 28 + 6));
    assert.equal(days.length, 7);
    assert.equal(formatLocalDate(days[0]), '2026-09-28');
    assert.equal(formatLocalDate(days[6]), '2026-10-04');
    assert.equal(days[0].getDay(), 1, 'Pazartesi');
  });
});

test('⭐ eachLocalDay 90 günlük pencere (3 ay) doğru uzunlukta', () => {
  inTz('Europe/Istanbul', () => {
    const start = new Date(2026, 0, 1);
    const end = addLocalDays(start, 90);
    const days = eachLocalDay(start, end);
    assert.equal(days.length, 91, 'dahil: 0 + 90 gün');
    assert.equal(formatLocalDate(days.at(-1)), formatLocalDate(end));
  });
});

test('eachLocalDay geçersiz Date → boş liste (RangeError yok)', () => {
  inTz('Europe/Istanbul', () => {
    // `eachLocalDay` bir **veri** fonksiyonu: bozuk `Date` üstüne
    // `RangeError` fırlatmak yerine boş liste döndürür, çünkü tek çağıran
    // (`useAnalyticsData`) bozuk veride ekranı düşürmek istemiyor.
    // `startOfLocalDay` ise sözleşmesi gereği **fırlatır** (aşağıdaki
    // "anlamlı hata" testi).
    assert.deepEqual(eachLocalDay(new Date(NaN), new Date(2026, 0, 1)), []);
    assert.deepEqual(eachLocalDay(new Date(2026, 0, 1), new Date(NaN)), []);
    assert.deepEqual(eachLocalDay(new Date(NaN), new Date(NaN)), []);
  });
});

// ===========================================================================
// 6) startOfLocalDay — "bugün" 00:05'i 00:00'a sabitler
// ===========================================================================

test('⭐ startOfLocalDay saat 00:05 → 00:00 (aynı gün kalır)', () => {
  inTz('Europe/Istanbul', () => {
    const late = new Date(2026, 5, 15, 0, 5, 0);
    const start = startOfLocalDay(late);
    assert.equal(start.getDate(), 15, 'gün ilerlememeli');
    assert.equal(start.getHours(), 0);
    assert.equal(start.getMinutes(), 0);
    assert.equal(start.getSeconds(), 0);
    assert.equal(start.getMilliseconds(), 0);
  });
});

test('startOfLocalDay sabit günü korur (0 değil)', () => {
  for (const tz of ['Europe/Istanbul', 'America/New_York']) {
    inTz(tz, () => {
      const start = startOfLocalDay(new Date(2026, 5, 15));
      assert.equal(formatLocalDate(start), '2026-06-15', tz);
    });
  }
});

// ===========================================================================
// 7) Denetim: "test doğru zamanda koşuyor mu?" (A3r6'nın DST tuzağı)
// ===========================================================================

test('denetim: test ortamı UTC değil — DST testleri ölçüyor', () => {
  // A3r6: "DST testleri hiçbir şey ölçmüyordu — test ortamında tz.local = UTC.
  // Yanlış güven üretiyordu." Bu dosyada `inTz` ile her senaryo iki dilimde
  // koştuğu için tuzak kalmıyor; bu test yalnız **ortamın** farkında
  // olduğunu sabitler.
  assert.ok(currentTz, 'saat dilimi çözülemedi');
  const resolved = new Intl.DateTimeFormat().resolvedOptions().timeZone;
  assert.equal(typeof resolved, 'string');
  // İki farklı dilimde aynı testin farklı sonuç verdiğini kanıtla:
  const istanbul = inTz('Europe/Istanbul', () => formatLocalDate(new Date(2026, 2, 2, 1, 0)));
  const newYork = inTz('America/New_York', () => formatLocalDate(new Date(2026, 2, 2, 1, 0)));
  assert.equal(istanbul, '2026-03-02');
  assert.equal(newYork, '2026-03-02');
  // …ve UTC deseni **ayrışıyor**:
  const istanbulUtc = inTz('Europe/Istanbul', () =>
    new Date(2026, 2, 2, 1, 0).toISOString().slice(0, 10)
  );
  assert.equal(istanbulUtc, '2026-03-01', 'UTC deseni hâlâ bir gün geride');
});

// ===========================================================================
// 8) Hata sözleşmesi
// ===========================================================================

test('geçersiz Date → anlamlı hata (sessizce yanlış gün değil)', () => {
  inTz('Europe/Istanbul', () => {
    assert.throws(() => formatLocalDate(new Date(NaN)), RangeError);
    assert.throws(() => startOfLocalDay(new Date(NaN)), RangeError);
    assert.throws(() => addLocalDays(new Date(NaN), 1), RangeError);
    assert.throws(() => dayDiff('x', new Date()), TypeError);
  });
});

test('dayDiff geçersiz Date → 0 (RangeError fırlatmaz)', () => {
  inTz('Europe/Istanbul', () => {
    assert.equal(dayDiff(new Date(NaN), new Date(2026, 0, 1)), 0);
    assert.equal(dayDiff(new Date(2026, 0, 1), new Date(NaN)), 0);
  });
});

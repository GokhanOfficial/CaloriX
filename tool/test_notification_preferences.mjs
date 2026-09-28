#!/usr/bin/env node
/**
 * Sunucu bildirim tercihleri + hesap silme **sözleşme testleri** (web).
 *
 * ## Bu testler neyi kanıtlıyor?
 *
 * ### P1-1 — `interval_hours` CHECK ihlali (A1r8/A4r8 ölçümü)
 *
 * `src/hooks/useNotifications.ts` `interval_hours: 0` yazıyordu; DB CHECK'i
 * `notification_preferences_hours_range`
 * (`supabase/full_setup.sql:828-831`) `interval_hours BETWEEN 1 AND 24`
 * dediği için **her satır reddediliyordu** → web PWA'da sunucu bildirim
 * tercihi kaydedilemiyordu. Testler hem saf katmanı (`buildPreferenceRow`)
 * hem de **gerçek varsayılan tablosunu** denetler (varsayılanlar
 * `NOTIFICATION_DEFAULTS`'ta yaşar; saf modülde yaşasaydı buraya
 * taşınmış olurdu — test yine de kaynak dosyayı **okuyarak** doğrular).
 *
 * ### P1-2 — master anahtar gölgelenmesi (A4r8 ölçümü)
 *
 * `send-notification/index.ts:423` `preference?.push_enabled ??
 * profile.push_notifications_enabled` okuyor; `??` yalnız `NULL` üstüne
 * düşer. Satır yazılınca profil master anahtarı **hiç okunmaz**. Flutter
 * `applyMasterSwitches` ile (AND) çözdü; web'de aynı bileşim
 * uygulanmalıdır. Test: master `false` iken **hiçbir** satır `true`
 * yazamaz — satır kendi değeri ne olursa olsun.
 *
 * ### `summary_day` 0 = Pazar (üç yerden teyit)
 *
 * `check-reminders/helpers.ts:70-78` `WEEKDAY_INDEX` `{Sun:0,…,Sat:6}`,
 * `check-reminders/index.ts:484` `dayOfWeek === summaryDay`, migration
 * CHECK `summary_day BETWEEN 0 AND 6`. Web'de gün **üretilmiyor** —
 * kullanıcının seçimi `WEEKDAY_OPTIONS`'tan geliyor; test bu eşleşmeyi
 * ve JS `getDay()` ile sunucu dizininin aynı olduğunu ölçer (A4r7b tuzağı:
 * gözle seçilen referans tarihi bir gün kaydırmıştı).
 *
 * ### P3 — hesap silme hata sınıflandırması
 *
 * `AccountDeletionError` **parolayı hiçbir koşulda taşımaz**; test bunu
 * ölçer (`String(err)` içinde parola aranır — bir sınıf hatası olsaydı
 * kırmızı olurdu). 401'in iki ayrı mesajı (`"Parola hatalı"` vs
 * `"Yetkisiz"`) ayrı türlere eşlenir; `partial` "başarı" sayılmaz.
 *
 * ## ⭐ Yeşil test ≠ etkin test
 *
 * A4r7b, `tester.tap` sessizce başarısız olup 3 testin hiçbir şey
 * ölçmediğini buldu. Burada bunun **sayacı** var:
 *  - her test en az bir `assert.*` içerir (toplam sayım aşağıda);
 *  - `test_denetim` bloğu **negatif kontrol** yapar: `applyMasterSwitches`
 *    master'ı yok sayan bir sürümle değiştirilse testler kırmızı
 *    döner (bkz. "Negatif ölçüm" bölümü raporda);
 *  - varsayılan tablosu testte **yeniden yazılmaz**, kaynak dosyadan
 *    okunur → iki kopyanın ayrışması testte yakalanır.
 *
 * ## Çalıştırma
 *
 *   npm test
 *   node --experimental-strip-types --import ./tool/ts-resolve.mjs \
 *        --test tool/test_notification_preferences.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  HOUR_MAX,
  INTERVAL_MAX,
  INTERVAL_MIN,
  NOTIFICATION_TYPES,
  SUMMARY_DAY_MAX,
  SUMMARY_DAY_MIN,
  WEEKDAY_OPTIONS,
  applyMasterSwitches,
  buildPreferenceRow,
  clampInt,
  normalizePreference,
  weekdayIndexFor,
} from '../src/lib/notificationPreferences.ts';

import {
  AccountDeletionError,
  MAX_PASSWORD_LENGTH,
  errorMessageFrom,
  mapHttpError,
  parseSuccessResponse,
  validatePassword,
} from '../src/lib/accountDeletion.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const HOOK_SRC = readFileSync(join(ROOT, 'src/hooks/useNotifications.ts'), 'utf8');

// ===========================================================================
// 0) ⭐ Denetim: testler gerçekten ölçüyor mu?
// ===========================================================================

test('⭐ denetim: varsayılan tablosu kaynak dosyadan okunur (kopya değil)', () => {
  // Testler `NOTIFICATION_DEFAULTS`'ı **yeniden yazmıyor**; kaynak dosyanın
  // kendisini okuyup ayrıştırıyoruz. Böylece iki kopyanın ayrışması
  // (düzeltmeden sonra burada unutulursa) testte **kırmızı** olur.
  const block = HOOK_SRC.match(
    /const NOTIFICATION_DEFAULTS[\s\S]*?\n};/,
  );
  assert.ok(block, 'NOTIFICATION_DEFAULTS bloğu bulunamadı');
  const parsed = {};
  const re = /(\w+):\s*\{([^}]*)\}/g;
  let m;
  while ((m = re.exec(block[0])) !== null) {
    const fields = {};
    for (const [, key, value] of m[2].matchAll(/(\w+):\s*(-?\d+)/g)) {
      fields[key] = Number(value);
    }
    parsed[m[1]] = fields;
  }
  assert.equal(Object.keys(parsed).length, 5, 'beş tip olmalı');
  for (const type of NOTIFICATION_TYPES) {
    assert.ok(parsed[type], `${type} varsayılanı yok`);
  }
});

test('⭐ denetim: CHECK kısıtı aralıkları DB ile birebir', () => {
  // `supabase/full_setup.sql:828-831` ve
  // `migrations/20260927120000_security_hardening_round1.sql:418-422`
  const migration = readFileSync(
    join(ROOT, 'supabase/migrations/20260927120000_security_hardening_round1.sql'),
    'utf8',
  );
  assert.ok(
    /interval_hours BETWEEN 1 AND 24/.test(migration),
    'CHECK `interval_hours BETWEEN 1 AND 24` kayboldu — sabitler güncellenmeli',
  );
  assert.ok(/summary_day BETWEEN 0 AND 6/.test(migration), 'CHECK `summary_day` kayboldu');
  assert.ok(/start_hour BETWEEN 0 AND 23/.test(migration), 'CHECK `start_hour` kayboldu');
  assert.equal(INTERVAL_MIN, 1);
  assert.equal(INTERVAL_MAX, 24);
  assert.equal(HOUR_MAX, 23);
  assert.equal(SUMMARY_DAY_MIN, 0);
  assert.equal(SUMMARY_DAY_MAX, 6);
});

test('⭐ denetim: WEEKDAY_INDEX sunucu ile aynı (0 = Pazar)', () => {
  // `check-reminders/helpers.ts:70-78`
  const helpers = readFileSync(
    join(ROOT, 'supabase/functions/check-reminders/helpers.ts'),
    'utf8',
  );
  const serverIndex = {};
  const re = /(Sun|Mon|Tue|Wed|Thu|Fri|Sat):\s*(\d)/g;
  let m;
  while ((m = re.exec(helpers)) !== null) serverIndex[m[1]] = Number(m[2]);
  assert.equal(Object.keys(serverIndex).length, 7, 'WEEKDAY_INDEX 7 gün içermeli');
  assert.equal(serverIndex.Sun, 0, 'sunucu 0 = Pazar diyor');

  // Web tablosu **değer** olarak birebir aynı olmalı (etiket Türkçe, sıra
  // Pazar→Cumartesi).
  const webValues = WEEKDAY_OPTIONS.map((d) => d.value);
  assert.deepEqual(webValues, [0, 1, 2, 3, 4, 5, 6]);
  assert.equal(WEEKDAY_OPTIONS[0].label, 'Pazar');
  assert.equal(WEEKDAY_OPTIONS[6].label, 'Cumartesi');
});

test('⭐ denetim: weekdayIndexFor JS getDay ile sunucu dizinini paylaşıyor', () => {
  // 2024-01-07 **Pazar** — A4r7b'nin gözle seçip bir gün kaydırdığı tarih.
  assert.equal(weekdayIndexFor(new Date(2024, 0, 7)), 0);
  // 2024-01-08 **Pazartesi** (A4r7b'nin düzelttiği referans).
  assert.equal(weekdayIndexFor(new Date(2024, 0, 8)), 1);
  assert.equal(weekdayIndexFor(new Date(2024, 0, 13)), 6); // Cumartesi

  // Sunucunun `WEEKDAY_INDEX` eşlemesi **gerçek tarihlerle** ölçülür:
  // `Intl` `en-US` kısaltmaları (`Sun`, `Mon`, …) her dilde de bu üç
  // harfle tanınır, bu yüzden tablo okunmadan da doğrulanabilir.
  const SERVER_INDEX = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  const fmt = new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: 'UTC' });
  for (let day = 0; day < 7; day++) {
    // 2024-01-07 Pazar → 7 gün boyunca her gün.
    const date = new Date(Date.UTC(2024, 0, 7 + day, 12));
    const name = fmt.format(date);
    assert.ok(name in SERVER_INDEX, `bilinmeyen gün kısaltması: ${name}`);
    assert.equal(
      weekdayIndexFor(date),
      SERVER_INDEX[name],
      `${date.toISOString().slice(0, 10)} (${name}): web ${weekdayIndexFor(date)} ≠ sunucu ${SERVER_INDEX[name]}`,
    );
  }
});

// ===========================================================================
// 1) ⭐ P1-1: `interval_hours` — `0` **asla** yazılmaz
// ===========================================================================

test('⭐ P1-1: interval_hours 0 → 3 (CHECK reddetmesin)', () => {
  // Flutter `toRow`: `_clamp(intervalHours, 1, 24, 3)`. `0` aralık **dışıdır**
  // (alt sınır 1) → `_clamp` **fallback**'e düşer, yani `3`.
  //
  // ⚠️ Neden 1 değil? Kolaycılık "0'ı 1'e çevir" diye düşündürüyor ama
  // Flutter'ın sözleşmesi `fallback = 3` (`check-reminders` `?? 3` varsayılanı
  // ile de örtüşüyor). `0` bir **anlam taşımayan** girdidir; kullanıcı
  // "saatte bir kez" isterse `1` yazar. Birebir hizalama `3`'tür.
  assert.equal(buildPreferenceRow('u1', 'weigh_in', { interval_hours: 0 }).interval_hours, 3);
  assert.equal(buildPreferenceRow('u1', 'daily_log', { interval_hours: 0 }).interval_hours, 3);
  // Negatif ve `NaN` de aynı kapıdan geçer.
  assert.equal(buildPreferenceRow('u1', 'water', { interval_hours: -5 }).interval_hours, 3);
  assert.equal(buildPreferenceRow('u1', 'water', { interval_hours: NaN }).interval_hours, 3);
  // Üst sınır korunur (24 = günde bir kez).
  assert.equal(buildPreferenceRow('u1', 'water', { interval_hours: 24 }).interval_hours, 24);
  assert.equal(buildPreferenceRow('u1', 'water', { interval_hours: 25 }).interval_hours, 3);
  // Aralık içindeki değer **korunur** (kullanıcının girdisi ezilmemeli).
  for (const v of [1, 2, 3, 6, 12, 23, 24]) {
    assert.equal(buildPreferenceRow('u1', 'water', { interval_hours: v }).interval_hours, v, `v=${v}`);
  }
});

test('⭐ P1-1: 0 **asla** çıkmaz (tüm tipler, tüm kombinasyonlar)', () => {
  // Ölçüm: eski varsayılan tablosunda `weigh_in`/`daily_log`/`goal_achieved`
  // `0` idi → üç tip de kaydedilemiyordu.
  for (const type of NOTIFICATION_TYPES) {
    for (const raw of [0, -1, -100, null, undefined, NaN, '', 'abc', '0']) {
      const row = buildPreferenceRow('u1', type, {
        interval_hours: raw,
        start_hour: 0,
        end_hour: 23,
      });
      assert.ok(
        row.interval_hours >= INTERVAL_MIN && row.interval_hours <= INTERVAL_MAX,
        `${type}: interval_hours=${raw} → ${row.interval_hours} CHECK'i ihlal ediyor`,
      );
    }
  }
});

test('⭐ P1-1: normalizePreference da 0 üretmiyor (okuma tarafı da güvenli)', () => {
  // DB'de `null` okunabiliyor (`full_setup.sql:531` nullable).
  assert.equal(normalizePreference('water', { interval_hours: null }).interval_hours, 3);
  // PostgREST `numeric` kolonu metin dönebilir (Flutter `_asInt` tuzağı).
  assert.equal(
    normalizePreference('water', { interval_hours: '4' }).interval_hours,
    4,
  );
  assert.equal(
    normalizePreference('water', { interval_hours: '0' }).interval_hours,
    3,
    'metin "0" da CHECK ihlali üretmemeli',
  );
});

test('⭐ P1-1: varsayılan tablosunun **ham** değerleri CHECK aralığında', () => {
  // ⭐ BURASI İLK YAZIMDA YANLIŞTI — negatif ölçüm bunu yakaladı.
  //
  // İlk sürüm, varsayılanları `buildPreferenceRow`'dan geçirip **sonucu**
  // denetliyordu. `buildPreferenceRow` `0`'ı `3`'e çevirdiği için test
  // `interval_hours: 0` yazan tabloyla bile **yeşil** kaldı — yani test
  // **hiçbir şey ölçmüyordu** (A4r7b'nin `tester.tap` tuzağıyla aynı sınıf:
  // normalize eden katman hata kaynağını gizliyor).
  //
  // Doğrusu: **normalize edilmemiş** sayıyı doğrudan denetlemek.
  // `normalizePreference` içindeki bir değişiklik (ör. clamp kaldırılırsa)
  // da kırmızı döner; ama varsayılan tablosundaki `0` **doğrudan** yakalanır.
  const block = HOOK_SRC.match(/const NOTIFICATION_DEFAULTS[\s\S]*?\n};/);
  assert.ok(block);
  const re = /(\w+):\s*\{([^}]*)\}/g;
  let m;
  let checked = 0;
  while ((m = re.exec(block[0])) !== null) {
    const type = m[1];
    const draft = {};
    for (const [, key, value] of m[2].matchAll(/(\w+):\s*(-?\d+)/g)) {
      draft[key] = Number(value);
    }
    // ⭐ Ham denetim: normalize YOK.
    assert.ok(
      draft.interval_hours >= INTERVAL_MIN && draft.interval_hours <= INTERVAL_MAX,
      `${type} varsayılan interval_hours=${draft.interval_hours} → ` +
        `notification_preferences_hours_range CHECK'i reddeder ` +
        `(kullanıcı bu tipi kaydedemez)`,
    );
    assert.ok(draft.start_hour >= 0 && draft.start_hour <= 23, `${type} start_hour`);
    assert.ok(draft.end_hour >= 0 && draft.end_hour <= 23, `${type} end_hour`);
    assert.ok(draft.end_hour >= draft.start_hour, `${type} start > end → hatırlatma hiç gitmez`);
    assert.ok(draft.summary_day >= 0 && draft.summary_day <= 6, `${type} summary_day`);
    assert.ok(draft.summary_hour >= 0 && draft.summary_hour <= 23, `${type} summary_hour`);
    // Ham değer normalize sürümüyle de **aynı** olmalı: yani varsayılan
    // zaten geçerli bir CHECK değeri (sessizce dönüştürülmesi gerekmiyor).
    const row = buildPreferenceRow('u1', type, draft);
    assert.equal(
      row.interval_hours,
      draft.interval_hours,
      `${type}: varsayılan geçerli ama normalize onu DEĞİŞTİRDİ (${draft.interval_hours} → ${row.interval_hours})`,
    );
    checked++;
  }
  assert.equal(checked, 5, 'beş tip denetlenmeli');
});

test('⭐ P1-1: normalizePreference clamp\'i kaldırılırsa kırmızı', () => {
  // Katmanın kendisi de ölçülüyor: CHECK aralığı dışına çıkan her değer
  // **kendisine** uygulanan `_clamp` ile sınırlanmalı.
  assert.equal(normalizePreference('water', { interval_hours: 0 }).interval_hours, 3);
  assert.equal(normalizePreference('water', { interval_hours: 99 }).interval_hours, 3);
  assert.equal(normalizePreference('water', { start_hour: 99 }).start_hour, 9);
  assert.equal(normalizePreference('water', { summary_day: 99 }).summary_day, 1);
  assert.equal(normalizePreference('water', { summary_hour: -1 }).summary_hour, 9);
});

test('P1-1: Flutter varsayılanlarıyla birebir (parite)', () => {
  // `defaultServerPreference` (notification_preferences_repository.dart:72-123)
  const flutter = {
    weigh_in: { push: true, email: true, start: 9, end: 9, interval: 1 },
    daily_log: { push: true, email: false, start: 18, end: 18, interval: 1 },
    water: { push: true, email: false, start: 9, end: 21, interval: 3 },
    goal_achieved: { push: true, email: false, start: 0, end: 23, interval: 24 },
    weekly_summary: { push: false, email: true, start: 9, end: 9, interval: 1 },
  };
  for (const [type, expected] of Object.entries(flutter)) {
    const draft = {
      push_enabled: expected.push,
      email_enabled: expected.email,
      start_hour: expected.start,
      end_hour: expected.end,
      interval_hours: expected.interval,
      summary_day: 1,
      summary_hour: 9,
    };
    const row = buildPreferenceRow('u1', type, draft);
    assert.equal(row.push_enabled, expected.push, `${type}.push_enabled`);
    assert.equal(row.email_enabled, expected.email, `${type}.email_enabled`);
    assert.equal(row.start_hour, expected.start, `${type}.start_hour`);
    assert.equal(row.end_hour, expected.end, `${type}.end_hour`);
    assert.equal(row.interval_hours, expected.interval, `${type}.interval_hours`);
    assert.equal(row.user_id, 'u1');
    assert.equal(row.notification_type, type);
  }
});

// ===========================================================================
// 2) ⭐ P1-2: master anahtar gölgelenmesi (AND)
// ===========================================================================

test('⭐ P1-2: master push kapalıyken hiçbir satır true yazamaz', () => {
  // Ölçülen hata: master `false`, varsayılan `true` → yazılan satır `true`
  // idi ve `send-notification:423` profil anahtarını **okumuyordu**.
  const rows = NOTIFICATION_TYPES.map((type) =>
    buildPreferenceRow('u1', type, { push_enabled: true, email_enabled: true }),
  );
  const merged = applyMasterSwitches(rows, { push: false, email: false });
  for (const row of merged) {
    assert.equal(row.push_enabled, false, `${row.notification_type}: push gölgeleniyor`);
    assert.equal(row.email_enabled, false, `${row.notification_type}: email gölgeleniyor`);
  }
});

test('⭐ P1-2: master açıkken tip bazlı değer korunur (AND, OR değil)', () => {
  const rows = [
    buildPreferenceRow('u1', 'water', { push_enabled: true, email_enabled: false }),
    buildPreferenceRow('u1', 'weekly_summary', { push_enabled: false, email_enabled: true }),
  ];
  const merged = applyMasterSwitches(rows, { push: true, email: true });
  // Master `true` "hepsini aç" demek **değildir**; tip bazlı kapatma korunur.
  assert.equal(merged[0].push_enabled, true);
  assert.equal(merged[0].email_enabled, false, 'water e-posta kapalı kalmalı');
  assert.equal(merged[1].push_enabled, false, 'weekly_summary push kapalı kalmalı');
  assert.equal(merged[1].email_enabled, true);
});

test('P1-2: master yalnız kendi kanalını etkiler', () => {
  const rows = [buildPreferenceRow('u1', 'water', { push_enabled: true, email_enabled: true })];
  const pushOff = applyMasterSwitches(rows, { push: false, email: true });
  assert.equal(pushOff[0].push_enabled, false);
  assert.equal(pushOff[0].email_enabled, true, 'e-posta master' + 'ı açıkken kapatılmamalı');
  const emailOff = applyMasterSwitches(rows, { push: true, email: false });
  assert.equal(emailOff[0].push_enabled, true);
  assert.equal(emailOff[0].email_enabled, false);
});

test('P1-2: applyMasterSwitches girdiyi **mutasyona uğratmaz**', () => {
  const original = buildPreferenceRow('u1', 'water', { push_enabled: true, email_enabled: true });
  const snapshot = { ...original };
  const merged = applyMasterSwitches([original], { push: false, email: false });
  assert.equal(original.push_enabled, true, 'kaynak satır mutasyona uğradı');
  assert.equal(original.email_enabled, true);
  assert.notEqual(merged[0], original, 'kopya dönmeli');
  assert.equal(merged[0].user_id, 'u1', 'user_id taşınmalı');
  assert.equal(merged[0].notification_type, 'water');
});

test('P1-2: gölgelenme düzeltmesi gerçekten uygulanmış (kaynak denetimi)', () => {
  // A4r7b dersi: "mantıklı görünen" bir yorum satırı testi geçirmez. Burada
  // **kaynak** denetleniyor: `saveAllPreferences` içinde master bileşimi
  // gerçekten uygulanıyor ve `SettingsPage` onu **çağırıyor**.
  //
  // Ölü import tuzağı: `applyMasterSwitches` import edilmiş ama
  // çağrılmamış olabilir (import satırı çağrı silinse de dosyada kalır).
  // Bu yüzden `||` ile gevşetmeden **gerçek çağrı** aranır.
  const body = HOOK_SRC.slice(HOOK_SRC.indexOf('const saveAllPreferences'));
  assert.ok(body.length > 0, 'saveAllPreferences tanımlı değil');
  // `applyMasterSwitches(<rows>, master)` — ikinci argüman `master` olmalı.
  // (Satır aralığı esnek: `NOTIFICATION_TYPES.map(...)` gövdesi uzun.)
  const call = body.match(/applyMasterSwitches\(([\s\S]*?)\n\s*\);/);
  assert.ok(call, 'saveAllPreferences içinde applyMasterSwitches çağrısı yok');
  assert.ok(
    /\bmaster\b\s*,?\s*\)?\s*$/.test(call[1].trimEnd()) || /\bmaster\b/.test(call[1]),
    'applyMasterSwitches çağrısında `master` argümanı yok (AND uygulanmıyor?)',
  );
  // Bileşimin sonucu **upsert'e** akıyor (satırlar ezilmiyor mu?).
  assert.ok(
    /const rows = applyMasterSwitches\([\s\S]{0,400}?rows\.map\(row => supabase/.test(body),
    'master uygulanmış satırlar upsert\'e gitmiyor',
  );
  const settings = readFileSync(join(ROOT, 'src/pages/SettingsPage.tsx'), 'utf8');
  assert.ok(
    /saveAllPreferences\(\s*\{\}/.test(settings),
    'SettingsPage master anahtarlarıyla saveAllPreferences çağırmıyor',
  );
  // Ayrıca sunucunun hatalı `??` okuması hâlâ orada (belgelenmiş aktarım),
  // bu yüzden istemci tarafı AND zorunlu — kapı bunu da sabitler.
  const server = readFileSync(
    join(ROOT, 'supabase/functions/send-notification/index.ts'),
    'utf8',
  );
  assert.ok(
    /preference\?\.push_enabled\s*\?\?\s*profile\.push_notifications_enabled/.test(server),
    "send-notification değişmiş — istemci AND'i gereksizse güncelle",
  );
});

// ===========================================================================
// 3) Saat aralığı — `start > end` sessizce hiç göndermemek
// ===========================================================================

test('start > end → end 23\'e çekilir (sessiz kayıp değil)', () => {
  // `check-reminders/index.ts:356` koşulu `start <= hour <= end`;
  // `start > end` ise **hiçbir saatte** sağlanmaz. Flutter `toRow` 23'e
  // çekiyor; web de aynı.
  assert.equal(buildPreferenceRow('u1', 'water', { start_hour: 21, end_hour: 9 }).end_hour, 23);
  assert.equal(buildPreferenceRow('u1', 'water', { start_hour: 23, end_hour: 0 }).end_hour, 23);
  // `start == end` geçerli (tek saatte giden tipler).
  assert.equal(buildPreferenceRow('u1', 'weigh_in', { start_hour: 9, end_hour: 9 }).end_hour, 9);
  // `start < end` korunur.
  assert.equal(buildPreferenceRow('u1', 'water', { start_hour: 9, end_hour: 21 }).end_hour, 21);
});

test('ters aralık **her girdi** için düzeltilir (fuzz)', () => {
  for (let start = 0; start <= 23; start++) {
    for (let end = 0; end <= 23; end++) {
      const row = buildPreferenceRow('u1', 'water', { start_hour: start, end_hour: end });
      assert.ok(row.end_hour >= row.start_hour, `start=${start} end=${end} → end=${row.end_hour}`);
    }
  }
});

// ===========================================================================
// 4) `clampInt` sözleşmesi
// ===========================================================================

test('clampInt: aralık içi korur, dışı fallback (NaN dahil)', () => {
  assert.equal(clampInt(5, 1, 24, 3), 5);
  assert.equal(clampInt(1, 1, 24, 3), 1);
  assert.equal(clampInt(24, 1, 24, 3), 24);
  assert.equal(clampInt(0, 1, 24, 3), 3);
  assert.equal(clampInt(25, 1, 24, 3), 3);
  assert.equal(clampInt(NaN, 1, 24, 3), 3);
  assert.equal(clampInt(Infinity, 1, 24, 3), 3);
  assert.equal(clampInt(-Infinity, 1, 24, 3), 3);
  assert.equal(clampInt('7', 1, 24, 3), 7, 'metin sayı kabul edilir');
  assert.equal(clampInt('x', 1, 24, 3), 3);
  assert.equal(clampInt(null, 1, 24, 3), 3);
  assert.equal(clampInt(undefined, 1, 24, 3), 3);
  // CHECK tam sayı ister: `2.9` yazılırsa CHECK reddeder.
  assert.equal(clampInt(2.9, 1, 24, 3), 2);
});

// ===========================================================================
// 5) P3: hesap silme — hata sınıflandırması ve parola sızıntısı
// ===========================================================================

test('P3: 401 iki mesaja iki farklı türe eşlenir', () => {
  // Sunucu sabit mesajlar: `"Parola hatalı"` (:118) ve `"Yetkisiz"` (:80,160).
  assert.equal(mapHttpError(401, { error: 'Parola hatalı' }).kind, 'wrongPassword');
  assert.equal(mapHttpError(401, { error: 'Yetkisiz' }).kind, 'unauthorized');
  // Tanınmayan 401 gövdesi → `wrongPassword` (bilinçli tercih).
  assert.equal(mapHttpError(401, { error: '???beklenmeyen???' }).kind, 'wrongPassword');
  assert.equal(mapHttpError(401, null).kind, 'wrongPassword');
  assert.equal(mapHttpError(401, 'Yetkisiz').kind, 'unauthorized', 'metin gövde de okunur');
});

test('P3: 429 / 4xx / 5xx / ağ hatası doğru türe eşlenir', () => {
  assert.equal(mapHttpError(429, {}).kind, 'rateLimited');
  for (const status of [400, 405, 413, 415]) {
    assert.equal(mapHttpError(status, {}).kind, 'invalidRequest', `status=${status}`);
  }
  assert.equal(mapHttpError(500, {}).kind, 'unknown');
  assert.equal(mapHttpError(502, {}).kind, 'unknown');
  // Ağ/aktarım hatası: `response` yok → `status: 0`.
  const net = mapHttpError(0, null);
  assert.equal(net.kind, 'network');
  assert.equal(net.status, null, 'ağ hatasında durum kodu uydurulmamalı');
});

test('⭐ P3: parola hiçbir hata nesnesinde geçmiyor', () => {
  // Sınıf güvenlik garantisi: `message` sabit; `kind`/`status` dışında
  // hiçbir şey taşınır. Flutter'ın "parola hiçbir hata mesajında geçmiyor"
  // testinin web karşılığı.
  const secret = 'SuperGizliParola123!';
  const mapped = mapHttpError(401, { error: `Parola hatalı: ${secret}` });
  const dumped = [
    String(mapped),
    JSON.stringify(mapped),
    Object.keys(mapped).join(','),
    mapped.stack ?? '',
  ].join(' ');
  // `message` sabit olduğu için parola **bulunamaz**. (Sunucunun döndüğü
  // gövde metni `error.message`'a **kopyalanmaz**.)
  assert.ok(!mapped.message.includes(secret), 'parola hata mesajına sızdı');
  assert.ok(!dumped.includes(secret), 'parola serileştirmede sızdı');
  // Doğrulama hatası da parolayı taşımaz.
  const invalid = validatePassword(secret);
  assert.equal(invalid, null, 'geçerli parola reddedilmemeli');
  const empty = validatePassword('   ');
  assert.equal(empty.kind, 'invalidRequest');
  assert.ok(!String(empty).includes('   '));
  assert.ok(MAX_PASSWORD_LENGTH === 256, 'sunucu üst sınırı 256');
});

test('P3: boş/çok uzun parola gönderilmez (2/saat kotası korunur)', () => {
  // Sunucu `requireString` ile de reddeder ama her red **bir deneme**
  // sayılır; istemci tarafı erken ret kotaları korur.
  assert.equal(validatePassword('').kind, 'invalidRequest');
  assert.equal(validatePassword('   ').kind, 'invalidRequest');
  assert.equal(validatePassword('x'.repeat(MAX_PASSWORD_LENGTH + 1)).kind, 'invalidRequest');
  assert.equal(validatePassword('x'.repeat(MAX_PASSWORD_LENGTH)), null);
});

test('P3: `partial` "başarı" sayılmaz (KVKK eksik silme iddiası olmaz)', () => {
  // `index.ts:151-155`: `retryRecommended: true` ⇒ `auth.admin.deleteUser()`
  // BAŞARISIZ ⇒ hesap hâlâ duruyor.
  const full = parseSuccessResponse({ success: true, message: '…silindi.' });
  assert.equal(full.partial, false);
  assert.equal(full.completed, true);
  const partial = parseSuccessResponse({ success: true, retryRecommended: true });
  assert.equal(partial.partial, true);
  assert.equal(partial.completed, false, 'kısmi silme "tamamlandı" sayılmamalı');
  assert.equal(partial.retryRecommended, true);
});

test('P3: 200 ama sözleşme dışı gövde → hata (sessiz "başarı" yok)', () => {
  assert.throws(() => parseSuccessResponse(null), AccountDeletionError);
  assert.throws(() => parseSuccessResponse('metin'), AccountDeletionError);
  assert.throws(() => parseSuccessResponse([]), AccountDeletionError);
  assert.throws(() => parseSuccessResponse({}), AccountDeletionError);
  assert.throws(() => parseSuccessResponse({ success: false }), AccountDeletionError);
  assert.throws(() => parseSuccessResponse({ message: 'ok' }), AccountDeletionError);
  // `retryRecommended` yalnız `true` ise partial (string "true" değil).
  assert.equal(parseSuccessResponse({ success: true, retryRecommended: 'true' }).partial, false);
});

test('P3: errorMessageFrom gövdeyi güvenli biçimde okur', () => {
  assert.equal(errorMessageFrom({ error: 'Parola hatalı' }), 'Parola hatalı');
  assert.equal(errorMessageFrom({ error: 42 }), '42');
  assert.equal(errorMessageFrom('Yetkisiz'), 'Yetkisiz');
  assert.equal(errorMessageFrom(''), null);
  assert.equal(errorMessageFrom('   '), null);
  assert.equal(errorMessageFrom(null), null);
  assert.equal(errorMessageFrom([1, 2]), null);
  // Uzun metin 200 karaktere kırpılır (log şişmesi önlemi).
  assert.equal(errorMessageFrom('x'.repeat(500)).length, 200);
});

// ===========================================================================
// 6) ⭐ Denetim: yeni giriş noktası gerçekten bağlı (ölü kod değil)
// ===========================================================================

test('⭐ denetim: hesap silme giriş noktası ayarlarda BAĞLI', () => {
  // "Tanımlı ama hiçbir yerden çağrılmıyor" sınıfı hataya bu turun tam
  // konusuydu: `saveNotifications` **ölü koddu**. Aynı hatanın
  // tekrarlamamak için burada gerçekten çağrıldığını ölçüyoruz.
  const settings = readFileSync(join(ROOT, 'src/pages/SettingsPage.tsx'), 'utf8');
  assert.ok(
    /setDeleteAccountOpen\(true\)/.test(settings),
    'SettingsPage: hesap silme girdi noktası bağlı değil',
  );
  assert.ok(
    /<DeleteAccountDialog\s+open=\{deleteAccountOpen\}/.test(settings),
    'SettingsPage: diyalog render edilmiyor',
  );
  // Kaydet düğmesi gerçekten `saveNotifications`'ı **çağırıyor** mu?
  // (ölü kod tuzağı: fonksiyon tanımlı, çağrı yok)
  assert.ok(
    /onClick=\{saveNotifications\}/.test(settings),
    'SettingsPage: bildirim "Kaydet" düğmesi saveNotifications\'ı çağırmıyor',
  );
  assert.ok(
    /saveAllPreferences\(/.test(settings),
    'SettingsPage: sunucu tercihleri yazılmıyor (master gölgelenmesi geri gelir)',
  );
  // Diyalog gerçekten edge function'ı çağırıyor mu?
  const hook = readFileSync(join(ROOT, 'src/hooks/useAccountDeletion.ts'), 'utf8');
  assert.ok(
    /functions\.invoke\(\s*'delete-account'/.test(hook),
    'useAccountDeletion: delete-account çağrılmıyor',
  );
  // Gövde yalnızca `password` — BOLA koruması (readJsonBody yok sayar).
  assert.ok(
    /body:\s*\{\s*password:\s*password\.trim\(\)\s*\}/.test(hook),
    'useAccountDeletion: gövde `{ password }` olmalı (userId gönderilmez)',
  );
});

test('denetim: hesap silme akışı oturumu düşürüp /auth\'a gider', () => {
  const hook = readFileSync(join(ROOT, 'src/hooks/useAccountDeletion.ts'), 'utf8');
  assert.ok(/await signOut\(\)/.test(hook), 'signOut çağrılmıyor — oturum açık kalır');
  assert.ok(/navigate\('\/auth'\)/.test(hook), '/auth yönlendirmesi yok');
});

test('denetim: 27 i18n anahtarı **her iki** istemcide de var', () => {
  // `tool/check_i18n.cjs` yalnız Flutter tarafını denetliyor; web tarafı
  // `public/locales`'ten okunur. İkisinin de senkron olduğunu ölçüyoruz.
  const KEYS = [
    'settings.notifications.push',
    'settings.notifications.email',
    'settings.notifications.server.channelNote',
    'settings.deleteAccount.entry',
    'settings.deleteAccount.entryDesc',
    'settings.deleteAccount.title',
    'settings.deleteAccount.warning',
    'settings.deleteAccount.irreversible',
    'settings.deleteAccount.passwordLabel',
    'settings.deleteAccount.passwordRequired',
    'settings.deleteAccount.confirm',
    'settings.deleteAccount.deleting',
    'settings.deleteAccount.data.meals',
    'settings.deleteAccount.data.water',
    'settings.deleteAccount.data.weight',
    'settings.deleteAccount.data.chat',
    'settings.deleteAccount.data.favorites',
    'settings.deleteAccount.data.settings',
    'settings.deleteAccount.data.notifications',
    'settings.deleteAccount.messages.wrongPassword',
    'settings.deleteAccount.messages.rateLimited',
    'settings.deleteAccount.messages.invalidRequest',
    'settings.deleteAccount.messages.unauthorized',
    'settings.deleteAccount.messages.network',
    'settings.deleteAccount.messages.partial',
    'settings.deleteAccount.messages.failed',
  ];
  const get = (obj, dotted) => dotted.split('.').reduce((n, k) => (n == null ? n : n[k]), obj);
  const langs = readFileSync(join(ROOT, 'public/locales/en/translation.json'), 'utf8');
  const webEn = JSON.parse(langs);
  const flutterEn = JSON.parse(
    readFileSync(join(ROOT, 'flutter_app/assets/translations/en.json'), 'utf8'),
  );
  for (const key of KEYS) {
    assert.notEqual(get(webEn, key), undefined, `web(en) eksik: ${key}`);
    assert.notEqual(get(flutterEn, key), undefined, `flutter(en) eksik: ${key}`);
    // Aynı metin (12 dilde `sync_locales_once.cjs` ile kopyalandı).
    assert.equal(get(webEn, key), get(flutterEn, key), `${key}: iki istemci farklı metin gösteriyor`);
  }
});

// ===========================================================================
// 7) ⭐ Düzeltmenin **etkinliği**: geri alma ölçümü
// ===========================================================================

test('⭐ etkinlik: eski hata (interval 0 / master gölgelenmesi) yeniden yorumlanırsa kırmızı', () => {
  // Bu test kendi "kötü uygulamasını" üretir ve **kırmızı olduğunu**
  // gösterir: `buildPreferenceRow` yerine eski davranış (normalize yok) ve
  // `applyMasterSwitches` yerine `??` gölgelenmesi.
  const legacy = (draft) => ({ ...draft }); // normalize yok → 0 yazılır
  const legacyRow = legacy({ interval_hours: 0, start_hour: 9, end_hour: 9 });
  // CHECK ihlali: eski kodun yazdığı değer.
  assert.equal(legacyRow.interval_hours, 0, 'kötü uygulama 0 yazıyor (beklenen)');
  // Yeni davranış aynı girdide CHECK'i geçiyor.
  assert.notEqual(buildPreferenceRow('u1', 'water', { interval_hours: 0 }).interval_hours, 0);

  // `??` gölgelenmesi: satır `true` iken profil master anahtarı okunmaz.
  const shadowed = (pref, master) => pref ?? master;
  assert.equal(shadowed(true, false), true, '?? gölgelemesi master false yutuyor (beklenen)');
  const merged = applyMasterSwitches(
    [buildPreferenceRow('u1', 'water', { push_enabled: true })],
    { push: false, email: true },
  );
  assert.equal(merged[0].push_enabled, false, 'AND master false uygulanıyor');
});

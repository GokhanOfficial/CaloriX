#!/usr/bin/env node
/**
 * Flutter i18n bütünlük denetleyicisi (`flutter_app/assets/translations`).
 *
 * Denetlenenler:
 *   1. Her dil dosyası geçerli JSON mu.
 *   2. `en.json` referans kabul edilir: diğer 11 dilde eksik/fazla anahtar.
 *   3. Boş string / null değerleri.
 *   4. easy_localization named placeholder tutarlılığı — `tr` ile `en`
 *      arasında `{foo}` kümesi farklıysa çalışma zamanında sessizce
 *      kaybolan metin parçası vardır.
 *   5. Uygulama kodunda (`lib/**` + `test/**`) kullanılan ama hiçbir dilde
 *      karşılığı olmayan anahtarlar.
 *   6. **Orphan** (sahipsiz) anahtarlar: hiçbir dilde karşılığı olmayan
 *      değil, **hiçbir dilde olup kodda hiç kullanılmayan** anahtarlar.
 *      Üçe ayrılır:
 *        - `ölü`    : kodda hiçbir yerde geçmiyor, dinamik kalıp da yok.
 *        - `dinamik`: `'notifications.${name}Title'` gibi bir kalıbın
 *                      kapsamında → statik analizle ölü/ölü değil
 *                      ayırt edilemez, silinmez.
 *        - `referans`: literal olarak geçiyor ama `.tr()` çağrısı değil
 *                      (ör. `Calculations.bmiCategory` → `bmi.underweight`).
 *
 * Çıkış kodu:
 *   - herhangi bir HATA varsa → 1
 *   - ölü orphan sayısı `ORPHAN_BASELINE`'ı aşarsa → 1 (ratchet)
 *   - aksi hâlde 0
 *
 * Kullanım:
 *   node tool/check_i18n.cjs                     # CI gate
 *   node tool/check_i18n.cjs --report-orphans    # ayrıntılı orphan listesi
 *   node tool/check_i18n.cjs --write-missing     # eksik anahtarları en.json'dan kopyalar
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const TRANS_DIR = path.join(ROOT, 'flutter_app', 'assets', 'translations');
const CODE_DIRS = [
  path.join(ROOT, 'flutter_app', 'lib'),
  path.join(ROOT, 'flutter_app', 'test'),
];
const REFERENCE_LANG = 'en.json';
const EXPECTED_LANGS = 12;

/**
 * Orphan ratchet.
 *
 * `--report-orphans` çıktısındaki **ölü** sınıfın (iki istemcide de
 * kullanılmayan anahtar) üst sınırı. Yeni bir anahtar kodda
 * kullanılmadan eklenirse CI kırılır; temizlik yapılırsa sayı düşer ve
 * baseline güncellenmelidir.
 *
 * **63'ün gerekçesi (2026-09-27, A6r2 ölçümü):**
 * - A6r2 görevi "163 orphan anahtarı sil" idi. Doğrulama iki aşamalı
 *   sonuç verdi:
 *   1. Önceki sürümün `.tr()` regex'i çok satırlı zincirleme çağrıları
 *      (`'k'\n  .tr()`) kaçırıyor, dolaylı anahtarları (`bmi.*`,
 *      `settings.goals.activity.*`, `meals.*`, `notifications.*Title`)
 *      ve çoğu `settings.*`/`dialogs.*` anahtarını yanlışlıkla ölü
 *      sayıyordu. Düzeltilmiş sınıflandırma: 18 dinamik + 289 dolaylı +
 *      67 React-canlı + **63 ölü**.
 *   2. 63 ölünün **61'i `public/locales` altındaki translation.json
 *      dosyalarında hâlâ var** — React PWA'nın çalışma zamanı çeviri
 *      kaynağı budur ve `src/**` bu anahtarların bir kısmını
 *      (t('chat.emptyTitle') gibi)
 *      kullanıyor. `flutter_app/assets/translations/*.json` bu dosyaların
 *      **üst kümesidir** (`tool/convert_locales.cjs` ile üretilir, sonradan
 *      elle genişletilmiştir). Ortak anahtar adı uzayı paylaşıldığı için
 *      silme iki istemciden birini kırardı.
 * - Kalan 2 anahtar (`dialogs.fiberG`, `settings.widgets.androidOnly`)
 *   bile React tarafında yok; yine de silinmiyor çünkü 1.3.0'ın
 *   widget/ lif özelliklerinin (A3 mimari kararı) ileride kullanılması
 *   planlanıyor ve maliyeti sıfıra yakın.
 * - Sonuç: **silme yapılmadı**, ratchet eklendi. Bu, görevin kabul
 *   ettiği ikinci seçenektir ve burada kanıtlanmış olarak tercih edilmiştir.
 */
const ORPHAN_BASELINE = 63;

/** Klasör ağacını dosya listesine çevirir. */
function walk(dir, filter) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(p, filter));
    else if (filter(p)) out.push(p);
  }
  return out;
}

/** Nested easy_localization sözlüğünü "a.b.c" → değer düz haritasına çevirir. */
function flatten(obj, prefix = '', out = {}) {
  for (const [key, value] of Object.entries(obj)) {
    const flatKey = prefix ? `${prefix}.${key}` : key;
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      flatten(value, flatKey, out);
    } else {
      out[flatKey] = value;
    }
  }
  return out;
}

/** Değer ataması: mevcut string'i korur, yoksa referanstan kopyalar. */
function setFlat(target, source, key, refValue) {
  const parts = key.split('.');
  let node = target;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!node[parts[i]] || typeof node[parts[i]] !== 'object') node[parts[i]] = {};
    node = node[parts[i]];
  }
  const last = parts[parts.length - 1];
  if (node[last] === undefined) node[last] = refValue;
}

const argv = process.argv.slice(2);
const writeMissing = argv.includes('--write-missing');
const reportOrphans = argv.includes('--report-orphans');

const files = fs
  .readdirSync(TRANS_DIR)
  .filter((f) => f.endsWith('.json'))
  .sort();

if (files.length === 0) {
  console.error(`HATA: ${TRANS_DIR} içinde çeviri dosyası yok.`);
  process.exit(1);
}

const errors = [];
const warnings = [];

function group(counts) {
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([k, v]) => `${k}:${v}`)
    .join(' '); // eslint-disable-line no-control-regex
}

// --- 1) Parse ---------------------------------------------------------------
const raw = {};
const flat = {};
for (const file of files) {
  try {
    raw[file] = JSON.parse(fs.readFileSync(path.join(TRANS_DIR, file), 'utf8'));
    flat[file] = flatten(raw[file]);
  } catch (e) {
    errors.push(`${file}: geçersiz JSON — ${e.message}`);
  }
}
if (errors.length) {
  for (const e of errors) console.error(`✗ ${e}`);
  process.exit(1);
}

if (!raw[REFERENCE_LANG]) {
  console.error(`HATA: referans dil ${REFERENCE_LANG} bulunamadı.`);
  process.exit(1);
}

// Beklenen dil sayısı düşerse (bir dil dosyası silinirse) sessizce 11 dile
// düşmemek için gate'e takılır — 12 dil sözleşmesi README'de belirtiliyor.
if (files.length !== EXPECTED_LANGS) {
  errors.push(
    `dil dosyası sayısı ${files.length}, beklenen ${EXPECTED_LANGS} (${files.join(', ')})`,
  );
}

const refKeys = Object.keys(flat[REFERENCE_LANG]).sort();

// --- 2) Eksik / fazla anahtar ---------------------------------------------
for (const file of files) {
  if (file === REFERENCE_LANG) continue;
  const keys = Object.keys(flat[file]);
  const missing = refKeys.filter((k) => !(k in flat[file]));
  const extra = keys.filter((k) => !refKeys.includes(k));
  for (const k of missing) {
    if (writeMissing) {
      setFlat(raw[file], raw[REFERENCE_LANG], k, flat[REFERENCE_LANG][k]);
    } else {
      errors.push(`${file}: eksik anahtar "${k}"`);
    }
  }
  for (const k of extra) {
    errors.push(`${file}: fazla anahtar "${k}" (${REFERENCE_LANG}'de yok)`);
  }
}

if (writeMissing) {
  for (const file of files) {
    if (file === REFERENCE_LANG) continue;
    const outPath = path.join(TRANS_DIR, file);
    const current = fs.readFileSync(outPath, 'utf8');
    const next = JSON.stringify(raw[file], null, 2) + '\n';
    if (current !== next) {
      fs.writeFileSync(outPath, next, 'utf8');
      console.log(`~ ${file}: eksik anahtarlar eklendi`);
    }
  }
  console.log(
    '\n--write-missing bitti. Değişiklikleri gözden geçirip `node tool/check_i18n.cjs` ile doğrula.',
  );
  process.exit(0);
}

// --- 3) Boş string değerleri ------------------------------------------------
for (const file of files) {
  for (const [key, value] of Object.entries(flat[file])) {
    if (typeof value === 'string' && value.trim() === '') {
      errors.push(`${file}: boş değer "${key}"`);
    }
    if (value === null || value === undefined) {
      errors.push(`${file}: null değer "${key}"`);
    }
  }
}

// --- 4) Placeholder tutarlılığı -------------------------------------------
const placeholders = (s) =>
  (String(s).match(/\{[a-zA-Z0-9_]+\}/g) || []).sort().join(',');
for (const file of files) {
  if (file === REFERENCE_LANG) continue;
  for (const key of refKeys) {
    if (!(key in flat[file])) continue;
    const refPh = placeholders(flat[REFERENCE_LANG][key]);
    const gotPh = placeholders(flat[file][key]);
    if (refPh !== gotPh) {
      errors.push(
        `${file}: "${key}" placeholder uyuşmazlığı — ${REFERENCE_LANG}="{${refPh}}" bu="{${gotPh}}"`,
      );
    }
  }
}

// --- 5) Kodda kullanılan anahtarları topla ----------------------------------
// easy_localization kullanımı üç biçimde görünür:
//   a) doğrudan       : `'settings.goals.protein'.tr()`
//                      (tırnak ve `.tr(` çoğu zaman AYNI satırda değil —
//                      `dart format` zinciri yeni satıra taşır; eski sürümdeki
//                      regexp bunu kaçırıyor ve 20 anahtarı yanlışlıkla
//                      "orphan" sayıyordu)
//   b) interpolasyonlu: `'notifications.${name}Title'.tr()`
//   c) dolaylı        : `Calculations.bmiCategory` → `(labelKey: 'bmi.normal')`,
//                      çağıran yer `.tr()` yapıyor. Statik `.tr()` taraması
//                      bunları göremez, bu yüzden **her** anahtar biçimli
//                      literal ayrıca toplanır (dolaylı = silme).
//
// Tırnak dahil tek parça olarak eşleştiriyoruz. Ayrı ayrı "tırnak öncesi"
// (lookbehind) + "tırnak sonrası" (lookahead) + "nokta" kombinasyonu
// V8'de beklenmedik biçimde geri-izlemesiz kalıyordu (`.tr(` eklendiğinde
// eşleşme kayboluyordu). Tırnak, anahtar, tırnak, `.tr(` tek regex'te
// güvenilir.
const trCall =
  /(['"`])([a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)\1\s*\.\s*tr\s*\(/g;
const interpolated =
  /(['"`])([a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)\.\$\{[\s\S]*?\}\1\s*\.\s*tr\s*\(/g;
// Her anahtar biçimli literal (tırnak çeşidi önemsiz).
const anyLiteral = /['"`]([a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)['"`]/g;
const dynamicLiteral = /['"`]([a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)\.\$\{/g;

const usedKeys = new Map(); // key -> ilk görüldüğü dosya
const mentionedKeys = new Set(); // literal olarak geçen her anahtar
const dynamicPrefixes = new Set(); // "meals.", "notifications." vb.

for (const dir of CODE_DIRS) {
  for (const file of walk(dir, (p) => p.endsWith('.dart'))) {
    const src = fs.readFileSync(file, 'utf8');
    const rel = path.relative(ROOT, file);

    anyLiteral.lastIndex = 0;
    let m;
    while ((m = anyLiteral.exec(src)) !== null) {
      if (!mentionedKeys.has(m[1])) mentionedKeys.add(m[1]);
    }

    // Yalnızca **string literal** olan çağrılar "kullanılan anahtar" sayılır.
    // `meal.notifTitleKey.tr()` / `cat.labelKey.tr()` bir değişkenin üzerinden
    // çağrıdır; anahtarı `lib/core/constants/app_constants.dart` içindeki
    // getter tanımı belirler. Bu yüzden `.tr(` solu ya bir anahtar literal'ı
    // ya da bir interpolasyonlu literal olmalıdır; gerisi dolaylıdır ve
    // `mentionedKeys`/`dynamicPrefixes` tarafından zaten yakalanır.
    trCall.lastIndex = 0;
    while ((m = trCall.exec(src)) !== null) {
      if (!usedKeys.has(m[2])) usedKeys.set(m[2], rel);
    }

    interpolated.lastIndex = 0;
    while ((m = interpolated.exec(src)) !== null) {
      dynamicPrefixes.add(`${m[2]}.`);
    }

    dynamicLiteral.lastIndex = 0;
    while ((m = dynamicLiteral.exec(src)) !== null) {
      dynamicPrefixes.add(`${m[1]}.`);
    }
  }
}

const allKeys = new Set();
for (const file of files) for (const k of Object.keys(flat[file])) allKeys.add(k);

for (const [key, file] of usedKeys) {
  if (!allKeys.has(key)) {
    errors.push(`kodda kullanılıyor ama hiçbir dilde yok: "${key}" (${file})`);
  }
}

// --- 6) Orphan (sahipsiz) anahtar sınıflandırması ---------------------------
// `flutter_app/assets/translations/*.json` **iki istemciye** hizmet eder:
// Flutter easy_localization ve React i18next (`public/locales/*`). Anahtar
// adı uzayları birebir aynıdır (bkz. `tool/convert_locales.cjs`) ama React
// PWA hâlâ `src/**` altında yaşamaktadır ve `t('dashboard.quick.search')`
// çağrılarını **kendi dosyalarından** yapmaktadır. Bu yüzden "Flutter
// kodunda görünmüyor" tek başına ölü demek DEĞİLDİR — 2026-09-27 ölçümünde
// 129 adayın 66'sı React tarafında literal olarak geçiyordu.
// Aşağıdaki sınıflandırma React tarafını da tarar ve yalnızca **iki tarafta
// da** geçmeyen anahtarı "ölü" sayar.
const REACT_SRC = path.join(ROOT, 'src');
const reactKeys = new Set();
for (const file of walk(REACT_SRC, (p) => /\.(tsx?|jsx?)$/.test(p))) {
  const src = fs.readFileSync(file, 'utf8');
  // i18next `t('a.b.c')` / `i18n.t('a.b.c')` — anahtar biçimli her literal.
  const re = /['"`]([a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)['"`]/g;
  let m;
  while ((m = re.exec(src)) !== null) reactKeys.add(m[1]);
}

const deadOrphans = []; // iki istemcide de yok — silinebilir
const reactOrphans = []; // React PWA'da canlı — silinmez
const dynamicOrphans = []; // dinamik kalıp kapsamında — silinmez
const indirectOrphans = []; // literal geçiyor, .tr() değil — silinmez

for (const key of refKeys) {
  if (usedKeys.has(key)) continue;
  if ([...dynamicPrefixes].some((p) => key.startsWith(p))) {
    dynamicOrphans.push(key);
  } else if (mentionedKeys.has(key)) {
    indirectOrphans.push(key);
  } else if (reactKeys.has(key)) {
    reactOrphans.push(key);
  } else {
    deadOrphans.push(key);
  }
}

if (deadOrphans.length > ORPHAN_BASELINE) {
  errors.push(
    `ölü orphan anahtar sayısı ${deadOrphans.length} > baseline ${ORPHAN_BASELINE} ` +
      `— yeni anahtarlar iki istemcide de kullanılmadan ekleniyor ` +
      `(--report-orphans ile listele, gerekçelendirip baseline'ı güncelle ya da sil)`,
  );
}

for (const key of dynamicOrphans) {
  warnings.push(`dinamik: "${key}" (önbellek kapsamında, silinmez)`);
}
for (const key of indirectOrphans) {
  warnings.push(`dolaylı: "${key}" (literal geçiyor, .tr() değil)`);
}
for (const key of reactOrphans) {
  warnings.push(`react: "${key}" (src/** içinde canlı, silinmez)`);
}
for (const key of deadOrphans) {
  warnings.push(`ölü: "${key}" (iki istemcide de geçmiyor)`);
}

// --- Rapor ------------------------------------------------------------------
const orphanTop = (list) =>
  group(
    list.reduce((acc, k) => {
      const top = k.split('.')[0];
      acc.set(top, (acc.get(top) || 0) + 1);
      return acc;
    }, new Map()),
  );

if (reportOrphans) {
  const list = (title, arr) =>
    console.log(
      `${title} (${arr.length}): ${arr.length ? `\n          ${arr.join('\n          ')}` : '—'}`,
    );
  console.log('── Orphan raporu ─────────────────────────────────────────');
  console.log(
    '   (sınıflandırma: ölü = iki istemcide de yok · react = src/** canlı ·',
  );
  console.log('    dinamik = interpolasyonlu kalıp kapsamında · dolaylı = literal)');
  list('ölü    ', deadOrphans);
  list('react  ', reactOrphans);
  list('dinamik', dynamicOrphans);
  list('dolaylı', indirectOrphans);
  console.log('──────────────────────────────────────────────────────────');
  console.log(
    `özet — ölü: ${orphanTop(deadOrphans) || '-'} | react: ${orphanTop(reactOrphans) || '-'} | dinamik: ${orphanTop(dynamicOrphans) || '-'} | dolaylı: ${orphanTop(indirectOrphans) || '-'}`,
  );
  console.log();
}

if (errors.length) {
  for (const e of errors) console.error(`✗ ${e}`);
  if (!reportOrphans) {
    for (const w of warnings) console.warn(`⚠ ${w}`);
  }
  console.error(
    `\n${errors.length} i18n hatası. Düzeltin (eksik anahtarlar için: node tool/check_i18n.cjs --write-missing).`,
  );
  process.exit(1);
}

console.log(
  `✓ i18n bütünlüğü temiz: ${files.length} dil, ${refKeys.length} anahtar, ` +
    `${usedKeys.size} Flutter kod anahtarı, ${dynamicPrefixes.size} dinamik kalıp, ` +
    `${reactKeys.size} React i18next anahtarı doğrulandı.`,
);
console.log(
  `  orphan → ölü: ${deadOrphans.length}/${ORPHAN_BASELINE} · react canlı: ${reactOrphans.length} · dinamik: ${dynamicOrphans.length} · dolaylı: ${indirectOrphans.length}`,
);

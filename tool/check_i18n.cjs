#!/usr/bin/env node
/**
 * Flutter i18n bütünlük denetleyicisi (`flutter_app/assets/translations`).
 *
 * Denetlenenler:
 *   1. Her dil dosyası geçerli JSON mu.
 *   2. `en.json` referans kabul edilir: diğer 11 dilde eksik/fazla anahtar.
 *   3. Boş string değerleri.
 *   4. easy_localization named placeholder tutarlılığı — `tr` ile `en`
 *      arasında `{foo}` kümesi farklıysa çalışma zamanında sessizce
 *      kaybolan metin parçası vardır.
 *   5. Uygulama kodunda (lib/**) `.tr()` ile kullanılan ama hiçbir dilde
 *      karşılığı olmayan anahtarlar.
 *   6. Hiçbir dilde karşılığı olmayan "sahipsiz" çeviri anahtarları
 *      (tasarım: uyarı, hata değil — ileride kullanılabilir).
 *
 * Çıkış kodu: tespit edilen HATA yoksa 0, varsa 1 (CI gate).
 *
 * Kullanım:
 *   node tool/check_i18n.cjs                 # sadece rapor (CI için)
 *   node tool/check_i18n.cjs --write-missing # eksik anahtarları en.json'dan kopyalar
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const TRANS_DIR = path.join(ROOT, 'flutter_app', 'assets', 'translations');
const LIB_DIR = path.join(ROOT, 'flutter_app', 'lib');
const REFERENCE_LANG = 'en.json';

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

const writeMissing = process.argv.includes('--write-missing');

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

// --- 5) Kodda kullanılan ama hiçbir dilde karşılığı olmayan anahtarlar -----
const allKeys = new Set();
for (const file of files) for (const k of Object.keys(flat[file])) allKeys.add(k);

const usedKeys = new Map();
// easy_localization kullanımı: 'a.b.c'.tr() — interpolasyonlu key'ler ayrıca ele alınır.
const trCall = /'([a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)'\.tr\s*\(/g;
const interpolated = /'([a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)\.\$\{[^}]+\}'\.tr\s*\(/g;
for (const file of walk(LIB_DIR, (p) => p.endsWith('.dart'))) {
  const src = fs.readFileSync(file, 'utf8');
  const rel = path.relative(ROOT, file);
  for (const re of [trCall, interpolated]) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(src)) !== null) {
      if (!usedKeys.has(m[1])) usedKeys.set(m[1], rel);
    }
  }
}
for (const [key, file] of usedKeys) {
  if (!allKeys.has(key)) {
    errors.push(`kodda kullanılıyor ama hiçbir dilde yok: "${key}" (${file})`);
  }
}

// --- 6) Sahipsiz anahtarlar ------------------------------------------------
for (const key of refKeys) {
  if (!usedKeys.has(key)) {
    warnings.push(`${REFERENCE_LANG}: "${key}" kodda kullanılmıyor`);
  }
}

// --- Rapor ------------------------------------------------------------------
for (const w of warnings) console.warn(`⚠ ${w}`);
if (errors.length) {
  for (const e of errors) console.error(`✗ ${e}`);
  console.error(
    `\n${errors.length} i18n hatası. Düzeltin (eksik anahtarlar için: node tool/check_i18n.cjs --write-missing).`,
  );
  process.exit(1);
}

console.log(
  `✓ i18n bütünlüğü temiz: ${files.length} dil, ${refKeys.length} anahtar, ` +
    `${usedKeys.size} kod anahtarı doğrulandı.`,
);

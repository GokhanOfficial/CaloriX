#!/usr/bin/env node
/**
 * Web (i18next) locale dosyalarını easy_localization formatına dönüştürür.
 *
 *   public/locales/<lang>/translation.json  ->  flutter_app/assets/translations/<lang>.json
 *
 * Dönüşümler:
 *   - i18next interpolasyonu  {{var}}  ->  {var}
 *   - nested anahtar yapısı korunur (easy_localization nested JSON destekler)
 *
 * Kullanım:  node tool/convert_locales.cjs            (tüm diller)
 *            node tool/convert_locales.cjs en tr      (seçili diller)
 *
 * DİKKAT: Bu script `flutter_app/assets/translations/*.json` dosyalarını
 * **üzerine yazar**. Kaynak `public/locales` (i18next) 360 anahtara sahipken
 * Flutter tarafı elle 457 anahtara kadar genişletildi; script'i çalıştırmak
 * 97 anahtarı sessizce siler. Yeni anahtar eklerken bu script'i değil
 * `node tool/check_i18n.cjs --write-missing` kullan.
 */
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'public', 'locales');
const DEST = path.join(__dirname, '..', 'flutter_app', 'assets', 'translations');

const args = process.argv.slice(2);
const langs = args.length
  ? args
  : fs.readdirSync(SRC).filter((d) => fs.existsSync(path.join(SRC, d, 'translation.json')));

/** obj içindeki tüm string değerlerde {{var}} -> {var} */
function convertInterpolation(value) {
  if (typeof value === 'string') {
    return value.replace(/\{\{\s*(\w+)\s*\}\}/g, '{$1}');
  }
  if (Array.isArray(value)) return value.map(convertInterpolation);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, convertInterpolation(v)]),
    );
  }
  return value;
}

fs.mkdirSync(DEST, { recursive: true });

let ok = 0;
for (const lang of langs) {
  const srcFile = path.join(SRC, lang, 'translation.json');
  if (!fs.existsSync(srcFile)) {
    console.warn(`⚠ ${lang}: translation.json bulunamadı, atlandı`);
    continue;
  }
  const raw = JSON.parse(fs.readFileSync(srcFile, 'utf8'));
  const converted = convertInterpolation(raw);
  const destFile = path.join(DEST, `${lang}.json`);
  fs.writeFileSync(destFile, JSON.stringify(converted, null, 2) + '\n', 'utf8');
  const keys = JSON.stringify(converted).match(/"/g)?.length ?? 0;
  console.log(`✓ ${lang} -> ${path.relative(process.cwd(), destFile)}`);
  ok++;
}
console.log(`\n${ok}/${langs.length} dil dönüştürüldü.`);

#!/usr/bin/env node
/**
 * Sürüm tutarlılığı denetleyicisi.
 *
 * Aynı sürüm bilgisi birden çok yerde tutuluyor ve zamanla ayrışıyor:
 *   - flutter_app/pubspec.yaml            → version: 1.3.0+4
 *   - AppConstants.appVersion             → data_transfer_repository,
 *                                           about_page, settings_page
 *   - CHANGELOG.md                        → başlık sürümü
 *   - README.md / README_EN.md            → kurulum / indirme notları
 *
 * Ayrışma = kullanıcıya yanlış sürüm gösterilir (About ekranı) ve veri
 * dışa aktarımı yanlış sürüm damgasıyla işaretlenir.
 *
 * Çıkış kodu: sapma varsa 1 (CI gate).
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

const errors = [];

// --- pubspec.yaml -----------------------------------------------------------
const pubspec = read('flutter_app/pubspec.yaml');
const versionLine = pubspec.match(/^version:\s*(\S+)/m);
if (!versionLine) {
  errors.push('flutter_app/pubspec.yaml: `version:` satırı bulunamadı');
}
const [pubspecVersion, pubspecBuild] = versionLine
  ? versionLine[1].split('+')
  : [null, null];
if (pubspecVersion && !/^\d+\.\d+\.\d+$/.test(pubspecVersion)) {
  errors.push(`pubspec version biçimsiz: "${pubspecVersion}" (X.Y.Z olmalı)`);
}
if (pubspecBuild && !/^\d+$/.test(pubspecBuild)) {
  errors.push(`pubspec build numarası biçimsiz: "${pubspecBuild}"`);
}

// --- AppConstants.appVersion ------------------------------------------------
const constants = read('flutter_app/lib/core/constants/app_constants.dart');
const appVersion = constants.match(/appVersion\s*=\s*'([^']+)'/);
if (!appVersion) {
  errors.push(
    'app_constants.dart: `appVersion` sabiti bulunamadı (derleme hatası)',
  );
} else if (appVersion[1] !== pubspecVersion) {
  errors.push(
    `AppConstants.appVersion = "${appVersion[1]}" ama pubspec version = "${pubspecVersion}"`,
  );
}

// --- CHANGELOG.md -----------------------------------------------------------
// Flutter sürüm başlıkları "## [flutter 1.2.1+3] - tarih" biçimindedir
// (React/web için ayrı "# Değişiklik Günlüğü" bölümü de vardır). En üstteki
// *flutter* başlığı referans sürümü verir.
const changelog = read('CHANGELOG.md');
const topVersion = changelog.match(
  /^##\s*\[(?:flutter\s+)?(\d+\.\d+\.\d+)(?:\+\d+)?\]/m,
);
if (!topVersion) {
  warnings('CHANGELOG.md: flutter sürüm başlığı bulunamadı (## [flutter X.Y.Z+N])');
} else if (topVersion[1] !== pubspecVersion) {
  errors.push(
    `CHANGELOG.md en üst flutter sürümü = ${topVersion[1]} ama pubspec = ${pubspecVersion}`,
  );
}

function warnings(msg) {
  console.warn(`⚠ ${msg}`);
}

// --- Rapor ------------------------------------------------------------------
if (errors.length) {
  for (const e of errors) console.error(`✗ ${e}`);
  console.error(`\n${errors.length} sürüm tutarsızlığı.`);
  process.exit(1);
}
console.log(
  `✓ Sürüm tutarlı: ${pubspecVersion}+${pubspecBuild} ` +
    `(pubspec = AppConstants = CHANGELOG).`,
);

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
  errors.push(
    'CHANGELOG.md: flutter sürüm başlığı bulunamadı (## [flutter X.Y.Z+N])',
  );
} else if (topVersion[1] !== pubspecVersion) {
  errors.push(
    `CHANGELOG.md en üst flutter sürümü = ${topVersion[1]} ama pubspec = ${pubspecVersion}`,
  );
}

// --- Varsayılan hedefler ↔ Calculations.macros tutarlılığı -----------------
// `AppConstants.defaultFat = 65`, `Calculations.macros(2000).fat = 67`
// (2000 * 0.30 / 9 = 66.67 → 67) idi. Profil yokken onboarding "2000 kcal"
// derken makro kartı 65 g yağ gösteriyordu — kullanıcıyı yanıltan, iki
// ekranda farklı sayı gösteren tutarsızlık (P1, Tur 1 bulgusu).
//
// `defaultProtein` (150 = 2000*0.30/4) zaten tutarlıydı; sapma yağdaydı
// (65 vs 67). Karbonhidrat oranı `Calculations.macros` içinde **0.40**
// (200 → 225 g arası bir fark yok; 2000*0.40/4 = 200 ✓).
const MACRO_SPLIT = { protein: 0.30, carbs: 0.40, fat: 0.30 };
const KCAL_PER_G = { protein: 4, carbs: 4, fat: 9 };

const caloriesConst = constants.match(/defaultCalories\s*=\s*(\d+)/);
if (!caloriesConst) {
  errors.push('app_constants.dart: `defaultCalories` sabiti bulunamadı');
} else {
  const kcal = Number(caloriesConst[1]);
  for (const [name, ratio] of Object.entries(MACRO_SPLIT)) {
    // Calculations.macros: (kcal * ratio / kcalPerG).round()
    const expected = Math.round((kcal * ratio) / KCAL_PER_G[name]);
    const m = constants.match(
      new RegExp(`default${name[0].toUpperCase()}${name.slice(1)}\\s*=\\s*(\\d+)`),
    );
    if (!m) {
      errors.push(`app_constants.dart: \`default${name}\` sabiti bulunamadı`);
    } else if (Number(m[1]) !== expected) {
      errors.push(
        `AppConstants.default${name[0].toUpperCase()}${name.slice(1)} = ${m[1]} ` +
          `ama Calculations.macros(${kcal}).${name} = ${expected} ` +
          `(${kcal} kcal × ${ratio} ÷ ${KCAL_PER_G[name]})`,
      );
    }
  }
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

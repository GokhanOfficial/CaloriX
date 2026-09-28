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
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

const errors = [];
const warnings = [];

/** Dosyayı okur; yoksa `null` döner (opsiyonel dosyalar için). */
const readOptional = (p) => {
  try {
    return fs.readFileSync(path.join(ROOT, p), 'utf8');
  } catch (_) {
    return null;
  }
};

const exists = (p) => fs.existsSync(path.join(ROOT, p));

/**
 * Bir kaynak dosyayı okur. `read` gibi **zorlayıcı** değildir: bulunamazsa
 * `''` döner (bileşen silinmiş olabilir).
 *
 * `readOptional` yalnız tam yol verilebildiğinde çalışır; burada dosya
 * adıyla aranır (`src/components/ui/macro-bar.tsx` gibi).
 */
const readAny = (name) => {
  const roots = [
    'src/components/ui',
    'src/components/dashboard',
    'src/components',
  ];
  for (const root of roots) {
    const full = readOptional(`${root}/${name}`);
    if (full !== null) return full;
  }
  return '';
};

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

// --- React PWA: src/lib/constants.ts ↔ Flutter ↔ hesap ----------------------
// İki istemci aynı veri modelini ve aynı varsayılan hedefleri paylaşıyor.
// `AppConstants.defaultFat` 65 → **67** düzeltildiğinde (A3, `be8158a`)
// React tarafı 65'te kaldı; `check_versions.cjs` o ana kadar yalnızca Flutter
// tarafını denetlediği için sapma **hiçbir araçla** yakalanmıyordu — kullanıcı
// PWA'da 65 g, uygulamada 67 g yağ hedefi görüyordu.
//
// `calculateMacros(2000).fat` = 2000 × 0.30 / 9 = 66.67 → **67** (her iki
// istemcide de). Bu yüzden `DEFAULT_GOALS.fat` de 67 olmalı.
const reactConstants = read('src/lib/constants.ts');
const reactFat = reactConstants.match(/DEFAULT_GOALS\s*=\s*\{([\s\S]*?)\}/);
if (!reactFat) {
  errors.push('src/lib/constants.ts: `DEFAULT_GOALS` nesnesi bulunamadı');
} else {
  const readField = (name) => {
    const m = reactFat[1].match(new RegExp(`${name}\\s*:\\s*(\\d+)`));
    return m ? Number(m[1]) : null;
  };
  const pair = [
    ['calories', 'defaultCalories'],
    ['protein', 'defaultProtein'],
    ['carbs', 'defaultCarbs'],
    ['fat', 'defaultFat'],
    ['water', 'defaultWater'],
  ];
  for (const [reactKey, flutterKey] of pair) {
    const got = readField(reactKey);
    if (got === null) {
      errors.push(`src/lib/constants.ts: DEFAULT_GOALS.${reactKey} alanı yok`);
      continue;
    }
    const fm = constants.match(
      new RegExp(`${flutterKey}\\s*=\\s*(\\d+)`),
    );
    if (!fm) {
      errors.push(`app_constants.dart: ${flutterKey} sabiti bulunamadı`);
    } else if (Number(fm[1]) !== got) {
      errors.push(
        `DEFAULT_GOALS.${reactKey} (web) = ${got} ama ` +
          `AppConstants.${flutterKey} (Flutter) = ${fm[1]} — ` +
          `iki istemci farklı varsayılan hedef gösteriyor`,
      );
    }
  }
}

// --- İki istemciden biri hesapladığında diğerinin sabitiyle uyuşmamalı ------
// Makro oranları `Calculations.macros` (Flutter) ve `calculateMacros`
// (React) içinde **ayrı ayrı** yazılı. Biri değişirse diğeri eski kalır ve
// `defaultFat/Protein/Carbs` kapısı yine sessizce geçer (çünkü sapma
// sabitler arasında değil, oranlarda olur).
const FLUTTER_MACRO = read(
  'flutter_app/lib/core/utils/calculations.dart',
);
const reactSplit = read('src/lib/calculations.ts');
const ratioOf = (src, re) => {
  const m = src.match(re);
  return m ? Number(m[1]) : null;
};

/**
 * `10_000` gibi sayısal ayraçlı sabitleri okur.
 * `ratioOf` `Number('10_000')` → `NaN` verir (JS'te sayısal ayraç yok).
 */
const numOf = (src, re) => {
  const m = src.match(re);
  if (!m) return null;
  const n = Number(String(m[1]).replace(/_/g, ''));
  return Number.isFinite(n) ? n : null;
};
/**
 * Flutter oranları ondalık (`0.30`), web yüzdeler (`30`). Karşılaştırma
 * öncesi **tek ölçüğe** indirgeniyor: ikisi de oran (0…1) olur.
 */
const asRatio = (v) => (v === null ? null : v > 1 ? v / 100 : v);
// Flutter: `static const double proteinRatio = 0.30;` (tek kaynak)
const fRatios = {
  protein: asRatio(ratioOf(FLUTTER_MACRO, /proteinRatio\s*=\s*([\d.]+)/)),
  carbs: asRatio(ratioOf(FLUTTER_MACRO, /carbsRatio\s*=\s*([\d.]+)/)),
  fat: asRatio(ratioOf(FLUTTER_MACRO, /fatRatio\s*=\s*([\d.]+)/)),
};
// React: oranlar artık **tek kaynakta** (`PROTEIN_PERCENT = 30` …) ve
// `calculateMacros` imzasında varsayılan olarak kullanılıyor
// (`proteinPercent = PROTEIN_PERCENT`). Daha önce imzada literal `30`
// yazılıydı; A5r8 oranları sabitlere taşıdı (yoksa `ratchet` gereksinimi
// üç ayrı yerde aynı sayı tutmak olurdu).
const rProtein = asRatio(ratioOf(reactSplit, /PROTEIN_PERCENT\s*=\s*([\d.]+)/));
const rCarbs = asRatio(ratioOf(reactSplit, /CARBS_PERCENT\s*=\s*([\d.]+)/));
const rFat = asRatio(ratioOf(reactSplit, /FAT_PERCENT\s*=\s*([\d.]+)/));
// Sabitler tanımlıysa `calculateMacros` gerçekten onları **kullanıyor** mu?
if (rProtein !== null && !/proteinPercent\s*=\s*PROTEIN_PERCENT/.test(reactSplit)) {
  errors.push(
    'src/lib/calculations.ts: `PROTEIN_PERCENT` tanımlı ama ' +
      '`calculateMacros` imzasında kullanılmıyor — sabit güncellenince ' +
      'hesap değişmez (ölü sabit)',
  );
}

// Oranlar toplamı 1.0 olmalı — yoksa hedef kalori ile makro kalorisi
// tutmaz ve dashboard'da "toplam" satırı tutarsız görünür.
for (const [label, set] of [['Flutter', fRatios], ['web', {
  protein: rProtein, carbs: rCarbs, fat: rFat,
}]]) {
  const vals = Object.values(set);
  if (vals.some((v) => v === null)) continue;
  const sum = vals.reduce((a, b) => a + b, 0);
  if (Math.abs(sum - 1) > 1e-9) {
    errors.push(
      `makro oranları toplamı 1.0 değil (${label}: ${sum}) — ` +
        `hedef kalori ile makro kalorisi tutmuyor`,
    );
  }
}

// Gram başına kalori (atwater) iki tarafta da 4/4/9 olmalı.
const ATWATER = { protein: 4, carbs: 4, fat: 9 };
for (const [name, expected] of Object.entries(ATWATER)) {
  const camel = name[0].toUpperCase() + name.slice(1);
  const fVal = ratioOf(
    FLUTTER_MACRO,
    new RegExp(`${name}KcalPerG\\s*=\\s*(\\d+)`),
  );
  // React: `Math.round(proteinCalories / 4)` — yorum satırı "4 kcal per gram"
  const rVal = ratioOf(reactSplit, new RegExp(`${name}Calories\\s*/\\s*(\\d+)`));
  if (fVal !== null && fVal !== expected) {
    errors.push(
      `Flutter ${name}KcalPerG = ${fVal} ama fizyolojik sabit ${expected}`,
    );
  }
  if (rVal !== null && rVal !== expected) {
    errors.push(
      `web ${name}Calories / ${rVal} — beklenen ${camel}KcalPerG ${expected}`,
    );
  }
}

for (const [name, fv, rv] of [
  ['protein', fRatios.protein, rProtein],
  ['carbs', fRatios.carbs, rCarbs],
  ['fat', fRatios.fat, rFat],
]) {
  if (fv === null || rv === null) {
    errors.push(
      `makro oranı okunamadı: ${name} (Flutter=${fv}, web=${rv}) — ` +
        `calculations.macros / calculateMacros imzası değişmiş olabilir`,
    );
  } else if (Math.abs(fv - rv) > 1e-9) {
    errors.push(
      `makro oranı ayrışmış: ${name} Flutter=${fv} web=${rv} — ` +
        `iki istemci farklı makro dağılımı hesaplıyor`,
    );
  }
}

// Aktivite çarpanları ve hedef modifikatörleri de iki istemcide ayrı yazılı.
//
// `ActivityLevel` (çarpan) ve `Goal` (modifikatör) enum'ları aynı sözdizimini
// paylaşır: `name(value),`. **Yalnız `enum X {` ile başlayan blok** alınır,
// aksi hâlde `MealType(1, '🌅')` gibi üç argümanlı girdiler de eşleşir.
function enumBody(src, name) {
  const m = src.match(new RegExp(`enum\\s+${name}\\s*\\{([\\s\\S]*?)\\n\\}`));
  return m ? m[1] : null;
}
const fActivityBody = enumBody(constants, 'ActivityLevel');
const fGoalBody = enumBody(constants, 'Goal');
if (!fActivityBody) errors.push('app_constants.dart: `enum ActivityLevel` bulunamadı');
if (!fGoalBody) errors.push('app_constants.dart: `enum Goal` bulunamadı');

const fLevels = {};
if (fActivityBody) {
  // Son girdi nokta ile biter: `veryActive(1.9);`
  const re = /^\s*(\w+)\(([\d.]+)\)[,;]\s*$/gm;
  let fl;
  while ((fl = re.exec(fActivityBody)) !== null) fLevels[fl[1]] = Number(fl[2]);
}
const rLevels = {};
const rBlock = reactConstants.match(
  /ACTIVITY_LEVELS\s*=\s*\{([\s\S]*?)\}\s*as const/,
);
if (rBlock) {
  const rRe = /(\w+)\s*:\s*\{[^}]*multiplier\s*:\s*([\d.]+)/g;
  let r;
  while ((r = rRe.exec(rBlock[1])) !== null) rLevels[r[1]] = Number(r[2]);
} else {
  errors.push('src/lib/constants.ts: `ACTIVITY_LEVELS` bloğu bulunamadı');
}
for (const [level, mult] of Object.entries(fLevels)) {
  if (!(level in rLevels)) {
    errors.push(
      `aktivite çarpanı eksik (web): ${level} (Flutter=${mult})`,
    );
  } else if (Math.abs(rLevels[level] - mult) > 1e-9) {
    errors.push(
      `aktivite çarpanı ayrışmış: ${level} Flutter=${mult} web=${rLevels[level]}`,
    );
  }
}
// Dart enum adı `veryActive`, React/DB anahtarı `very_active`; fark
// bilinçlidir (`activityLevelToDb` eşleyicisi). Bu yüzden web'de
// **fazladan** seviye, aynı çarpanı taşıyan bir Flutter seviyesine
// eşleniyorsa sapma sayılmaz — çünkü zaten karşılık vardır. Karşılığı
// olmayan seviye hatadır (activityLevelToDb tanımı da kontrol edilir).
// Dart enum adı `veryActive`, React/DB anahtarı `very_active`; fark
// bilinçlidir (`activityLevelToDb` eşleyicisi). Bu yüzden **isim** eşleşmesi
// yerine çarpan **değeri** eşleşmesi denetlenir: web'de `1.9` çarpanı
// varsa Flutter'da da `1.9` olmalı, tersi de. Eşleşmeyen bir çarpan
// yalnız bir tarafta kalmış demektir (yeni seviye eklendi, iki istemci
// güncellenmedi).
const fMultipliers = Object.values(fLevels);
for (const [level, mult] of Object.entries(rLevels)) {
  if (level in fLevels) continue;
  if (!fMultipliers.includes(mult)) {
    errors.push(
      `aktivite çarpanı fazladan (web): ${level} = ${mult} — ` +
        `ActivityLevel enum'unda aynı çarpanlı bir karşılığı yok`,
    );
  }
}
// `activityLevelToDb`/`activityLevelFromDb` eşleyicisi gerçekten var mı?
// Yoksa web tarafı `veryActive`'i DB'ye camelCase gönderir ve CHECK kısıtı
// patlar (A5'ın bulduğu, A2r2'nin Flutter'ta düzelttiği hata).
if (!/function\s+activityLevelToDb/.test(reactConstants)) {
  errors.push(
    'src/lib/constants.ts: `activityLevelToDb` eşleyicisi yok — ' +
      'camelCase aktivite seviyesi DB CHECK kısıtına takılır',
  );
}
if (!/function\s+activityLevelFromDb/.test(reactConstants)) {
  errors.push(
    'src/lib/constants.ts: `activityLevelFromDb` eşleyicisi yok — ' +
      'DB\'den okunan snake_case değer her zaman "moderate"\'a düşer',
  );
}

const fGoals = {};
if (fGoalBody) {
  // Son girdi nokta ile biter: `gain(500);`
  const re = /^\s*(\w+)\((-?\d+)\)[,;]\s*$/gm;
  let g;
  while ((g = re.exec(fGoalBody)) !== null) fGoals[g[1]] = Number(g[2]);
}
const rGoals = {};
// `GOALS` bloğu `GOALS = {...} as const;` ile biter ama düzenli ifade
// tembel olduğu için `}` ilk kapanışta durur. `calorieModifier` eşleşmesi
// zaten sadece `GOALS` girdilerinde bulunur, yine de blok sınırı
// `calorieModifier` satırından sonraki ilk `};`'a kadar uzatılır.
const rGoalBlock = reactConstants.match(
  /GOALS\s*=\s*\{([\s\S]*?calorieModifier[\s\S]*?)\}\s*as const/,
);
if (rGoalBlock) {
  const rgRe = /(\w+)\s*:\s*\{[^}]*calorieModifier\s*:\s*(-?\d+)/g;
  let rg;
  while ((rg = rgRe.exec(rGoalBlock[1])) !== null) {
    rGoals[rg[1]] = Number(rg[2]);
  }
} else {
  errors.push('src/lib/constants.ts: `GOALS` bloğu bulunamadı');
}
for (const [goal, mod] of Object.entries(fGoals)) {
  if (!(goal in rGoals)) {
    errors.push(`hedef modifikatörü eksik (web): ${goal} (Flutter=${mod})`);
  } else if (rGoals[goal] !== mod) {
    errors.push(
      `hedef modifikatörü ayrışmış: ${goal} Flutter=${mod} web=${rGoals[goal]}`,
    );
  }
}

// Minimum kalori tabanı da iki yerde yazılı (web: `MIN_TARGET_CALORIES`).
// Dart: `return value < 1200 ? 1200 : value;`
// Web: `return value < MIN_TARGET_CALORIES ? MIN_TARGET_CALORIES : value;`
const fFloor = FLUTTER_MACRO.match(/value\s*<\s*(\d+)\s*\?\s*(\d+)\s*:/);
// Web tabanı artık **adlandırılmış** sabitte (`MIN_TARGET_CALORIES = 1200`)
// ve `calculateTargetCalories` onu kullanıyor. İkisi de gerekiyor:
// sabit tanımlı ama kullanılmıyorsa kapı yanlış yeşil verir.
const rFloorConst = ratioOf(reactSplit, /MIN_TARGET_CALORIES\s*=\s*(\d+)/);
const rFloorUsed = /value\s*<\s*MIN_TARGET_CALORIES\s*\?/.test(reactSplit);
const rFloor = rFloorConst;
if (fFloor && rFloor !== null && Number(fFloor[2]) !== rFloor) {
  errors.push(
    `minimum kalori tabanı ayrışmış: Flutter=${fFloor[2]} web=${rFloor}`,
  );
}
if (rFloor !== null && !rFloorUsed) {
  errors.push(
    'src/lib/calculations.ts: `MIN_TARGET_CALORIES` tanımlı ama ' +
      '`calculateTargetCalories` kullanmıyor — taban ölü sabit',
  );
}

// --- Formül seviyesi denetim (Tur 8) ---------------------------------------
//
// Yukarıdaki kapılar **sabitleri** karşılaştırıyor. Asıl ayrışma riski
// sabitlerde değil, **formülün kendisinde**: BMR'ın cinsiyet sabiti
// (`+5` / `-161`), BMI'nin alt sınır kontrolü, yılın taban değeri vb.
// 8 turda Flutter tarafında düzeltilen hesap hatalarının bir kısmı
// (özellikle `Gender.other` 166 kcal farkı) yalnız **sabit** denetimiyle
// yakalanamazdı — aynı sabit, farklı dallarda kullanılıyordu.
//
// Aşağıdaki kapılar **davranış sözleşmesini** metinden okur ve iki tarafı
// karşılaştırır. Her biri "bu olmazsa iki istemci farklı sayı üretir" notuyla
// yazılmıştır.

// 1) BMR cinsiyet sabitleri — `Gender.other` farkının kaynağı.
//
// Dart: `final effective = gender == Gender.female ? base - 161 : base + 5;`
// Web (düzeltilmiş): `genderForBmr(gender) === 'male' ? 5 : -161` ve
// `genderForBmr`: `return gender === 'female' ? 'female' : 'male';`
//
// Sapma senaryosu: web tarafı `gender === 'male' ? +5 : -161` yazarsa
// `other` **kadın** formülüne düşer → 166 kcal fark (P1).
const fBmrF = ratioOf(FLUTTER_MACRO, /Gender\.female\s*\?\s*base\s*-\s*(\d+)/);
const fBmrM = ratioOf(FLUTTER_MACRO, /:\s*base\s*\+\s*(\d+)/);
// `fBmrF` regex'i `−161` **mutlak** değerini yakalar (`\d+` işareti
// yutmaz) → fark hesabında işareti geri koy.
const fBmrFemale = fBmrF === null ? null : -Math.abs(fBmrF);
// Web: `+ (genderForBmr(gender) === 'male' ? 5 : -161)`
const rBmrBranch = reactSplit.match(
  /===\s*'male'\s*\?\s*(\d+)\s*:\s*-\s*(\d+)/,
);
const rBmrM = rBmrBranch ? Number(rBmrBranch[1]) : null;
const rBmrF = rBmrBranch ? -Number(rBmrBranch[2]) : null;
const rGenderRule = reactSplit.match(
  /function\s+genderForBmr[\s\S]{0,400}?===\s*'female'\s*\?\s*'female'\s*:\s*'male'/,
);

if (fBmrF === null || fBmrM === null) {
  errors.push(
    'calculations.dart: BMR cinsiyet sabitleri okunamadı ' +
      `(kadın -${fBmrF}, erkek +${fBmrM}) — formül imzası değişmiş olabilir`,
  );
}
if (rBmrF === null || rBmrM === null) {
  errors.push(
    'src/lib/calculations.ts: BMR cinsiyet sabitleri okunamadı ' +
      `(erkek +${rBmrM}, kadın ${rBmrF})`,
  );
}
if (fBmrF !== null && fBmrM !== null && rBmrF !== null && rBmrM !== null) {
  if (fBmrFemale !== rBmrF || fBmrM !== rBmrM) {
    errors.push(
      `BMR cinsiyet sabiti ayrışmış: Flutter erkek +${fBmrM}/kadın ${fBmrFemale} · ` +
        `web erkek +${rBmrM}/kadın ${rBmrF}`,
    );
  }
  // Fark `erkek − kadın` = `(+5) − (−161)` = 166 kcal.
  const genderGap = fBmrM - fBmrFemale;
  if (genderGap !== 166) {
    warnings.push(
      `Mifflin-St Jeor cinsiyet farkı ${genderGap} kcal (klasik: 166) — ` +
        'formül kasıtlı olarak değiştirildiyse bu bir ürün kararıdır',
    );
  }
}

// `other` kuralı: Dart'ta **ternary** (`female ? A : B`), web'de
// `genderForBmr` **fonksiyonu** üzerinden. Web'de kural kaybolursa
// (`function genderForBmr` silinir veya `male`'e çevrilirse) `other`
// sessizce kadın tarafına düşer.
if (!rGenderRule) {
  errors.push(
    "src/lib/calculations.ts: `genderForBmr` kuralı yok veya değişmiş — " +
      "'other'/null cinsiyet KADIN formülüne düşer " +
      `(Flutter'da erkek formülüne düşüyor; 166 kcal fark)`,
  );
}

// 2) BMI alt sınırı — negatif kilo/boy reddi.
//
// Dart (A3r6 düzeltmesi): `if (!heightCm.isFinite || heightCm <= 0) return 0;`
//                         `if (!weightKg.isFinite) return 0;`  ← **ağırlık ≤ 0 YOK**
// Web (düzeltilmiş):    `if (!Number.isFinite(weightKg) || weightKg <= 0) return 0;`
//
// Ağırlık kontrolü web'de **daha katı**. Bu kasıtlı: Dart'ın
// `bmi(70, -180) = 24.2` hatasını (kare pozitif) web'de kapatıyor.
// Ayrışma **kabul edilir** ama kaydedilir ki bir sonraki tur "parite
// bozuldu" sanıp geri almasın.
const fBmiWeightGuard = /if\s*\(!weightKg\.isFinite\s*\|\|\s*weightKg\s*<=\s*0\)/.test(
  FLUTTER_MACRO,
);
const rBmiWeightGuard = /if\s*\(!Number\.isFinite\(weightKg\)\s*\|\|\s*weightKg\s*<=\s*0\)/.test(
  reactSplit,
);
if (fBmiWeightGuard !== rBmiWeightGuard) {
  warnings.push(
    'BMI ağırlık alt sınırı iki tarafta farklı: ' +
      `Dart ${fBmiWeightGuard ? 'weightKg <= 0 → 0' : 'yalnız isFinite kontrolü'} · ` +
      `web ${rBmiWeightGuard ? 'weightKg <= 0 → 0' : 'yalnız isFinite kontrolü'}. ` +
      'Dart tarafındaki eksik kontrol `bmi(70, -180) = 24.2` hatasını ' +
      'üretiyor (bkz. TRANSFER-defteri T6).',
  );
}
if (!rBmiWeightGuard) {
  errors.push(
    'src/lib/calculations.ts: `calculateBMI` negatif ağırlığı reddetmiyor — ' +
      'kare pozitif olduğu için imkânsız kayıt "normal BMI" görünür',
  );
}

// 3) Su hedefi çarpanı — `kg * 33` iki tarafta ayrı ayrı yazılı.
//
// Dart: `(weightKg * 33).round()`; Web: `Math.round(weightKg * 33)`.
const fWaterMult = ratioOf(FLUTTER_MACRO, /weightKg\s*\*\s*([\d.]+)\)\.round/);
const rWaterMult = ratioOf(reactSplit, /weightKg\s*\*\s*([\d.]+)\)/);
if (fWaterMult === null || rWaterMult === null) {
  errors.push(
    'su hedefi çarpanı okunamadı ' +
      `(Flutter=${fWaterMult}, web=${rWaterMult}) — waterTargetMl imzası değişmiş`,
  );
} else if (Math.abs(fWaterMult - rWaterMult) > 1e-9) {
  errors.push(
    `su hedefi çarpanı ayrışmış: Flutter=${fWaterMult} ml/kg web=${rWaterMult} ml/kg`,
  );
}

// 4) Yıl tabanı ve üst sınır — `calculateAge` / `Calculations.age`.
//
// Dart: `maxAge = 120` ve `if (years > maxAge) return maxAge;`
// Web:  `MAX_AGE = 120` ve `Math.min(age, MAX_AGE)`.
const fMaxAge = ratioOf(FLUTTER_MACRO, /maxAge\s*=\s*(\d+)/);
const rMaxAge = ratioOf(reactSplit, /MAX_AGE\s*=\s*(\d+)/);
if (fMaxAge === null || rMaxAge === null) {
  errors.push(
    `yaş üst sınırı okunamadı (Flutter=${fMaxAge}, web=${rMaxAge})`,
  );
} else if (fMaxAge !== rMaxAge) {
  errors.push(
    `yaş üst sınırı ayrışmış: Flutter=${fMaxAge} web=${rMaxAge} — ` +
      '1800 doğum yılı gibi bir kayıt BMR\'yi çarpık değerlere sürükler',
  );
}

// `maxAge` **kullanılıyor mu?** Sabit tanımlı ama hiç uygulanmıyorsa
// yine de ayrışma vardır (web'de üst sınır uygulanmıyordu).
const fAgeClamp = /years\s*>\s*maxAge/.test(FLUTTER_MACRO);
const rAgeClamp = /Math\.min\(\s*age\s*,\s*MAX_AGE\s*\)/.test(reactSplit);
if (fAgeClamp !== rAgeClamp) {
  errors.push(
    'yaş üst sınırı **uygulanmıyor** (sabit tanımlı ama kırpma yok): ' +
      `Dart=${fAgeClamp ? 'var' : 'yok'} web=${rAgeClamp ? 'var' : 'yok'}`,
  );
}

// 5) Öğün miktarı üst sınırı — DB CHECK ile iki istemci aynı sınırlı mı?
//
// DB: `meal_entries.amount_g_ml > 0 AND amount_g_ml <= 10000`
// Web (Tur 8): `MAX_MEAL_AMOUNT = 10_000` + `isUsableAmount`
// Flutter: repository katmanında (bu kapı metinden okuyamaz — kapsam dışı).
const rMealMax = numOf(reactSplit, /MAX_MEAL_AMOUNT\s*=\s*([\d_]+)/);
if (rMealMax === null) {
  warnings.push(
    'src/lib/calculations.ts: `MAX_MEAL_AMOUNT` bulunamadı — miktar üst ' +
      'sınırı sözleşmesi (DB CHECK: ≤ 10000) kilitlenemiyor',
  );
} else if (rMealMax !== 10000) {
  errors.push(
    `öğün miktarı üst sınırı DB CHECK ile ayrışmış: web=${rMealMax} ` +
      'DB kabul ediyor: 10000',
  );
}
if (!/function\s+isUsableAmount/.test(reactSplit)) {
  errors.push(
    'src/lib/calculations.ts: `isUsableAmount` yok — üç yol (elle ekleme, ' +
      'düzenleme, AI tanıma) miktar doğrulamasını atlıyor',
  );
}

// 6) İlerleme yüzdesi — Flutter `Calculations.progress` zaten korumalı,
// web'de **hiç kullanılmıyordu** (bileşenler kendi bölmesini yapıyordu).
const fProgressGuard = /if\s*\(!target\.isFinite\s*\|\|\s*target\s*==\s*0\)/.test(
  FLUTTER_MACRO,
);
const rProgressGuard = /!Number\.isFinite\(target\)[\s\S]{0,80}?target\s*<=\s*0/.test(
  reactSplit,
);
if (!fProgressGuard || !rProgressGuard) {
  errors.push(
    'ilerleme yüzdesi sıfıra bölme koruması eksik: ' +
      `Flutter=${fProgressGuard ? 'var' : 'yok'} web=${rProgressGuard ? 'var' : 'yok'} ` +
      '— hedef 0 iken çubuk ya hiç çizilmiyor ya da tamamen dolu görünüyor',
  );
}
// Koruma `calculateProgress` içindeyse, **bileşenler** de onu kullanmalı;
// yoksa fonksiyon ölü kod ve koruma işe yaramıyor (Tur 8'deki hatanın
// tam kendisi).
// Koruma `calculateProgress` içindeyse, **bileşenler** de onu kullanmalı;
// yoksa fonksiyon ölü kod ve koruma işe yaramıyor. Tur 8'deki hatanın
// tam kendisi: `calculateProgress` 3 katmanlı savunma yapıyordu ama
// **hiçbir bileşen onu çağırmıyordu** — üç bileşen kendi bölmesini
// yapıyordu. Bu yüzden kapı "en az 2" değil **"hepsi"** ister.
//
// Yorum satırları **temizlenir** ve **çağrı** aranır (import yeterli
// değil): bileşenlerin açıklamaları `calculateProgress` kelimesini
// geçiriyor, yalın `includes()` çağrısı yorumu "kullanım" sanar; import
// satırı ise çağrı **kaldırıldığında** da dosyada kalır (ölü import).
// 2026-09-28'de ikisi de ölçüldü.
const stripComments = (src) =>
  src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^[ \t]*\/\/.*$/gm, '');

const PROGRESS_CONSUMERS = [
  ['macro-bar.tsx', 'src/components/ui'],
  ['circular-progress.tsx', 'src/components/ui'],
  ['WaterTracker.tsx', 'src/components/dashboard'],
];
const usesProgress = ([f, root]) => {
  const raw = readOptional(`${root}/${f}`);
  if (!raw) return false;
  const code = stripComments(raw)
    .replace(/^\s*import[\s\S]*?;\s*$/gm, '')
    .replace(/from\s+["'][^"']+["'];?/g, '');
  return /\bcalculateProgress\s*\(/.test(code);
};
const usersOfProgress = PROGRESS_CONSUMERS.filter(usesProgress);
if (usersOfProgress.length < PROGRESS_CONSUMERS.length) {
  const missing = PROGRESS_CONSUMERS.filter((c) => !usesProgress(c)).map(([f]) => f);
  errors.push(
    '`calculateProgress` var ama ' + missing.join(', ') + ' **çağırmıyor** — ' +
      'sıfıra bölme koruması bu bileşenlerde etkisiz ' +
      '(hedef 0 iken çubuk kaybolur ya da tamamen dolar)',
  );
}

// --- package.json (React) sürümü -------------------------------------------
// React PWA'nın `APP_VERSION = '1.1.0'` sabiti (src/lib/constants.ts)
// `package.json` ile **bağımsız** ilerliyor. İkisi ayrışırsa About ekranı ile
// veri dışa aktarımı farklı sürüm damgası üretir (`useDataExport` version
// damgası). İkisinin en azından `package.json` ile uyuşması gerekiyor.
const pkg = JSON.parse(read('package.json'));
const reactAppVersion = reactConstants.match(/APP_VERSION\s*=\s*'([^']+)'/);
if (!reactAppVersion) {
  errors.push("src/lib/constants.ts: `APP_VERSION` sabiti bulunamadı");
} else if (reactAppVersion[1] !== pkg.version) {
  errors.push(
    `src/lib/constants.ts APP_VERSION = "${reactAppVersion[1]}" ama ` +
      `package.json version = "${pkg.version}"`,
  );
}

// --- Android: local.properties sürüm bayatlığı ---------------------------
// `flutter.versionName` / `flutter.versionCode` **Gradle'in kalıcı kaynağı**
// değildir: Flutter Gradle plugin'i `pubspec.yaml`'i okuyup
// `local.properties`'e **yazar**. Bu yüzden buradaki fark bir hata değil
// normal davranıştır (dosya `.gitignore`'da, CI'da yeniden üretilir).
//
// Yine de kontrol ediliyor: dosya repoda **izleniyorsa** bayat bir değer
// "kalıcı kaynak" gibi görünür ve geliştiriciyi yanıltır; `flutter.versionCode`
// de pubspec build numarasından farklıysa zorunlu güncelleme kararı
// (`minSupportedVersionCode`) cihazda yanlış sonuç verir.
const localProps = readOptional('flutter_app/android/local.properties');
if (localProps) {
  const tracked = (() => {
    try {
      return execFileSync('git', ['ls-files', '--error-unmatch',
        'flutter_app/android/local.properties'],
      { cwd: ROOT, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim() !== '';
    } catch (_) {
      return false;
    }
  })();
  const lpVersion = localProps.match(/^flutter\.versionName=(.*)$/m);
  const lpCode = localProps.match(/^flutter\.versionCode=(\d+)\s*$/m);
  if (!lpVersion) {
    errors.push(
      'flutter_app/android/local.properties: `flutter.versionName` yok ' +
        '(Gradle `versionName = flutter.versionName` boş kalır)',
    );
  } else {
    const value = lpVersion[1].trim();
    if (value !== pubspecVersion) {
      const msg =
        `flutter.versionName = "${value}" ama pubspec version = "${pubspecVersion}"`;
      // İzlenen dosyada bayatlık **hata** (kalıcı kaynak izlenimi);
      // yerel/üretilen dosyada uyarı beklenen davranıştır.
      (tracked ? errors : warnings).push(
        `flutter_app/android/local.properties: ${msg}` +
        (tracked
          ? ' — dosya repoda izleniyor, bayat değer kalıcı kaynak gibi görünüyor'
          : ' — normal: Flutter Gradle plugin pubspec\'i okuyup bu dosyayı yeniden yazar'),
      );
    }
  }
  if (!lpCode) {
    errors.push(
      'flutter_app/android/local.properties: `flutter.versionCode` yok ' +
        '(Gradle `versionCode = flutter.versionCode` boş kalır)',
    );
  } else if (pubspecBuild && Number(lpCode[1]) !== Number(pubspecBuild)) {
    (tracked ? errors : warnings).push(
      `flutter_app/android/local.properties: flutter.versionCode = ${lpCode[1]} ` +
        `ama pubspec build = ${pubspecBuild}`,
    );
  }
} else {
  warnings.push(
    'flutter_app/android/local.properties yok — normal (Flutter `flutter build` ' +
      'ilk çalıştırmada üretir; gradle `flutter.versionName` kaynağı pubspec.yaml)',
  );
}

// --- Release script'i ↔ pubspec -------------------------------------------
// `tool/release_android.sh` sürümü `pubspec.yaml`'den okur; ek olarak
// `CHANGELOG.md`'ye ve `AppConstants`'a dokunmadığı için bu kapı gerekir.
const releaseScript = read('tool/release_android.sh');
if (!/pubspec\.yaml/.test(releaseScript)) {
  errors.push(
    'tool/release_android.sh: sürümü `pubspec.yaml`\'den okumuyor — ' +
      'elle gömülü bir sürüm kaynakla ayrışabilir',
  );
}
// Kullanıcıya gösterilen yayın notu bayatı: script `--min-code` ile
// zorunlu güncelleme eşiğini ayarlar; `CHANGELOG`'daki yayın talimatı
// pubspec ile aynı örneği vermeli.
const readmePublish = read('README.md');
const readmeExample = readmePublish.match(/version:\s*(\d+\.\d+\.\d+\+\d+)/);
if (!readmeExample) {
  errors.push(
    'README.md: yayınlama talimatında `version: X.Y.Z+N` örneği yok',
  );
} else if (readmeExample[1] !== versionLine[1]) {
  errors.push(
    `README.md yayın talimatı "version: ${readmeExample[1]}" yazıyor ama ` +
      `pubspec "${versionLine[1]}" — talimatı kopyalayan geliştirici ` +
      `yanlış sürümle release yapar`,
  );
}

// --- Rapor ------------------------------------------------------------------
if (warnings.length) {
  for (const w of warnings) console.warn(`⚠ ${w}`);
}
if (errors.length) {
  for (const e of errors) console.error(`✗ ${e}`);
  console.error(`\n${errors.length} sürüm/sabit tutarsızlığı.`);
  process.exit(1);
}
console.log(
  `✓ Sürüm tutarlı: ${pubspecVersion}+${pubspecBuild} ` +
    `(pubspec = AppConstants = CHANGELOG = README) · ` +
    `web ${pkg.version} (package.json = APP_VERSION) · ` +
    `varsayılan hedefler ve makro oranları iki istemcide aynı.`,
);

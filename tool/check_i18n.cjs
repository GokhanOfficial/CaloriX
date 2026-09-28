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
 *   4b. Placeholder **sızıntısı**: değer içinde Dart interpolasyonu
 *      (`${...}`) — kullanıcıya ham metin olarak gösterilir.
 *   4c. **Placeholder ayracı**: boşluk ayıran dillerde (`tr`, `en`, `de`, …)
 *      `{min}до` gibi yapışık kullanım okunabilirliği bozar. CJK diller
 *      bu kurala tabi değildir (`{min}から{max}` doğru yazımdır).
 *   4d. **RTL sızıntısı** (`ar.json`): Arapça metinde kalan İngilizce
 *      cümle ve ASCII satır sonu noktalaması. Ölçüm (2026-09-28): 461
 *      anahtar tarandı, **1 gerçek unutulmuş çeviri** bulundu —
 *      `dashboard.remaining` = `"kcal متبقية"` (İngilizce "remaining kcal"
 *      harf harfine bırakılmış) → düzeltildi. Parantez (`(kcal)`) ve
 *      `...` kısaltması kasıtlı olduğundan yalnızca uyarı üretir.
 *   4e. **Tarih/sayı biçimi**: `DateFormat(...)` / `NumberFormat(...)`
 *      çağrıları locale'sizse ya da sabit bir dile bağlıysa hata
 *      (aktif kullanıcı dilini yok sayarlar). `yyyy-MM-dd` **veritabanına
 *      yazılan** makine biçimi olduğu için bağlam denetimiyle istisna;
 *      aynı desen **kullanıcıya gösterilen** bir tarihte hata.
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
 *   node tool/check_i18n.cjs --verbose           # RTL/format uyarı listesi
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
//
// easy_localization `{ad}` placeholder'ları `String.format` benzeri bir
// dönüşümle ikame eder. En yaygın sessiz çeviri hatası: bir dilde
// `{min}`/`{max}` yazıp diğerinde `{min}` unutmak → metnin ortasında
// **"{max}"** ya da `{min} ile {max} kg` içinde **boşluk** kalır.
//
// Bu kontrol 2026-09-27'den önce **hiç yoktu**; `onboarding.errAgeRange`
// gibi çoklu-placeholder anahtarları 12 dilde farklı sayıda placeholder
// taşıyabiliyordu ve fark edilmiyordu. Ayrıca iki sınıf daha denetleniyor:
//
//   a) **Ekstranın tamamı placeholder** — `{ad}` kullanıcının girdiği
//      serbest metin olabilir ama `{count}`/`{amount}` sayısal olmalı; yine de
//      `{name}` tek başına bir değer olarak anlamsızsa en azından `tr` ile
//      aynı küme olmalı (aşağıdaki denetim bunu zaten garanti ediyor).
//   b) **Sıra farkı** — `{a} {b}` ↔ `{b} {a}`: bazı diller (Arapça, Japonca)
//      özneyi nesneden önce söyler, ama placeholder kümesi aynı kaldığı için
//      ikame bozulmaz. Bu yüzden **küme** karşılaştırılır, sıra değil.
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

// --- 4b) Placeholder sızması (ters yön) ------------------------------------
// `${...}` Dart interpolasyonu bir çeviri değeri içinde geçerse
// (`"Merhaba ${name}"`) easy_localization o metni olduğu gibi basar ve
// kullanıcı `${name}` görür. Ayrıca easy_localization'ın `{}` sözdizimi
// Dart'ın kendi `$` interpolasyonuyla karışır; JSON'da `$` geçen değer
// yaygın bir tuzak.
for (const file of files) {
  for (const [key, value] of Object.entries(flat[file])) {
    if (typeof value !== 'string') continue;
    if (value.includes('${')) {
      errors.push(
        `${file}: "${key}" Dart interpolasyonu (\${...}) içeriyor — ` +
          `kullanıcıya ham metin olarak gösterilir`,
      );
    }
  }
}

// --- 4c) Placeholder ayracı (boşluk dili) ----------------------------------
// Boşlukla ayrılan dillerde (Latin, Kıbrıs, Yunanca) placeholder'ın
// ardından/öncesinde **boşluk ya da noktalama** olmalıdır. Atlanırsa
// metin `{min}до {max}` gibi yapışık okunur — `{min}` kaybolmaz ama
// okunabilirliği bozulur ve bazı yerelleştirme motorlarında ikame de
// karışır.
//
// CJK (zh/ja/ko) ve boşluk kullanmayan dillerde bu kural **geçerli
// değildir** (`{min}から{max}` doğru yazımdır), bu yüzden dil bazında
// uygulanır. Arapça/Farsça/İbranice kelimeleri boşlukla ayırır ama
// noktalama çeşidi farklıdır; onlar için Latin benzeri ayraç aranır.
const SPACE_SEPARATED = new Set([
  'tr.json', 'en.json', 'de.json', 'fr.json', 'es.json', 'it.json',
  'pt.json', 'ru.json', 'nl.json', 'pl.json', 'sv.json',
]);
// Bir placeholder'ın hemen ardından/öncesinde kabul edilen ayraçlar.
// Harf/rakam **değildir**; ideografik semboller de (→, ~, |) kabul edilir.
const GLUE_AFTER = /[\s,.;:!?()[\]{}\-–—/\\|·•~<>«»„"“”'’…؟،؛]/;
const GLUE_BEFORE = /[\s,.;:!?()[\]{}\-–—/\\|·•~<>«»„"“”'’…؟،؛]/;
for (const file of files) {
  if (!SPACE_SEPARATED.has(file)) continue;
  for (const [key, value] of Object.entries(flat[file])) {
    if (typeof value !== 'string') continue;
    const found = value.match(/\{[a-zA-Z0-9_]+\}/g) || [];
    if (found.length < 2) continue;
    for (const ph of new Set(found)) {
      const idx = value.indexOf(ph);
      const after = value[idx + ph.length];
      const before = idx > 0 ? value[idx - 1] : undefined;
      const bad = [];
      if (after !== undefined && !GLUE_AFTER.test(after)) bad.push(`"${ph}${after}"`);
      if (before !== undefined && !GLUE_BEFORE.test(before)) bad.push(`"${before}${ph}"`);
      if (bad.length) {
        errors.push(
          `${file}: "${key}" placeholder yapışık — ${bad.join(', ')}; ` +
            `boşluk ayıran dillerde ayraç (boşluk/kesme) gerekli`,
        );
      }
    }
  }
}

// --- 4d) RTL sızıntısı (Arapça) --------------------------------------------
// Arapça metinlerde LTR varsayılanının sızdığı üç örnek denetleniyor:
//   1. **Satır sonu noktalama** — ASCII `.` `!` `?` `:` `;` Arapçada
//      noktalama değildir (doğrusu `؟` `،` `؛`). Üç noktalı `...` ise
//      **beklenen** kısaltma işaretidir (bkz. `common.loading`:
//      `'جار التحميل...'`), sadece gerçek cümle noktası hata sayılır.
//   2. **Cümle sonu parantez** — `... (kcal)` kalıbı. Birim/marka
//      parantezi (`(kcal)`, `(g)`, `(مل)`, `(أيام)`) **doğru** kullanımdır
//      (Arapçada parantez yönü sağdan sola akar); LTR sızıntısı değildir.
//   3. **Harf girdisi olmayan metin** — İngilizce marka/birim (`kcal`,
//      `CaloriX`, `g`) kasıtlıdır ama **cümle** düzeyinde kalan metin
//      çeviri eksikliğidir.
//
// ### Neden yalnızca 1 ve 3 hata, 2 uyarı?
// 2026-09-28 ölçümü: 461 anahtarın tamamı incelendi. Bulunan ASCII noktalama
// ve parantez kullanımlarının **tamamı** kasıtlıydı — `...` kısaltması,
// `!` ünlem, `kcal`/`g` birim parantezi. Bu yüzden parantez denetimi
// **hata değil uyarı** üretir: gerçek bir LTR sızıntısı olduğunda (ör.
// `这是 (test)` tipi karışık metin) gözle görülebilir ama kapıyı kırmaz.
const RTL_LANGS = ['ar.json'];
/** Noktanın noktalama değil, parçası olduğu bağlamlar. */
const DOT_OK = [
  /\d\.\d/, // 1.3 sürüm, ondalık sayı
  /\.[A-Za-z]{2,4}\b/, // .apk, .json, .com uzantıları
  /https?:\/\//,
  /@[a-z]/i, // e-posta
  /\.{3}/, // kısaltma "..." (yaygın ve doğru)
];
for (const file of files) {
  if (!RTL_LANGS.includes(file)) continue;
  for (const [key, value] of Object.entries(flat[file])) {
    if (typeof value !== 'string' || value.trim() === '') continue;
    // 3) **Sözdizimi sızıntısı**: metin, hedef alfabesine ait olmayan bir
    //    *kelimeyle* başlıyorsa ya da içinde hiç hedef alfabesinden harf
    //    yoksa çeviri eksiktir.
    //
    //    Ölçüm (2026-09-28): `dashboard.remaining` = `"kcal متبقية"` —
    //    İngilizce "remaining kcal" kalıbı harf harfine bırakılmıştı
    //    (`tr: "kalan kcal"`, `en: "remaining kcal"`). Kullanıcı Arapçada
    //    "kcal kaldı" yerine "kcal mتبقية" görüyordu.
    //
    //    Marka/birim olarak bilinen İngilizce kelimeler istisnadır:
    //    `CaloriX` (ürün adı), `PWA`. Bunlar cümleye başlık olarak da
    //    kabul edilir (`"CaloriX {version} جاهز."` doğru bir cümledir).
    //    Birimler (`kcal`) yalnızca **hedef alfabe bulunmadığında** ve
    //    metin birim dışında hiçbir şey içermiyorsa kabul edilir
    //    (`"kcal"` gibi tek kelimelik etiketler).
    const ARABIC = /[\u0600-\u06FF]/;
    const hasArabic = ARABIC.test(value);
    const firstWord = value.trim().split(/\s+/)[0] || '';
    const leadingToken = firstWord.replace(/[.,!?:;،؛؟]+$/, '');
    if (!hasArabic) {
      // Hiç Arapça harfi yok: yalnızca marka/birim etiketi kabul edilir.
      const pureLabel = /^(CaloriX|PWA|kcal|Kcal|KCAL|ml|mL|API)$/.test(leadingToken);
      if (!pureLabel) {
        errors.push(
          `${file}: "${key}" Arapça alfabe içermiyor — çeviri eksik: ` +
            `${JSON.stringify(value.slice(0, 40))}`,
        );
      }
    } else if (ARABIC.test(leadingToken)) {
      // Arapça metinde ASCII **noktalama** değil, Latin harfiyle başlayan
      // kelime: hedef dilin başında yabancı kelime kalmış demektir
      // (marka/birim istisnası yukarıda).
      if (/^[A-Za-z][A-Za-z0-9.]*$/.test(leadingToken)) {
        const latinOk = new Set(['CaloriX', 'PWA']);
        if (!latinOk.has(leadingToken)) {
          errors.push(
            `${file}: "${key}" Latin kelimeyle başlıyor ("${leadingToken}") — ` +
              `Arapça çeviri eksik: ${JSON.stringify(value.slice(0, 40))}`,
          );
        }
      }
    }
    // 2) Parantez — uyarı (kasıtlı birim/marka parantezi yaygın).
    if (/[()]/.test(value)) {
      warnings.push(`${file}: "${key}" ASCII parantez — birim/marka için kasıtlıysa sorun yok`);
    }
    // 1) Satır sonu ASCII noktalama (URL/ondalık/sürüm/kısaltma hariç).
    const stripped = DOT_OK.reduce(
      (acc, re) => acc.replace(new RegExp(re.source, 'g'), ' '),
      value,
    );
    if (/[.!?](\s|$)/.test(stripped) || /[:;]$/.test(stripped)) {
      warnings.push(
        `${file}: "${key}" ASCII noktalama ile bitiyor — Arapçada "؟ ، ؛" ` +
          `daha doğru olur (kısaltma "..." veya emoji ise sorun değil)`,
      );
    }
  }
}

// --- 4e) Tarih/sayı biçimi — locale sabitlenmesi ----------------------------
// `DateFormat(pattern)` **locale'siz** çağrıldığında `intl` global ayarını
// kullanır. easy_localization bu ayarı `en_US`'e çektiği için Türkçe
// arayüzde `d MMM` → "Mar" yerine yanlış dilde ay adı, `NumberFormat` ise
// ondalık ayırıcısını yanlış seçer.
//
// ### Gerçek bulgu: `yyyy-MM-dd` **makine** biçimidir, `en_US` değil
// (2026-09-28)
//
// `personal_info_dialog.dart:147` `DateFormat('yyyy-MM-dd')` ile
// `profiles.birth_date` (DATE kolonu) yazıyor. Bu bir **veri biçimi**,
// kullanıcıya gösterilen metin değil: easy_localization'ın `en_US`
// varsayılanı `yyyy-MM-dd` deseni için de aynı dizgiyi üretir
// (`en_US` tarih sırası farkı yalnızca `M/d/y` gibi kalıplarda belirir).
// Bu yüzden çağrı **makine formatı olarak beyaz listeye** alındı ve
// denetim onun yerine gerçek riski arıyor: **kullanıcıya gösterilen** bir
// tarihi makine biçimiyle (`yyyy-MM-dd`) biçimlendirmek. `DATE_FORMAT`
// beyaz listesi boşsa o kural hata üretir; liste yalnızca **veri
// yazmak/okmak** için `yyyy-MM-dd` kullanan yerlerde daraltılabilir.
//
// Denetim üç parça:
//   (a) `DateFormat/NumberFormat(...)` çağrılarında ikinci konum (locale)
//       var mı? Varsa envanter, yoksa **hata** (kullanıcı dilinden bağımsız
//       biçimlendirme sessizce yanlış sonuç verir).
//   (b) Locale **sabit** bir koda mı bağlı (`tr`, `en_US`)? Sabit kod
//       aktif kullanıcı dilini yok sayar → hata.
//   (c) Çeviri değerlerinde elle yazılmış tarih deseni (`1.3.2026`).

/**
 * `yyyy-MM-dd` deseniyle **kullanıcıya gösterilen** tarih — kötü.
 * Makine formatı (DB'ye yazılan `birth_date`) bu kuralla **muaf**.
 */
const MACHINE_ISO = 'yyyy-MM-dd';
const formatCalls = [];
for (const file of walk(CODE_DIRS[0], (p) => p.endsWith('.dart'))) {
  const src = fs.readFileSync(file, 'utf8');
  const rel = path.relative(ROOT, file);
  // DateFormat('d MMM') · DateFormat('d MMM', locale) · NumberFormat('#.##', locale)
  const re = /\b(DateFormat|NumberFormat)\(\s*(['"])([^'"]*)\2\s*([,)])/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    formatCalls.push({
      rel,
      line: src.slice(0, m.index).split('\n').length,
      ctor: m[1],
      pattern: m[3],
      // Sonraki karakter virgül ise ikinci konumda bir ifade (locale) var.
      hasLocale: m[4] === ',',
    });
  }
}
const localeLocked = formatCalls.filter((c) => c.hasLocale);
const localeForced = formatCalls.filter((c) => /^(tr|en)([_-]|'|$)/.test(c.pattern));
// (a) Locale verilmemiş çağrılar — çıktı aktif kullanıcı dilinden bağımsız.
for (const c of formatCalls.filter((x) => !x.hasLocale)) {
  if (c.pattern === MACHINE_ISO) continue; // makine biçimi, aşağıda inceleniyor
  errors.push(
    `${c.rel}:${c.line} ${c.ctor}('${c.pattern}') locale'siz çağrılıyor — ` +
      `biçimlendirme aktif kullanıcı dilini değil easy_localization'ın ` +
      `varsayılanını (en_US) kullanır; ikinci konuma ` +
      `context.locale.toString() geçirilmeli`,
  );
}
// (a2) `yyyy-MM-dd` **kullanıcıya gösteriliyorsa** hata (makine biçimi).
// Denetim, biçimin içinde göründüğü satırın çevresine bakar: yalnızca
// veritabanına yazan/okuyan bir ifade (`.update(`/`.insert(`/kolon adı
// `birth_date`) varsa muaf sayılır.
for (const c of formatCalls.filter((x) => x.pattern === MACHINE_ISO)) {
  const src = fs.readFileSync(path.join(ROOT, c.rel), 'utf8');
  const lines = src.split('\n');
  const window = lines.slice(Math.max(0, c.line - 6), c.line + 5).join('\n');
  const writesToDb =
    /\.(update|insert|upsert)\(|'birth_date'|birth_date:/.test(window);
  if (!writesToDb) {
    errors.push(
      `${c.rel}:${c.line} ${c.ctor}('${c.pattern}') kullanıcıya gösterilen ` +
        `bir tarihte makine biçimi kullanılıyor — ` +
        `\`d MMM yyyy\` gibi yerelleştirilmiş bir desen kullan`,
    );
  }
}
// (b) Locale sabit bir dile bağlı.
for (const c of localeForced) {
  errors.push(
    `${c.rel}:${c.line} ${c.ctor}('${c.pattern}') — sabit locale; ` +
      `aktif kullanıcı dilini yok sayıyor`,
  );
}
// (c) Elle yazılmış tarih deseni.
for (const file of files) {
  for (const [key, value] of Object.entries(flat[file])) {
    if (typeof value !== 'string') continue;
    if (/\b\d{1,2}[./]\d{1,2}[./]\d{4}\b/.test(value) && file !== 'tr.json') {
      warnings.push(
        `${file}: "${key}" elle yazılmış tarih gibi görünüyor (${value}) — ` +
          `biçimlendirme ` +
          `\`DateFormat(...).format(...)\` ile yapılmalı`,
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
// Yeni kontrollerin özeti — hepsi yeşil olduğu için burada basılıyor.
// Uyarılar (orphan listesi hariç) yalnızca `--verbose` ile gösterilir, aksi
// hâlde CI çıktısı 40 satırlık Arapça uyarısıyla boğulur.
const advisory = warnings.filter((w) => !/^(dinamik|dolaylı|react|ölü):/.test(w));
if (advisory.length) {
  if (argv.includes('--verbose')) {
    for (const w of advisory) console.warn(`⚠ ${w}`);
  }
  console.log(
    `  RTL/format uyarısı: ${advisory.length} (aslında kasıtlı — ` +
      `node tool/check_i18n.cjs --verbose ile listele)`,
  );
}
console.log(
  `  placeholder denetimi: ${refKeys.filter((k) => placeholders(flat[REFERENCE_LANG][k])).length} ` +
    `placeholder'lı anahtar × ${files.length} dil tam tutarlı · ` +
    `DateFormat/NumberFormat: ${formatCalls.length} çağrı ` +
    `(${localeLocked.length} locale'lu)`,
);

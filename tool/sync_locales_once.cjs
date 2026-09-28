#!/usr/bin/env node
/**
 * `public/locales/**` ↔ `flutter_app/assets/translations/**` eşitleyici —
 * **tek seferlik** göç (A5r10, 2026-09-28).
 *
 * ## Amaç
 *
 * `settings.notifications.{push,email}` ve `settings.notifications.server.channelNote`
 * ile `settings.deleteAccount.*` anahtarları Flutter tarafında **vardı**
 * (A4r4b/A4r7), React tarafında yoktu. Web PWA artık bu anahtarları
 * kullandığı için `public/locales/<lang>/translation.json` dosyalarına da
 * eklenmelidir — aksi hâlde i18next `fallbackLng: 'en'` ile sessizce
 * İngilizce döner ve 11 dilde Türkçe metin görünür.
 *
 * ## Neden bu bir dosya, `convert_locales.cjs` değil?
 *
 * `convert_locales.cjs` **yönü ters** çalışır: `public/locales` →
 * `flutter_app/assets/translations` ve Flutter tarafındaki 152 ek anahtarı
 * **sessizce siler** (kendi uyarısında yazılı). Burada yalnızca **eksik**
 * anahtarlar kopyalanır, hiçbir şey silinmez/üzerine yazılmaz.
 *
 * ## Kaynak
 *
 * `flutter_app/assets/translations/<lang>.json` (Flutter tarafında zaten
 * doğru çevirileri var). `en` ve `tr` elle doğrulandı; 12 dilin tamamı
 * Flutter dosyasından birebir alındı — böylece iki istemci **aynı** metni
 * gösterir.
 *
 * Kullanım:  node tool/sync_locales_once.mjs [--dry-run]
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const WEB_DIR = path.join(ROOT, 'public', 'locales');
const FLUTTER_DIR = path.join(ROOT, 'flutter_app', 'assets', 'translations');
const dryRun = process.argv.includes('--dry-run');

/** Kopyalanacak anahtar yolları (`.` ile ayrılmış). */
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
  'settings.deleteAccount.messages.localCleanup',
];

const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const write = (p, obj) => fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n', 'utf8');

/** `"a.b.c"` → `{a:{b:{c:…}}}`; kök nesneyi yerinde günceller. */
function setPath(root, dotted, value) {
  const parts = dotted.split('.');
  let node = root;
  for (const p of parts.slice(0, -1)) {
    if (!node[p] || typeof node[p] !== 'object') node[p] = {};
    node = node[p];
  }
  node[parts[parts.length - 1]] = value;
}

function getPath(root, dotted) {
  return dotted.split('.').reduce((n, k) => (n == null ? n : n[k]), root);
}

const langs = fs.readdirSync(FLUTTER_DIR).filter((f) => f.endsWith('.json'));
let changed = 0;
const report = [];

for (const file of langs) {
  const lang = file.replace(/\.json$/, '');
  const webFile = path.join(WEB_DIR, lang, 'translation.json');
  if (!fs.existsSync(webFile)) {
    report.push(`⚠ ${lang}: public/locales/${lang}/translation.json yok — atlandı`);
    continue;
  }
  const flutter = read(path.join(FLUTTER_DIR, file));
  const web = read(webFile);
  const added = [];
  const missingSource = [];
  for (const key of KEYS) {
    const value = getPath(flutter, key);
    if (value === undefined) {
      missingSource.push(key);
      continue;
    }
    if (getPath(web, key) === undefined) {
      setPath(web, key, value);
      added.push(key);
    }
  }
  if (missingSource.length > 0) {
    report.push(`✗ ${lang}: Flutter tarafında eksik: ${missingSource.join(', ')}`);
  }
  if (added.length > 0) {
    if (!dryRun) write(webFile, web);
    changed++;
    report.push(`✓ ${lang}: +${added.length} anahtar eklendi`);
  } else {
    report.push(`· ${lang}: zaten tam`);
  }
}

for (const line of report) console.log(line);
console.log(
  `\n${dryRun ? '[dry-run] ' : ''}${changed}/${langs.length} web locale dosyası güncellendi.`,
);
if (report.some((l) => l.startsWith('✗'))) process.exit(1);

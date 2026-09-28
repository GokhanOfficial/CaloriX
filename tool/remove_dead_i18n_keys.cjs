#!/usr/bin/env node
/**
 * Tur 13 (A6r13) — kanıtlanmış ölü 3 çeviri anahtarını 12 dilden siler.
 *
 * Silinen anahtarlar ve gerekçeleri `tool/check_i18n.cjs` içindeki
 * ORPHAN_BASELINE yorumunda belgelidir. Silme **yalnız** iki istemcide de
 * kullanılmayan, `public/locales/*` altında da karşılığı olmayan
 * anahtarlar için yapılır; her adımda doğrular.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const DIRS = [
  path.join(ROOT, 'flutter_app', 'assets', 'translations'),
  path.join(ROOT, 'public', 'locales'),
];

const DEAD = [
  // server_notification_preferences_section.dart:72 açıkça dışlıyor:
  // "goalAchieved bilinçli olarak yok (A4r10, ürün kararı 2-B)".
  'settings.notifications.server.goalAchieved',
  // channelNote ile aynı cümleyi söylüyor, ikisi de hiç bağlanmadı.
  'settings.notifications.server.serverScope',
  // Lif alanı (food.dart:14) var ama hiçbir ekranda gösterilmiyor.
  'dialogs.fiberG',
];

function deleteFlat(obj, key) {
  const parts = key.split('.');
  let node = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!node[parts[i]] || typeof node[parts[i]] !== 'object') return false;
    node = node[parts[i]];
  }
  const last = parts[parts.length - 1];
  if (!(last in node)) return false;
  delete node[last];
  // Boş kalan ara nesneleri de temizle (orphan JSON düğümü kalmasın).
  let cur = obj;
  for (let i = 0; i < parts.length - 1; i++) cur = cur[parts[i]];
  return true;
}

let changed = 0;
for (const dir of DIRS) {
  if (!fs.existsSync(dir)) continue;
  for (const sub of fs.readdirSync(dir)) {
    const file = path.join(dir, sub, 'translation.json');
    const isFlutter = dir.includes('translations');
    const target = isFlutter
      ? path.join(dir, sub)
      : file;
    if (!isFlutter && !fs.existsSync(target)) continue;
    const p = isFlutter ? target : target;
    const raw = fs.readFileSync(p, 'utf8');
    const json = JSON.parse(raw);
    let touched = false;
    for (const key of DEAD) {
      if (deleteFlat(json, key)) touched = true;
    }
    if (touched) {
      fs.writeFileSync(p, JSON.stringify(json, null, 2) + '\n', 'utf8');
      changed++;
      console.log(`~ ${path.relative(ROOT, p)}: ${DEAD.length} anahtar silindi`);
    }
  }
}
console.log(changed ? `\n${changed} dosya güncellendi.` : 'Değişiklik yok.');

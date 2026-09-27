#!/usr/bin/env node
/**
 * A4r2'nin Tur 2'de eklediği 24 yeni çeviri anahtarını 12 dile ekler.
 * Ana kaynak: `tool/new_keys_tur2.json` (A4'ün kodundan birebir türetildi).
 * Tur 2'deki A6 görevi: A4'ün tablosunu `assets/translations/*.json`'a uygula.
 */
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const TRANS_DIR = path.join(ROOT, 'flutter_app', 'assets', 'translations');
const TABLE = require('./new_keys_tur2.json');

function setFlat(target, key, value) {
  const parts = key.split('.');
  let node = target;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!node[parts[i]] || typeof node[parts[i]] !== 'object') node[parts[i]] = {};
    node = node[parts[i]];
  }
  node[parts[parts.length - 1]] = value;
}

const files = fs.readdirSync(TRANS_DIR).filter((f) => f.endsWith('.json'));
for (const file of files) {
  const lang = path.basename(file, '.json');
  const table = TABLE[lang];
  if (!table) throw new Error(`tablo yok: ${lang}`);
  const p = path.join(TRANS_DIR, file);
  const before = fs.readFileSync(p, 'utf8');
  const data = JSON.parse(before);
  for (const [key, value] of Object.entries(table)) setFlat(data, key, value);
  const after = JSON.stringify(data, null, 2) + '\n';
  if (before !== after) {
    fs.writeFileSync(p, after, 'utf8');
    console.log(`~ ${file}: ${Object.keys(table).length} anahtar eklendi`);
  } else {
    console.log(`= ${file}: zaten güncel`);
  }
}

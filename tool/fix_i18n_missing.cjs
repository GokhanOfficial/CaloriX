#!/usr/bin/env node
/**
 * Yeni kodla eklenen i18n anahtarlarını 12 dile gerçek çevirilerle ekler.
 *
 * `tool/check_i18n.cjs` eksik anahtarları listeler; bu script onları
 * gerçek metinlerle doldurur (İngilizce kopyalamak yerine).
 *
 * Yeni bir anahtar tanımlarken: 12 dilin tamamına buraya bir giriş ekleyin
 * ve `node tool/fix_i18n_missing.cjs` + `node tool/check_i18n.cjs` çalıştırın.
 *
 * Kullanım:  node tool/fix_i18n_missing.cjs
 */
const fs = require('fs');
const path = require('path');

const TRANS_DIR = path.join(__dirname, '..', 'flutter_app', 'assets', 'translations');

/**
 * key -> { dil: çeviri }
 * `en` ve `tr` referans kabul edilir; yalnızca kalan 10 dil burada.
 */
const TRANSLATIONS = {
  // --- Önceki turda tamamlananlar -----------------------------------------
  'common.undo': {
    de: 'Rückgängig', es: 'Deshacer', fr: 'Annuler', it: 'Annulla',
    pt: 'Desfazer', ru: 'Отменить', ja: '元に戻す', ko: '실행 취소',
    zh: '撤销', ar: 'تراجع',
  },
  'dashboard.edit': {
    de: 'Bearbeiten', es: 'Editar', fr: 'Modifier', it: 'Modifica',
    pt: 'Editar', ru: 'Изменить', ja: '編集', ko: '편집', zh: '编辑', ar: 'تحرير',
  },
  'dashboard.delete': {
    de: 'Löschen', es: 'Eliminar', fr: 'Supprimer', it: 'Elimina',
    pt: 'Excluir', ru: 'Удалить', ja: '削除', ko: '삭제', zh: '删除', ar: 'حذف',
  },
  'analytics.goToCalories': {
    de: 'Kalorienanalyse ansehen', es: 'Ver análisis de calorías',
    fr: 'Voir les analyses caloriques', it: 'Vedi analisi calorie',
    pt: 'Ver análise de calorias', ru: 'Перейти к анализу калорий',
    ja: 'カロリー分析を見る', ko: '칼로리 분석 보기',
    zh: '查看热量分析', ar: 'عرض تحليل السعرات',
  },
  'analytics.charts.macroFocus.title': {
    de: '{macro}-Verlauf', es: 'Seguimiento de {macro}', fr: 'Suivi de {macro}',
    it: 'Andamento {macro}', pt: 'Acompanhamento de {macro}',
    ru: 'Динамика: {macro}', ja: '{macro}の推移', ko: '{macro} 추이',
    zh: '{macro}趋势', ar: 'تتبع {macro}',
  },

  // --- Yeni kodla gelen anahtarlar ---------------------------------------
  'dialogs.photoTooLarge': {
    en: 'Photo is too large', tr: 'Fotoğraf çok büyük',
    de: 'Foto ist zu groß', es: 'La foto es demasiado grande',
    fr: 'Photo trop volumineuse', it: 'Foto troppo grande',
    pt: 'Foto muito grande', ru: 'Фото слишком большое',
    ja: '写真が大きすぎます', ko: '사진이 너무 큽니다',
    zh: '照片太大', ar: 'الصورة كبيرة جدًا',
  },
  'dialogs.flash': {
    en: 'Flash', tr: 'Flaş',
    de: 'Blitz', es: 'Flash', fr: 'Flash', it: 'Flash',
    pt: 'Flash', ru: 'Вспышка', ja: 'フラッシュ', ko: '플래시',
    zh: '闪光灯', ar: 'الفلاش',
  },
  'dialogs.amountRequired': {
    en: 'Amount is required', tr: 'Miktar gerekli',
    de: 'Menge ist erforderlich', es: 'Se requiere la cantidad',
    fr: 'Quantité requise', it: 'Quantità richiesta',
    pt: 'Quantidade obrigatória', ru: 'Требуется количество',
    ja: '量を入力してください', ko: '양을 입력하세요',
    zh: '请输入数量', ar: 'الكمية مطلوبة',
  },
  'errors.notFound': {
    en: 'Page not found', tr: 'Sayfa bulunamadı',
    de: 'Seite nicht gefunden', es: 'Página no encontrada',
    fr: 'Page introuvable', it: 'Pagina non trovata',
    pt: 'Página não encontrada', ru: 'Страница не найдена',
    ja: 'ページが見つかりません', ko: '페이지를 찾을 수 없습니다',
    zh: '页面未找到', ar: 'الصفحة غير موجودة',
  },
  'common.comingSoon': {
    en: 'Coming soon', tr: 'Çok yakında',
    de: 'Demnächst', es: 'Próximamente', fr: 'Bientôt',
    it: 'Presto disponibile', pt: 'Em breve', ru: 'Скоро',
    ja: '近日公開', ko: '출시 예정', zh: '即将推出', ar: 'قريبًا',
  },
};

function setFlat(target, key, value) {
  const parts = key.split('.');
  let node = target;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!node[parts[i]] || typeof node[parts[i]] !== 'object') node[parts[i]] = {};
    node = node[parts[i]];
  }
  node[parts[parts.length - 1]] = value;
}

function hasFlat(obj, key) {
  return key.split('.').reduce((n, p) => (n ? n[p] : undefined), obj) !== undefined;
}

let changed = 0;
for (const [key, byLang] of Object.entries(TRANSLATIONS)) {
  for (const [lang, value] of Object.entries(byLang)) {
    const file = path.join(TRANS_DIR, `${lang}.json`);
    const json = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (hasFlat(json, key)) continue;
    setFlat(json, key, value);
    fs.writeFileSync(file, JSON.stringify(json, null, 2) + '\n', 'utf8');
    console.log(`+ ${lang}.json: "${key}" = ${JSON.stringify(value)}`);
    changed++;
  }
}
console.log(`\n${changed} çeviri eklendi.`);

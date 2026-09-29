/**
 * Kaynak dosyadan template literal bloğu çıkaran küçük, saf yardımcı (A1r11).
 *
 * `probe_prompt_source.ts` production `index.ts`'i okuyup
 * `const systemPrompt = \`...\`` ile `const response = await fetch(` arasındaki
 * bloğu döndürür. Böylece prompt metni probe betiğine **kopyalanmaz**.
 *
 * Saf fonksiyondur: ağ/ortam bağımlılığı yok, `Deno.test` ile test edilebilir.
 */

/** Bir kaynak metinden `start` işaretinden `end` işaretine kadar olan aralığı verir. */
export function extractTemplateLiteral(source: string, start: string, end: string): string {
  const startIndex = source.indexOf(start);
  if (startIndex === -1) {
    throw new Error(`extractTemplateLiteral: başlangıç işareti bulunamadı: ${JSON.stringify(start)}`);
  }
  const bodyStart = startIndex + start.length;
  const endIndex = source.indexOf(end, bodyStart);
  if (endIndex === -1) {
    throw new Error(`extractTemplateLiteral: bitiş işareti bulunamadı: ${JSON.stringify(end)}`);
  }
  const block = source.slice(bodyStart, endIndex);
  if (!block.includes("`")) {
    throw new Error("extractTemplateLiteral: template literal açılışı bulunamadı");
  }
  return block;
}

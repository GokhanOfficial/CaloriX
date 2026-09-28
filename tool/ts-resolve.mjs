/**
 * Node ESM çözücü — `.ts` uzantısız **göreli** import'lar için.
 *
 * ## Neden gerekiyor
 *
 * `src/lib/calculations.ts` → `import { … } from './constants'` yazıyor
 * (Vite/bundler uzantıyı tamamlar). Node'un ESM çözücüsü ise uzantısız
 * yolları **bulamaz**. `tool/test_backup_import.mjs` bu sorunu yaşamıyordu
 * çünkü içe aktardığı `src/lib/import/backupImport.ts` hiçbir göreli TS
 * import'u içermiyor.
 *
 * `node --experimental-strip-types --test` + bu yükleyici ile **ek
 * bağımlılık yok** ve `npm test` yalnız Node kurulu olan bir CI'da da
 * çalışır. Kayıt: `package.json` → `test` betiğinde `--import ./tool/ts-resolve.mjs`
 * olarak geçiyor.
 *
 * ## Kapsam (bilinçli olarak dar)
 *
 * Yalnız **göreli** yollar (`./`, `../`) çözülür ve yalnız uzantısızsa
 * `.ts` denenir. Paket adlarına (`react`, `date-fns`) **dokunulmaz** —
 * `node_modules` çözümlemesi Node'un kendi işi.
 */
import { register } from 'node:module';
import { pathToFileURL } from 'node:url';

register('./ts-resolve-hooks.mjs', pathToFileURL(import.meta.filename));

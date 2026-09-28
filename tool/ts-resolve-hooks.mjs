/**
 * `ts-resolve.mjs` için çözücü kancaları (Node ≥ 20 `module.register`).
 *
 * Uzantısız **göreli** import'lara `.ts` uzanır. Gerekçe ve kapsam
 * `ts-resolve.mjs` dosyasında.
 */
import { existsSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

const CANDIDATES = ['', '.ts', '.tsx', '/index.ts', '/index.tsx'];

/** @type {import('node:module').ResolveHook} */
export async function resolve(specifier, context, nextResolve) {
  const relative = specifier.startsWith('./') || specifier.startsWith('../');
  if (!relative) return nextResolve(specifier, context);

  const parent = context.parentURL ?? pathToFileURL(`${process.cwd()}/`).href;
  for (const suffix of CANDIDATES) {
    const candidate = new URL(specifier + suffix, parent);
    if (existsSync(fileURLToPath(candidate))) {
      return nextResolve(candidate.href, context);
    }
  }
  // Bulunamadıysa Node'un kendi hatası üretsin (daha açıklayıcı).
  return nextResolve(specifier, context);
}

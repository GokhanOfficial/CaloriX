/// <reference types="vite/client" />

/**
 * `VITE_*` değişkenleri istemci bundle'ına gömülür (gizli tutulamaz).
 * Bu yüzden burada YALNIZCA publishable/anon seviyesindeki değerler
 * tanımlanır. `service_role` veya DB parolası ASLA `VITE_` önekiyle
 * kullanılmamalıdır — istemciye sızar.
 */
interface ImportMetaEnv {
  /** Supabase proje URL'si, ör. https://<ref>.supabase.co */
  readonly VITE_SUPABASE_URL: string;
  /** Publishable/anon anahtar (sb_publishable_... veya eski anon JWT). */
  readonly VITE_SUPABASE_PUBLISHABLE_KEY: string;
  /** Supabase proje kimliği (CLI/edge function çıktılarında kullanılır). */
  readonly VITE_SUPABASE_PROJECT_ID?: string;
  /** Web Push VAPID *public* anahtarı. Gizli anahtar sunucu tarafında kalır. */
  readonly VITE_VAPID_PUBLIC_KEY?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

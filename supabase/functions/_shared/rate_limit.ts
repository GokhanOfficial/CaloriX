/**
 * Orta katman (edge function) rate limit / maliyet koruması.
 *
 * Amaç: `ai-chat`, `recognize-food*`, `calculate-macros` gibi AI çağrısı yapan
 * fonksiyonların sınırsız çağrılmasını (maliyet/DoS) engellemek.
 *
 * Uygulama (iki katman):
 *  1. **Kalıcı sayaç (birincil)** — `public.rate_limits` tablosu ve
 *     `public.rate_limit_hit()` RPC'si. Bellek değil, veritabanı sayacıdır;
 *     bu yüzden Edge Runtime'ın birden fazla instance'ı çalışsa bile sınır
 *     instance başına değil **global** olarak uygulanır.
 *     RPC atomiktir (`INSERT ... ON CONFLICT DO UPDATE` tek satır kilidi alır),
 *     eşzamanlı isteklerde sayaç kaybı (lost update) olmaz.
 *  2. **Bellek içi sayaç (yedek)** — DB erişilemezse (RPC migration'ı
 *     uygulanmamış, ağ hatası, timeout) fonksiyon çökmez; süreç içi kaba
 *     sınıra düşer. Bu yol instance başına sayar, yani **zayıftır**; loglanır.
 *
 * Geçiş notu: `20260927220500_persistent_rate_limit.sql` uygulanana kadar
 * yalnızca 2. yol çalışır. Migration sonrası RPC bir kez denenir; başarısız
 * olursa 1 dakika boyunca tekrar denemez (her istekte DB'ye gitmemek için).
 */

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/** Bellek içi sayaç kovası. */
type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();

/** RPC'nin bir süre boyunca denenmemesi için kısa devre zamanlayıcısı (ms). */
const DB_BYPASS_COOLDOWN_MS = 60_000;
let dbBypassUntil = 0;

/** Anahtar başına izin verilen istek sayısı. */
export type RateLimitRule = {
  /** Pencere uzunluğu (saniye). */
  windowSeconds: number;
  /** Pencere içinde izin verilen istek sayısı */
  max: number;
};

export type RateLimitResult = { allowed: boolean; retryAfter: number };

function supabaseServiceClient(): SupabaseClient | null {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return null;
  return createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Kalıcı (DB) sayacı artırır. Tablo/RPC yoksa veya hata olursa `null` döner
 * (çağıran bellek içi yola düşer).
 */
async function checkRateLimitDb(key: string, rule: RateLimitRule): Promise<RateLimitResult | null> {
  if (Date.now() < dbBypassUntil) return null;

  const client = supabaseServiceClient();
  if (!client) {
    dbBypassUntil = Date.now() + DB_BYPASS_COOLDOWN_MS;
    return null;
  }

  // Kova adı anahtardan türetilir: `<scope>:u:<id>` -> `<scope>`
  const scope = key.split(":")[0] || "unknown";
  try {
    const { data, error } = await client.rpc("rate_limit_hit", {
      p_key: key.slice(0, 512),
      p_bucket: scope.slice(0, 64),
      p_max_count: rule.max,
      p_window_seconds: rule.windowSeconds,
    });
    if (error || !data || typeof data !== "object") {
      dbBypassUntil = Date.now() + DB_BYPASS_COOLDOWN_MS;
      // Şema/mesaj istemciye ASLA dönmez; yalnızca sunucu logu.
      console.error("Kalici rate limit kullanilamadi, bellek ici yola dusuluyor:", error?.message);
      return null;
    }
    const result = data as { allowed?: unknown; retry_after?: unknown };
    return {
      allowed: result.allowed === true,
      retryAfter: typeof result.retry_after === "number" && Number.isFinite(result.retry_after)
        ? Math.max(0, Math.trunc(result.retry_after))
        : 0,
    };
  } catch (error) {
    dbBypassUntil = Date.now() + DB_BYPASS_COOLDOWN_MS;
    console.error("Kalici rate limit cagrisi basarisiz:", error instanceof Error ? error.message : error);
    return null;
  }
}

/**
 * Bellek içi kaba hız sınırı (yedek yol). Aşıldığında `retryAfter` saniyesi
 * ile `false` döner.
 */
export function checkRateLimitMemory(key: string, rule: RateLimitRule): RateLimitResult {
  const now = Date.now();
  const existing = buckets.get(key);
  if (!existing || existing.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + rule.windowSeconds * 1000 });
    prune(now);
    return { allowed: true, retryAfter: 0 };
  }
  if (existing.count >= rule.max) {
    return { allowed: false, retryAfter: Math.ceil((existing.resetAt - now) / 1000) };
  }
  existing.count += 1;
  return { allowed: true, retryAfter: 0 };
}

/** Bellem taşmasını önlemek için süresi dolmuş kovaları temizler. */
function prune(now: number): void {
  if (buckets.size < 5000) return;
  for (const [key, bucket] of buckets) {
    if (bucket.resetAt <= now) buckets.delete(key);
  }
}

/**
 * Hız sınırı kontrolü. Önce kalıcı DB sayacını dener; DB erişilemezse bellek
 * içi yola düşer. **Fonksiyon hiçbir koşulda çökmez.**
 */
export async function checkRateLimit(key: string, rule: RateLimitRule): Promise<RateLimitResult> {
  const fromDb = await checkRateLimitDb(key, rule);
  if (fromDb) return fromDb;
  return checkRateLimitMemory(key, rule);
}

/** İstek için hız sınırı anahtarı: `userId` varsa kullanıcı bazlı, değilse IP bazlı. */
export function rateLimitKey(scope: string, req: Request, userId?: string): string {
  if (userId) return `${scope}:u:${userId}`;
  const forwarded = req.headers.get("x-forwarded-for") || "";
  const ip = forwarded.split(",")[0]?.trim() || req.headers.get("cf-connecting-ip") || "unknown";
  return `${scope}:ip:${ip}`;
}

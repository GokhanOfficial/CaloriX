/**
 * Orta katman (edge function) rate limit / maliyet koruması.
 *
 * Amaç: `ai-chat`, `recognize-food*`, `calculate-macros` gibi AI çağrısı yapan
 * fonksiyonların anon anahtarla sınırsız çağrılmasını (maliyet/DoS) engellemek.
 * Uygulama: süreç içi sayaç. Bellek içi olduğu için instance ölçeklendirmesinde
 * tam kesin değildir; üretimde kalıcı sayaç için `rate_limits` tablosu + RPC önerilir
 * (bkz. RAPOR-A1-security-tur1, "Sonraki öneriler").
 */

type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();

/** Anahtar başına izin verilen istek sayısı. */
export type RateLimitRule = {
  /** Pencere uzunluğu (saniye). */
  windowSeconds: number;
  /** Pencere içinde izin verilen istek sayısı. */
  max: number;
};

/**
 * Kaba hız sınırı. Aşıldığında `retryAfter` saniyesi ile `false` döner.
 */
export function checkRateLimit(key: string, rule: RateLimitRule): { allowed: boolean; retryAfter: number } {
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

/** Bellek taşmasını önlemek için süresi dolmuş kovaları temizler. */
function prune(now: number): void {
  if (buckets.size < 5000) return;
  for (const [key, bucket] of buckets) {
    if (bucket.resetAt <= now) buckets.delete(key);
  }
}

/** İstek için hız sınırı anahtarı: `userId` varsa kullanıcı bazlı, değilse IP bazlı. */
export function rateLimitKey(scope: string, req: Request, userId?: string): string {
  if (userId) return `${scope}:u:${userId}`;
  const forwarded = req.headers.get("x-forwarded-for") || "";
  const ip = forwarded.split(",")[0]?.trim() || req.headers.get("cf-connecting-ip") || "unknown";
  return `${scope}:ip:${ip}`;
}

/**
 * Ortak HTTP güvenlik yardımcıları (tüm edge function'lar tarafından kullanılır).
 *
 * Amaç:
 *  - CORS: sabit `*` yerine izin listesi (bilinmeyen origin -> `*` fallback),
 *    preflight (OPTIONS) doğru, `Vary` başlığı eklenmiş, credential gerektiren
 *    durumda (`*` kullanılan halde) `Access-Control-Allow-Credentials` gönderilmez.
 *  - Hata sızıntısı: istemciye asla `error.message` / stack / tablo şeması dönülmez.
 *  - Auth: `Authorization` başlığı **sunucu tarafında** `supabase.auth.getUser()`
 *    ile doğrulanır (payload decode YAPILMAZ).
 */

// Uygulamanın tarayıcı tabanlı kaynakları. Supabase Dashboard > Auth > URL
// Configuration ile eşleşmeli. Eşleşmeyen origin için `*` fallback kullanılır
// (native istemciler `Origin` göndermez).
const ALLOWED_ORIGINS = [
  "https://calorix.app",
  "https://www.calorix.app",
  "http://localhost:3000",
  "http://localhost:5173",
  "http://127.0.0.1:5173",
  "http://127.0.0.1:3000",
];

const ALLOWED_HEADERS = "authorization, x-client-info, apikey, content-type";
const ALLOWED_METHODS = "GET, POST, OPTIONS";

/** İstek Origin'ine göre CORS başlıklarını üretir. */
export function corsHeaders(origin?: string | null): Record<string, string> {
  const normalized = (origin || "").trim();
  const allowOrigin = ALLOWED_ORIGINS.includes(normalized) ? normalized : "*";
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": ALLOWED_HEADERS,
    "Access-Control-Allow-Methods": ALLOWED_METHODS,
    "Access-Control-Max-Age": "86400",
    // CORS sonuçları origin'e göre değişebildiği için cache'e yazılmasın.
    "Vary": "Origin",
  };
}

/** Preflight (OPTIONS) yanıtı. `Access-Control-Allow-Methods` her zaman gönderilir. */
export function preflightResponse(req: Request): Response {
  return new Response(null, {
    status: 204,
    headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Length": "0" },
  });
}

/**
 * JSON yanıt. `X-Content-Type-Options` ile tarayıcıda MIME sniffing engellenir.
 * `msg` sadece **sabit** (kullanıcı girdisi veya iç hata detayı içermeyen) metin olmalıdır.
 */
export function jsonResponse(
  req: Request,
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req.headers.get("Origin")),
      "Content-Type": "application/json; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}

/** Güvenli hata yanıtı: detay yalnızca sunucu loguna yazılır, istemciye sabit mesaj döner. */
export function errorResponse(req: Request, status: number, publicMessage: string, logContext?: unknown): Response {
  if (logContext !== undefined) console.error(publicMessage, logContext);
  return jsonResponse(req, { error: publicMessage }, status);
}

/** Mevcut `corsHeaders` şeklini koruyan yardımcı (tanımı alan fonksiyonlar için). */
export function legacyJson(req: Request, body: unknown, status = 200, baseHeaders?: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...(baseHeaders ?? corsHeaders(req.headers.get("Origin"))),
      "Content-Type": "application/json; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "no-store",
    },
  });
}

/** Web Push endpoint'i için host izin listesi (SSRF/kötüye kullanım azaltma). */
const PUSH_ENDPOINT_HOST_SUFFIXES = [
  "fcm.googleapis.com",
  "updates.push.services.mozilla.com",
  "push.services.mozilla.com",
  "web.push.apple.com",
];

export function isAllowedPushEndpoint(endpoint: string): boolean {
  try {
    const url = new URL(endpoint);
    if (url.protocol !== "https:") return false;
    const host = url.hostname.toLowerCase();
    return PUSH_ENDPOINT_HOST_SUFFIXES.some((suffix) => host === suffix || host.endsWith(`.${suffix}`));
  } catch (_) {
    return false;
  }
}

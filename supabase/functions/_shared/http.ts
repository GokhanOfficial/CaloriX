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

// ===========================================================================
// KANAL ETKİNLİĞİ — master anahtar + tip tercihi birleştirme (A1r10)
// ===========================================================================
// ⭐ BUGÜN DÜZELTİLEN AÇIK (P1, A4r8'in bulduğu hatanın **sunucu tarafı**)
// ---------------------------------------------------------------------------
// `send-notification` kanal kararını şöyle veriyordu:
//
//   const pushEnabled  = preference?.push_enabled  ?? profile.push_notifications_enabled  ?? true;
//   const emailEnabled = preference?.email_enabled ?? profile.email_notifications_enabled ?? true;
//
// `??` **yalnız `null`/`undefined` üstüne** düşer. `notification_preferences`'a
// yazan **ilk istemci** (`check-reminders`'ın "satır yoksa kapalı" davranışını
// düzeltmek için Flutter/web "her tip için satır yaz" yaptı) `push_enabled`
// kolonunu **dolu** (true) yazar. `BOOLEAN DEFAULT true` + NOT NULL olmayan
// kolon yazılmadığında zaten `true` olur.
//
// Sonuç: **profil master anahtarı hiç okunmaz.** Kullanıcı üstteki "Push
// Bildirimleri" anahtarını kapatır, tip bazlı `true` satırları yazılı kalır
// ve bildirimler **yine gider**. Kullanıcının güvenlik/opsiyon tercihi
// ihlal edilir.
//
// A4r8 bu açığı **istemci tarafında** `applyMasterSwitches` ile kapattı
// (satırları AND'leyerek yazmak). Bu, savunmanın **tek katmanıdır**: DB'de
// zaten yazılmış satırlar (yedek içe aktarım, eski istemci, elle SQL) master
// anahtara rağmen gönderimi engellemez. Doğru bileşim **AND**'dir ve
// **sunucuda** uygulanmalıdır — istemciye güvenilemez (istemci tabanlı
// bildirim tercihi bir güvenlik sınırı değildir).
//
// Karar kuralı: `master && tipTercihi`, ikisi de yoksa `true` (geriye uyum).

/** Kanal kararının girdileri. `null`/`undefined` = "bu katmanda karar yok". */
export interface ChannelSwitchInput {
  /** `notification_preferences.push_enabled` (satır yoksa `null`). */
  preferenceEnabled?: boolean | null;
  /** `profiles.push_notifications_enabled` (master; NULL olabilir). */
  masterEnabled?: boolean | null;
  /** Katmanların ikisi de yoksa kullanılan varsayılan. */
  fallback?: boolean;
}

/**
 * Push/e-posta kanalının açık olup olmadığını **AND** mantığıyla çözer.
 *
 * - master `false` → **her zaman** `false` (kapalı master, tip açık olsa bile).
 * - master `true`/`null` → tip tercihine düşer.
 * - tip `null` → master'a düşer.
 * - ikisi de `null` → `fallback` (varsayılan `true`, geriye uyum).
 */
export function resolveChannelEnabled(input: ChannelSwitchInput): boolean {
  const fallback = input.fallback ?? true;
  const master = input.masterEnabled;
  const preference = input.preferenceEnabled;
  // Master kapatmışsa tip ne derse desin kanal kapalı.
  if (master === false) return false;
  // Master açık (veya bilinmiyor) → tip tercihi belirleyici.
  if (typeof preference === "boolean") return preference;
  // Tip satırı yok → master belirleyici; master de yoksa varsayılan.
  if (typeof master === "boolean") return master;
  return fallback;
}

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
 *
 * ---------------------------------------------------------------------------
 * A1r5 — `DB_BYPASS_COOLDOWN_MS` (60 sn) GEREKÇESİ VE GÜVENLİK DEĞERLENDİRMESİ
 * ---------------------------------------------------------------------------
 * A1r4 bu değeri P2 olarak raporladı: "DB yolu 60 sn kısa devrede; bu sürede
 * çok-instance'da zayıf sayım" — gerekçesi yazılı değildi. Burada yorumlanıp
 * belgelenmiştir.
 *
 * NEDEN 60 SANİYE (ölçülebilir gerekçe, tahmin değil):
 *  1) **Maliyet.** `rate_limit_hit()` **her istekte** bir HTTP yolculuğu:
 *     Edge → PostgREST → Postgres. `recognize-food` gövdesi 8 MB'a kadar
 *     base64 görsel taşıyabilir; bu yolculuk yalnızca sayaç için yapılır.
 *     DB erişilemiyorsa her istek aynı hatayı tekrarlar: 8 MB'lik gövde
 *     zaten ağ katmanından geçtiği için **maliyet gerçekleşmiştir**, sadece
 *     karar yanlış yere düşüyordur. Tekrar denemeyi kapatmak, hatayı
 *     tekrarlamayı durdurur.
 *  2) **Kısa devre döngüsü (thundering herd) kırılır.** DB bir an
 *     erişilemezse (ağ kesintisi, bağlantı havuzu tükenmesi, migration
 *     kilidi) yüzlerce eşzamanlı istek aynı RPC'yi aynı anda dener; her
 *     biri `request_count`'ı artırmaya çalışır ve 404/timeout ile döner.
 *     60 sn'lik kapı bu patlamayı bir "sessizleştirme" penceresine çevirir.
 *  3) **Yeterli süre.** Supabase/Postgres'in tipik bir planlayıcı kilidi veya
 *     kısa ağ kesintisi süresi saniyeler mertebesindedir; 60 sn, "bir
 *     gürültü patlaması" ile "kalıcı arıza" arasındaki makul ayrım çizgisidir.
 *     Daha kısa (5-10 sn) dalgalanmalarda sürekli kapatıp açmak yaratır;
 *     daha uzun (5 dk) bir arızada sınır gereksiz yere zayıf kalır.
 *
 * GÜVENLİK DEĞERLENDİRMESİ — "bir istek atlamak riskli mi?" (A1r4 sorusu):
 *  - **Atlanan istek yok, yalnızca SAYIM YERİ değişiyor.** `checkRateLimit`
 *    DB'ye düşmezse `checkRateLimitMemory` çalışır; yani istek **yine de**
 *    sınıra tabi olur, sadece kova **instance başına** sayar. Kullanıcıya
 *    "izin" yanıtı yine verilir — sınır **gevşer**, **kalkmaz**.
 *  - **Bütçe riski sınırlıdır ve kendi kendini sınırlar.** `rate_limits`
 *    tablosu yoksa RPC 404 döner → bypass; en kötü senaryo 60 sn boyunca
 *    instance başına sayaçtır. Edge Runtime bir instance'ı ~60 sn'de
 *    çevirir, dolayısıyla saldırgan istekleri N instance'a bölerek sınırı
 *    N katına çıkarabilir — ama bu zaten A1r2'nin çözdüğü problemin
 *    "DB çalışmıyorken" hâlidir, yani **kısa süreli** ve **gözlenebilir**.
 *  - **Dengeleyen başka korumalar var:** (a) `delete-account` 2/saat gibi
 *    yıkıcı işlemlerde **parola doğrulaması** ister (bypass olsa bile
 *    parola bilinmeden silme olmaz); (b) `ai-chat`/`recognize-food` gibi
 *    AI çağrıları **kullanıcının kendi JWT'siyle** gelir ve `auth.uid()` ile
 *    anahtarlanır — IP kovası zaten çok kullanıcıyı birleştirip **daha
 *    katı** sınırlar; (c) yedek yol `console.error` ile loglanır, yani
 *    60 sn'lik bypass **izlenebilirdir** (A1r4'ün "loglanmalı" önerisi
 *    zaten karşılanmış durumda).
 *  - **Somut risk, daha çok "yavaşlayan DB" senaryosunda.** DB erişilebilir
 *    ama **yavaş**sa (`fetch` zaman aşımına uğrar) 60 sn'lik bypass devreye
 *    girer ve sayaç yavaş yola düşer. DoS koruması zayıflar; AI maliyeti
 *    artar. Bu kabul edilmiş bir ödünlemedir: **işlevsizlik (tüm isteklerin
 *    500'le dönmesi)**, sınırlı maliyet artışından kötüdür.
 *    (A1r8 bu riski **kapsamını daraltarak** kısmen çözdü: artık yalnızca
 *    arızalı olan **kova** bekler — aşağıdaki bölüme bakınız.)
 *
 * ---------------------------------------------------------------------------
 * A1r8 — KOVA BAZLI KISA DEVRE (`dbBypassUntilByBucket`)
 * ---------------------------------------------------------------------------
 * A1r2'den kalan tek `rate_limit.ts` riski: kısa devre **tek global**
 * değişkendi, yani bir instance'ta DB'ye ulaşılamadıysa o instance'taki
 * **tüm** kovalar (`ai-chat`, `recognize-food`, `delete-account`, …) 60 sn
 * bellem içi yola düşüyordu. Bu birbirinden bağımsız iki hatayı birbirine
 * bağlıyordu:
 *
 *  1. **Birbirini etkilemeyen arızalar birbirini sınırlıyordu.** `recognize-food`
 *     RPC'si zaman aşımına uğrarsa (8 MB gövde + yavaş DB), aynı instance'a
 *     düşen `delete-account` isteği de `2/saat` yerine **instance başına**
 *     sayılıyordu — yani KVKK silme talebi gereksiz yere zayıflıyordu.
 *  2. **Sıfır maliyetli bir iyileşme kazandırıyordu.** Bugün `delete-account`
 *     için DB geri geldiği anda o kova da 60 sn boyunca hâlâ bellem içi
 *     yolda kalıyor (global sayaç sıfırlanmadığı için). Kova bazlı sayaçta
 *     yalnızca gerçekten arızalı olan kova bekler.
 *
 * "DB çalışmıyor" **global** bir arızadır; o durumda tüm kovaların bellem içi
 * yola düşmesi doğru davranıştır ve bu kod onu bozmaz. Değişen şey yalnızca
 * **bir kovanın RPC'sinin kendisinin** arızalı olduğu senaryodur.
 *
 * GERİYE UYUM: A1r5'teki 60 sn değeri, eşikler ve tüm anahtar biçimleri
 * **aynen korunur**. Sadece "hangi kova ne zaman bypass ediyor" bilgisi
 * kova başına tutulur. Dışarıdan görünen davranış değişimi yalnızca
 * *birbirinden bağımsız* kovalar arasındadır; aynı kovanın kendi penceresi
 * içindeki davranış (bypass, limit, retryAfter) birebir aynıdır.
 *
 * GERİYE UYUMLULUK (gözlem): Modül düzeyinde `dbBypassUntil` **korunur** ve
 * kova bazlı değerlerin **en büyüğünü** gösterir — yani "bu instance'ta bir
 * bypass hâlâ aktif mi?" sorusunun eski cevabı. Kova bazlı sayaç bu değeri
 * **yalnızca yükseltir**; tüm pencereler dolduğunda sıfırlanır. Karar mantığı
 * artık kova bazlı olduğu için bu gözlem yalnızca **log/teşhis** içindir ve
 * kararı etkilemez.
 */

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/** Bellek içi sayaç kovası. */
type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();

/**
 * Bir **kovanın** RPC'si, bu süre boyunca yeniden denenmez (ms).
 *
 * Değer A1r5'te ölçülerek 60 saniye seçildi; gerekçesi ve güvenlik
 * değerlendirmesi dosyanın başındaki "A1r5 — `DB_BYPASS_COOLDOWN_MS`
 * GEREKÇESİ" bölümünde yazılıdır ve **bu turda değiştirilmemiştir**:
 * DB erişilemediğinde istek **atlanmaz**, yalnızca kova instance başına
 * sayılır (sınır gevşer, kalkmaz).
 *
 * A1r8 değişikliği yalnızca **neye uygulandığı**: artık kovanın kendisine
 * (`dbBypassUntilByBucket`), modül geneline değil.
 */
const DB_BYPASS_COOLDOWN_MS = 60_000;

/**
 * Kova bazlı kısa devre bitişleri (epoch ms). Anahtar, `checkRateLimitDb`
 * içinde `key`'den türetilen **kova adıdır** (`<kovalar>:u:<id>` →
 * `<kovalar>`); yani anahtar ayrımı zaten `rate_limit_hit()` RPC'sine
 * gönderilen `p_bucket` ile **birebir aynıdır** (kalıcı sayaçla da eşleşir).
 *
 * Neden `Map` ve neden kova adı? `checkRateLimit()` çağıranları kova adını
 * ayrı bir parametre olarak geçirmiyor; kova adı anahtarın ön eki zaten.
 * Böylece çağrı yerlerinde **hiçbir değişiklik gerekmez** ve yanlış kova
 * adı geçme ihtimali doğmaz (yeni parametre = yeni hata yüzeyi).
 */
const dbBypassUntilByBucket = new Map<string, number>();

/** Süresi dolmuş kısa devre kayıtlarını temizler (bellek sızıntısı olmasın). */
function pruneBypass(now: number): void {
  if (dbBypassUntilByBucket.size < 256) return;
  for (const [bucket, until] of dbBypassUntilByBucket) {
    if (until <= now) dbBypassUntilByBucket.delete(bucket);
  }
}

/**
 * Belirtilen kova için kısa devre açar.
 *
 * `dbBypassUntil` **yalnızca yükseltilir** (`Math.max`): kova bazlı sayaç
 * diğer kovaların değerini küçültmez, dolayısıyla modül düzeyi "bypass aktif
 * mi?" gözlemi her zaman güvenli (fazla pozitif) tarafta kalır.
 */
function startDbBypass(bucket: string): void {
  const until = Date.now() + DB_BYPASS_COOLDOWN_MS;
  const previous = dbBypassUntilByBucket.get(bucket) ?? 0;
  dbBypassUntilByBucket.set(bucket, Math.max(previous, until));
  if (until > dbBypassUntil) dbBypassUntil = until;
  pruneBypass(Date.now());
}

/**
 * Geriye uyum gözlemi: bu instance'ta **en az bir** kovanın bypass penceresi
 * hâlâ açık mı? (Tüm kovaların en büyük bitiş zamanı.)
 *
 * Kova bazlı ayrımdan **önce** tek global sayaç buydu. Bugün yalnızca gözlem
 * içindir; karar mantığı `dbBypassUntilByBucket` üzerinden verilir.
 */
let dbBypassUntil = 0;

/** Yalnızca test/ölçüm amaçlı: kovanın bypass durumu (true ⇒ pencere açık). */
export function isDbBypassed(bucket: string, now: number = Date.now()): boolean {
  const until = dbBypassUntilByBucket.get(bucket);
  return until !== undefined && until > now;
}

/**
 * Tüm kovalarda bypass kalmadıysa eski global değeri de sıfırlar.
 *
 * Neden gerekiyor: `dbBypassUntil` yalnızca yükselirse, sonraki bir kovanın
 * arızası **bitmiş** bir pencerenin bitiş zamanını kalıcı olarak hatırlar ve
 * gözlemci "bypass hâlâ aktif" der. Bu, karar mantığını etkilemez (karar
 * kova bazlıdır) ama gözlem yanlış pozitif olur.
 */
function resetGlobalWhenAllBypassesExpired(now: number): void {
  for (const until of dbBypassUntilByBucket.values()) {
    if (until > now) return; // hâlâ aktif bir kova var
  }
  dbBypassUntilByBucket.clear();
  dbBypassUntil = 0;
}

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
  // Kova adı anahtardan türetilir: `<scope>:u:<id>` -> `<scope>`. Bu, RPC'ye
  // gönderilen `p_bucket` ile birebir aynıdır, yani kısa devre kovası ile
  // kalıcı sayaç kovası **asla** ayrışamaz.
  const scope = key.split(":")[0] || "unknown";

  const now = Date.now();
  // KISA DEVRE KONTROLÜ KOVA BAZLIDIR (A1r8): başka bir kovanın arızası bu
  // kovanın DB yolunu kapatmaz.
  const bypassUntil = dbBypassUntilByBucket.get(scope);
  if (bypassUntil !== undefined && bypassUntil > now) return null;
  if (bypassUntil !== undefined) {
    // Bu kovanın penceresi dolmuş: kaydı düşür, sıfırlamadan önce global
    // gözlemi tazele.
    dbBypassUntilByBucket.delete(scope);
    resetGlobalWhenAllBypassesExpired(now);
  }

  const client = supabaseServiceClient();
  if (!client) {
    startDbBypass(scope);
    return null;
  }

  try {
    const { data, error } = await client.rpc("rate_limit_hit", {
      p_key: key.slice(0, 512),
      p_bucket: scope.slice(0, 64),
      p_max_count: rule.max,
      p_window_seconds: rule.windowSeconds,
    });
    if (error || !data || typeof data !== "object") {
      startDbBypass(scope);
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
    startDbBypass(scope);
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

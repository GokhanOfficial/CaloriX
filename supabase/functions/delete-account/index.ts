// Hesap silme (KVKK / Google Play "Hesap Silme" zorunluluğu).
//
// Amaç: kullanıcının **kendi** hesabını ve tüm kişisel verisini, mevcut parolası
// ile onayladıktan sonra kalıcı olarak silmek.
//
// Güvenlik kararları (2026-09-28, A1r3):
//  - Parola onayı zorunludur. JWT'yi elinde tutan biri (cihazda açık oturum,
//    XSS) başkasının hesabını silemez; hesabın kendisi de onay gerektirir.
//  - **RLS'e güvenilmez**: `user_roles` gibi tablolarda DELETE politikası
//    kasıtlı olarak YOKTUR, `notifications` INSERT'i yalnızca service_role'a
//    açıktır. Bu yüzden tüm silme service_role ile yapılır ve kullanıcı kapsamı
//    (`userId`) **doğrulanmış JWT'den** gelir; istek gövdesinden hiçbir kimlik
//    bilgisi kabul edilmez (BOLA koruması).
//  - Sıralama: storage → uygulama tabloları → `auth.admin.deleteUser()`.
//    Son adımda FK `ON DELETE CASCADE` devreye girerek kalan her şeyi temizler
//    (A1r5: `foods.created_by` de CASCADE — URUN-KARARLARI 3-A; kullanıcının
//    eklediği gıdalar ve `food_nutrition` kayıtları da hesapla birlikte silinir,
//    `created_by IS NULL` seed gıdalar **korunur**).
//  - Idempotent: her adım "yoksa başarılı" sayılır; yarıda kalan bir silme
//    yeniden denendiğinde tamamlanır.
//  - İstemciye SABİT mesaj döner; hiçbir tablo/kolom/ayar adı sızmaz.
//
// `INTERNAL_FUNCTION_TOKEN` KULLANILMAZ: bu fonksiyon bir cron değil, kullanıcı
// JWT'siyle çağrılan bir uç noktadır.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { AuthError, readJsonBody, requireUserContext } from "../_shared/auth.ts";
import { errorResponse, jsonResponse, preflightResponse } from "../_shared/http.ts";
import { checkRateLimit, rateLimitKey } from "../_shared/rate_limit.ts";
import { ValidationError, requireString } from "../_shared/validate.ts";
import {
  DATA_TABLES,
  DELETION_PARTIAL_MESSAGE,
  DELETION_SUCCESS_MESSAGE,
  assertSafeDeletionOrder,
  isAlreadyDeletedAuthError,
  mapPasswordErrorToStatus,
  ownerFilterColumn,
} from "./helpers.ts";

// ---------------------------------------------------------------------------
// Uygulama
// ---------------------------------------------------------------------------

/**
 * Silme denemeleri: **saatte 2** (kötüye kullanım / CSRF-zorlama koruması).
 *
 * A1r4'ün revizyonu: A1r3 `max: 5` koymuştu. Beş denemenin anlamı yok çünkü
 * bu bir **yıkıcı ve geri alınamaz** işlem: hesabı silebilmek için parolanın
 * **doğru** olması gerekir, yani zorlayan taraf parolayı zaten biliyordur.
 * 5 deneme, saldırganın/istenmeyen bir eylemin 5 silme yapmasına izin verir.
 * Doğru parolayla yapılan **kısmi silme** (bkz. `DELETION_PARTIAL_MESSAGE`)
 * zaten bu kotayı tüketir, ama kullanıcı kendi hesabını silmek istediğinde
 * bu tavan ona **rahatsızlık** yaratabilir. Gerçek tehdit modeli:
 *   - CSRF zorlama: saldırganın `Authorization` başlığı gönderemez (CORS
 *     `allowed headers` yalnızca tarayıcı origin'lerine izin verir, üstelik
 *     `access-control-allow-credentials` yok) → zaten mümkün değil.
 *   - Oturum hırsızlığı (XSS): saldırgan oturumu kullanabilir ama
 *     **parolayı bilmez** → silemez.
 * Dolayısıyla kotanın birincil işi parola tahminini yavaşlatmak; 2 deneme
 * saatte zaten kaba kuvvet için yeterince katıdır, başarılı silmeyi ise
 * rahatsız etmez. `checkRateLimit` **kullanıcı bazlıdır**
 * (`rateLimitKey(scope, req, userId)` → `delete-account:u:<uuid>`), yani
 * IP tabanlı paylaşılan kotanın aksine bir kullanıcı başka birini
 * etkilemez.
 */
const RATE_LIMIT = { windowSeconds: 3600, max: 2 };

/** Yanlış parola denemeleri sonrası ek doğrulama yavaşlatması (kaba kuvvet zorlaştırma). */
const PASSWORD_FAIL_DELAY_MS = 400;

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST") return errorResponse(req, 405, "Yalnızca POST desteklenir");

  try {
    // 1) Kimlik doğrulama: `requireUserContext` JWT'yi **sunucu tarafında**
    //    doğrular (payload decode YAPILMAZ) ve kapsamı `userId` ile sabitler.
    const { userId, userClient, serviceClient } = await requireUserContext(req, { serviceRole: true });
    if (!userId) return errorResponse(req, 401, "Yetkisiz");

    // 2) Kaba kuvvet / CSRF-zorlama koruması.
    const limit = await checkRateLimit(rateLimitKey("delete-account", req, userId), RATE_LIMIT);
    if (!limit.allowed) {
      return jsonResponse(req, { error: "Çok fazla deneme yapıldı, lütfen bekleyin" }, 429, {
        "Retry-After": String(limit.retryAfter),
      });
    }

    // 3) Gövde: **yalnızca** parola. Kullanıcı kimliği gövdeden ALINMAZ.
    const body = await readJsonBody(req, 4_096);
    const password = requireString(body.password, "password", 256);

    // 4) Parola doğrulaması — hesabın **kendisine** ait olduğunu kanıtlar.
    //    `userClient` çağıranın kendi JWT'siyle açılmıştır; bu yüzden `signInWithPassword`
    //    doğru kullanıcıyı doğrular. Yanlışsa 401 + sabit mesaj.
    const { data: userData, error: passwordError } = await userClient.auth.getUser();
    if (passwordError || !userData?.user?.email) {
      console.error("Hesap silme: kullanıcı e-postası alınamadı", passwordError?.message);
      return errorResponse(req, 500, "İstek işlenemedi");
    }

    const { error: signInError } = await userClient.auth.signInWithPassword({
      email: userData.user.email,
      password,
    });
    if (signInError) {
      const mapped = mapPasswordErrorToStatus({
        message: signInError.message,
        status: (signInError as { status?: number }).status,
      });
      if (mapped.status !== 429) {
        // Sabit gecikme: parola tahmin etmeyi kaba kuvvetle zorlaştırır.
        await new Promise((resolve) => setTimeout(resolve, PASSWORD_FAIL_DELAY_MS));
      }
      // Detay yalnızca sunucu logunda; istemciye tablo/kolon sızan metin dönmez.
      console.error("Hesap silme reddedildi: parola doğrulaması başarısız");
      return errorResponse(req, mapped.status, mapped.publicMessage);    }

    // 5) Silme sırası (doğrulanır — bkz. assertSafeDeletionOrder).
    assertSafeDeletionOrder();

    // 6) Storage: kullanıcının klasörü. Kova listesini **yoklamak yerine**
    //    tüm kovaları tarar; yeni kova eklenirse silme kapsamı genişler.
    await deleteUserStorageFiles(serviceClient, userId);

    // 7) Uygulama tabloları — service_role (RLS atlanır) ve idempotent biçimde.
    //    Kısmi silme (A1r4): hata alan tablolar **raporlanır**, ama auth
    //    kaydı silinmeden önce kullanıcıya **başarı** denmez.
    const rows = await deleteUserRows(serviceClient, userId);

    // 8) Son adım: auth kullanıcısını sil. `ON DELETE CASCADE` ile kalan tüm
    //    satırlar (user_roles dahil, `foods.created_by` dahil) temizlenir.
    //    Idempotent: kullanıcı zaten yoksa GoTrue "User not found" döner ve bu
    //    **başarı** sayılır — ama **yalnızca** o hata için (bkz.
    //    `isAlreadyDeletedAuthError`; "schema not found" gibi başka hatalar
    //    artık kısmi silme mesajına düşer).
    await deleteAuthUser(serviceClient, userId);

    console.log(
      `Hesap silindi: user=${userId} silinen=${rows.deleted.join(",") || "-"} ` +
        `basarisiz=${rows.failed.length}`,
    );

    if (rows.failed.length > 0) {
      // Yalnızca `auth.admin.deleteUser()` **başarısız** olduğu için bu dal
      // çalışmışsa, yani auth kaydı duruyor ve silme yeniden denenebilir.
      // Bu yüzden istemciye başarı diyoruz ama **açıkça** eksik bırakıldığını
      // söylüyoruz: KVKK "sil" talebi karşılanmadı, kullanıcı tekrar
      // denemeli. Gövde sabit ve şemasız.
      return jsonResponse(req, {
        success: true,
        message: DELETION_PARTIAL_MESSAGE,
        retryRecommended: true,
      });
    }
    return jsonResponse(req, { success: true, message: DELETION_SUCCESS_MESSAGE });
  } catch (error) {
    if (error instanceof AuthError) {
      return errorResponse(req, error.status, error.status === 401 ? "Yetkisiz" : "İstek işlenemedi");
    }
    if (error instanceof ValidationError) {
      // Alan adı/şema sızdırmayan sabit mesaj.
      return errorResponse(req, error.status, "Eksik veya geçersiz istek");
    }
    console.error("delete-account beklenmeyen hata", error);
    return errorResponse(req, 500, "Hesap silinemedi, lütfen daha sonra tekrar deneyin");
  }
};

// ---------------------------------------------------------------------------
// Silme adımları (her biri idempotent)
// ---------------------------------------------------------------------------

type ServiceClient = SupabaseClient;

/** Kullanıcıya ait storage dosyalarını siler. Hata durumunda silmeyi düşürmez. */
async function deleteUserStorageFiles(client: ServiceClient, userId: string): Promise<void> {
  try {
    const { data: buckets, error: bucketError } = await client.storage
      .listBuckets();
    if (bucketError || !buckets || buckets.length === 0) return;
    for (const bucket of buckets) {
      // Politikalar `<user_id>/<dosya>` düzenini zorunlu kılar; yine de burada
      // sunucu tarafında ayrıca filtreliyoruz (kullanıcı kapsamı asla genişlemez).
      const { error } = await client.storage.from(bucket.id).remove([`${userId}`]);
      if (error) {
        console.error(`Storage silinemedi (bucket=${bucket.id}):`, error.message);
      }
    }
  } catch (error) {
    // Storage erişilemezse hesap silme **durdurulmaz**: KVKK için kritik olan
    // veritabanı + auth kayıtlarıdır; dosyalar sonradan temizlenebilir.
    console.error("Storage temizliği atlandı:", error);
  }
}

/** Kullanıcının tüm uygulama satırlarını siler. */
export async function deleteUserRows(
  client: ServiceClient,
  userId: string,
): Promise<{ deleted: string[]; failed: Array<{ table: string; message: string }> }> {
  const deleted: string[] = [];
  const failed: Array<{ table: string; message: string }> = [];
  for (const table of DATA_TABLES) {
    const column = ownerFilterColumn(table);
    const { error } = await client
      .from(table)
      .delete()
      .eq(column, userId);
    if (error) {
      // A1r4'ün bulduğu sessiz veri kaybı: buradaki `continue` ile hata
      // yutuluyordu. `deleted` listesine girmediği için çağıran hatayı
      // **fark edemiyor**, `console.error` da üretim loglarında çoğu zaman
      // görülmüyor. Üstelik bu tablo bir sonraki adımda `auth.admin.deleteUser()`
      // ile **kalıcı olarak temizlenmeyebilir** (bkz. `tablesWithoutCascade`):
      //   - `notification_preferences` FK'si `ON DELETE CASCADE` → temizlenir.
      //   - `profiles` silinemezse kullanıcının profili **kalır** ve
      //     `auth.admin.deleteUser()` de FK ihlali nedeniyle BAŞARISIZ olur.
      // Yani sessizce "başarılı" dönen bir 200, KVKK açısından eksik silmedir.
      // Bu yüzden: hatayı topla, işin sonunda **gürültü taşımayan** ama
      // **başarısız** bir sonuç üret (aşağıdaki çağıran).
      const message = error.message;
      if (/not found|does not exist|schema cache/i.test(message)) {
        // Tablo/şema yok: hedef veri de yoktur, idempotent başarı sayılır.
        deleted.push(table);
        continue;
      }
      failed.push({ table, message });
      continue;
    }
    deleted.push(table);
  }
  if (failed.length > 0) {
    // Detay yalnızca sunucu logunda (istemciye tablo/kolon adı sızmaz).
    console.error(
      "Hesap silme: bazı tablolar temizlenemedi: " +
        failed.map((f) => `${f.table} (${f.message})`).join(", "),
    );
  }
  return { deleted, failed };
}

/** `auth.admin.deleteUser()` — idempotent (kullanıcı yoksa başarı sayılır). */
export async function deleteAuthUser(client: ServiceClient, userId: string): Promise<void> {
  const { error } = await client.auth.admin.deleteUser(userId);
  if (!error) return;
  // A1r5: A1r4'ün bulduğu **çok geniş** `includes("not found")` eşleşmesi
  // daraltıldı.
  // A1r8: karar artık önce GoTrue'nun **mühürlü hata kodunu** (`error.code`,
  // kaynak: supabase/auth v2.185.0 `apierrors/errorcode.go` →
  // `ErrorCodeUserNotFound = "user_not_found"`) okuyor; mesaj deseni ikincil
  // sinyal olarak kaldı (eski sürüm / vakalar).
  // `"schema not found"` / `"session not found"` gibi hatalar istisna
  // fırlatır → çağıran `DELETION_PARTIAL_MESSAGE` döner ve kullanıcıya
  // **başarı** denmez (KVKK eksik silme iddiası olmaz).
  if (isAlreadyDeletedAuthError({ message: error.message, status: error.status, code: error.code })) {
    // Zaten silinmiş → idempotent başarı.
    return;
  }
  throw error;
}

serve(handler);

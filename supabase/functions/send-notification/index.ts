// Bildirim gönderimi (web push + e-posta + notifications tablosu).
// Güvenlik: P0 kapatıldı — fonksiyon artık anonim/kanonik (service_role olmayan)
// bir JWT ile çağrıldığında **herhangi bir kullanıcıya** bildirim gönderemez.
// - Çağıran, hedef kullanıcının kendisi olmak zorunda (userId === doğrulanmış uid).
// - Dahili (cron) çağırma, `x-calorix-internal-token` başlığı ile korunur ve
//   yalnızca sunucu tarafındaki `INTERNAL_FUNCTION_TOKEN` değerini bilen taraf yapabilir.
// - Push endpoint'i Web Push sağlayıcı hostları ile sınırlandırılır (SSRF/abus).
// - Push gövdesi RFC 8291 `aes128gcm` ile **şifrelenir** (2026-09-28, A1r3);
//   düz metin gönderilmez. VAPID imzası ile gövde şifreleme birlikte çalışır:
//   RFC 8291 §3.3 gereği şifreli istekte `Authorization: vapid` **zorunludur**.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Resend } from "https://esm.sh/resend@2.0.0";
import { AuthError, readJsonBody, requireUserContext } from "../_shared/auth.ts";
import { errorResponse, isAllowedPushEndpoint, jsonResponse, preflightResponse, resolveChannelEnabled } from "../_shared/http.ts";
import { checkRateLimit, rateLimitKey } from "../_shared/rate_limit.ts";
import { ValidationError, requireEnum, requireUuid } from "../_shared/validate.ts";
import {
  buildVapidAuthorization,
  deriveVapidPublicKey,
  importVapidPrivateKey,
  preparePushPayload,
} from "../_shared/vapid.ts";
import { encryptPushBody, PushEncryptionError } from "../_shared/web_push_crypto.ts";

const NOTIFICATION_TYPES = [
  "weigh_in",
  "daily_log",
  "water",
  "goal_achieved",
  "weekly_summary",
] as const;
type NotificationType = (typeof NOTIFICATION_TYPES)[number];

/** Saniyede 1 bildirim: kötüye kullanımda e-posta/push israfını sınırlar. */
const RATE_LIMIT = { windowSeconds: 60, max: 60 };

interface PushSubscription {
  endpoint: string;
  p256dh: string;
  auth: string;
}

// Email templates
// A1r4: `title` parametresi Tur 1'den kalan **ölü parametre** idi (hiçbir
// şablonda kullanılmıyor; başlık şablonlarda sabit). Kaldırıldı — ölü
// parametre, ileride "burada title kullanılıyor sanıp" hata yapılmasına
// yol açan yanıltıcı bir imzadır. Test, imzanın senkron kaldığını doğrular.
const getEmailTemplate = (type: string, message: string, userName: string) => {
  // HTML enjeksiyonuna karşı kullanıcı/AI metinleri kaçırılır.
  const safeMessage = escapeHtml(message).replace(/\n/g, "<br />");
  const safeName = escapeHtml(userName);
  const templates: Record<string, string> = {
    weigh_in: `
      <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #10b981 0%, #059669 100%); padding: 30px; border-radius: 12px; text-align: center; color: white;">
          <h1 style="margin: 0 0 10px 0;">⚖️ Tartılma Zamanı!</h1>
        </div>
        <div style="padding: 30px; background: #f9fafb; border-radius: 12px; margin-top: 20px;">
          <p style="font-size: 18px; color: #374151;">Merhaba ${safeName},</p>
          <p style="font-size: 16px; color: #6b7280; line-height: 1.6;">${safeMessage}</p>
          <a href="https://calorix.app" style="display: inline-block; background: #10b981; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; margin-top: 20px;">Kilonu Kaydet</a>
        </div>
      </div>
    `,
    daily_log: `
      <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); padding: 30px; border-radius: 12px; text-align: center; color: white;">
          <h1 style="margin: 0 0 10px 0;">📝 Kayıt Hatırlatması</h1>
        </div>
        <div style="padding: 30px; background: #f9fafb; border-radius: 12px; margin-top: 20px;">
          <p style="font-size: 18px; color: #374151;">Merhaba ${safeName},</p>
          <p style="font-size: 16px; color: #6b7280; line-height: 1.6;">${safeMessage}</p>
          <a href="https://calorix.app" style="display: inline-block; background: #f59e0b; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; margin-top: 20px;">Öğün Ekle</a>
        </div>
      </div>
    `,
    water: `
      <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); padding: 30px; border-radius: 12px; text-align: center; color: white;">
          <h1 style="margin: 0 0 10px 0;">💧 Su İçme Zamanı!</h1>
        </div>
        <div style="padding: 30px; background: #f9fafb; border-radius: 12px; margin-top: 20px;">
          <p style="font-size: 18px; color: #374151;">Merhaba ${safeName},</p>
          <p style="font-size: 16px; color: #6b7280; line-height: 1.6;">${safeMessage}</p>
          <a href="https://calorix.app" style="display: inline-block; background: #3b82f6; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; margin-top: 20px;">Su Ekle</a>
        </div>
      </div>
    `,
    goal_achieved: `
      <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); padding: 30px; border-radius: 12px; text-align: center; color: white;">
          <h1 style="margin: 0 0 10px 0;">🎉 Tebrikler!</h1>
        </div>
        <div style="padding: 30px; background: #f9fafb; border-radius: 12px; margin-top: 20px;">
          <p style="font-size: 18px; color: #374151;">Merhaba ${safeName},</p>
          <p style="font-size: 16px; color: #6b7280; line-height: 1.6;">${safeMessage}</p>
        </div>
      </div>
    `,
    weekly_summary: `
      <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #ec4899 0%, #db2777 100%); padding: 30px; border-radius: 12px; text-align: center; color: white;">
          <h1 style="margin: 0 0 10px 0;">📊 Haftalık Özetiniz</h1>
        </div>
        <div style="padding: 30px; background: #f9fafb; border-radius: 12px; margin-top: 20px;">
          <p style="font-size: 18px; color: #374151;">Merhaba ${safeName},</p>
          <div style="font-size: 16px; color: #6b7280; line-height: 1.6;">${safeMessage}</div>
          <a href="https://calorix.app/analytics" style="display: inline-block; background: #ec4899; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; margin-top: 20px;">Detayları Gör</a>
        </div>
      </div>
    `,
  };
  return templates[type] || templates.daily_log;
};

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// --- Web Push (VAPID, RFC 8292) ---------------------------------------------

/**
 * VAPID anahtar çiftini süreç ömrü boyunca önbelleğe alır. Her bildirim için
 * PKCS#8 içe aktarma + public key türetme yapmak gereksiz CPU maliyetidir;
 * anahtar döndürmedikçe önbellek geçerli kalır.
 */
let vapidKeys: { privateKey: CryptoKey; publicKey: string; subject: string } | null = null;

async function loadVapidKeys(): Promise<{ privateKey: CryptoKey; publicKey: string; subject: string } | null> {
  if (vapidKeys) return vapidKeys;
  const privateKeyRaw = (Deno.env.get("VAPID_PRIVATE_KEY") || "").trim();
  const subject = (Deno.env.get("VAPID_SUBJECT") || "").trim();
  if (!privateKeyRaw || !subject) {
    // Sessizce yutulmaz: e-posta akışı çalışmaya devam eder, ama push'un neden
    // gitmediği logda açıkça görünür (A1 raporu P3 izlenebilirlik maddesi).
    console.error(
      "VAPID yapılandırması eksik (VAPID_PRIVATE_KEY/VAPID_SUBJECT) — push atlandı, e-posta akışı sürüyor",
    );
    return null;
  }
  try {
    const privateKey = await importVapidPrivateKey(privateKeyRaw);
    // VAPID_PUBLIC_KEY verilmemişse private key'den türet (RFC 8292 `k` = uygulama
    // sunucusu anahtarı; istemcide kayıtlı applicationServerKey ile eşleşmelidir).
    const configured = (Deno.env.get("VAPID_PUBLIC_KEY") || "").trim();
    const publicKey = configured || await deriveVapidPublicKey(privateKey);
    vapidKeys = { privateKey, publicKey, subject };
    return vapidKeys;
  } catch (error) {
    console.error("VAPID anahtarı yüklenemedi:", error);
    return null;
  }
}

/** Push isteğinin sonucu — abonelik temizliği için ayrıntı taşır. */
interface PushResult {
  ok: boolean;
  /** Push servisi abone öldü (404 Gone / 410) — kayıt silinmeli. */
  expired: boolean;
}

async function sendPushNotification(
  subscription: PushSubscription,
  payload: { title: string; body: string; data?: Record<string, unknown> },
  keys: { privateKey: CryptoKey; publicKey: string; subject: string },
): Promise<PushResult> {
  // Kullanıcının kaydettiği endpoint'i doğrulanmazsa saldırgan kendi sunucusuna
  // istek yaptırabilir (SSRF / uygulama içi kalıcı istek).
  if (!isAllowedPushEndpoint(subscription.endpoint)) {
    console.error("İzin verilmeyen push endpoint'i engellendi");
    return { ok: false, expired: false };
  }

  let authorization: string;
  try {
    // `aud` = push endpoint'inin origin'i (RFC 8292 §2.1).
    authorization = await buildVapidAuthorization({
      subject: keys.subject,
      audience: new URL(subscription.endpoint).origin,
      privateKey: keys.privateKey,
      publicKey: keys.publicKey,
    });
  } catch (error) {
    console.error("VAPID yetkilendirme başlığı üretilemedi:", error);
    return { ok: false, expired: false };
  }

  let plaintext: string;
  try {
    // Şema + 4096 bayt sınırı uygulanır (aşırı uzun gövde push servisinde reddedilir).
    // Bu sınır **şifrelenmemiş** JSON içindir; şifreli gövde ~%3 daha büyüktür
    // (21 bayt başlık + 16 bayt GCM etiketi), `encryptPushBody` de ayrıca
    // 4096 baytlık push sınırını denetler.
    plaintext = preparePushPayload(payload).body;
  } catch (error) {
    console.error("Push payload reddedildi:", error);
    return { ok: false, expired: false };
  }

  // RFC 8291 `aes128gcm` şifrelemesi. `auth`/`p256dh` bozuksa PushEncryptionError
  // fırlatır; burada YUTULMAZ — push bu abonelik için atlanır, e-posta akışı ve
  // `notifications` kaydı normal devam eder (A1'in süreklilik maddesi).
  let encrypted: { headers: Record<string, string>; body: Uint8Array };
  try {
    encrypted = await encryptPushBody({
      authSecret: subscription.auth,
      p256dh: subscription.p256dh,
      plaintext,
      // 24 saat: kullanıcı uygulamayı kapattıysa bildirim bir sonraki açılışta görünür.
      ttlSeconds: 86_400,
      urgency: "normal",
    });
  } catch (error) {
    if (error instanceof PushEncryptionError) {
      // Abonelik anahtarları bozuk/eksik — bu bir hata değil, elde edilemeyen
      // bir abonelik demektir. Neden loglanır ama akış kırılmaz.
      console.error(`Push şifrelenemedi (abonelik anahtarı geçersiz), atlandı: ${error.message}`);
    } else {
      console.error("Push şifreleme hatası:", error);
    }
    return { ok: false, expired: false };
  }

  try {
    const response = await fetch(subscription.endpoint, {
      method: "POST",
      headers: {
        ...encrypted.headers,
        // RFC 8291 §3.3: `aes128gcm` içerik şifrelemesinde VAPID yetkilendirmesi
        // zorunludur; push servisi imzasız şifreli isteği reddeder.
        Authorization: authorization,
      },
      signal: AbortSignal.timeout(10_000),
      body: encrypted.body as unknown as BodyInit,
    });

    if (response.status !== 201) {
      // Hata gövdesi yalnızca sunucu loguna, kısaltılmış ve temizlenmiş halde yazılır
      // (base64 anahtar/JWT veya endpoint sızdırmamak için token'lar maskelenir).
      const raw = (await response.text()).slice(0, 300);
      const safe = raw
        .replace(/[A-Za-z0-9_-]{40,}/g, "<redacted>")
        .replace(/[\r\n]+/g, " ")
        .trim();
      console.error(`Push reddedildi: status=${response.status} body=${safe}`);
      return { ok: false, expired: response.status === 404 || response.status === 410 };
    }

    return { ok: true, expired: false };
  } catch (error) {
    console.error("Push gönderim hatası:", error);
    return { ok: false, expired: false };
  }
}

// Send email notification
async function sendEmailNotification(
  email: string,
  userName: string,
  type: string,
  title: string,
  message: string,
): Promise<boolean> {
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  if (!resendApiKey) {
    console.error("RESEND_API_KEY yapılandırılmamış");
    return false;
  }

  const resend = new Resend(resendApiKey);

  try {
    const emailResponse = await resend.emails.send({
      from: "CaloriX <notifications@resend.dev>",
      to: [email],
      subject: title,
      html: getEmailTemplate(type, message, userName),
    });

    console.log("E-posta gönderildi:", emailResponse?.data?.id ?? "bilinmiyor");
    return true;
  } catch (error) {
    console.error("E-posta gönderim hatası:", error);
    return false;
  }
}

/**
 * Çağrının "dahili" (check-reminders gibi sunucu tarafı cron işi) olup olmadığını
 * doğrular.
 *
 * Güvenlik notu: `x-calorix-internal: 1` gibi bir başlık istemcinin de taklit
 * edebileceği bir değerdir; bu nedenle **yalnızca** token tanımlıysa kabul edilir.
 * Token tanımlı değilse dahili çağrı için service_role JWT'si zorunlu kılınır
 * (`isServiceRoleJwt`). Üretimde `INTERNAL_FUNCTION_TOKEN` tanımlanmalıdır.
 */
async function isInternalCall(req: Request): Promise<boolean> {
  const expected = Deno.env.get("INTERNAL_FUNCTION_TOKEN");
  if (expected) {
    return req.headers.get("x-calorix-internal-token") === expected;
  }
  console.warn("INTERNAL_FUNCTION_TOKEN tanımlı değil; dahili çağrı için service_role JWT'si bekleniyor.");
  return await isServiceRoleJwt(req);
}

/** `Authorization` başlığı service_role yetkisine sahip mi? (sunucu tarafında doğrulanır) */
async function isServiceRoleJwt(req: Request): Promise<boolean> {
  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) return false;
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return false;

  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser();
  if (error || !data?.user) return false;
  const appMetadata = (data.user.app_metadata ?? {}) as Record<string, unknown>;
  return appMetadata.role === "service_role";
}

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST") return errorResponse(req, 405, "Yalnızca POST desteklenir");

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    if (!supabaseUrl) return errorResponse(req, 500, "Sunucu yapılandırması eksik");

    // 1) Yetkilendirme: ya doğrulanmış kullanıcı JWT'si ya da dahili çağrı.
    const internal = await isInternalCall(req);
    if (!internal) {
      // Kanonik olmayan (anon/service_role) JWT bu fonksiyona kabul edilmez.
      const { userId } = await requireUserContext(req, { serviceRole: false });

      const body = await readJsonBody(req);
      const targetUserId = requireUuid(body.userId, "userId");
      // 2) Yetki kapsamı (BOLA): bildirim yalnızca sahibine gönderilebilir.
      if (targetUserId !== userId) {
        console.error(`Yetkisiz bildirim denemesi: ${userId} -> ${targetUserId}`);
        return errorResponse(req, 403, "Bu işlem için yetkiniz yok");
      }
      return await processNotification(req, body, targetUserId, false);
    }

    const body = await readJsonBody(req);
    const targetUserId = requireUuid(body.userId, "userId");
    return await processNotification(req, body, targetUserId, true);
  } catch (error) {
    if (error instanceof AuthError) return errorResponse(req, error.status, error.status === 401 ? "Yetkisiz" : "İstek işlenemedi");
    // A1r4: sabit mesaj — `ValidationError` metni alan adı/şema sızdırır.
    if (error instanceof ValidationError) {
      console.error("send-notification doğrulama hatası:", error.message);
      return errorResponse(req, error.status, "Eksik veya geçersiz istek");
    }
    console.error("send-notification beklenmeyen hata", error);
    return errorResponse(req, 500, "Beklenmeyen bir hata oluştu");
  }
};

async function processNotification(
  req: Request,
  body: Record<string, unknown>,
  userId: string,
  internal: boolean,
): Promise<Response> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) return errorResponse(req, 500, "Sunucu yapılandırması eksik");

  // Kullanıcı bazlı kaba hız sınırı (e-posta/push israfı ve suistimal koruması).
  const limit = await checkRateLimit(rateLimitKey("send-notification", req, userId), RATE_LIMIT);
  if (!limit.allowed) {
    return jsonResponse(req, { error: "Çok fazla bildirim gönderildi" }, 429, {
      "Retry-After": String(limit.retryAfter),
    });
  }

  // service_role kullanılır: notifications tablosuna INSERT politikası yalnızca
  // service_role'a açıktır (bkz. 20260115162000_notifications_policy.sql).
  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const type = requireEnum(body.type, "type", NOTIFICATION_TYPES) as NotificationType;
  const title = requireTitle(body.title);
  const message = requireMessage(body.message);
  const data = (body.data && typeof body.data === "object" && !Array.isArray(body.data))
    ? (body.data as Record<string, unknown>)
    : undefined;

  console.log(`Bildirim işleniyor: kullanıcı=${userId} tip=${type} kaynak=${internal ? "dahili" : "kullanıcı"}`);

  // Get user profile
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("email, display_name, push_notifications_enabled, email_notifications_enabled")
    .eq("id", userId)
    .single();

  if (profileError || !profile) {
    console.error("Profil bulunamadı:", profileError?.message);
    return errorResponse(req, 404, "Kullanıcı profili bulunamadı");
  }

  // Get notification preferences for this type
  const { data: preference } = await supabase
    .from("notification_preferences")
    .select("*")
    .eq("user_id", userId)
    .eq("notification_type", type)
    .maybeSingle();

  // ⭐ Kanal kararı **AND** mantığıyla (A1r10, P1 düzeltmesi).
  //
  // Eski karar `preference?.push_enabled ?? profile.push_notifications_enabled
  // ?? true` idi. `??` yalnız `NULL` üstüne düştüğü için, `notification_
  // preferences`'a satır yazan ilk istemciden sonra **profil master anahtarı
  // hiç okunmuyordu**: kullanıcı üstteki "Push Bildirimleri" anahtarını
  // kapatırsa bile tip bazlı `true` satırları bildirimi göndermeye devam eder.
  //
  // A4r8 bunu **istemci tarafında** `applyMasterSwitches` ile kapattı; bu tek
  // katmandır ve DB'de zaten yazılmış satırları (yedek içe aktarım, eski
  // istemci, elle SQL) engellemez. İstemci tabanlı bildirim tercihi bir
  // güvenlik sınırı **değildir** — karar sunucuda verilir.
  const pushEnabled = resolveChannelEnabled({
    preferenceEnabled: preference?.push_enabled,
    masterEnabled: profile.push_notifications_enabled,
  });
  const emailEnabled = resolveChannelEnabled({
    preferenceEnabled: preference?.email_enabled,
    masterEnabled: profile.email_notifications_enabled,
  });

  let pushSent = false;
  let emailSent = false;

  // Send push notification
  if (pushEnabled) {
    const keys = await loadVapidKeys();
    if (!keys) {
      // VAPID eksik: push atlanır ama e-posta ve DB kaydı akışı bozulmaz.
      console.warn(`Bildirim ${userId} için push atlandı (VAPID yapılandırması eksik)`);
    } else {
      const { data: subscriptions } = await supabase
        .from("push_subscriptions")
        .select("id, endpoint, p256dh, auth")
        .eq("user_id", userId);

      // 404/410 dönen abonelikler birikir ve her bildirimde tekrar denenir;
      // push servisi öldüğünü bildirdiğinde kayıt silinir.
      const expiredIds: string[] = [];
      for (const sub of subscriptions || []) {
        const result = await sendPushNotification(
          { endpoint: sub.endpoint, p256dh: sub.p256dh, auth: sub.auth },
          { title, body: message, data },
          keys,
        );
        if (result.ok) pushSent = true;
        if (result.expired) expiredIds.push(sub.id as string);
      }

      if (expiredIds.length > 0) {
        const { error: cleanupError } = await supabase
          .from("push_subscriptions")
          .delete()
          .eq("user_id", userId)
          .in("id", expiredIds);
        if (cleanupError) {
          console.error("Ölü push aboneliği silinemedi:", cleanupError.message);
        } else {
          console.log(`${expiredIds.length} ölü push aboneliği temizlendi (user=${userId})`);
        }
      }
    }
  }

  // Send email notification
  if (emailEnabled && profile.email) {
    emailSent = await sendEmailNotification(
      profile.email,
      profile.display_name || "Kullanıcı",
      type,
      title,
      message,
    );
  }

  // Save notification to database
  // NOT: notifications.type CHECK kısıtı legacy değerleri kabul eder; yeni migration
  // CHECK'i send-notification/send-notification'ın gönderdiği değerlerle uyumlu hale
  // getirir. INSERT başarısız olursa push/email yine gönderilmiş olabilir (loglanır).
  const { error: insertError } = await supabase.from("notifications").insert({
    user_id: userId,
    title,
    message,
    type,
    push_sent: pushSent,
    email_sent: emailSent,
  });

  if (insertError) {
    console.error("Bildirim kaydedilemedi:", insertError.message);
  }

  console.log(`Bildirim tamam: push=${pushSent} email=${emailSent}`);
  return jsonResponse(req, { success: true, pushSent, emailSent });
}

function requireTitle(value: unknown): string {
  if (typeof value !== "string" || !value.trim()) throw new ValidationError("title zorunlu");
  if (value.length > 120) throw new ValidationError("title en fazla 120 karakter olabilir");
  return value.trim();
}

function requireMessage(value: unknown): string {
  if (typeof value !== "string" || !value.trim()) throw new ValidationError("message zorunlu");
  if (value.length > 5000) throw new ValidationError("message en fazla 5000 karakter olabilir");
  return value.trim();
}

serve(handler);

// Bildirim gönderimi (web push + e-posta + notifications tablosu).
// Güvenlik: P0 kapatıldı — fonksiyon artık anonim/kanonik (service_role olmayan)
// bir JWT ile çağrıldığında **herhangi bir kullanıcıya** bildirim gönderemez.
// - Çağıran, hedef kullanıcının kendisi olmak zorunda (userId === doğrulanmış uid).
// - Dahili (cron) çağırma, `x-calorix-internal-token` başlığı ile korunur ve
//   yalnızca sunucu tarafındaki `INTERNAL_FUNCTION_TOKEN` değerini bilen taraf yapabilir.
// - Push endpoint'i Web Push sağlayıcı hostları ile sınırlandırılır (SSRF/abus).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Resend } from "https://esm.sh/resend@2.0.0";
import { AuthError, readJsonBody, requireUserContext } from "../_shared/auth.ts";
import { errorResponse, isAllowedPushEndpoint, jsonResponse, preflightResponse } from "../_shared/http.ts";
import { checkRateLimit, rateLimitKey } from "../_shared/rate_limit.ts";
import { ValidationError, requireEnum, requireUuid } from "../_shared/validate.ts";

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
const getEmailTemplate = (type: string, title: string, message: string, userName: string) => {
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

// Send Web Push notification
async function sendPushNotification(
  subscription: PushSubscription,
  payload: { title: string; body: string; data?: Record<string, unknown> },
): Promise<boolean> {
  // VAPID anahtarları Web Push isteği imzalamak için gereklidir; anahtarlar yoksa
  // imzasız istek göndermek yerine göndermemek daha doğrudur (tarayıcı reddeder).
  const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  if (!vapidPublicKey || !vapidPrivateKey) {
    console.error("VAPID anahtarları yapılandırılmamış, push atlandı");
    return false;
  }

  // Kullanıcının kaydettiği endpoint'i doğrulanmazsa saldırgan kendi sunucusuna
  // istek yaptırabilir (SSRF / uygulama içi kalıcı istek).
  if (!isAllowedPushEndpoint(subscription.endpoint)) {
    console.error("İzin verilmeyen push endpoint'i engellendi");
    return false;
  }

  try {
    const response = await fetch(subscription.endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        TTL: "86400",
        // Not: gerçek Web Push (VAPID) imzası `web-push` paketi ile üretilmelidir.
        // Şu an yalnızca kimlik doğrulama yapılır; anahtar varsa burada imzalanır.
        "Authorization": `vapid t=${vapidPublicKey}`,
      },
      signal: AbortSignal.timeout(10_000),
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      console.error("Push gönderilemedi:", response.status, (await response.text()).slice(0, 200));
      return false;
    }

    console.log("Push bildirimi gönderildi");
    return true;
  } catch (error) {
    console.error("Push gönderim hatası:", error);
    return false;
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
      html: getEmailTemplate(type, title, message, userName),
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
    if (error instanceof ValidationError) return errorResponse(req, error.status, error.message);
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
  const limit = checkRateLimit(rateLimitKey("send-notification", req, userId), RATE_LIMIT);
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

  // Use defaults if no preference found
  const pushEnabled = preference?.push_enabled ?? profile.push_notifications_enabled ?? true;
  const emailEnabled = preference?.email_enabled ?? profile.email_notifications_enabled ?? true;

  let pushSent = false;
  let emailSent = false;

  // Send push notification
  if (pushEnabled) {
    const { data: subscriptions } = await supabase
      .from("push_subscriptions")
      .select("*")
      .eq("user_id", userId);

    for (const sub of subscriptions || []) {
      const sent = await sendPushNotification(
        { endpoint: sub.endpoint, p256dh: sub.p256dh, auth: sub.auth },
        { title, body: message, data },
      );
      if (sent) pushSent = true;
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

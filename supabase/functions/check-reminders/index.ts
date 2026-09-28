// Hatırlatıcı zamanlayıcısı (cron).
// Güvenlik sertleştirmeleri:
//  - P0: Fonksiyon anonim (anon) JWT ile çağrılabiliyordu. Artık dahili çağrı
//    (x-calorix-internal-token / INTERNAL_FUNCTION_TOKEN) veya service_role JWT'si
//    gerektirir; aksi halde tüm kullanıcı listesi ve hatırlatma akışı dışarıdan tetiklenemez.
//  - P0/P1: `notifications.type` CHECK kısıtı, gönderilen yeni tip değerlerini
//    (water, daily_log, weekly_summary, goal_achieved) reddediyordu → DB'ye kayıt
//    hiç yazılamıyordu. Değerler artık mevcut CHECK ile uyumlu legacy adlara eşlenir
//    (yeni migration CHECK'i normalize ediyor).
//  - Kolon uyumsuzluğu giderildi: meal_entries.calories/protein_g/... yerine
//    calculated_* ; water_entries.entry_time ve weight_entries.recorded_at yerine entry_date.
//  - Zaman aşımı: dış AI çağrısında AbortSignal.timeout kullanılıyor.
//  - Hata sızıntısı: istemciye sabit mesaj, detay yalnızca sunucu logunda.
import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  errorResponse,
  jsonResponse,
  preflightResponse,
} from "../_shared/http.ts";
import { isSameIsoWeek, getZonedParts, writeReminderStamp } from "./helpers.ts";
import { checkRateLimit, rateLimitKey } from "../_shared/rate_limit.ts";

/** Dış AI çağrısı için üst süre sınırı. */
const AI_TIMEOUT_MS = 20_000;
const PUSH_TIMEOUT_MS = 10_000;
/** Aynı pencere içinde tekrar tetiklemeyi (manuel tetikleme) engeller. */
const RATE_LIMIT = { windowSeconds: 300, max: 2 };

const FALLBACK_MESSAGES = {
  motivational:
    "Bugün de sağlıklı beslenmeye devam! Öğünlerini kaydetmeyi unutma 💪",
  error: "Bir gün atlamak sorun değil, önemli olan devam etmek! 💪",
};

// Generate motivational message using OpenAI
async function generateMotivationalMessage(): Promise<string> {
  const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
  const openaiBaseUrl = Deno.env.get("OPENAI_BASE_URL") ||
    "https://gen.pollinations.ai/v1";
  const openaiModel = Deno.env.get("OPENAI_MODEL") || "gpt-5-mini";

  if (!openaiApiKey) return FALLBACK_MESSAGES.motivational;

  try {
    const response = await fetch(`${openaiBaseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openaiApiKey}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(AI_TIMEOUT_MS),
      body: JSON.stringify({
        model: openaiModel,
        messages: [
          {
            role: "system",
            content:
              "Sen bir sağlıklı beslenme ve kalori takip uygulamasının asistanısın. Kullanıcıyı motive edici, kısa ve samimi Türkçe mesajlar yaz. Emoji kullan. Mesaj 100 karakteri geçmesin.",
          },
          {
            role: "user",
            content:
              "Kullanıcı 24 saattir yemek kaydı girmemiş. Onu motive edici bir hatırlatma mesajı yaz.",
          },
        ],
        max_tokens: 100,
        temperature: 0.8,
      }),
    });

    if (!response.ok) {
      console.error("Motivasyon mesajı hata durumu:", response.status);
      return FALLBACK_MESSAGES.motivational;
    }
    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) {
      return FALLBACK_MESSAGES.motivational;
    }
    return content.trim().slice(0, 200);
  } catch (error) {
    console.error("Motivasyon mesajı hatası:", error);
    return FALLBACK_MESSAGES.error;
  }
}

/** İki zaman damgası arası gün farkı. */
function daysBetween(from: Date, to: Date): number {
  return Math.floor((to.getTime() - from.getTime()) / (1000 * 60 * 60 * 24));
}

function hoursBetween(from: Date, to: Date): number {
  return (to.getTime() - from.getTime()) / (1000 * 60 * 60);
}

// Send notification via edge function
async function sendNotification(
  supabaseUrl: string,
  internalToken: string | null | undefined,
  userId: string,
  type: string,
  title: string,
  message: string,
) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (internalToken) {
    // Tercih edilen yol: paylaşılan sunucu içi token (kullanıcı JWT'si yok).
    headers["x-calorix-internal-token"] = internalToken;
  } else {
    // Geri düşüş: service_role JWT'si ile çağrı. Daha önce kullanılan anon anahtarı
    // service_role'a yükseltilemiyordu; anon ile çağırmak 401 alıyordu.
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceRoleKey) {
      console.error(
        "INTERNAL_FUNCTION_TOKEN ve SUPABASE_SERVICE_ROLE_KEY yok, bildirim atlandı",
      );
      return;
    }
    headers["Authorization"] = `Bearer ${serviceRoleKey}`;
  }

  try {
    const response = await fetch(
      `${supabaseUrl}/functions/v1/send-notification`,
      {
        method: "POST",
        headers,
        signal: AbortSignal.timeout(PUSH_TIMEOUT_MS),
        body: JSON.stringify({ userId, type, title, message }),
      },
    );

    if (!response.ok) {
      console.error(`Bildirim gönderilemedi (${type}):`, response.status);
    }
  } catch (error) {
    console.error(`Bildirim hatası (${type}):`, error);
  }
}

/**
 * Çağrının yetkili olup olmadığını doğrular.
 * 1) Sunucu içi token (INTERNAL_FUNCTION_TOKEN tanımlıysa) — tercih edilen ve
 *    istemcinin taklit edemeyeceği tek yöntem.
 * 2) Token tanımlı değilse: service_role JWT'si (`app_metadata.role`).
 *    `x-calorix-internal: 1` gibi bir başlık istemci tarafından da gönderilebilir
 *    olduğu için KABUL EDİLMEZ — bu, "anon ile tetiklenebilir" P0 açığını geri açardı.
 */
async function isAuthorizedCall(req: Request): Promise<boolean> {
  const expected = Deno.env.get("INTERNAL_FUNCTION_TOKEN");
  if (expected) {
    if (req.headers.get("x-calorix-internal-token") === expected) return true;
    console.warn(
      "Geçersiz iç çağrı token'ı ile hatırlatıcı tetikleme denemesi reddedildi",
    );
    return false;
  }

  console.warn(
    "INTERNAL_FUNCTION_TOKEN tanımlı değil; yalnızca service_role JWT'si kabul edilir.",
  );
  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) return false;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return false;

  // Sunucu tarafında gerçek doğrulama: yalnızca service_role yetkisi kabul edilir.
  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser();
  if (error || !data?.user) return false;
  const appMetadata = (data.user.app_metadata ?? {}) as Record<string, unknown>;
  if (appMetadata.role === "service_role") return true;

  console.warn("Yetkisiz hatırlatıcı çağrısı reddedildi");
  return false;
}

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST" && req.method !== "GET") {
    return errorResponse(req, 405, "Yalnızca GET/POST desteklenir");
  }

  try {
    // 1) Yetkilendirme (P0).
    if (!(await isAuthorizedCall(req))) {
      return errorResponse(req, 401, "Yetkisiz");
    }

    // 2) Tekrarlı tetikleme koruması.
    const limit = await checkRateLimit(
      rateLimitKey("check-reminders", req, "internal"),
      RATE_LIMIT,
    );
    if (!limit.allowed) {
      return jsonResponse(
        req,
        { success: true, message: "Zaten çalışıyor/atlandı" },
        200,
        {
          "Retry-After": String(limit.retryAfter),
        },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const internalToken = Deno.env.get("INTERNAL_FUNCTION_TOKEN");
    if (!supabaseUrl || !supabaseServiceKey) {
      console.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY eksik");
      return errorResponse(req, 500, "Sunucu yapılandırması eksik");
    }
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const now = new Date();

    // 3) İdempotency: aynı tip hatırlatma bu saat içinde zaten gönderildiyse atlanır.
    //    (Aksi halde her çalıştırmada last_*_reminder güncellenmeden önceki
    //     zamanlayıcı çalıştırmaları aynı bildirimi tekrar tekrar gönderebiliyordu.)
    const sentThisRun: Array<{ userId: string; type: string; at: string }> = [];
    // Damga yazılamayan gönderimler (A1r3'ün bıraktığı P2 düzeltmesi):
    // sessizce yutulurdu, sonuç kullanıcıya günde ~12 kez aynı bildirim gider.
    // Artık hem loglanır hem de koşu özetine yansır → izlenebilir.
    const stampFailures: Array<{ userId: string; column: string }> = [];

    console.log(`Hatırlatıcı kontrolü: ${now.toISOString()} (saat/gün profilden)`);

    // Get all users with notifications enabled
    // `timezone` artık SELECT'e dahil: sabit `UTC+3` yerine kullanıcının
    // kendi saat dilimi kullanılır (A1r4).
    const { data: profiles, error: profilesError } = await supabase
      .from("profiles")
      .select(
        "id, display_name, timezone, daily_water_target_ml, weigh_in_frequency_days, last_weigh_in_reminder, last_water_reminder, last_daily_log_reminder, last_weekly_summary, onboarding_completed",
      )
      .eq("onboarding_completed", true);

    if (profilesError) {
      console.error("Profil listesi alınamadı:", profilesError.message);
      return errorResponse(req, 500, "Kullanıcı listesi alınamadı");
    }

    const profileList = profiles || [];
    console.log(`Kontrol edilecek profil sayısı: ${profileList.length}`);

    for (const profile of profileList) {
      // Saat dilimi (A1r4): `now` sabit `UTC+3` ile kaydırılmıyor artık.
      // Kullanıcının `profiles.timezone` değeri **kendi gün ve saat parçalarını**
      // üretir; geçersiz/boş değerde `Intl` RangeError fırlatmasın diye
      // `getZonedParts` `UTC`'ye düşer ve bunu loglar (sessiz hata yok).
      // `summary_day` (0=Pazar..6=Cumartesi) ile `weekday` aynı dizindir.
      const zoned = getZonedParts(profile.timezone, now, console.error);
      const normalizedHour = zoned.hour;
      const dayOfWeek = zoned.weekday;
      // Su hatırlatmasının "bugün" süzgeci kullanıcının kendi günüdür; eski
      // `now.toISOString().split("T")[0]` UTC günüydü (TR'de 03:00'e kadar
      // bir gün geriden hesaplanıyordu → gece yenen su "dün" sayılıyordu).
      const today = zoned.date;

      // Tercihleri tek sorguda çek (N+1 azaltma + alan yazım hatası düzeltmesi:
      // "last_daily_log_reminder" kolonu migration ile eklenmişti, SELECT'te yoktu).
      const { data: preferences } = await supabase
        .from("notification_preferences")
        .select(
          "notification_type, push_enabled, email_enabled, start_hour, end_hour, interval_hours, summary_day, summary_hour",
        )
        .eq("user_id", profile.id);

      const prefMap = new Map(
        (preferences || []).map((p) => [p.notification_type, p]),
      );

      // Aynı tip hatırlatma bu koşuda zaten gönderildiyse tekrar gönderme.
      const alreadySent = (type: string) =>
        sentThisRun.some((s) => s.userId === profile.id && s.type === type);

      // 1. WEIGH-IN REMINDER
      const weighPref = prefMap.get("weigh_in");
      if (
        weighPref?.push_enabled || weighPref?.email_enabled ||
        (!weighPref && profile.weigh_in_frequency_days)
      ) {
        const frequencyDays = profile.weigh_in_frequency_days || 7;
        const lastReminder = profile.last_weigh_in_reminder
          ? new Date(profile.last_weigh_in_reminder)
          : null;
        const daysSinceReminder = lastReminder
          ? daysBetween(lastReminder, now)
          : frequencyDays + 1;

        if (
          daysSinceReminder >= frequencyDays && normalizedHour === 9 &&
          !alreadySent("weigh_in")
        ) {
          // Son kilo kaydı: kolon adı entry_date (recorded_at yok).
          const { data: lastWeight } = await supabase
            .from("weight_entries")
            .select("entry_date")
            .eq("user_id", profile.id)
            .is("deleted_at", null)
            .order("entry_date", { ascending: false })
            .limit(1)
            .maybeSingle();

          const daysSinceWeight = lastWeight?.entry_date
            ? daysBetween(new Date(`${lastWeight.entry_date}T00:00:00Z`), now)
            : frequencyDays + 1;

          if (daysSinceWeight >= frequencyDays) {
            await sendNotification(
              supabaseUrl,
              internalToken,
              profile.id,
              "weigh_in",
              "⚖️ Tartılma Zamanı!",
              `Son tartılmanın üzerinden ${daysSinceWeight} gün geçti. Bugün tartılmayı unutma!`,
            );
            sentThisRun.push({
              userId: profile.id,
              type: "weigh_in",
              at: now.toISOString(),
            });

            const stamped = await writeReminderStamp(
              supabase,
              profile.id,
              "last_weigh_in_reminder",
              now.toISOString(),
              console.error,
            );
            if (!stamped) stampFailures.push({ userId: profile.id, column: "last_weigh_in_reminder" });
          }
        }
      }

      // 2. WATER REMINDER
      const waterPref = prefMap.get("water");
      if (
        (waterPref?.push_enabled || waterPref?.email_enabled) &&
        !alreadySent("water")
      ) {
        const startHour = waterPref?.start_hour ?? 9;
        const endHour = waterPref?.end_hour ?? 21;
        const intervalHours = waterPref?.interval_hours ?? 3;

        if (normalizedHour >= startHour && normalizedHour <= endHour) {
          const lastWaterReminder = profile.last_water_reminder
            ? new Date(profile.last_water_reminder)
            : null;
          const hoursSinceReminder = lastWaterReminder
            ? hoursBetween(lastWaterReminder, now)
            : intervalHours + 1;

          if (hoursSinceReminder >= intervalHours) {
            // Bugünkü su: entry_time yerine entry_date (tarih kolonu).
            const { data: waterEntries } = await supabase
              .from("water_entries")
              .select("amount_ml")
              .eq("user_id", profile.id)
              .eq("entry_date", today)
              .is("deleted_at", null);

            const totalWater = (waterEntries || []).reduce(
              (sum, e) => sum + Number(e.amount_ml || 0),
              0,
            );
            const target = profile.daily_water_target_ml || 2500;
            const percentage = target > 0
              ? Math.round((totalWater / target) * 100)
              : 0;

            if (percentage < 100) {
              await sendNotification(
                supabaseUrl,
                internalToken,
                profile.id,
                "water",
                "💧 Su İçme Zamanı!",
                `Bugün hedefinizin %${percentage}'ine ulaştınız. Su içmeyi unutmayın!`,
              );
              sentThisRun.push({
                userId: profile.id,
                type: "water",
                at: now.toISOString(),
              });

              const stamped = await writeReminderStamp(
                supabase,
                profile.id,
                "last_water_reminder",
                now.toISOString(),
                console.error,
              );
              if (!stamped) stampFailures.push({ userId: profile.id, column: "last_water_reminder" });
            }
          }
        }
      }

      // 3. DAILY LOG REMINDER (24 saat kayıt yok)
      const dailyPref = prefMap.get("daily_log");
      if (
        (dailyPref?.push_enabled || dailyPref?.email_enabled) &&
        normalizedHour === 18 && !alreadySent("daily_log")
      ) {
        const yesterdayDate = new Date(now.getTime() - 24 * 60 * 60 * 1000)
          .toISOString().slice(0, 10);

        const { data: recentEntries } = await supabase
          .from("meal_entries")
          .select("id")
          .eq("user_id", profile.id)
          .gte("entry_date", yesterdayDate)
          .is("deleted_at", null)
          .limit(1);

        if (!recentEntries || recentEntries.length === 0) {
          const lastReminder = profile.last_daily_log_reminder
            ? new Date(profile.last_daily_log_reminder)
            : null;
          const hoursSinceReminder = lastReminder
            ? hoursBetween(lastReminder, now)
            : 25;

          if (hoursSinceReminder >= 24) {
            const motivationalMessage = await generateMotivationalMessage();

            await sendNotification(
              supabaseUrl,
              internalToken,
              profile.id,
              "daily_log",
              "📝 Kayıt Hatırlatması",
              motivationalMessage,
            );
            sentThisRun.push({
              userId: profile.id,
              type: "daily_log",
              at: now.toISOString(),
            });

            const stamped = await writeReminderStamp(
              supabase,
              profile.id,
              "last_daily_log_reminder",
              now.toISOString(),
              console.error,
            );
            if (!stamped) stampFailures.push({ userId: profile.id, column: "last_daily_log_reminder" });
          }
        }
      }

      // 4. WEEKLY SUMMARY (summary_day: 1 = Pazartesi)
      const summaryPref = prefMap.get("weekly_summary");
      const summaryDay = summaryPref?.summary_day ?? 1;
      const summaryHour = summaryPref?.summary_hour ?? 9;

      // Idempotency (A1r3, P1): `last_weekly_summary` damgası. Bu sütun
      // migration `20260928120000_push_idempotency_and_limits.sql` ile eklendi.
      // Önceden hiçbir damga tutulmadığı için cron, `summary_hour` içinde
      // saatte bir çalıştığı sürece haftalık özeti **her seferinde** yeniden
      // gönderiyordu (kullanıcıya günde ~12 kez bildirim + e-posta).
      // Aynı ISO haftası içinde ikinci kez gönderilmez.
      const lastSummary = profile.last_weekly_summary
        ? new Date(profile.last_weekly_summary)
        : null;
      const summaryAlreadySent = lastSummary
        ? isSameIsoWeek(lastSummary, now)
        : false;

      if (
        (summaryPref?.push_enabled || summaryPref?.email_enabled) &&
        dayOfWeek === summaryDay &&
        normalizedHour === summaryHour &&
        !summaryAlreadySent &&
        !alreadySent("weekly_summary")
      ) {
        const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
          .toISOString().slice(0, 10);

        // Kolon adları gerçek şemaya göre düzeltildi (calculated_*, entry_date).
        const [
          { data: mealEntries },
          { data: waterEntries },
          { data: weightEntries },
        ] = await Promise.all([
          supabase
            .from("meal_entries")
            .select(
              "calculated_kcal, calculated_protein, calculated_carbs, calculated_fat, entry_date",
            )
            .eq("user_id", profile.id)
            .gte("entry_date", weekAgo)
            .is("deleted_at", null),
          supabase
            .from("water_entries")
            .select("amount_ml, entry_date")
            .eq("user_id", profile.id)
            .gte("entry_date", weekAgo)
            .is("deleted_at", null),
          supabase
            .from("weight_entries")
            .select("weight_kg, entry_date")
            .eq("user_id", profile.id)
            .gte("entry_date", weekAgo)
            .is("deleted_at", null)
            .order("entry_date", { ascending: true }),
        ]);

        const totalCalories = (mealEntries || []).reduce(
          (sum, e) => sum + Number(e.calculated_kcal || 0),
          0,
        );
        const avgCalories = mealEntries?.length
          ? Math.round(totalCalories / 7)
          : 0;
        const totalWater = (waterEntries || []).reduce(
          (sum, e) => sum + Number(e.amount_ml || 0),
          0,
        );
        const avgWater = Math.round(totalWater / 7);

        let weightChange = 0;
        if (weightEntries && weightEntries.length >= 2) {
          weightChange = Number(
            (Number(weightEntries[weightEntries.length - 1].weight_kg) -
              Number(weightEntries[0].weight_kg)).toFixed(1),
          );
        }

        // E-posta gövdesi HTML şablonuna gömülür → kaçırılması gerekir.
        const summaryMessage = [
          "<p><strong>Bu hafta:</strong></p>",
          '<ul style="margin: 10px 0; padding-left: 20px;">',
          `<li>Günlük ortalama kalori: <strong>${avgCalories} kcal</strong></li>`,
          `<li>Günlük ortalama su: <strong>${avgWater} ml</strong></li>`,
          weightChange !== 0
            ? `<li>Kilo değişimi: <strong>${
              weightChange > 0 ? "+" : ""
            }${weightChange} kg</strong></li>`
            : "",
          "</ul>",
          "<p>Harika iş çıkardın! Devam et 🎯</p>",
        ].join("");

        await sendNotification(
          supabaseUrl,
          internalToken,
          profile.id,
          "weekly_summary",
          "📊 Haftalık Özetiniz",
          summaryMessage,
        );
        sentThisRun.push({
          userId: profile.id,
          type: "weekly_summary",
          at: now.toISOString(),
        });

        // Idempotency damgası: aynı ISO haftasında tekrar gönderilmesin.
        // Önceki hatırlatıcılar gibi burada da "gönderdikten sonra" yazılır.
        // Damga yazılamazsa **bu koşuda tekrar gönderim yapılmaz**; kullanıcı
        // bir sonraki cron'da tekrar alacak, ama bu artık loglanan ve
        // özetlenen bir durumdur (eskiden tamamen sessizdi).
        const stamped = await writeReminderStamp(
          supabase,
          profile.id,
          "last_weekly_summary",
          now.toISOString(),
          console.error,
        );
        if (!stamped) stampFailures.push({ userId: profile.id, column: "last_weekly_summary" });
      }
    }

    if (stampFailures.length > 0) {
      // Tek satır toplam: kullanıcı/kolon listesi logda kalır, HTTP gövdesi
      // istemciye (cron) sabit kalır ve şema sızdırmaz.
      console.error(
        `${stampFailures.length} hatırlatma damgası yazılamadı; bu gönderimler bir sonraki ` +
          `koşuda TEKRAR denenecek (tekrar gönderim riski): ` +
          stampFailures.map((f) => `${f.column}@${f.userId}`).join(", "),
      );
    }

    return jsonResponse(req, {
      success: true,
      message: "Hatırlatıcılar kontrol edildi",
      sent: sentThisRun.length,
      // Sıfırdan farklıysa cron alarmı üretir; normalde 0.
      stampFailures: stampFailures.length,
    });
  } catch (error: unknown) {
    console.error("check-reminders hatası:", error);
    return errorResponse(req, 500, "Hatırlatıcı kontrolü tamamlanamadı");
  }
};

serve(handler);

import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Generate motivational message using OpenAI
async function generateMotivationalMessage(): Promise<string> {
  const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
  const openaiBaseUrl = Deno.env.get("OPENAI_BASE_URL") || "https://gen.pollinations.ai/v1";
  const openaiModel = Deno.env.get("OPENAI_MODEL") || "gpt-5-mini";

  if (!openaiApiKey) {
    return "Bugün de sağlıklı beslenmeye devam! Öğünlerini kaydetmeyi unutma 💪";
  }

  try {
    const response = await fetch(`${openaiBaseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: openaiModel,
        messages: [
          {
            role: "system",
            content: "Sen bir sağlıklı beslenme ve kalori takip uygulamasının asistanısın. Kullanıcıyı motive edici, kısa ve samimi Türkçe mesajlar yaz. Emoji kullan. Mesaj 100 karakteri geçmesin."
          },
          {
            role: "user",
            content: "Kullanıcı 24 saattir yemek kaydı girmemiş. Onu motive edici bir hatırlatma mesajı yaz."
          }
        ],
        max_tokens: 100,
        temperature: 0.8,
      }),
    });

    const data = await response.json();
    return data.choices?.[0]?.message?.content || "Bugün de sağlıklı beslenmeye devam! 💪";
  } catch (error) {
    console.error("Error generating motivational message:", error);
    return "Bir gün atlamak sorun değil, önemli olan devam etmek! 💪";
  }
}

// Send notification via edge function
async function sendNotification(
  supabaseUrl: string,
  supabaseAnonKey: string,
  userId: string,
  type: string,
  title: string,
  message: string
) {
  try {
    const response = await fetch(`${supabaseUrl}/functions/v1/send-notification`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ userId, type, title, message }),
    });

    if (!response.ok) {
      console.error(`Failed to send notification to ${userId}:`, await response.text());
    } else {
      console.log(`Notification sent to ${userId}: ${type}`);
    }
  } catch (error) {
    console.error(`Error sending notification to ${userId}:`, error);
  }
}

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const now = new Date();
    const currentHour = now.getUTCHours() + 3; // Turkey time (UTC+3)
    const normalizedHour = currentHour >= 24 ? currentHour - 24 : currentHour;
    const today = now.toISOString().split("T")[0];
    const dayOfWeek = now.getDay();

    console.log(`Running reminder check at ${now.toISOString()}, hour: ${normalizedHour}, day: ${dayOfWeek}`);

    // Get all users with notifications enabled
    const { data: profiles, error: profilesError } = await supabase
      .from("profiles")
      .select("id, display_name, email, daily_water_target_ml, weigh_in_frequency_days, last_weigh_in_reminder, last_water_reminder, last_daily_log_reminder, onboarding_completed")
      .eq("onboarding_completed", true);

    if (profilesError) {
      console.error("Error fetching profiles:", profilesError);
      throw profilesError;
    }

    console.log(`Found ${profiles?.length || 0} profiles to check`);

    for (const profile of profiles || []) {
      // Get user's notification preferences
      const { data: preferences } = await supabase
        .from("notification_preferences")
        .select("*")
        .eq("user_id", profile.id);

      const prefMap = new Map(preferences?.map(p => [p.notification_type, p]) || []);

      // 1. WEIGH-IN REMINDER
      const weighPref = prefMap.get("weigh_in");
      if (weighPref?.push_enabled || weighPref?.email_enabled || (!weighPref && profile.weigh_in_frequency_days)) {
        const frequencyDays = profile.weigh_in_frequency_days || 7;
        const lastReminder = profile.last_weigh_in_reminder ? new Date(profile.last_weigh_in_reminder) : null;
        const daysSinceReminder = lastReminder
          ? Math.floor((now.getTime() - lastReminder.getTime()) / (1000 * 60 * 60 * 24))
          : frequencyDays + 1;

        // Check if it's time to send reminder
        if (daysSinceReminder >= frequencyDays && normalizedHour === 9) {
          // Check last weight entry
          const { data: lastWeight } = await supabase
            .from("weight_entries")
            .select("recorded_at")
            .eq("user_id", profile.id)
            .order("recorded_at", { ascending: false })
            .limit(1)
            .single();

          const daysSinceWeight = lastWeight
            ? Math.floor((now.getTime() - new Date(lastWeight.recorded_at).getTime()) / (1000 * 60 * 60 * 24))
            : frequencyDays + 1;

          if (daysSinceWeight >= frequencyDays) {
            await sendNotification(
              supabaseUrl,
              supabaseAnonKey,
              profile.id,
              "weigh_in",
              "⚖️ Tartılma Zamanı!",
              `Son tartılmanın üzerinden ${daysSinceWeight} gün geçti. Bugün tartılmayı unutma!`
            );

            await supabase
              .from("profiles")
              .update({ last_weigh_in_reminder: now.toISOString() })
              .eq("id", profile.id);
          }
        }
      }

      // 2. WATER REMINDER
      const waterPref = prefMap.get("water");
      if (waterPref?.push_enabled || waterPref?.email_enabled) {
        const startHour = waterPref?.start_hour ?? 9;
        const endHour = waterPref?.end_hour ?? 21;
        const intervalHours = waterPref?.interval_hours ?? 3;

        // Check if current hour is within schedule and matches interval
        if (normalizedHour >= startHour && normalizedHour <= endHour) {
          const lastWaterReminder = profile.last_water_reminder ? new Date(profile.last_water_reminder) : null;
          const hoursSinceReminder = lastWaterReminder
            ? (now.getTime() - lastWaterReminder.getTime()) / (1000 * 60 * 60)
            : intervalHours + 1;

          if (hoursSinceReminder >= intervalHours) {
            // Check today's water intake
            const { data: waterEntries } = await supabase
              .from("water_entries")
              .select("amount_ml")
              .eq("user_id", profile.id)
              .gte("entry_time", today);

            const totalWater = waterEntries?.reduce((sum, e) => sum + e.amount_ml, 0) || 0;
            const target = profile.daily_water_target_ml || 2500;
            const percentage = Math.round((totalWater / target) * 100);

            if (percentage < 100) {
              await sendNotification(
                supabaseUrl,
                supabaseAnonKey,
                profile.id,
                "water",
                "💧 Su İçme Zamanı!",
                `Bugün hedefinizin %${percentage}'ine ulaştınız. Su içmeyi unutmayın!`
              );

              await supabase
                .from("profiles")
                .update({ last_water_reminder: now.toISOString() })
                .eq("id", profile.id);
            }
          }
        }
      }

      // 3. DAILY LOG REMINDER (24 hours without entry)
      const dailyPref = prefMap.get("daily_log");
      if ((dailyPref?.push_enabled || dailyPref?.email_enabled) && normalizedHour === 18) {
        const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();

        const { data: recentEntries } = await supabase
          .from("meal_entries")
          .select("id")
          .eq("user_id", profile.id)
          .gte("entry_date", yesterday.split("T")[0])
          .limit(1);

        if (!recentEntries || recentEntries.length === 0) {
          const lastReminder = profile.last_daily_log_reminder ? new Date(profile.last_daily_log_reminder) : null;
          const hoursSinceReminder = lastReminder
            ? (now.getTime() - lastReminder.getTime()) / (1000 * 60 * 60)
            : 25;

          if (hoursSinceReminder >= 24) {
            const motivationalMessage = await generateMotivationalMessage();

            await sendNotification(
              supabaseUrl,
              supabaseAnonKey,
              profile.id,
              "daily_log",
              "📝 Kayıt Hatırlatması",
              motivationalMessage
            );

            await supabase
              .from("profiles")
              .update({ last_daily_log_reminder: now.toISOString() })
              .eq("id", profile.id);
          }
        }
      }

      // 4. WEEKLY SUMMARY (Monday)
      const summaryPref = prefMap.get("weekly_summary");
      const summaryDay = summaryPref?.summary_day ?? 1;
      const summaryHour = summaryPref?.summary_hour ?? 9;

      if ((summaryPref?.push_enabled || summaryPref?.email_enabled) && dayOfWeek === summaryDay && normalizedHour === summaryHour) {
        // Calculate last week's stats
        const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString().split("T")[0];

        const { data: mealEntries } = await supabase
          .from("meal_entries")
          .select("calories, protein_g, carbs_g, fat_g")
          .eq("user_id", profile.id)
          .gte("entry_date", weekAgo);

        const { data: waterEntries } = await supabase
          .from("water_entries")
          .select("amount_ml")
          .eq("user_id", profile.id)
          .gte("entry_time", weekAgo);

        const { data: weightEntries } = await supabase
          .from("weight_entries")
          .select("weight_kg, recorded_at")
          .eq("user_id", profile.id)
          .gte("recorded_at", weekAgo)
          .order("recorded_at", { ascending: true });

        const totalCalories = mealEntries?.reduce((sum, e) => sum + (e.calories || 0), 0) || 0;
        const avgCalories = mealEntries?.length ? Math.round(totalCalories / 7) : 0;
        const totalWater = waterEntries?.reduce((sum, e) => sum + e.amount_ml, 0) || 0;
        const avgWater = Math.round(totalWater / 7);

        let weightChange = 0;
        if (weightEntries && weightEntries.length >= 2) {
          weightChange = Number((weightEntries[weightEntries.length - 1].weight_kg - weightEntries[0].weight_kg).toFixed(1));
        }

        const summaryMessage = `
          <p><strong>Bu hafta:</strong></p>
          <ul style="margin: 10px 0; padding-left: 20px;">
            <li>Günlük ortalama kalori: <strong>${avgCalories} kcal</strong></li>
            <li>Günlük ortalama su: <strong>${avgWater} ml</strong></li>
            ${weightChange !== 0 ? `<li>Kilo değişimi: <strong>${weightChange > 0 ? '+' : ''}${weightChange} kg</strong></li>` : ''}
          </ul>
          <p>Harika iş çıkardın! Devam et 🎯</p>
        `;

        await sendNotification(
          supabaseUrl,
          supabaseAnonKey,
          profile.id,
          "weekly_summary",
          "📊 Haftalık Özetiniz",
          summaryMessage
        );
      }
    }

    return new Response(
      JSON.stringify({ success: true, message: "Reminders checked" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: unknown) {
    console.error("Error in check-reminders:", error);
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
};

serve(handler);

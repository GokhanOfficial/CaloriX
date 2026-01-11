import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Resend } from "https://esm.sh/resend@2.0.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface NotificationRequest {
  userId: string;
  type: 'weigh_in' | 'daily_log' | 'water' | 'goal_achieved' | 'weekly_summary';
  title: string;
  message: string;
  data?: Record<string, unknown>;
}

interface PushSubscription {
  endpoint: string;
  p256dh: string;
  auth: string;
}

// Email templates
const getEmailTemplate = (type: string, title: string, message: string, userName: string) => {
  const templates: Record<string, string> = {
    weigh_in: `
      <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #10b981 0%, #059669 100%); padding: 30px; border-radius: 12px; text-align: center; color: white;">
          <h1 style="margin: 0 0 10px 0;">⚖️ Tartılma Zamanı!</h1>
        </div>
        <div style="padding: 30px; background: #f9fafb; border-radius: 12px; margin-top: 20px;">
          <p style="font-size: 18px; color: #374151;">Merhaba ${userName},</p>
          <p style="font-size: 16px; color: #6b7280; line-height: 1.6;">${message}</p>
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
          <p style="font-size: 18px; color: #374151;">Merhaba ${userName},</p>
          <p style="font-size: 16px; color: #6b7280; line-height: 1.6;">${message}</p>
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
          <p style="font-size: 18px; color: #374151;">Merhaba ${userName},</p>
          <p style="font-size: 16px; color: #6b7280; line-height: 1.6;">${message}</p>
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
          <p style="font-size: 18px; color: #374151;">Merhaba ${userName},</p>
          <p style="font-size: 16px; color: #6b7280; line-height: 1.6;">${message}</p>
        </div>
      </div>
    `,
    weekly_summary: `
      <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #ec4899 0%, #db2777 100%); padding: 30px; border-radius: 12px; text-align: center; color: white;">
          <h1 style="margin: 0 0 10px 0;">📊 Haftalık Özetiniz</h1>
        </div>
        <div style="padding: 30px; background: #f9fafb; border-radius: 12px; margin-top: 20px;">
          <p style="font-size: 18px; color: #374151;">Merhaba ${userName},</p>
          <div style="font-size: 16px; color: #6b7280; line-height: 1.6;">${message}</div>
          <a href="https://calorix.app/analytics" style="display: inline-block; background: #ec4899; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; margin-top: 20px;">Detayları Gör</a>
        </div>
      </div>
    `,
  };
  return templates[type] || templates.daily_log;
};

// Send Web Push notification
async function sendPushNotification(
  subscription: PushSubscription,
  payload: { title: string; body: string; data?: Record<string, unknown> }
): Promise<boolean> {
  const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");

  if (!vapidPublicKey || !vapidPrivateKey) {
    console.error("VAPID keys not configured");
    return false;
  }

  try {
    // Using Web Push protocol
    const response = await fetch(subscription.endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "TTL": "86400",
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      console.error("Push notification failed:", await response.text());
      return false;
    }

    console.log("Push notification sent successfully");
    return true;
  } catch (error) {
    console.error("Error sending push notification:", error);
    return false;
  }
}

// Send email notification
async function sendEmailNotification(
  email: string,
  userName: string,
  type: string,
  title: string,
  message: string
): Promise<boolean> {
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  
  if (!resendApiKey) {
    console.error("RESEND_API_KEY not configured");
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

    console.log("Email sent successfully:", emailResponse);
    return true;
  } catch (error) {
    console.error("Error sending email:", error);
    return false;
  }
}

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { userId, type, title, message, data }: NotificationRequest = await req.json();

    console.log(`Processing notification for user ${userId}, type: ${type}`);

    // Get user profile
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("email, display_name, push_notifications_enabled, email_notifications_enabled")
      .eq("id", userId)
      .single();

    if (profileError || !profile) {
      console.error("Error fetching profile:", profileError);
      return new Response(
        JSON.stringify({ error: "User profile not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get notification preferences for this type
    const { data: preference } = await supabase
      .from("notification_preferences")
      .select("*")
      .eq("user_id", userId)
      .eq("notification_type", type)
      .single();

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

      if (subscriptions && subscriptions.length > 0) {
        for (const sub of subscriptions) {
          const sent = await sendPushNotification(
            { endpoint: sub.endpoint, p256dh: sub.p256dh, auth: sub.auth },
            { title, body: message, data }
          );
          if (sent) pushSent = true;
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
        message
      );
    }

    // Save notification to database
    const { error: insertError } = await supabase.from("notifications").insert({
      user_id: userId,
      title,
      message,
      type,
      push_sent: pushSent,
      email_sent: emailSent,
    });

    if (insertError) {
      console.error("Error saving notification:", insertError);
    }

    console.log(`Notification processed: push=${pushSent}, email=${emailSent}`);

    return new Response(
      JSON.stringify({ success: true, pushSent, emailSent }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: unknown) {
    console.error("Error in send-notification:", error);
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
};

serve(handler);

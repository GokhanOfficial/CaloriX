// @ts-nocheck
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ChatRole = "user" | "assistant" | "system" | "tool";
type ChatAttachment = {
  path: string;
  name: string;
  type: string;
  size: number;
  signedUrl?: string;
};
type PendingAction = {
  type: "add_meal" | "add_water" | "add_weight" | "update_goals";
  summary: string;
  payload: Record<string, unknown>;
};
type ChatMessage = {
  id: string;
  thread_id: string;
  user_id: string;
  role: ChatRole;
  content: string | null;
  attachments: ChatAttachment[];
  tool_calls: Array<Record<string, unknown>>;
  tool_results: Array<Record<string, unknown>>;
  pending_action: PendingAction | null;
  action_status: string | null;
  created_at: string;
};

type RequestBody = { mode?: "chat"; threadId: string; locale?: string; language?: string; timeZone?: string; currentDate?: string };

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const openAIApiKey = Deno.env.get("OPENAI_API_KEY") || "";
const openAIBaseUrl = Deno.env.get("OPENAI_BASE_URL") || "https://gen.pollinations.ai/v1";
const openAIModel = Deno.env.get("OPENAI_MODEL") || "gpt-5-mini";

const publicProfileFields = "id, display_name, birth_date, gender, height_cm, current_weight_kg, target_weight_kg, activity_level, goal, bmr, tdee, daily_calorie_target, protein_target_g, carbs_target_g, fat_target_g, daily_water_target_ml, weigh_in_frequency_days";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function requireNumber(value: unknown, field: string, min = 0, max = Number.MAX_SAFE_INTEGER) {
  const number = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(number) || number < min || number > max) {
    throw new Error(`Invalid ${field}`);
  }
  return number;
}

function requireString(value: unknown, field: string) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`Invalid ${field}`);
  }
  return value.trim();
}

function sanitizeDate(value: unknown) {
  const text = requireString(value, "entry_date");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) throw new Error("Invalid entry_date");
  return text;
}

function isValidDateOnly(value: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function getLocalDateInTimeZone(timeZone: string) {
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(new Date());
    const year = parts.find((part) => part.type === "year")?.value;
    const month = parts.find((part) => part.type === "month")?.value;
    const day = parts.find((part) => part.type === "day")?.value;
    if (year && month && day) return `${year}-${month}-${day}`;
  } catch (_) {
    // Fallback below
  }
  return new Date().toISOString().slice(0, 10);
}

function validateToolDate(date: string, currentDate: string, toolName: string) {
  if (!isValidDateOnly(date)) throw new Error("Invalid date format. Use YYYY-MM-DD.");
  const requested = new Date(`${date}T00:00:00Z`).getTime();
  const current = new Date(`${currentDate}T00:00:00Z`).getTime();
  const diffDays = Math.round((requested - current) / 86400000);
  if (Math.abs(diffDays) > 370) {
    throw new Error(`${toolName} refused: ${date} is too far from current local date ${currentDate}. If the user said today, use ${currentDate}. Ask the user to confirm unusually old/future dates.`);
  }
  return date;
}

async function getSignedAttachments(serviceClient: ReturnType<typeof createClient>, attachments: ChatAttachment[]) {
  const result: ChatAttachment[] = [];
  for (const attachment of attachments || []) {
    if (!attachment.path) continue;
    const { data } = await serviceClient.storage.from("chat-attachments").createSignedUrl(attachment.path, 60 * 60);
    result.push({ ...attachment, signedUrl: data?.signedUrl });
  }
  return result;
}

function toOpenAIContent(message: ChatMessage) {
  const text = message.content || "";
  if (message.role !== "user" || !message.attachments?.length) return text;

  const content: Array<Record<string, unknown>> = [];
  if (text.trim()) content.push({ type: "text", text });
  for (const attachment of message.attachments) {
    if (attachment.signedUrl) {
      content.push({ type: "image_url", image_url: { url: attachment.signedUrl } });
    }
  }
  return content.length ? content : text;
}

function getToolDefinitions() {
  return [
    {
      type: "function",
      function: {
        name: "get_profile",
        description: "Kullanıcının profil, hedef, makro, su ve vücut bilgilerini okur.",
        parameters: { type: "object", properties: {}, additionalProperties: false },
      },
    },
    {
      type: "function",
      function: {
        name: "get_daily_log",
        description: "Belirli bir gün için öğün, su, kilo ve toplam makro verilerini okur.",
        parameters: {
          type: "object",
          properties: { date: { type: "string", description: "YYYY-MM-DD" } },
          required: ["date"],
          additionalProperties: false,
        },
      },
    },
    {
      type: "function",
      function: {
        name: "get_period_summary",
        description: "Son N gün için günlük kalori, makro, su ve kilo özetini okur.",
        parameters: {
          type: "object",
          properties: { days: { type: "number", minimum: 1, maximum: 90 } },
          required: ["days"],
          additionalProperties: false,
        },
      },
    },
    {
      type: "function",
      function: {
        name: "add_meal",
        description: "Kullanıcı açıkça istediğinde öğün/yemek kaydı ekler. Eksik besin değerleri varsa önce kullanıcıdan bilgi iste veya makul tahmin yapıp açıklamada belirt.",
        parameters: {
          type: "object",
          properties: {
            entry_date: { type: "string", description: "YYYY-MM-DD" },
            meal_type: { type: "string", enum: ["breakfast", "lunch", "dinner", "snack"] },
            custom_name: { type: "string" },
            amount_g_ml: { type: "number" },
            calculated_kcal: { type: "number" },
            calculated_protein: { type: "number" },
            calculated_carbs: { type: "number" },
            calculated_fat: { type: "number" },
            note: { type: "string" }
          },
          required: ["entry_date", "meal_type", "custom_name", "amount_g_ml", "calculated_kcal", "calculated_protein", "calculated_carbs", "calculated_fat"],
          additionalProperties: false,
        },
      },
    },
    {
      type: "function",
      function: {
        name: "add_water",
        description: "Kullanıcı istediğinde su kaydı ekler.",
        parameters: {
          type: "object",
          properties: { entry_date: { type: "string", description: "YYYY-MM-DD" }, amount_ml: { type: "number" } },
          required: ["entry_date", "amount_ml"],
          additionalProperties: false,
        },
      },
    },
    {
      type: "function",
      function: {
        name: "add_weight",
        description: "Kullanıcı istediğinde kilo kaydı ekler.",
        parameters: {
          type: "object",
          properties: { entry_date: { type: "string", description: "YYYY-MM-DD" }, weight_kg: { type: "number" }, note: { type: "string" } },
          required: ["entry_date", "weight_kg"],
          additionalProperties: false,
        },
      },
    },
    {
      type: "function",
      function: {
        name: "update_goals",
        description: "Kullanıcı istediğinde kalori, makro, su, hedef kilo, aktivite veya hedef tipini günceller.",
        parameters: {
          type: "object",
          properties: {
            daily_calorie_target: { type: "number" },
            protein_target_g: { type: "number" },
            carbs_target_g: { type: "number" },
            fat_target_g: { type: "number" },
            daily_water_target_ml: { type: "number" },
            goal: { type: "string", enum: ["lose", "maintain", "gain"] },
            activity_level: { type: "string", enum: ["sedentary", "light", "moderate", "active", "very_active"] },
            target_weight_kg: { type: "number" }
          },
          additionalProperties: false,
        },
      },
    },
  ];
}

async function runReadTool(serviceClient: ReturnType<typeof createClient>, userId: string, name: string, args: Record<string, unknown>) {
  if (name === "get_profile") {
    const { data, error } = await serviceClient.from("profiles").select(publicProfileFields).eq("id", userId).single();
    if (error) throw error;
    return data;
  }

  if (name === "get_daily_log") {
    const date = sanitizeDate(args.date);
    const [meals, water, weight, profile] = await Promise.all([
      serviceClient.from("meal_entries").select("id, entry_date, meal_type, custom_name, amount_g_ml, calculated_kcal, calculated_protein, calculated_carbs, calculated_fat, note, source, created_at").eq("user_id", userId).eq("entry_date", date).is("deleted_at", null).order("created_at", { ascending: true }),
      serviceClient.from("water_entries").select("id, entry_date, entry_time, amount_ml, created_at").eq("user_id", userId).eq("entry_date", date).is("deleted_at", null).order("entry_time", { ascending: true }),
      serviceClient.from("weight_entries").select("id, entry_date, weight_kg, note, created_at").eq("user_id", userId).lte("entry_date", date).is("deleted_at", null).order("entry_date", { ascending: false }).limit(1).maybeSingle(),
      serviceClient.from("profiles").select("daily_calorie_target, protein_target_g, carbs_target_g, fat_target_g, daily_water_target_ml").eq("id", userId).single(),
    ]);
    if (meals.error) throw meals.error;
    if (water.error) throw water.error;
    if (weight.error) throw weight.error;
    if (profile.error) throw profile.error;

    const totals = (meals.data || []).reduce((acc, entry) => ({
      calories: acc.calories + Number(entry.calculated_kcal || 0),
      protein: acc.protein + Number(entry.calculated_protein || 0),
      carbs: acc.carbs + Number(entry.calculated_carbs || 0),
      fat: acc.fat + Number(entry.calculated_fat || 0),
    }), { calories: 0, protein: 0, carbs: 0, fat: 0 });
    const totalWater = (water.data || []).reduce((sum, entry) => sum + Number(entry.amount_ml || 0), 0);
    return { date, targets: profile.data, meals: meals.data || [], water: water.data || [], latestWeight: weight.data, totals, totalWater };
  }

  if (name === "get_period_summary") {
    const days = Math.round(requireNumber(args.days, "days", 1, 90));
    const end = new Date();
    const start = new Date();
    start.setDate(end.getDate() - days + 1);
    const startStr = start.toISOString().slice(0, 10);
    const endStr = end.toISOString().slice(0, 10);
    const [meals, water, weights] = await Promise.all([
      serviceClient.from("meal_entries").select("entry_date, calculated_kcal, calculated_protein, calculated_carbs, calculated_fat").eq("user_id", userId).gte("entry_date", startStr).lte("entry_date", endStr).is("deleted_at", null),
      serviceClient.from("water_entries").select("entry_date, amount_ml").eq("user_id", userId).gte("entry_date", startStr).lte("entry_date", endStr).is("deleted_at", null),
      serviceClient.from("weight_entries").select("entry_date, weight_kg").eq("user_id", userId).gte("entry_date", startStr).lte("entry_date", endStr).is("deleted_at", null).order("entry_date", { ascending: true }),
    ]);
    if (meals.error) throw meals.error;
    if (water.error) throw water.error;
    if (weights.error) throw weights.error;
    return { start: startStr, end: endStr, meals: meals.data || [], water: water.data || [], weights: weights.data || [] };
  }

  throw new Error("Tool not allowed");
}

async function executeWriteTool(serviceClient: ReturnType<typeof createClient>, userId: string, name: string, payload: Record<string, unknown>, currentDate: string) {
  if (name === "add_meal") {
    const mealType = requireString(payload.meal_type, "meal_type");
    if (!["breakfast", "lunch", "dinner", "snack"].includes(mealType)) throw new Error("Invalid meal_type");
    const entry = {
      user_id: userId,
      entry_date: validateToolDate(sanitizeDate(payload.entry_date), currentDate, name),
      meal_type: mealType,
      custom_name: requireString(payload.custom_name, "custom_name"),
      amount_g_ml: requireNumber(payload.amount_g_ml, "amount_g_ml", 0.1, 10000),
      calculated_kcal: requireNumber(payload.calculated_kcal, "calculated_kcal", 0, 20000),
      calculated_protein: requireNumber(payload.calculated_protein, "calculated_protein", 0, 2000),
      calculated_carbs: requireNumber(payload.calculated_carbs, "calculated_carbs", 0, 2000),
      calculated_fat: requireNumber(payload.calculated_fat, "calculated_fat", 0, 2000),
      note: typeof payload.note === "string" ? payload.note : null,
      source: "text",
    };
    const { data, error } = await serviceClient.from("meal_entries").insert(entry).select().single();
    if (error) throw error;
    return data;
  }

  if (name === "add_water") {
    const { data, error } = await serviceClient.from("water_entries").insert({
      user_id: userId,
      entry_date: validateToolDate(sanitizeDate(payload.entry_date), currentDate, name),
      amount_ml: Math.round(requireNumber(payload.amount_ml, "amount_ml", 1, 10000)),
    }).select().single();
    if (error) throw error;
    return data;
  }

  if (name === "add_weight") {
    const { data, error } = await serviceClient.from("weight_entries").insert({
      user_id: userId,
      entry_date: validateToolDate(sanitizeDate(payload.entry_date), currentDate, name),
      weight_kg: requireNumber(payload.weight_kg, "weight_kg", 1, 1000),
      note: typeof payload.note === "string" ? payload.note : null,
    }).select().single();
    if (error) throw error;
    return data;
  }

  if (name === "update_goals") {
    const allowed = ["daily_calorie_target", "protein_target_g", "carbs_target_g", "fat_target_g", "daily_water_target_ml", "goal", "activity_level", "target_weight_kg"];
    const updates: Record<string, unknown> = { updated_at: new Date().toISOString() };
    for (const key of allowed) {
      if (payload[key] !== undefined) updates[key] = payload[key];
    }
    if (Object.keys(updates).length === 1) throw new Error("No allowed goal updates");
    const { data, error } = await serviceClient.from("profiles").update(updates).eq("id", userId).select(publicProfileFields).single();
    if (error) throw error;
    return data;
  }

  throw new Error("Unsupported action");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) return jsonResponse({ error: "Supabase configuration missing" }, 500);
    if (!openAIApiKey) return jsonResponse({ error: "OpenAI API key not configured" }, 500);

    const authHeader = req.headers.get("Authorization") || "";
    const authClient = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } } });
    const serviceClient = createClient(supabaseUrl, supabaseServiceRoleKey);
    const { data: { user }, error: userError } = await authClient.auth.getUser();
    if (userError || !user) return jsonResponse({ error: "Unauthorized" }, 401);

    const body = await req.json() as RequestBody;
    const threadId = body.threadId || "";
    const requestedLocale = body.locale || req.headers.get("accept-language")?.split(",")?.[0] || "en-US";
    const requestedLanguage = body.language || requestedLocale.split("-")[0] || "en";
    const requestedTimeZone = body.timeZone || "UTC";
    const currentLocalDate = body.currentDate && isValidDateOnly(body.currentDate) ? body.currentDate : getLocalDateInTimeZone(requestedTimeZone);
    if (!threadId) return jsonResponse({ error: "threadId is required" }, 400);

    const { data: thread, error: threadError } = await serviceClient.from("chat_threads").select("id, user_id").eq("id", threadId).eq("user_id", user.id).single();
    if (threadError || !thread) return jsonResponse({ error: "Thread not found" }, 404);

    const { data: messages, error: messagesError } = await serviceClient
      .from("chat_messages")
      .select("*")
      .eq("thread_id", threadId)
      .eq("user_id", user.id)
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .limit(50);
    if (messagesError) throw messagesError;

    const chronological = ((messages || []) as ChatMessage[]).reverse();
    for (const message of chronological) {
      message.attachments = await getSignedAttachments(serviceClient, message.attachments || []);
    }

    const systemPrompt = `You are CaloriX's nutrition assistant.
Respond in the user's active language and locale. User locale: ${requestedLocale}. User language: ${requestedLanguage}. User time zone: ${requestedTimeZone}. Current local date today is ${currentLocalDate}.
Use locale-appropriate wording, dates, units, decimal separators and meal naming. Interpret "today", "bugün", "now", and similar relative date phrases as ${currentLocalDate}; never infer dates from model training date or server UTC date. If the user's language is Turkish, respond in Turkish; otherwise respond in ${requestedLanguage} when possible.
You may read the user's profile, meal, water, weight and goal data only through the provided tools.
When the user clearly asks you to add a meal, add water, add weight or update goals, use the write tools directly. For any write tool date, use ${currentLocalDate} unless the user explicitly gives another date. Do not ask for extra confirmation unless the request is ambiguous, unsafe, or missing required data.
For food entries, if nutrition data is not exact, make a conservative estimate and clearly state that it was estimated.
Keep replies concise, practical and friendly. Do not claim to provide medical advice; recommend consulting a professional when appropriate.
Only the latest 50 chat messages are provided as context; behave as if older messages are unavailable.`;

    const openAIMessages: Array<Record<string, unknown>> = [
      { role: "system", content: systemPrompt },
      ...chronological.filter((m) => m.role === "user" || m.role === "assistant").map((message) => ({
        role: message.role,
        content: toOpenAIContent(message),
      })),
    ];

    const toolCalls: Array<Record<string, unknown>> = [];
    const toolResults: Array<Record<string, unknown>> = [];

    for (let iteration = 0; iteration < 5; iteration++) {
      const response = await fetch(`${openAIBaseUrl}/chat/completions`, {
        method: "POST",
        headers: { Authorization: `Bearer ${openAIApiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model: openAIModel, messages: openAIMessages, tools: getToolDefinitions(), tool_choice: "auto", max_tokens: 900, temperature: 0.4 }),
      });
      if (!response.ok) throw new Error(`AI service error: ${response.status}`);
      const data = await response.json();
      const assistantMessage = data.choices?.[0]?.message;
      const calls = assistantMessage?.tool_calls || [];

      if (!calls.length) {
        const content = assistantMessage?.content || "Bir yanıt oluşturamadım.";
        const { data: saved, error } = await serviceClient.from("chat_messages").insert({
          thread_id: threadId,
          user_id: user.id,
          role: "assistant",
          content,
          tool_calls: toolCalls,
          tool_results: toolResults,
        }).select().single();
        if (error) throw error;
        return jsonResponse({ message: saved });
      }

      openAIMessages.push(assistantMessage);
      for (const call of calls) {
        const name = call.function?.name;
        const args = JSON.parse(call.function?.arguments || "{}");
        toolCalls.push({ id: call.id, name, arguments: args });

        const writeTools = ["add_meal", "add_water", "add_weight", "update_goals"];
        try {
          const result = writeTools.includes(name)
            ? await executeWriteTool(serviceClient, user.id, name, args, currentLocalDate)
            : await runReadTool(serviceClient, user.id, name, args);
          toolResults.push({ id: call.id, name, result });
          openAIMessages.push({ role: "tool", tool_call_id: call.id, content: JSON.stringify(result) });
        } catch (toolError) {
          const result = { error: true, message: toolError instanceof Error ? toolError.message : "Tool execution failed" };
          toolResults.push({ id: call.id, name, result });
          openAIMessages.push({ role: "tool", tool_call_id: call.id, content: JSON.stringify(result) });
        }
      }
    }

    const { data: saved, error } = await serviceClient.from("chat_messages").insert({
      thread_id: threadId,
      user_id: user.id,
      role: "assistant",
      content: requestedLanguage === "tr" ? "Verilerinizi inceledim, ancak yanıtı tamamlayamadım. Lütfen tekrar deneyin." : "I reviewed your data, but could not complete the response. Please try again.",
      tool_calls: toolCalls,
      tool_results: toolResults,
    }).select().single();
    if (error) throw error;
    return jsonResponse({ message: saved });
  } catch (error) {
    console.error("ai-chat error", error);
    return jsonResponse({ error: "An unexpected error occurred" }, 500);
  }
});

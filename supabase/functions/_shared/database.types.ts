/**
 * `ai-chat` edge function için minimal `supabase-js` veritabanı tipleri.
 *
 * Neden ayrı dosya? Flutter istemcisinin `types.ts` dosyası
 * (`src/integrations/supabase/types.ts`) A2'nin alanında; burada dokunulmaz.
 * Bu dosya yalnızca edge function'ın `createClient<Database>()` çağrısında
 * kullanılır ve `supabase gen types typescript` çıktısıyla uyumludur.
 *
 * Kapsam bilinçli olarak daraltılmıştır: `ai-chat/index.ts` yalnızca şu
 * tabloları okur/yazar. Alanlar `never` yerine gerçek tiplidir; bilinmeyen
 * kolonlar için `Row`/`Insert`/`Update` indeks imzaları kullanılır.
 */

// ---------------------------------------------------------------
// Ortak yardımcı tipler
// ---------------------------------------------------------------
type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type MealType = "breakfast" | "lunch" | "dinner" | "snack";
export type FoodSource = "photo" | "text" | "manual";
export type ChatRole = "user" | "assistant" | "system" | "tool";

// ---------------------------------------------------------------
// Tablolar
// ---------------------------------------------------------------
export type ProfilesRow = {
  id: string;
  display_name: string | null;
  email: string | null;
  avatar_url: string | null;
  birth_date: string | null;
  gender: "male" | "female" | "other" | null;
  height_cm: number | null;
  current_weight_kg: number | null;
  target_weight_kg: number | null;
  activity_level: "sedentary" | "light" | "moderate" | "active" | "very_active" | null;
  goal: "lose" | "maintain" | "gain" | null;
  bmr: number | null;
  tdee: number | null;
  daily_calorie_target: number | null;
  protein_target_g: number | null;
  carbs_target_g: number | null;
  fat_target_g: number | null;
  daily_water_target_ml: number | null;
  weigh_in_frequency_days: number | null;
  last_weigh_in_reminder: string | null;
  push_notifications_enabled: boolean | null;
  email_notifications_enabled: boolean | null;
  onboarding_completed: boolean | null;
  auto_recalculate_macros: boolean | null;
  timezone: string | null;
  created_at: string;
  updated_at: string;
};

export type MealEntriesRow = {
  id: string;
  user_id: string;
  entry_date: string;
  meal_type: MealType;
  food_id: string | null;
  custom_name: string | null;
  amount_g_ml: number;
  calculated_kcal: number;
  calculated_protein: number;
  calculated_carbs: number;
  calculated_fat: number;
  note: string | null;
  photo_url: string | null;
  source: FoodSource;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

export type WaterEntriesRow = {
  id: string;
  user_id: string;
  entry_date: string;
  entry_time: string;
  amount_ml: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

export type WeightEntriesRow = {
  id: string;
  user_id: string;
  entry_date: string;
  weight_kg: number;
  note: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

export type ChatThreadsRow = {
  id: string;
  user_id: string;
  title: string | null;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
};

export type ChatMessagesRow = {
  id: string;
  thread_id: string;
  user_id: string;
  role: ChatRole;
  content: string | null;
  attachments: Json;
  tool_calls: Json;
  tool_results: Json;
  pending_action: Json | null;
  action_status: "pending" | "approved" | "rejected" | "executed" | "failed" | null;
  metadata: Json;
  created_at: string;
  deleted_at: string | null;
};

/** Sadece kolon adları gereken yerlerde kullanılır. */
export type UnknownRow = Record<string, never>;

// ---------------------------------------------------------------
// supabase-js `Database` sözleşmesi
// ---------------------------------------------------------------
type TableDefinition<Row, Insert = Partial<Row>, Update = Partial<Row>> = {
  Row: Row;
  Insert: Insert;
  Update: Update;
  Relationships: [];
};

export type Database = {
  public: {
    Tables: {
      profiles: TableDefinition<ProfilesRow>;
      meal_entries: TableDefinition<MealEntriesRow>;
      water_entries: TableDefinition<WaterEntriesRow>;
      weight_entries: TableDefinition<WeightEntriesRow>;
      chat_threads: TableDefinition<ChatThreadsRow>;
      chat_messages: TableDefinition<ChatMessagesRow>;
    };
    Views: Record<string, never>;
    Functions: {
      rate_limit_hit: {
        Args: {
          p_key: string;
          p_bucket: string;
          p_max_count: number;
          p_window_seconds: number;
        };
        Returns: Json;
      };
      cleanup_rate_limits: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
    };
    Enums: {
      meal_type: MealType;
      food_source: FoodSource;
      app_role: "admin" | "moderator" | "user";
    };
    CompositeTypes: Record<string, never>;
  };
};

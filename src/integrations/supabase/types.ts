export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.1"
  }
  public: {
    Tables: {
      favorite_foods: {
        Row: {
          created_at: string
          food_id: string
          id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          food_id: string
          id?: string
          user_id: string
        }
        Update: {
          created_at?: string
          food_id?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "favorite_foods_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["id"]
          },
        ]
      }
      food_nutrition: {
        Row: {
          carbs_g: number
          created_at: string
          fat_g: number
          fiber_g: number | null
          food_id: string
          id: string
          kcal: number
          nova_score: number | null
          nutri_score: string | null
          per_100_g_ml: boolean | null
          protein_g: number
          salt_g: number | null
          saturated_fat_g: number | null
          sugar_g: number | null
          trans_fat_g: number | null
          updated_at: string
        }
        Insert: {
          carbs_g: number
          created_at?: string
          fat_g: number
          fiber_g?: number | null
          food_id: string
          id?: string
          kcal: number
          nova_score?: number | null
          nutri_score?: string | null
          per_100_g_ml?: boolean | null
          protein_g: number
          salt_g?: number | null
          saturated_fat_g?: number | null
          sugar_g?: number | null
          trans_fat_g?: number | null
          updated_at?: string
        }
        Update: {
          carbs_g?: number
          created_at?: string
          fat_g?: number
          fiber_g?: number | null
          food_id?: string
          id?: string
          kcal?: number
          nova_score?: number | null
          nutri_score?: string | null
          per_100_g_ml?: boolean | null
          protein_g?: number
          salt_g?: number | null
          saturated_fat_g?: number | null
          sugar_g?: number | null
          trans_fat_g?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_nutrition_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: true
            referencedRelation: "foods"
            referencedColumns: ["id"]
          },
        ]
      }
      foods: {
        Row: {
          barcode: string | null
          brand: string | null
          created_at: string
          created_by: string | null
          id: string
          image_url: string | null
          last_synced_at: string | null
          name: string
          popularity_count: number | null
          serving_description: string | null
          serving_size_g: number | null
          source: Database["public"]["Enums"]["food_source"]
          updated_at: string
          verified: boolean | null
        }
        Insert: {
          barcode?: string | null
          brand?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          image_url?: string | null
          last_synced_at?: string | null
          name: string
          popularity_count?: number | null
          serving_description?: string | null
          serving_size_g?: number | null
          source?: Database["public"]["Enums"]["food_source"]
          updated_at?: string
          verified?: boolean | null
        }
        Update: {
          barcode?: string | null
          brand?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          image_url?: string | null
          last_synced_at?: string | null
          name?: string
          popularity_count?: number | null
          serving_description?: string | null
          serving_size_g?: number | null
          source?: Database["public"]["Enums"]["food_source"]
          updated_at?: string
          verified?: boolean | null
        }
        Relationships: []
      }
      meal_entries: {
        Row: {
          amount_g_ml: number
          calculated_carbs: number
          calculated_fat: number
          calculated_kcal: number
          calculated_protein: number
          client_id: string | null
          created_at: string
          custom_name: string | null
          deleted_at: string | null
          entry_date: string
          food_id: string | null
          id: string
          meal_type: Database["public"]["Enums"]["meal_type"]
          note: string | null
          photo_url: string | null
          source: Database["public"]["Enums"]["food_source"]
          sync_state: Database["public"]["Enums"]["sync_state"]
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_g_ml: number
          calculated_carbs: number
          calculated_fat: number
          calculated_kcal: number
          calculated_protein: number
          client_id?: string | null
          created_at?: string
          custom_name?: string | null
          deleted_at?: string | null
          entry_date: string
          food_id?: string | null
          id?: string
          meal_type: Database["public"]["Enums"]["meal_type"]
          note?: string | null
          photo_url?: string | null
          source?: Database["public"]["Enums"]["food_source"]
          sync_state?: Database["public"]["Enums"]["sync_state"]
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_g_ml?: number
          calculated_carbs?: number
          calculated_fat?: number
          calculated_kcal?: number
          calculated_protein?: number
          client_id?: string | null
          created_at?: string
          custom_name?: string | null
          deleted_at?: string | null
          entry_date?: string
          food_id?: string | null
          id?: string
          meal_type?: Database["public"]["Enums"]["meal_type"]
          note?: string | null
          photo_url?: string | null
          source?: Database["public"]["Enums"]["food_source"]
          sync_state?: Database["public"]["Enums"]["sync_state"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_entries_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          created_at: string | null
          email_enabled: boolean | null
          end_hour: number | null
          id: string
          interval_hours: number | null
          notification_type: string
          push_enabled: boolean | null
          start_hour: number | null
          summary_day: number | null
          summary_hour: number | null
          updated_at: string | null
          user_id: string
        }
        Insert: {
          created_at?: string | null
          email_enabled?: boolean | null
          end_hour?: number | null
          id?: string
          interval_hours?: number | null
          notification_type: string
          push_enabled?: boolean | null
          start_hour?: number | null
          summary_day?: number | null
          summary_hour?: number | null
          updated_at?: string | null
          user_id: string
        }
        Update: {
          created_at?: string | null
          email_enabled?: boolean | null
          end_hour?: number | null
          id?: string
          interval_hours?: number | null
          notification_type?: string
          push_enabled?: boolean | null
          start_hour?: number | null
          summary_day?: number | null
          summary_hour?: number | null
          updated_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      notifications: {
        Row: {
          created_at: string
          email_sent: boolean | null
          id: string
          is_read: boolean | null
          message: string
          push_sent: boolean | null
          title: string
          type: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email_sent?: boolean | null
          id?: string
          is_read?: boolean | null
          message: string
          push_sent?: boolean | null
          title: string
          type: string
          user_id: string
        }
        Update: {
          created_at?: string
          email_sent?: boolean | null
          id?: string
          is_read?: boolean | null
          message?: string
          push_sent?: boolean | null
          title?: string
          type?: string
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          activity_level: string | null
          auto_recalculate_macros: boolean | null
          avatar_url: string | null
          birth_date: string | null
          bmr: number | null
          carbs_target_g: number | null
          created_at: string
          current_weight_kg: number | null
          daily_calorie_target: number | null
          daily_water_target_ml: number | null
          display_name: string | null
          email: string | null
          email_notifications_enabled: boolean | null
          fat_target_g: number | null
          gender: string | null
          goal: string | null
          height_cm: number | null
          id: string
          last_daily_log_reminder: string | null
          last_water_reminder: string | null
          last_weigh_in_reminder: string | null
          onboarding_completed: boolean | null
          protein_target_g: number | null
          push_notifications_enabled: boolean | null
          target_weight_kg: number | null
          tdee: number | null
          timezone: string | null
          updated_at: string
          weigh_in_frequency_days: number | null
        }
        Insert: {
          activity_level?: string | null
          auto_recalculate_macros?: boolean | null
          avatar_url?: string | null
          birth_date?: string | null
          bmr?: number | null
          carbs_target_g?: number | null
          created_at?: string
          current_weight_kg?: number | null
          daily_calorie_target?: number | null
          daily_water_target_ml?: number | null
          display_name?: string | null
          email?: string | null
          email_notifications_enabled?: boolean | null
          fat_target_g?: number | null
          gender?: string | null
          goal?: string | null
          height_cm?: number | null
          id: string
          last_daily_log_reminder?: string | null
          last_water_reminder?: string | null
          last_weigh_in_reminder?: string | null
          onboarding_completed?: boolean | null
          protein_target_g?: number | null
          push_notifications_enabled?: boolean | null
          target_weight_kg?: number | null
          tdee?: number | null
          timezone?: string | null
          updated_at?: string
          weigh_in_frequency_days?: number | null
        }
        Update: {
          activity_level?: string | null
          auto_recalculate_macros?: boolean | null
          avatar_url?: string | null
          birth_date?: string | null
          bmr?: number | null
          carbs_target_g?: number | null
          created_at?: string
          current_weight_kg?: number | null
          daily_calorie_target?: number | null
          daily_water_target_ml?: number | null
          display_name?: string | null
          email?: string | null
          email_notifications_enabled?: boolean | null
          fat_target_g?: number | null
          gender?: string | null
          goal?: string | null
          height_cm?: number | null
          id?: string
          last_daily_log_reminder?: string | null
          last_water_reminder?: string | null
          last_weigh_in_reminder?: string | null
          onboarding_completed?: boolean | null
          protein_target_g?: number | null
          push_notifications_enabled?: boolean | null
          target_weight_kg?: number | null
          tdee?: number | null
          timezone?: string | null
          updated_at?: string
          weigh_in_frequency_days?: number | null
        }
        Relationships: []
      }
      push_subscriptions: {
        Row: {
          auth: string
          created_at: string
          endpoint: string
          id: string
          p256dh: string
          user_id: string
        }
        Insert: {
          auth: string
          created_at?: string
          endpoint: string
          id?: string
          p256dh: string
          user_id: string
        }
        Update: {
          auth?: string
          created_at?: string
          endpoint?: string
          id?: string
          p256dh?: string
          user_id?: string
        }
        Relationships: []
      }
      recent_foods: {
        Row: {
          food_id: string
          id: string
          last_used_at: string
          use_count: number | null
          user_id: string
        }
        Insert: {
          food_id: string
          id?: string
          last_used_at?: string
          use_count?: number | null
          user_id: string
        }
        Update: {
          food_id?: string
          id?: string
          last_used_at?: string
          use_count?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recent_foods_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["id"]
          },
        ]
      }
      sync_log: {
        Row: {
          client_id: string | null
          created_at: string
          entity_id: string
          entity_type: string
          id: string
          operation: string
          payload: Json | null
          synced_at: string | null
          user_id: string
        }
        Insert: {
          client_id?: string | null
          created_at?: string
          entity_id: string
          entity_type: string
          id?: string
          operation: string
          payload?: Json | null
          synced_at?: string | null
          user_id: string
        }
        Update: {
          client_id?: string | null
          created_at?: string
          entity_id?: string
          entity_type?: string
          id?: string
          operation?: string
          payload?: Json | null
          synced_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      user_settings: {
        Row: {
          created_at: string
          id: string
          key: string
          updated_at: string
          user_id: string
          value: Json
        }
        Insert: {
          created_at?: string
          id?: string
          key: string
          updated_at?: string
          user_id: string
          value: Json
        }
        Update: {
          created_at?: string
          id?: string
          key?: string
          updated_at?: string
          user_id?: string
          value?: Json
        }
        Relationships: []
      }
      water_entries: {
        Row: {
          amount_ml: number
          client_id: string | null
          created_at: string
          deleted_at: string | null
          entry_date: string
          entry_time: string
          id: string
          sync_state: Database["public"]["Enums"]["sync_state"]
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_ml: number
          client_id?: string | null
          created_at?: string
          deleted_at?: string | null
          entry_date: string
          entry_time?: string
          id?: string
          sync_state?: Database["public"]["Enums"]["sync_state"]
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_ml?: number
          client_id?: string | null
          created_at?: string
          deleted_at?: string | null
          entry_date?: string
          entry_time?: string
          id?: string
          sync_state?: Database["public"]["Enums"]["sync_state"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      weight_entries: {
        Row: {
          client_id: string | null
          created_at: string
          deleted_at: string | null
          entry_date: string
          id: string
          note: string | null
          sync_state: Database["public"]["Enums"]["sync_state"]
          updated_at: string
          user_id: string
          weight_kg: number
        }
        Insert: {
          client_id?: string | null
          created_at?: string
          deleted_at?: string | null
          entry_date: string
          id?: string
          note?: string | null
          sync_state?: Database["public"]["Enums"]["sync_state"]
          updated_at?: string
          user_id: string
          weight_kg: number
        }
        Update: {
          client_id?: string | null
          created_at?: string
          deleted_at?: string | null
          entry_date?: string
          id?: string
          note?: string | null
          sync_state?: Database["public"]["Enums"]["sync_state"]
          updated_at?: string
          user_id?: string
          weight_kg?: number
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
    }
    Enums: {
      app_role: "admin" | "moderator" | "user"
      food_source: "barcode" | "photo" | "text" | "manual"
      meal_type: "breakfast" | "lunch" | "dinner" | "snack"
      sync_state: "pending" | "synced" | "conflict" | "failed"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "moderator", "user"],
      food_source: ["barcode", "photo", "text", "manual"],
      meal_type: ["breakfast", "lunch", "dinner", "snack"],
      sync_state: ["pending", "synced", "conflict", "failed"],
    },
  },
} as const

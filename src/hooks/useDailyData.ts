import { useState, useEffect, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { format } from "date-fns";
import type { MealType } from "@/lib/constants";

export interface MealEntry {
  id: string;
  food_id: string | null;
  custom_name: string | null;
  meal_type: MealType;
  amount_g_ml: number;
  calculated_kcal: number;
  calculated_protein: number;
  calculated_carbs: number;
  calculated_fat: number;
  entry_date: string;
  note: string | null;
  source: "barcode" | "photo" | "text" | "manual";
  created_at: string;
}

export interface WaterEntry {
  id: string;
  amount_ml: number;
  entry_date: string;
  entry_time: string;
  created_at: string;
}

export interface WeightEntry {
  id: string;
  weight_kg: number;
  entry_date: string;
  note: string | null;
  created_at: string;
}

export function useDailyData(date: Date) {
  const { user } = useAuth();
  const [mealEntries, setMealEntries] = useState<MealEntry[]>([]);
  const [waterEntries, setWaterEntries] = useState<WaterEntry[]>([]);
  const [latestWeight, setLatestWeight] = useState<WeightEntry | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const dateStr = format(date, "yyyy-MM-dd");

  const fetchData = useCallback(async () => {
    if (!user) {
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const { data: meals, error: mealsError } = await supabase
        .from("meal_entries")
        .select("*")
        .eq("user_id", user.id)
        .eq("entry_date", dateStr)
        .is("deleted_at", null)
        .order("created_at", { ascending: true });

      if (mealsError) throw mealsError;
      setMealEntries((meals || []) as MealEntry[]);

      const { data: water, error: waterError } = await supabase
        .from("water_entries")
        .select("*")
        .eq("user_id", user.id)
        .eq("entry_date", dateStr)
        .is("deleted_at", null)
        .order("entry_time", { ascending: true });

      if (waterError) throw waterError;
      setWaterEntries((water || []) as WaterEntry[]);

      const { data: weight, error: weightError } = await supabase
        .from("weight_entries")
        .select("*")
        .eq("user_id", user.id)
        .is("deleted_at", null)
        .order("entry_date", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (weightError) throw weightError;
      setLatestWeight(weight as WeightEntry | null);

      setError(null);
    } catch (err) {
      setError(err as Error);
    } finally {
      setLoading(false);
    }
  }, [user, dateStr]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const mealsByType = mealEntries.reduce((acc, entry) => {
    if (!acc[entry.meal_type]) {
      acc[entry.meal_type] = [];
    }
    acc[entry.meal_type].push(entry);
    return acc;
  }, {} as Record<MealType, MealEntry[]>);

  const totals = mealEntries.reduce(
    (acc, entry) => ({
      calories: acc.calories + entry.calculated_kcal,
      protein: acc.protein + entry.calculated_protein,
      carbs: acc.carbs + entry.calculated_carbs,
      fat: acc.fat + entry.calculated_fat,
    }),
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );

  const totalWater = waterEntries.reduce((sum, entry) => sum + entry.amount_ml, 0);

  const addMealEntry = async (entry: Omit<MealEntry, "id" | "created_at">) => {
    if (!user) return { error: new Error("Not authenticated") };

    try {
      const { data, error } = await supabase
        .from("meal_entries")
        .insert({
          user_id: user.id,
          ...entry,
        })
        .select()
        .single();

      if (error) throw error;

      setMealEntries((prev) => [...prev, data as MealEntry]);
      return { error: null };
    } catch (err) {
      return { error: err as Error };
    }
  };

  const updateMealEntry = async (
    id: string,
    updates: Partial<Omit<MealEntry, "id" | "created_at">>
  ) => {
    try {
      const { data, error } = await supabase
        .from("meal_entries")
        .update({
          ...updates,
          updated_at: new Date().toISOString(),
        })
        .eq("id", id)
        .select()
        .single();

      if (error) throw error;

      setMealEntries((prev) =>
        prev.map((entry) => (entry.id === id ? (data as MealEntry) : entry))
      );
      return { error: null };
    } catch (err) {
      return { error: err as Error };
    }
  };

  const deleteMealEntry = async (id: string) => {
    try {
      const { error } = await supabase
        .from("meal_entries")
        .update({ deleted_at: new Date().toISOString() })
        .eq("id", id);

      if (error) throw error;

      setMealEntries((prev) => prev.filter((entry) => entry.id !== id));
      return { error: null };
    } catch (err) {
      return { error: err as Error };
    }
  };

  const addWaterEntry = async (amount_ml: number) => {
    if (!user) return { error: new Error("Not authenticated") };

    try {
      const { data, error } = await supabase
        .from("water_entries")
        .insert({
          user_id: user.id,
          amount_ml,
          entry_date: dateStr,
        })
        .select()
        .single();

      if (error) throw error;

      setWaterEntries((prev) => [...prev, data as WaterEntry]);
      return { error: null };
    } catch (err) {
      return { error: err as Error };
    }
  };

  const addWeightEntry = async (weight_kg: number, note?: string) => {
    if (!user) return { error: new Error("Not authenticated") };

    try {
      const { data, error } = await supabase
        .from("weight_entries")
        .insert({
          user_id: user.id,
          weight_kg,
          entry_date: dateStr,
          note: note || null,
        })
        .select()
        .single();

      if (error) throw error;

      setLatestWeight(data as WeightEntry);
      return { error: null };
    } catch (err) {
      return { error: err as Error };
    }
  };

  return {
    mealEntries,
    mealsByType,
    waterEntries,
    latestWeight,
    totals,
    totalWater,
    loading,
    error,
    refetch: fetchData,
    addMealEntry,
    updateMealEntry,
    deleteMealEntry,
    addWaterEntry,
    addWeightEntry,
  };
}

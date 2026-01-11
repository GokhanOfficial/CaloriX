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
      // Fetch meal entries for the date
      const { data: meals, error: mealsError } = await supabase
        .from("meal_entries")
        .select("*")
        .eq("user_id", user.id)
        .eq("entry_date", dateStr)
        .is("deleted_at", null)
        .order("created_at", { ascending: true });

      if (mealsError) throw mealsError;
      setMealEntries((meals || []) as MealEntry[]);

      // Fetch water entries for the date
      const { data: water, error: waterError } = await supabase
        .from("water_entries")
        .select("*")
        .eq("user_id", user.id)
        .eq("entry_date", dateStr)
        .is("deleted_at", null)
        .order("entry_time", { ascending: true });

      if (waterError) throw waterError;
      setWaterEntries((water || []) as WaterEntry[]);

      // Fetch latest weight entry
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

  // Group meal entries by meal type
  const mealsByType = mealEntries.reduce((acc, entry) => {
    if (!acc[entry.meal_type]) {
      acc[entry.meal_type] = [];
    }
    acc[entry.meal_type].push(entry);
    return acc;
  }, {} as Record<MealType, MealEntry[]>);

  // Calculate totals
  const totals = mealEntries.reduce(
    (acc, entry) => ({
      calories: acc.calories + entry.calculated_kcal,
      protein: acc.protein + entry.calculated_protein,
      carbs: acc.carbs + entry.calculated_carbs,
      fat: acc.fat + entry.calculated_fat,
    }),
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );

  // Calculate total water intake
  const totalWater = waterEntries.reduce((sum, entry) => sum + entry.amount_ml, 0);

  // Add meal entry with optimistic update
  const addMealEntry = async (entry: Omit<MealEntry, "id" | "created_at">) => {
    if (!user) return { error: new Error("Not authenticated") };

    // Create optimistic entry
    const optimisticId = `temp-${Date.now()}`;
    const optimisticEntry: MealEntry = {
      ...entry,
      id: optimisticId,
      created_at: new Date().toISOString(),
    };

    // Optimistic update - add immediately to UI
    setMealEntries((prev) => [...prev, optimisticEntry]);

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

      // Replace optimistic entry with real one
      setMealEntries((prev) =>
        prev.map((e) => (e.id === optimisticId ? (data as MealEntry) : e))
      );
      return { error: null };
    } catch (err) {
      // Rollback optimistic update on error
      setMealEntries((prev) => prev.filter((e) => e.id !== optimisticId));
      return { error: err as Error };
    }
  };

  // Update meal entry with optimistic update
  const updateMealEntry = async (
    id: string,
    updates: Partial<Omit<MealEntry, "id" | "created_at">>
  ) => {
    // Store previous state for rollback
    const previousEntries = [...mealEntries];

    // Optimistic update
    setMealEntries((prev) =>
      prev.map((e) => (e.id === id ? { ...e, ...updates } : e))
    );

    try {
      const { error } = await supabase
        .from("meal_entries")
        .update({
          ...updates,
          updated_at: new Date().toISOString(),
        })
        .eq("id", id);

      if (error) throw error;
      return { error: null };
    } catch (err) {
      // Rollback on error
      setMealEntries(previousEntries);
      return { error: err as Error };
    }
  };

  // Delete meal entry with optimistic update
  const deleteMealEntry = async (id: string) => {
    // Store previous state for rollback
    const previousEntries = [...mealEntries];

    // Optimistic update - remove immediately from UI
    setMealEntries((prev) => prev.filter((e) => e.id !== id));

    try {
      const { error } = await supabase
        .from("meal_entries")
        .update({ deleted_at: new Date().toISOString() })
        .eq("id", id);

      if (error) throw error;
      return { error: null };
    } catch (err) {
      // Rollback on error
      setMealEntries(previousEntries);
      return { error: err as Error };
    }
  };

  // Add water entry with optimistic update
  const addWaterEntry = async (amount_ml: number) => {
    if (!user) return { error: new Error("Not authenticated") };

    // Create optimistic entry
    const optimisticId = `temp-${Date.now()}`;
    const optimisticEntry: WaterEntry = {
      id: optimisticId,
      amount_ml,
      entry_date: dateStr,
      entry_time: new Date().toISOString(),
      created_at: new Date().toISOString(),
    };

    // Optimistic update - add immediately to UI
    setWaterEntries((prev) => [...prev, optimisticEntry]);

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

      // Replace optimistic entry with real one
      setWaterEntries((prev) =>
        prev.map((e) => (e.id === optimisticId ? (data as WaterEntry) : e))
      );
      return { error: null };
    } catch (err) {
      // Rollback optimistic update on error
      setWaterEntries((prev) => prev.filter((e) => e.id !== optimisticId));
      return { error: err as Error };
    }
  };

  // Add weight entry with optimistic update
  const addWeightEntry = async (weight_kg: number, note?: string) => {
    if (!user) return { error: new Error("Not authenticated") };

    // Create optimistic entry
    const optimisticEntry: WeightEntry = {
      id: `temp-${Date.now()}`,
      weight_kg,
      entry_date: dateStr,
      note: note || null,
      created_at: new Date().toISOString(),
    };

    // Store previous state
    const previousWeight = latestWeight;

    // Optimistic update
    setLatestWeight(optimisticEntry);

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

      // Update with real data
      setLatestWeight(data as WeightEntry);
      return { error: null };
    } catch (err) {
      // Rollback on error
      setLatestWeight(previousWeight);
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

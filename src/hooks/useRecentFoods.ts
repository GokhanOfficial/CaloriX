import { useState, useEffect, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export interface RecentFood {
  id: string;
  food_id: string | null;
  name: string;
  brand: string | null;
  serving_size_g: number | null;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  last_used_at: string;
}

export function useRecentFoods() {
  const { user } = useAuth();
  const [recentFoods, setRecentFoods] = useState<RecentFood[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const fetchRecentFoods = useCallback(async () => {
    if (!user) return;

    setLoading(true);
    setError(null);

    try {
      // Get recent meal entries from meal_entries table (last 20 unique foods)
      const { data, error: fetchError } = await supabase
        .from("meal_entries")
        .select(`
          id,
          food_id,
          custom_name,
          amount_g_ml,
          calculated_kcal,
          calculated_protein,
          calculated_carbs,
          calculated_fat,
          created_at,
          foods (
            id,
            name,
            brand,
            serving_size_g,
            food_nutrition (
              kcal,
              protein_g,
              carbs_g,
              fat_g
            )
          )
        `)
        .eq("user_id", user.id)
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .limit(50);

      if (fetchError) throw fetchError;

      // Group by food name and get unique entries
      const seenNames = new Set<string>();
      const uniqueFoods: RecentFood[] = [];

      for (const entry of data || []) {
        const foodName = entry.foods 
          ? (entry.foods as any).name 
          : entry.custom_name || "Bilinmeyen";
        
        if (seenNames.has(foodName.toLowerCase())) continue;
        seenNames.add(foodName.toLowerCase());

        if (entry.foods && (entry.foods as any).food_nutrition) {
          // Food from database
          const food = entry.foods as any;
          const nutrition = food.food_nutrition;
          uniqueFoods.push({
            id: entry.id,
            food_id: entry.food_id,
            name: food.name,
            brand: food.brand,
            serving_size_g: food.serving_size_g,
            calories: nutrition.kcal,
            protein_g: nutrition.protein_g,
            carbs_g: nutrition.carbs_g,
            fat_g: nutrition.fat_g,
            last_used_at: entry.created_at,
          });
        } else {
          // Custom food entry - calculate per 100g values
          const amount = entry.amount_g_ml || 100;
          uniqueFoods.push({
            id: entry.id,
            food_id: null,
            name: entry.custom_name || "Bilinmeyen",
            brand: null,
            serving_size_g: amount,
            calories: Math.round((entry.calculated_kcal / amount) * 100),
            protein_g: Math.round((entry.calculated_protein / amount) * 100 * 10) / 10,
            carbs_g: Math.round((entry.calculated_carbs / amount) * 100 * 10) / 10,
            fat_g: Math.round((entry.calculated_fat / amount) * 100 * 10) / 10,
            last_used_at: entry.created_at,
          });
        }

        if (uniqueFoods.length >= 10) break;
      }

      setRecentFoods(uniqueFoods);
    } catch (err) {
      console.error("Recent foods fetch error:", err);
      setError(err as Error);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    fetchRecentFoods();
  }, [fetchRecentFoods]);

  return {
    recentFoods,
    loading,
    error,
    refetch: fetchRecentFoods,
  };
}

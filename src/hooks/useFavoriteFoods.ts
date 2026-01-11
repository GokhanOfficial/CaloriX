import { useState, useEffect, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export interface FavoriteFood {
  id: string;
  food_id: string | null;
  name: string;
  brand: string | null;
  serving_size_g: number | null;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  use_count: number;
}

export function useFavoriteFoods() {
  const { user } = useAuth();
  const [favorites, setFavorites] = useState<FavoriteFood[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const fetchFavorites = useCallback(async () => {
    if (!user) return;

    setLoading(true);
    setError(null);

    try {
      // Get most frequently used foods from meal_entries
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
        .limit(200);

      if (fetchError) throw fetchError;

      // Count frequency of each food
      const foodCounts = new Map<string, { count: number; entry: any }>();
      
      for (const entry of data || []) {
        const foodName = entry.foods 
          ? (entry.foods as any).name 
          : entry.custom_name || "Bilinmeyen";
        const key = foodName.toLowerCase();
        
        if (foodCounts.has(key)) {
          foodCounts.get(key)!.count++;
        } else {
          foodCounts.set(key, { count: 1, entry });
        }
      }

      // Sort by count and get top 10
      const sortedFoods = Array.from(foodCounts.entries())
        .sort((a, b) => b[1].count - a[1].count)
        .slice(0, 10);

      const formattedFavorites: FavoriteFood[] = sortedFoods.map(([_, { count, entry }]) => {
        if (entry.foods && (entry.foods as any).food_nutrition) {
          const food = entry.foods as any;
          const nutrition = food.food_nutrition;
          return {
            id: entry.id,
            food_id: entry.food_id,
            name: food.name,
            brand: food.brand,
            serving_size_g: food.serving_size_g,
            calories: nutrition.kcal,
            protein_g: nutrition.protein_g,
            carbs_g: nutrition.carbs_g,
            fat_g: nutrition.fat_g,
            use_count: count,
          };
        } else {
          // Custom food entry - calculate per 100g values
          const amount = entry.amount_g_ml || 100;
          return {
            id: entry.id,
            food_id: null,
            name: entry.custom_name || "Bilinmeyen",
            brand: null,
            serving_size_g: amount,
            calories: Math.round((entry.calculated_kcal / amount) * 100),
            protein_g: Math.round((entry.calculated_protein / amount) * 100 * 10) / 10,
            carbs_g: Math.round((entry.calculated_carbs / amount) * 100 * 10) / 10,
            fat_g: Math.round((entry.calculated_fat / amount) * 100 * 10) / 10,
            use_count: count,
          };
        }
      });

      setFavorites(formattedFavorites);
    } catch (err) {
      console.error("Favorites fetch error:", err);
      setError(err as Error);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    fetchFavorites();
  }, [fetchFavorites]);

  return {
    favorites,
    loading,
    error,
    refetch: fetchFavorites,
  };
}

import { useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useOnlineStatus } from "./useOnlineStatus";
import { useDebounce } from "./useDebounce";
import { useEffect } from "react";
import { useAuth } from "@/contexts/AuthContext";

export interface FoodSearchResult {
  id: string;
  name: string;
  brand: string | null;
  serving_size_g: number | null;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  isCustom?: boolean;
}

export function useFoodSearch(query: string) {
  const [results, setResults] = useState<FoodSearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const isOnline = useOnlineStatus();
  const { user } = useAuth();
  const debouncedQuery = useDebounce(query, 300);

  const searchFoods = useCallback(async (searchQuery: string) => {
    if (!searchQuery || searchQuery.length < 2) {
      setResults([]);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const allResults: FoodSearchResult[] = [];
      const seenNames = new Set<string>();

      // 1. Search in foods table with nutrition data (database foods)
      const { data: dbFoods, error: dbError } = await supabase
        .from("foods")
        .select(`
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
        `)
        .ilike("name", `%${searchQuery}%`)
        .order("popularity_count", { ascending: false })
        .limit(10);

      if (dbError) throw dbError;

      // Add database foods to results
      for (const item of dbFoods || []) {
        if (!item.food_nutrition) continue;
        const nutrition = item.food_nutrition as { kcal: number; protein_g: number; carbs_g: number; fat_g: number };
        const nameKey = item.name.toLowerCase();
        
        if (!seenNames.has(nameKey)) {
          seenNames.add(nameKey);
          allResults.push({
            id: item.id,
            name: item.name,
            brand: item.brand,
            serving_size_g: item.serving_size_g,
            calories: nutrition.kcal,
            protein_g: nutrition.protein_g,
            carbs_g: nutrition.carbs_g,
            fat_g: nutrition.fat_g,
            isCustom: false,
          });
        }
      }

      // 2. Search in user's custom meal entries (user-added foods)
      if (user) {
        const { data: customFoods, error: customError } = await supabase
          .from("meal_entries")
          .select(`
            id,
            custom_name,
            amount_g_ml,
            calculated_kcal,
            calculated_protein,
            calculated_carbs,
            calculated_fat,
            food_id
          `)
          .eq("user_id", user.id)
          .is("deleted_at", null)
          .is("food_id", null)
          .ilike("custom_name", `%${searchQuery}%`)
          .order("created_at", { ascending: false })
          .limit(50);

        if (!customError && customFoods) {
          // Group by name and get unique entries with calculated per-100g values
          for (const entry of customFoods) {
            if (!entry.custom_name) continue;
            const nameKey = entry.custom_name.toLowerCase();
            
            if (!seenNames.has(nameKey)) {
              seenNames.add(nameKey);
              
              // Calculate per 100g values
              const amount = entry.amount_g_ml || 100;
              allResults.push({
                id: `custom_${entry.id}`,
                name: entry.custom_name,
                brand: null,
                serving_size_g: amount,
                calories: Math.round((entry.calculated_kcal / amount) * 100),
                protein_g: Math.round((entry.calculated_protein / amount) * 100 * 10) / 10,
                carbs_g: Math.round((entry.calculated_carbs / amount) * 100 * 10) / 10,
                fat_g: Math.round((entry.calculated_fat / amount) * 100 * 10) / 10,
                isCustom: true,
              });
            }
          }
        }
      }

      // Sort: database foods first, then custom foods
      allResults.sort((a, b) => {
        if (a.isCustom && !b.isCustom) return 1;
        if (!a.isCustom && b.isCustom) return -1;
        return 0;
      });

      setResults(allResults.slice(0, 15));
    } catch (err) {
      console.error("Food search error:", err);
      setError(err as Error);
      setResults([]);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    searchFoods(debouncedQuery);
  }, [debouncedQuery, searchFoods]);

  return {
    results,
    loading,
    error,
    isOnline,
  };
}

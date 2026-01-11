import { useState, useEffect, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { format, subDays, startOfWeek, endOfWeek, startOfMonth, endOfMonth, eachDayOfInterval, parseISO } from "date-fns";
import { tr } from "date-fns/locale";

export interface DailyStats {
  date: string;
  dayLabel: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  water: number;
  hasData: boolean;
}

export interface WeightTrend {
  date: string;
  dateLabel: string;
  weight: number;
}

export interface AverageStats {
  avgCalories: number;
  avgProtein: number;
  avgCarbs: number;
  avgFat: number;
  avgWater: number;
  totalDays: number;
  daysWithData: number;
}

type Period = "week" | "month" | "3months";

export function useAnalyticsData(period: Period = "week") {
  const { user } = useAuth();
  const [dailyStats, setDailyStats] = useState<DailyStats[]>([]);
  const [weightTrend, setWeightTrend] = useState<WeightTrend[]>([]);
  const [averages, setAverages] = useState<AverageStats>({
    avgCalories: 0,
    avgProtein: 0,
    avgCarbs: 0,
    avgFat: 0,
    avgWater: 0,
    totalDays: 0,
    daysWithData: 0,
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const getDateRange = useCallback((p: Period) => {
    const today = new Date();
    let start: Date;
    let end: Date = today;

    switch (p) {
      case "week":
        start = startOfWeek(today, { locale: tr, weekStartsOn: 1 });
        end = endOfWeek(today, { locale: tr, weekStartsOn: 1 });
        break;
      case "month":
        start = startOfMonth(today);
        end = endOfMonth(today);
        break;
      case "3months":
        start = subDays(today, 90);
        break;
      default:
        start = subDays(today, 7);
    }

    return { start, end };
  }, []);

  const fetchData = useCallback(async () => {
    if (!user) {
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const { start, end } = getDateRange(period);
      const startStr = format(start, "yyyy-MM-dd");
      const endStr = format(end, "yyyy-MM-dd");

      // Fetch meal entries for the period
      const { data: meals, error: mealsError } = await supabase
        .from("meal_entries")
        .select("entry_date, calculated_kcal, calculated_protein, calculated_carbs, calculated_fat")
        .eq("user_id", user.id)
        .gte("entry_date", startStr)
        .lte("entry_date", endStr)
        .is("deleted_at", null);

      if (mealsError) throw mealsError;

      // Fetch water entries for the period
      const { data: water, error: waterError } = await supabase
        .from("water_entries")
        .select("entry_date, amount_ml")
        .eq("user_id", user.id)
        .gte("entry_date", startStr)
        .lte("entry_date", endStr)
        .is("deleted_at", null);

      if (waterError) throw waterError;

      // Fetch weight entries (all time for trend)
      const { data: weights, error: weightsError } = await supabase
        .from("weight_entries")
        .select("entry_date, weight_kg")
        .eq("user_id", user.id)
        .is("deleted_at", null)
        .order("entry_date", { ascending: true });

      if (weightsError) throw weightsError;

      // Generate all days in the period
      const days = eachDayOfInterval({ start, end: new Date(Math.min(end.getTime(), new Date().getTime())) });

      // Group data by date
      const mealsByDate: Record<string, { calories: number; protein: number; carbs: number; fat: number }> = {};
      const waterByDate: Record<string, number> = {};

      for (const meal of meals || []) {
        const date = meal.entry_date;
        if (!mealsByDate[date]) {
          mealsByDate[date] = { calories: 0, protein: 0, carbs: 0, fat: 0 };
        }
        mealsByDate[date].calories += meal.calculated_kcal;
        mealsByDate[date].protein += meal.calculated_protein;
        mealsByDate[date].carbs += meal.calculated_carbs;
        mealsByDate[date].fat += meal.calculated_fat;
      }

      for (const w of water || []) {
        const date = w.entry_date;
        waterByDate[date] = (waterByDate[date] || 0) + w.amount_ml;
      }

      // Create daily stats
      const stats: DailyStats[] = days.map((day) => {
        const dateStr = format(day, "yyyy-MM-dd");
        const mealData = mealsByDate[dateStr];
        const waterData = waterByDate[dateStr];
        const hasData = !!mealData || !!waterData;

        return {
          date: dateStr,
          dayLabel: period === "week" 
            ? format(day, "EEE", { locale: tr })
            : format(day, "d MMM", { locale: tr }),
          calories: Math.round(mealData?.calories || 0),
          protein: Math.round((mealData?.protein || 0) * 10) / 10,
          carbs: Math.round((mealData?.carbs || 0) * 10) / 10,
          fat: Math.round((mealData?.fat || 0) * 10) / 10,
          water: waterData || 0,
          hasData,
        };
      });

      setDailyStats(stats);

      // Calculate averages - only include days that have specific data type
      const daysWithMeals = stats.filter((s) => s.calories > 0);
      const daysWithWater = stats.filter((s) => s.water > 0);
      const daysWithData = stats.filter((s) => s.hasData);
      
      const mealCount = daysWithMeals.length || 1;
      const waterCount = daysWithWater.length || 1;

      setAverages({
        avgCalories: Math.round(daysWithMeals.reduce((sum, s) => sum + s.calories, 0) / mealCount),
        avgProtein: Math.round(daysWithMeals.reduce((sum, s) => sum + s.protein, 0) / mealCount * 10) / 10,
        avgCarbs: Math.round(daysWithMeals.reduce((sum, s) => sum + s.carbs, 0) / mealCount * 10) / 10,
        avgFat: Math.round(daysWithMeals.reduce((sum, s) => sum + s.fat, 0) / mealCount * 10) / 10,
        avgWater: Math.round(daysWithWater.reduce((sum, s) => sum + s.water, 0) / waterCount),
        totalDays: stats.length,
        daysWithData: daysWithData.length,
      });

      // Process weight trend
      const weightData: WeightTrend[] = (weights || []).map((w) => ({
        date: w.entry_date,
        dateLabel: format(parseISO(w.entry_date), "d MMM", { locale: tr }),
        weight: w.weight_kg,
      }));

      setWeightTrend(weightData);
      setError(null);
    } catch (err) {
      console.error("Analytics fetch error:", err);
      setError(err as Error);
    } finally {
      setLoading(false);
    }
  }, [user, period, getDateRange]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  return {
    dailyStats,
    weightTrend,
    averages,
    loading,
    error,
    refetch: fetchData,
  };
}

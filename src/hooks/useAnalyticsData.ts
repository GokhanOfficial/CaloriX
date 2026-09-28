import { useState, useEffect, useCallback, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { format, startOfWeek, endOfWeek, startOfMonth, endOfMonth } from "date-fns";
import { tr } from "date-fns/locale";
import {
  addLocalDays,
  dayDiff,
  eachLocalDay,
  formatLocalDate,
  parseDateOnly,
  startOfLocalDay,
} from "@/lib/dates";

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

/**
 * "Bugün"ün **yerel** gece yarısı.
 *
 * `new Date()` tek başına **gece yarısını aşmış** olabilir (ör. 00:10);
 * bir istek boyunca `new Date()` iki kez çağrılırsa (aralık + kırpma)
 * ikinci çağrı bir sonraki güne geçmiş olur ve `start > end` üretir.
 * Dart tarafında da `date_utils.startOfDay(now)` tek noktadan geçiyor.
 */
export const getToday = (): Date => startOfLocalDay(new Date());

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
    // **Yerel** gün başlangıcına sabitlenir: `new Date()` gece yarısını
    // aşmışsa (ör. 00:10), `startOfWeek`/`endOfWeek` zaten bugünü içerir
    // ama `addLocalDays(today, -90)` hesabı saat dilimine göre kayabiliyor.
    // Dart tarafı `date_utils.dart` `startOfDay` ile aynı normalizasyonu
    // yapıyor.
    const today = getToday();
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
        // **Takvim günü** — `addLocalDays` `setDate` tabanlıdır, yani
        // DST'de 23/25 saatlik günlerde de doğru günü verir. Eski
        // `subDays(today, 90)` de `setDate` kullanıyordu ama **ikinci**
        // bir `new Date()` çağrısı (kırpma) gece yarısını aşabildiği için
        // aralık bozulabiliyordu; artık tek `getToday()` var.
        start = addLocalDays(today, -90);
        break;
      default:
        start = addLocalDays(today, -7);
    }

    return { start, end };
  }, []);

  /**
   * Uçuşta kalan isteği geçersiz kılmak için sayaç (bkz. `useDailyData`
   * / `ProfileContext`).
   *
   * `period` değiştirilip ekran hızla açılıp kapatıldığında (Tabs) iki
   * istek yarışıyordu; yavaş çözülen önceki periyodun verisi geç gelen
   * yeni periyodun üzerine yazıyordu → grafik yanlış dönemi gösteriyordu.
   */
  const requestIdRef = useRef(0);

  const fetchData = useCallback(async () => {
    const requestId = ++requestIdRef.current;

    if (!user) {
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const { start, end } = getDateRange(period);
      const startStr = formatLocalDate(start);
      const endStr = formatLocalDate(end);

      // Fetch meal entries for the period
      const { data: meals, error: mealsError } = await supabase
        .from("meal_entries")
        .select("entry_date, calculated_kcal, calculated_protein, calculated_carbs, calculated_fat")
        .eq("user_id", user.id)
        .gte("entry_date", startStr)
        .lte("entry_date", endStr)
        .is("deleted_at", null);

      if (requestId !== requestIdRef.current) return;
      if (mealsError) throw mealsError;

      // Fetch water entries for the period
      const { data: water, error: waterError } = await supabase
        .from("water_entries")
        .select("entry_date, amount_ml")
        .eq("user_id", user.id)
        .gte("entry_date", startStr)
        .lte("entry_date", endStr)
        .is("deleted_at", null);

      if (requestId !== requestIdRef.current) return;
      if (waterError) throw waterError;

      // Kilo trendi — son 1 yıl.
      //
      // **Sınırsızdı (P1, iki istemci arasındaki davranış farkı).**
      // "Tüm geçmiş" sorgusu yıllarca günlük kilo giren bir kullanıcıda
      // binlerce satır indiriyor; grafik yine de son ~30 noktayı
      // gösteriyor. Flutter aynı ekranı 1 yıllık pencereyle sınırlıyor
      // (`analytics_repository.dart:352-362`), web'de bu sınır yoktu.
      const weightFromStr = formatLocalDate(addLocalDays(getToday(), -365));
      const { data: weights, error: weightsError } = await supabase
        .from("weight_entries")
        .select("entry_date, weight_kg")
        .eq("user_id", user.id)
        .is("deleted_at", null)
        .gte("entry_date", weightFromStr)
        .order("entry_date", { ascending: true });

      if (requestId !== requestIdRef.current) return;
      if (weightsError) throw weightsError;

      // Aralıktaki her günü üret.
      //
      // 1. **Bugünden sonraki günler kırpılıyor.** `endOfWeek`/`endOfMonth`
      //    gelecek tarihleri veriyordu; `hasData: false` günler grafiğe
      //    "0 kalori" olarak giriyordu haftanın geri kalanını
      //    yapay olarak düşürüyordu.
      // 2. **DST-safe (P1).** `eachDayOfInterval` **ters aralıkta
      //    `RangeError` fırlatır** ve aralığı saat dilimi kuralıyla
      //    ilerletir; 23 saatlik bir günde ilk günü atlayabiliyordu.
      //    Flutter tarafı `buildDays` bu yüzden `eachDayOfInterval`
      //    **kullanmıyor**, takvim günü gün gün (`addLocalDays`) üretiyor.
      //    Web tarafı da aynı sözleşmeye geçirildi ve ters aralık
      //    kontrolü `dayDiff` ile yapıldı (aynı `Date.now()` yerine
      //    **tek** `getToday()` çağrısı — iki kez çağırmak gece yarısını
      //    aşan bir istekte `start > end` üretiyordu).
      const cappedEnd = getToday();
      const days = dayDiff(start, cappedEnd) >= 0 ? eachLocalDay(start, cappedEnd) : [];

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
        // **Anahtar eşleşmesi `entry_date` ile yapılıyor.** `day`
        // yerel gece yarısına sabitlendiği için `format(day, "yyyy-MM-dd")`
        // zaten yerel günü verir; yine de tek kaynak (`formatLocalDate`).
        const dateStr = formatLocalDate(day);
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

      // Kilo trendi etiketleri.
      //
      // `entry_date` bir `DATE` kolonu olduğu için sunucu **"2026-03-01"**
      // (tarih-saat değil) döner. Bu dizeyi `new Date(...)` ile ayrıştırmak
      // **UTC gece yarısı** üretir ve `format()` yerel saatte yazdırır:
      // Batı yarımkürede doğru gün, Doğu yarımkürede **bir gün geri**
      // gösterilirdi. `parseDateOnly` yerel takvim gününe sabitler.
      //
      // Satır **atlanmaz** — okunamayan tarih ham dize olarak etiketlenir
      // (grafikte boş nokta, yanlış günden iyidir).
      const weightData: WeightTrend[] = (weights || [])
        .filter((w) => typeof w.entry_date === "string" && w.entry_date.trim() !== "")
        .map((w) => {
          const localDate = parseDateOnly(w.entry_date);
          return {
            date: w.entry_date,
            dateLabel: localDate
              ? format(localDate, "d MMM", { locale: tr })
              : w.entry_date,
            weight: w.weight_kg,
          };
        });

      setWeightTrend(weightData);
      setError(null);
    } catch (err) {
      if (requestId !== requestIdRef.current) return;
      console.error("Analytics fetch error:", err);
      setError(err as Error);
    } finally {
      if (requestId === requestIdRef.current) setLoading(false);
    }
  }, [user, period, getDateRange]);

  useEffect(() => {
    void fetchData();
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

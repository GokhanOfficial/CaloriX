import { useState, useEffect, useCallback, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { formatLocalDate } from "@/lib/dates";
import type { MealType } from "@/lib/constants";

/**
 * DB'nin kabul ettiği miktar aralığı — `meal_entries` CHECK kısıtı
 * (`full_setup.sql`, `amount_g_ml > 0 AND amount_g_ml <= 10000`).
 * Flutter tarafı da aynı sınırları uygular.
 */
export const MAX_MEAL_AMOUNT = 10_000;

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
  source: "photo" | "text" | "manual";
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

  // `date` bir `Date` nesnesidir ve her render'da **yeni referans** alır
  // (`new Date()` / `setState`). `useCallback` bağımlılığına doğrudan
  // konulamaz. O yüzden bağımlılık **gün dizesidir** ve gün değiştiğinde
  // `fetchData` yeniden üretilir (aşağıdaki `useEffect` buna bağlı).
  const dateStr = formatLocalDate(date);

  /**
   * Uçuşta kalan isteği geçersiz kılmak için sayaç (aynı desen
   * `ProfileContext`'teki `requestIdRef`).
   *
   * Sorun: kullanıcı gün seçicide hızlıca "bugün → dün → bugün" yaptığında
   * üç `fetchData` çağrısı birbirinden bağımsız çalışır. Yavaş olan ilk
   * istek, hızlı çözülen son istekten **sonra** dönerse `setMealEntries`
   * yanlış günün verisiyle ezilir → ekranda "bugün" başlığı altında
   * **dünün** öğünleri görünür. Çözülme anında jeton karşılaştırması
   * yapıldığı için geç gelen yanıt state'e hiç dokunmaz.
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
      const { data: meals, error: mealsError } = await supabase
        .from("meal_entries")
        .select("*")
        .eq("user_id", user.id)
        .eq("entry_date", dateStr)
        .is("deleted_at", null)
        .order("created_at", { ascending: true });

      if (requestId !== requestIdRef.current) return;
      if (mealsError) throw mealsError;
      setMealEntries((meals || []) as MealEntry[]);

      const { data: water, error: waterError } = await supabase
        .from("water_entries")
        .select("*")
        .eq("user_id", user.id)
        .eq("entry_date", dateStr)
        .is("deleted_at", null)
        .order("entry_time", { ascending: true });

      if (requestId !== requestIdRef.current) return;
      if (waterError) throw waterError;
      setWaterEntries((water || []) as WaterEntry[]);

      // En son kilo kaydı — tüm geçmişten (seçili günle sınırlı değil).
      // NOT: `.limit(1)` + `.single()` birlikte kullanılamaz: PostgREST 0 veya
      // 1 satır döndüğünde `.single()` hata verir. `.maybeSingle()` tek bir
      // nesne döndürdüğü için doğru seçim. Ayrıca RLS'e ek olarak kullanıcı
      // kapsamı burada da filtreleniyor (savunma katmanı).
      //
      // **Belirsiz sıralama (P1):** yalnız `entry_date` sıralanıyordu.
      // `weight_entries.entry_date` üzerinde tek gün için birden fazla satır
      // yazılabilir (kilo günü `DATE` kolonu; UI "bugün" günü tekilleştirmiyor)
      // ve aynı gün için satır **yoksa** `.limit(1)` hangi kaydı döndüreceğini
      // DB garanti etmez → "en son kilo" iki farklı kayıt arasında rastgele
      // değişebilir. `created_at` ikincil sıralama anahtarı eklendi:
      // aynı gün içinde en son **yazılan** kayıt seçilir.
      const { data: weight, error: weightError } = await supabase
        .from("weight_entries")
        .select("*")
        .eq("user_id", user.id)
        .is("deleted_at", null)
        .order("entry_date", { ascending: false })
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (requestId !== requestIdRef.current) return;
      if (weightError) throw weightError;
      setLatestWeight(weight as WeightEntry | null);

      setError(null);
    } catch (err) {
      if (requestId !== requestIdRef.current) return;
      setError(err as Error);
    } finally {
      if (requestId === requestIdRef.current) setLoading(false);
    }
  }, [user, dateStr]);

  useEffect(() => {
    void fetchData();
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

    // **Sınır yoktu (P1).** `AddMealDialog` ve `EditMealDialog` kendi
    // doğrulamasını yapsa da, miktarı o formdan geçmeyen yollar var:
    // AI tanıma (`UnifiedFoodDialog` → `calculated_kcal` doğrudan yazılır),
    // hızlı ekleme ve doğrudan `addMealEntry` çağrıları. Negatif ya da
    // `NaN` miktar DB CHECK kısıtını ihlal eder (400), `1e9` gibi aşırı bir
    // değer ise günlük toplamları tek öğünde bozar.
    //
    // Flutter tarafında aynı sınıf hata `recognition_confirm_dialog` /
    // `edit_meal_entry_dialog` / `add_manual_entry` ile kapatıldı
    // (`isUsableAmount`); web'de üç ayrı yol korumasız kalmıştı.
    const amount = entry.amount_g_ml;
    if (!Number.isFinite(amount) || amount <= 0 || amount > MAX_MEAL_AMOUNT) {
      return {
        error: new Error(
          `Geçersiz miktar (0-${MAX_MEAL_AMOUNT} g/ml aralığında olmalı)`
        ),
      };
    }

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
    // `user_id` filtresi yoktu: RLS `auth.uid() = user_id` ile korusa bile
    // savunma katmanı olarak burada da ekleniyor (bkz. `deleteMealEntry`,
    // `useNotifications.markAsRead` — ikisi de bu filtreyi kullanıyor).
    // `.eq("deleted_at", null)` ile "zaten silinmiş" kayıt güncellenmiyor.
    if (!user) return { error: new Error("Not authenticated") };

    try {
      const { data, error } = await supabase
        .from("meal_entries")
        .update({
          ...updates,
          updated_at: new Date().toISOString(),
        })
        .eq("id", id)
        .eq("user_id", user.id)
        .is("deleted_at", null)
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
    if (!user) return { error: new Error("Not authenticated") };

    try {
      const { error } = await supabase
        .from("meal_entries")
        .update({ deleted_at: new Date().toISOString() })
        .eq("id", id)
        .eq("user_id", user.id);

      if (error) throw error;

      setMealEntries((prev) => prev.filter((entry) => entry.id !== id));
      return { error: null };
    } catch (err) {
      return { error: err as Error };
    }
  };

  const addWaterEntry = async (amount_ml: number) => {
    if (!user) return { error: new Error("Not authenticated") };
    // Üst sınır yoktu: hızlı ekleme butonları ya da doğrudan çağrı ile
    // 1.000.000 ml yazılabiliyordu (günlük hedef 2500 ml). Flutter tarafı
    // 5000 ml'de kesiyor.
    if (!Number.isFinite(amount_ml) || amount_ml <= 0 || amount_ml > 5000) {
      return { error: new Error("Geçersiz su miktarı (0-5000 ml aralığında olmalı)") };
    }

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
    // Fiziksel olarak geçersiz kilo (NaN/≤0/≥500) trend grafiğini ve BMI'yı
    // bozuyordu. Flutter tarafı aynı sınıf hatayı 20–500 kg aralığında
    // sınırlıyor (bkz. `weight_card`).
    if (!Number.isFinite(weight_kg) || weight_kg < 20 || weight_kg > 500) {
      return { error: new Error("Geçersiz kilo (20-500 kg aralığında olmalı)") };
    }

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

import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { Database } from '@/integrations/supabase/types';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';
import { APP_VERSION } from '@/lib/constants';

/**
 * ISO zaman damgasını **yerel** takvim tarihine (`yyyy-MM-dd`) çevirir.
 * `toISOString().split('T')[0]` UTC tarihini verir; UTC+03:00'te gece 00:00
 * civarı yapılan kayıtlar "dün" olarak etiketleniyordu.
 * Geçersiz/boş girdi için `null` döner.
 */
function localDateFromIso(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export interface ExportData {
  version: string;
  exportedAt: string;
  profile: Record<string, unknown> | null;
  mealEntries: Record<string, unknown>[];
  waterEntries: Record<string, unknown>[];
  weightEntries: Record<string, unknown>[];
  foods: Record<string, unknown>[];
  favoriteFoods: Record<string, unknown>[];
  recentFoods: Record<string, unknown>[];
  notificationPreferences: Record<string, unknown>[];
}

export function useDataExport() {
  const { user } = useAuth();
  const { toast } = useToast();
  const [isExporting, setIsExporting] = useState(false);
  const [isImporting, setIsImporting] = useState(false);

  const exportData = async () => {
    if (!user) {
      toast({ title: 'Hata', description: 'Oturum açmanız gerekiyor', variant: 'destructive' });
      return;
    }

    setIsExporting(true);

    try {
      // Fetch all user data in parallel
      const [
        profileRes,
        mealEntriesRes,
        waterEntriesRes,
        weightEntriesRes,
        foodsRes,
        favoriteFoodsRes,
        recentFoodsRes,
        notificationPrefsRes,
      ] = await Promise.all([
        supabase.from('profiles').select('*').eq('id', user.id).single(),
        supabase.from('meal_entries').select('*').eq('user_id', user.id),
        supabase.from('water_entries').select('*').eq('user_id', user.id),
        supabase.from('weight_entries').select('*').eq('user_id', user.id),
        supabase.from('foods').select('*, food_nutrition(*)').eq('created_by', user.id),
        supabase.from('favorite_foods').select('*').eq('user_id', user.id),
        supabase.from('recent_foods').select('*').eq('user_id', user.id),
        supabase.from('notification_preferences').select('*').eq('user_id', user.id),
      ]);

      const exportData: ExportData = {
        version: APP_VERSION,
        exportedAt: new Date().toISOString(),
        profile: profileRes.data,
        mealEntries: mealEntriesRes.data || [],
        waterEntries: waterEntriesRes.data || [],
        weightEntries: weightEntriesRes.data || [],
        foods: foodsRes.data || [],
        favoriteFoods: favoriteFoodsRes.data || [],
        recentFoods: recentFoodsRes.data || [],
        notificationPreferences: notificationPrefsRes.data || [],
      };

      // Create and download JSON file
      const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `calorix-backup-${localDateFromIso(new Date().toISOString())}.json`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);

      toast({
        title: 'Dışa Aktarma Başarılı',
        description: `${mealEntriesRes.data?.length || 0} öğün, ${waterEntriesRes.data?.length || 0} su kaydı, ${weightEntriesRes.data?.length || 0} kilo kaydı dışa aktarıldı.`,
      });
    } catch (error) {
      console.error('Export error:', error);
      toast({ title: 'Hata', description: 'Veriler dışa aktarılamadı', variant: 'destructive' });
    } finally {
      setIsExporting(false);
    }
  };

  const importData = async (file: File) => {
    if (!user) {
      toast({ title: 'Hata', description: 'Oturum açmanız gerekiyor', variant: 'destructive' });
      return;
    }

    setIsImporting(true);

    try {
      const text = await file.text();
      const data: ExportData = JSON.parse(text);

      // Validate structure
      if (!data.version || !data.exportedAt) {
        throw new Error('Geçersiz yedek dosyası formatı');
      }

      let importedCount = {
        meals: 0,
        water: 0,
        weight: 0,
        foods: 0,
      };

      // Import custom foods first (they might be referenced by meal entries)
      if (data.foods && data.foods.length > 0) {
        for (const food of data.foods) {
          const nutrition = (food as any).food_nutrition?.[0];
          delete (food as any).food_nutrition;

          // Yedek dosyası kullanıcı kontrolünde: yalnızca beyaz listelenmiş
          // kolonlar kopyalanır (kullanıcı/denetim alanları hariç), böylece
          // yedekten `created_by`/`verified`/`popularity_count` gibi alanlar
          // değiştirilemez. Kolonlar migration
          // 20260111041204_...sql:80-98 (foods) ile eşleşir.
          // NOT: 'barcode' kolonu ve 'barcode' enum değeri
          // migration 20260822000000_remove_barcode.sql ile kaldırıldı.
          const name = (food as any).name;
          if (typeof name !== 'string' || !name.trim()) continue;

          const rawSource = (food as any).source;
          // Enum değeri doğrulanmazsa insert CHECK ihlaliyle tüm import'u
          // düşürüyordu; geçersizse DB varsayılanına ('manual') bırakıyoruz.
          const source =
            rawSource === 'photo' || rawSource === 'text' || rawSource === 'manual'
              ? rawSource
              : 'manual';

          const foodRow: Database['public']['Tables']['foods']['Insert'] = {
            name: name.trim(),
            created_by: user.id,
            source,
          };
          const brand = (food as any).brand;
          const serving_size_g = (food as any).serving_size_g;
          const serving_description = (food as any).serving_description;
          const image_url = (food as any).image_url;
          if (brand != null) foodRow.brand = brand;
          if (serving_size_g != null) foodRow.serving_size_g = serving_size_g;
          if (serving_description != null) foodRow.serving_description = serving_description;
          if (image_url != null) foodRow.image_url = image_url;

          // Check if food already exists
          // `.single()` 0 satırda hata döndürür (PGRST116) -> import sessizce
          // atlanıyordu. `.maybeSingle()` ile yalnızca gerçekten var mı diye bakıyoruz.
          const { data: existingFood } = await supabase
            .from('foods')
            .select('id')
            .eq('name', foodRow.name)
            .eq('created_by', user.id)
            .maybeSingle();

          if (!existingFood) {
            const { data: newFood, error: foodError } = await supabase
              .from('foods')
              .insert(foodRow)
              .select('id')
              .single();

            // Beslenme kolonları da beyaz listeli (migration satır 107-121).
            if (!foodError && newFood && nutrition) {
              const nutritionRow: Database['public']['Tables']['food_nutrition']['Insert'] = {
                food_id: newFood.id,
                kcal: Number((nutrition as any).kcal) || 0,
                protein_g: Number((nutrition as any).protein_g) || 0,
                carbs_g: Number((nutrition as any).carbs_g) || 0,
                fat_g: Number((nutrition as any).fat_g) || 0,
              };
              const optionalNutrition = {
                per_100_g_ml: (nutrition as any).per_100_g_ml,
                fiber_g: (nutrition as any).fiber_g,
                sugar_g: (nutrition as any).sugar_g,
                salt_g: (nutrition as any).salt_g,
                saturated_fat_g: (nutrition as any).saturated_fat_g,
              };
              for (const [key, value] of Object.entries(optionalNutrition)) {
                if (value !== undefined && value !== null) {
                  (nutritionRow as Record<string, unknown>)[key] = value;
                }
              }
              const { error: nutritionError } = await supabase
                .from('food_nutrition')
                .insert(nutritionRow);
              if (!nutritionError) importedCount.foods++;
            }
          }
        }
      }

      // Import meal entries (additive - don't delete existing)
      if (data.mealEntries && data.mealEntries.length > 0) {
        for (const entry of data.mealEntries) {
          // Check if entry already exists (by date+name combo)
          const entryDate = (entry as any).entry_date;
          const mealType = (entry as any).meal_type;
          const foodName = (entry as any).custom_name || (entry as any).food_name || '';
          
          const { data: existing } = await supabase
            .from('meal_entries')
            .select('id')
            .eq('user_id', user.id)
            .eq('entry_date', entryDate)
            .eq('custom_name', foodName)
            .eq('meal_type', mealType)
            .maybeSingle();

          if (!existing) {
            const { error } = await supabase.from('meal_entries').insert({
              user_id: user.id,
              entry_date: entryDate,
              meal_type: mealType,
              custom_name: foodName || null,
              amount_g_ml: (entry as any).amount_g_ml || (entry as any).amount_g || 100,
              calculated_kcal: (entry as any).calculated_kcal || (entry as any).calories || 0,
              calculated_protein: (entry as any).calculated_protein || (entry as any).protein_g || 0,
              calculated_carbs: (entry as any).calculated_carbs || (entry as any).carbs_g || 0,
              calculated_fat: (entry as any).calculated_fat || (entry as any).fat_g || 0,
              source: (entry as any).source || 'manual',
            });
            if (!error) importedCount.meals++;
          }
        }
      }

      // Import water entries
      if (data.waterEntries && data.waterEntries.length > 0) {
        for (const entry of data.waterEntries) {
          // `.single()` 0 satırda hata döndürür (PGRST116) ve bu hata
          // import'u sessizce düşürüyordu — `.maybeSingle()` kullanıyoruz.
          const { data: existing } = await supabase
            .from('water_entries')
            .select('id')
            .eq('user_id', user.id)
            .eq('entry_time', (entry as any).entry_time)
            .maybeSingle();

          if (!existing) {
            const { error } = await supabase.from('water_entries').insert({
              user_id: user.id,
              // `entry_time` TIMESTAMPTZ -> `entry_date` DATE. toISOString() UTC
              // kullandığı için yerel saat diliminde gece yarısını geçen kayıtlar
              // bir gün öne/arkaya kayabiliyordu; yerel tarih alınıyor.
              entry_date: (entry as any).entry_date || localDateFromIso((entry as any).entry_time),
              entry_time: (entry as any).entry_time,
              amount_ml: (entry as any).amount_ml,
            });
            if (!error) importedCount.water++;
          }
        }
      }

      // Import weight entries
      if (data.weightEntries && data.weightEntries.length > 0) {
        for (const entry of data.weightEntries) {
          // NOT: `weight_entries` tablosunda `recorded_at` kolonu YOK
          // (migration 20260111041204, satır ~178). Yedek `entry_date` içerdiği
          // için `created_at` üzerinden tarih türetiyoruz.
          const entryDate = (entry as any).entry_date || localDateFromIso((entry as any).created_at);
          if (!entryDate) continue;

          // Aynı gün için birden fazla kayıt olabilir; en güncelini seçiyoruz.
          const { data: existing } = await supabase
            .from('weight_entries')
            .select('id')
            .eq('user_id', user.id)
            .eq('entry_date', entryDate)
            .is('deleted_at', null)
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle();

          if (!existing) {
            const { error } = await supabase.from('weight_entries').insert({
              user_id: user.id,
              entry_date: entryDate,
              weight_kg: (entry as any).weight_kg,
              note: (entry as any).note || (entry as any).notes || null,
            });
            if (!error) importedCount.weight++;
          }
        }
      }

      toast({
        title: 'İçe Aktarma Başarılı',
        description: `${importedCount.meals} öğün, ${importedCount.water} su, ${importedCount.weight} kilo, ${importedCount.foods} yemek içe aktarıldı.`,
      });
    } catch (error) {
      console.error('Import error:', error);
      toast({
        title: 'Hata',
        description: error instanceof Error ? error.message : 'Veriler içe aktarılamadı',
        variant: 'destructive',
      });
    } finally {
      setIsImporting(false);
    }
  };

  return {
    exportData,
    importData,
    isExporting,
    isImporting,
  };
}

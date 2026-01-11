import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';

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
        version: '1.0.0',
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
      link.download = `calorix-backup-${new Date().toISOString().split('T')[0]}.json`;
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

          // Check if food already exists
          const { data: existingFood } = await supabase
            .from('foods')
            .select('id')
            .eq('name', (food as any).name)
            .eq('created_by', user.id)
            .single();

          if (!existingFood) {
            const { data: newFood, error: foodError } = await supabase
              .from('foods')
              .insert({
                ...(food as any),
                id: undefined, // Let DB generate new ID
                created_by: user.id,
              })
              .select('id')
              .single();

            if (!foodError && newFood && nutrition) {
              await supabase.from('food_nutrition').insert({
                ...nutrition,
                id: undefined,
                food_id: newFood.id,
              });
              importedCount.foods++;
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
              entry_date: (entry as any).entry_date,
              meal_type: (entry as any).meal_type,
              custom_name: (entry as any).custom_name || (entry as any).food_name,
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
          const { data: existing } = await supabase
            .from('water_entries')
            .select('id')
            .eq('user_id', user.id)
            .eq('entry_time', (entry as any).entry_time)
            .single();

          if (!existing) {
            const { error } = await supabase.from('water_entries').insert({
              user_id: user.id,
              entry_date: (entry as any).entry_date || new Date((entry as any).entry_time).toISOString().split('T')[0],
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
          const entryDate = (entry as any).entry_date || new Date((entry as any).recorded_at).toISOString().split('T')[0];
          
          const { data: existing } = await supabase
            .from('weight_entries')
            .select('id')
            .eq('user_id', user.id)
            .eq('entry_date', entryDate)
            .maybeSingle();

          if (!existing) {
            const { error } = await supabase.from('weight_entries').insert({
              user_id: user.id,
              entry_date: (entry as any).entry_date || new Date((entry as any).recorded_at).toISOString().split('T')[0],
              weight_kg: (entry as any).weight_kg,
              note: (entry as any).note || (entry as any).notes,
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

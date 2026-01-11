import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { format } from "date-fns";
import { AppLayout } from "@/components/layout/AppLayout";
import { DateSelector } from "@/components/common/DateSelector";
import { DailySummary } from "@/components/dashboard/DailySummary";
import { WaterTracker } from "@/components/dashboard/WaterTracker";
import { WeightBanner } from "@/components/dashboard/WeightBanner";
import { QuickAddMenu } from "@/components/dashboard/QuickAddMenu";
import { MealSection } from "@/components/dashboard/MealSection";
import { AddMealDialog } from "@/components/dialogs/AddMealDialog";
import { EditMealDialog } from "@/components/dialogs/EditMealDialog";
import { AddWeightDialog } from "@/components/dialogs/AddWeightDialog";
import { UnifiedFoodDialog } from "@/components/dialogs/UnifiedFoodDialog";
import { BarcodeScanDialog } from "@/components/dialogs/BarcodeScanDialog";
import { MEAL_TYPES, type MealType, DEFAULT_GOALS } from "@/lib/constants";
import { useToast } from "@/hooks/use-toast";
import { useDailyData } from "@/hooks/useDailyData";
import { useProfile } from "@/contexts/ProfileContext";
import { Skeleton } from "@/components/ui/skeleton";
import { supabase } from "@/integrations/supabase/client";

const Index = () => {
  const navigate = useNavigate();
  const [selectedDate, setSelectedDate] = useState(new Date());
  const [addMealOpen, setAddMealOpen] = useState(false);
  const [addWeightOpen, setAddWeightOpen] = useState(false);
  const [unifiedFoodDialogOpen, setUnifiedFoodDialogOpen] = useState(false);
  const [unifiedFoodDialogTab, setUnifiedFoodDialogTab] = useState<"search" | "ai">("search");
  const [barcodeDialogOpen, setBarcodeDialogOpen] = useState(false);
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [selectedMealType, setSelectedMealType] = useState<MealType>("breakfast");
  const [editingEntry, setEditingEntry] = useState<{
    id: string;
    name: string;
    mealType: MealType;
    amount: number;
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  } | null>(null);
  const { toast } = useToast();
  const { profile } = useProfile();

  const {
    mealsByType,
    totalWater,
    latestWeight,
    totals,
    loading,
    addMealEntry,
    updateMealEntry,
    deleteMealEntry,
    addWaterEntry,
    addWeightEntry,
  } = useDailyData(selectedDate);

  // Get targets from profile or use defaults
  const targets = {
    calories: profile?.daily_calorie_target || DEFAULT_GOALS.calories,
    protein: profile?.protein_target_g || DEFAULT_GOALS.protein,
    carbs: profile?.carbs_target_g || DEFAULT_GOALS.carbs,
    fat: profile?.fat_target_g || DEFAULT_GOALS.fat,
    water: profile?.daily_water_target_ml || DEFAULT_GOALS.water,
  };

  const handleAddWater = async (amount: number) => {
    const { error } = await addWaterEntry(amount);
    if (error) {
      toast({
        title: "Hata",
        description: "Su eklenirken bir hata oluştu",
        variant: "destructive",
      });
    } else {
      toast({
        title: `+${amount}ml su eklendi`,
        description: `Günlük toplam: ${totalWater + amount}ml`,
      });
    }
  };

  const handleLogWeight = () => {
    setAddWeightOpen(true);
  };

  const handleWeightSubmit = async (weight: number, note?: string) => {
    const { error } = await addWeightEntry(weight, note);
    if (error) {
      toast({
        title: "Hata",
        description: "Kilo kaydedilirken bir hata oluştu",
        variant: "destructive",
      });
      return { error };
    }

    // Update profile weight if auto-recalculate is enabled
    if (profile?.auto_recalculate_macros && weight !== profile.current_weight_kg) {
      try {
        // Recalculate macros with AI
        const response = await supabase.functions.invoke("calculate-macros", {
          body: {
            age: profile.birth_date
              ? Math.floor(
                  (Date.now() - new Date(profile.birth_date).getTime()) /
                    (365.25 * 24 * 60 * 60 * 1000)
                )
              : 30,
            gender: profile.gender || "other",
            height_cm: profile.height_cm || 170,
            current_weight_kg: weight,
            target_weight_kg: profile.target_weight_kg || weight,
            activity_level: profile.activity_level || "moderate",
            goal: profile.goal || "maintain",
            previous_macros: profile.daily_calorie_target
              ? {
                  daily_calorie_target: profile.daily_calorie_target,
                  protein_target_g: profile.protein_target_g || 0,
                  carbs_target_g: profile.carbs_target_g || 0,
                  fat_target_g: profile.fat_target_g || 0,
                }
              : undefined,
            previous_weight_kg: profile.current_weight_kg,
          },
        });

        if (response.data && !response.error) {
          await supabase
            .from("profiles")
            .update({
              current_weight_kg: weight,
              daily_calorie_target: response.data.daily_calorie_target,
              protein_target_g: response.data.protein_target_g,
              carbs_target_g: response.data.carbs_target_g,
              fat_target_g: response.data.fat_target_g,
              bmr: response.data.bmr,
              tdee: response.data.tdee,
              updated_at: new Date().toISOString(),
            })
            .eq("id", profile.id);

          toast({
            title: "Kilo kaydedildi",
            description: response.data.explanation || "Makrolar yeni kiloya göre güncellendi",
          });
        }
      } catch (err) {
        console.error("Error recalculating macros:", err);
      }
    } else {
      toast({
        title: "Kilo kaydedildi",
        description: `${weight} kg olarak kaydedildi`,
      });
    }

    return { error: null };
  };

  const handleAddMealEntry = (mealType: MealType) => {
    setSelectedMealType(mealType);
    setUnifiedFoodDialogTab("search");
    setUnifiedFoodDialogOpen(true);
  };

  const openUnifiedDialog = (tab: "search" | "ai") => {
    setUnifiedFoodDialogTab(tab);
    setUnifiedFoodDialogOpen(true);
  };

  const handleMealSubmit = async (data: {
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
  }) => {
    const { error } = await addMealEntry({
      ...data,
      food_id: null,
      entry_date: format(selectedDate, "yyyy-MM-dd"),
      note: null,
      source: "manual",
    });

    if (error) {
      toast({
        title: "Hata",
        description: "Yiyecek eklenirken bir hata oluştu",
        variant: "destructive",
      });
      return { error };
    }

    toast({
      title: "Yiyecek eklendi",
      description: `${data.custom_name} ${MEAL_TYPES[data.meal_type].label} öğününe eklendi`,
    });
    return { error: null };
  };

  const handleEditEntry = (mealType: MealType, entryId: string) => {
    const entries = mealsByType[mealType] || [];
    const entry = entries.find((e) => e.id === entryId);
    if (entry) {
      setEditingEntry({
        id: entry.id,
        name: entry.custom_name || "Yiyecek",
        mealType: entry.meal_type,
        amount: entry.amount_g_ml,
        calories: entry.calculated_kcal,
        protein: entry.calculated_protein,
        carbs: entry.calculated_carbs,
        fat: entry.calculated_fat,
      });
      setEditDialogOpen(true);
    }
  };

  const handleEditSubmit = async (data: {
    id: string;
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
  }) => {
    const { error } = await updateMealEntry(data.id, {
      custom_name: data.custom_name,
      meal_type: data.meal_type,
      amount_g_ml: data.amount_g_ml,
      calculated_kcal: data.calculated_kcal,
      calculated_protein: data.calculated_protein,
      calculated_carbs: data.calculated_carbs,
      calculated_fat: data.calculated_fat,
    });

    if (error) {
      toast({
        title: "Hata",
        description: "Yiyecek güncellenirken bir hata oluştu",
        variant: "destructive",
      });
      return { error };
    }

    toast({
      title: "Yiyecek güncellendi",
      description: `${data.custom_name} başarıyla güncellendi`,
    });
    return { error: null };
  };

  const handleDeleteEntry = async (id: string) => {
    const { error } = await deleteMealEntry(id);

    if (error) {
      toast({
        title: "Hata",
        description: "Yiyecek silinirken bir hata oluştu",
        variant: "destructive",
      });
      return { error };
    }

    toast({
      title: "Yiyecek silindi",
      description: "Kayıt başarıyla silindi",
    });
    return { error: null };
  };

  // Convert meal entries to the format expected by MealSection
  const getMealEntries = (mealType: MealType) => {
    return (mealsByType[mealType] || []).map((entry) => ({
      id: entry.id,
      name: entry.custom_name || "Yiyecek",
      amount: entry.amount_g_ml,
      unit: "g",
      calories: entry.calculated_kcal,
      protein: entry.calculated_protein,
      carbs: entry.calculated_carbs,
      fat: entry.calculated_fat,
    }));
  };

  if (loading) {
    return (
      <AppLayout>
        <div className="container max-w-lg px-4 space-y-4">
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-64 w-full" />
          <Skeleton className="h-24 w-full" />
          <Skeleton className="h-24 w-full" />
        </div>
      </AppLayout>
    );
  }

  return (
    <AppLayout>
      <div className="container max-w-lg px-4">
        {/* Date Selector */}
        <DateSelector date={selectedDate} onDateChange={setSelectedDate} />

        {/* Main Content */}
        <div className="space-y-4 pb-6">
          {/* Daily Summary Card */}
          <DailySummary
            calories={{ current: Math.round(totals.calories), target: targets.calories }}
            protein={{ current: Math.round(totals.protein), target: targets.protein }}
            carbs={{ current: Math.round(totals.carbs), target: targets.carbs }}
            fat={{ current: Math.round(totals.fat), target: targets.fat }}
          />

          {/* Weight Banner */}
          <WeightBanner
            lastWeight={latestWeight?.weight_kg || profile?.current_weight_kg}
            lastWeighDate={latestWeight ? new Date(latestWeight.entry_date) : undefined}
            reminderDays={profile?.weigh_in_frequency_days || 7}
            onLogWeight={handleLogWeight}
          />

          {/* Water Tracker */}
          <WaterTracker
            current={totalWater}
            target={targets.water}
            onAdd={handleAddWater}
          />

          {/* Quick Add Menu */}
          <QuickAddMenu
            onBarcodeScan={() => setBarcodeDialogOpen(true)}
            onPhotoAdd={() => openUnifiedDialog("ai")}
            onTextAdd={() => openUnifiedDialog("search")}
            onRecent={() => navigate("/add")}
            onFavorites={() => navigate("/add")}
          />

          {/* Meal Sections */}
          {(Object.keys(MEAL_TYPES) as MealType[])
            .sort((a, b) => MEAL_TYPES[a].order - MEAL_TYPES[b].order)
            .map((mealType) => (
              <MealSection
                key={mealType}
                mealType={mealType}
                entries={getMealEntries(mealType)}
                onAddEntry={() => handleAddMealEntry(mealType)}
                onEditEntry={(id) => handleEditEntry(mealType, id)}
              />
            ))}
        </div>
      </div>

      {/* Dialogs */}
      <AddMealDialog
        open={addMealOpen}
        onOpenChange={setAddMealOpen}
        defaultMealType={selectedMealType}
        onSubmit={handleMealSubmit}
      />
      <EditMealDialog
        open={editDialogOpen}
        onOpenChange={setEditDialogOpen}
        entry={editingEntry}
        onSubmit={handleEditSubmit}
        onDelete={handleDeleteEntry}
      />
      <AddWeightDialog
        open={addWeightOpen}
        onOpenChange={setAddWeightOpen}
        currentWeight={profile?.current_weight_kg || undefined}
        onSubmit={handleWeightSubmit}
      />
      <UnifiedFoodDialog
        open={unifiedFoodDialogOpen}
        onOpenChange={setUnifiedFoodDialogOpen}
        defaultMealType={selectedMealType}
        defaultTab={unifiedFoodDialogTab}
        onSubmit={async (foods) => {
          try {
            for (const food of foods) {
              await addMealEntry({
                ...food,
                food_id: food.food_id || null,
                entry_date: format(selectedDate, "yyyy-MM-dd"),
                note: null,
              });
            }
            return { error: null };
          } catch (err) {
            return { error: err as Error };
          }
        }}
      />
      <BarcodeScanDialog
        open={barcodeDialogOpen}
        onOpenChange={setBarcodeDialogOpen}
        defaultMealType="snack"
        onSubmit={async (foods) => {
          try {
            for (const food of foods) {
              await addMealEntry({
                ...food,
                food_id: food.food_id || null,
                entry_date: format(selectedDate, "yyyy-MM-dd"),
                note: null,
              });
            }
            return { error: null };
          } catch (err) {
            return { error: err as Error };
          }
        }}
      />
    </AppLayout>
  );
};

export default Index;

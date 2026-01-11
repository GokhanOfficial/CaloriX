import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ScanBarcode, Pencil, Search, WifiOff, Sparkles, Loader2 } from "lucide-react";
import { useOnlineStatus } from "@/hooks/useOnlineStatus";
import { MEAL_TYPES, type MealType } from "@/lib/constants";
import { UnifiedFoodDialog } from "@/components/dialogs/UnifiedFoodDialog";
import { AddFromFoodDialog } from "@/components/dialogs/AddFromFoodDialog";
import { AddMealDialog } from "@/components/dialogs/AddMealDialog";
import { FoodListSection } from "@/components/food/FoodListSection";
import { useDailyData } from "@/hooks/useDailyData";
import { useFavoriteFoods } from "@/hooks/useFavoriteFoods";
import { useRecentFoods } from "@/hooks/useRecentFoods";
import { useFoodSearch } from "@/hooks/useFoodSearch";
import { format } from "date-fns";
import { toast } from "sonner";

interface SelectedFood {
  food_id: string | null;
  name: string;
  brand: string | null;
  serving_size_g: number | null;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
}

const AddPage = () => {
  const isOnline = useOnlineStatus();
  const [selectedMeal, setSelectedMeal] = useState<MealType>("lunch");
  const [searchQuery, setSearchQuery] = useState("");
  const [unifiedDialogOpen, setUnifiedDialogOpen] = useState(false);
  const [unifiedDialogTab, setUnifiedDialogTab] = useState<"search" | "ai">("ai");
  const [manualDialogOpen, setManualDialogOpen] = useState(false);
  const [selectedFood, setSelectedFood] = useState<SelectedFood | null>(null);
  const [addDialogOpen, setAddDialogOpen] = useState(false);

  const { addMealEntry } = useDailyData(new Date());
  const { favorites, loading: favoritesLoading } = useFavoriteFoods();
  const { recentFoods, loading: recentLoading } = useRecentFoods();
  const { results: searchResults, loading: searchLoading } = useFoodSearch(searchQuery);

  const handleUnifiedSubmit = async (foods: Array<{
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
    source: "photo" | "text" | "manual";
    food_id?: string | null;
  }>) => {
    try {
      for (const food of foods) {
        await addMealEntry({
          ...food,
          food_id: food.food_id || null,
          entry_date: format(new Date(), "yyyy-MM-dd"),
          note: null,
        });
      }
      return { error: null };
    } catch (err) {
      return { error: err as Error };
    }
  };

  const handleFoodSelect = (food: {
    id: string;
    food_id: string | null;
    name: string;
    brand: string | null;
    serving_size_g: number | null;
    calories: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
  }) => {
    setSelectedFood({
      food_id: food.food_id,
      name: food.name,
      brand: food.brand,
      serving_size_g: food.serving_size_g,
      calories: food.calories,
      protein_g: food.protein_g,
      carbs_g: food.carbs_g,
      fat_g: food.fat_g,
    });
    setAddDialogOpen(true);
  };

  const handleSearchResultSelect = (result: {
    id: string;
    name: string;
    brand: string | null;
    serving_size_g: number | null;
    calories: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
  }) => {
    setSelectedFood({
      food_id: result.id,
      name: result.name,
      brand: result.brand,
      serving_size_g: result.serving_size_g,
      calories: result.calories,
      protein_g: result.protein_g,
      carbs_g: result.carbs_g,
      fat_g: result.fat_g,
    });
    setAddDialogOpen(true);
  };

  const handleAddFromFood = async (entry: {
    food_id: string | null;
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
  }) => {
    try {
      await addMealEntry({
        ...entry,
        source: "manual",
        entry_date: format(new Date(), "yyyy-MM-dd"),
        note: null,
      });
      
      toast.success("Yiyecek eklendi");
      return { error: null };
    } catch (err) {
      toast.error("Yiyecek eklenirken hata oluştu");
      return { error: err as Error };
    }
  };

  const handleManualSubmit = async (data: {
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
  }) => {
    try {
      await addMealEntry({
        ...data,
        food_id: null,
        source: "manual",
        entry_date: format(new Date(), "yyyy-MM-dd"),
        note: null,
      });
      
      toast.success("Yiyecek eklendi");
      return { error: null };
    } catch (err) {
      toast.error("Yiyecek eklenirken hata oluştu");
      return { error: err as Error };
    }
  };

  return (
    <AppLayout title="Yiyecek Ekle">
      <div className="container max-w-lg space-y-4 px-4 py-4">
        {/* Meal Selector */}
        <Card className="border-none bg-card shadow-lg">
          <CardContent className="p-4">
            <Label className="text-sm text-muted-foreground">Öğün</Label>
            <Select value={selectedMeal} onValueChange={(v) => setSelectedMeal(v as MealType)}>
              <SelectTrigger className="mt-1.5 h-12 bg-secondary">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {(Object.entries(MEAL_TYPES) as [MealType, typeof MEAL_TYPES[MealType]][]).map(
                  ([key, meal]) => (
                    <SelectItem key={key} value={key}>
                      <span className="flex items-center gap-2">
                        <span>{meal.icon}</span>
                        <span>{meal.label}</span>
                      </span>
                    </SelectItem>
                  )
                )}
              </SelectContent>
            </Select>
          </CardContent>
        </Card>

        {/* AI Methods */}
        <Card className="border-none bg-card shadow-lg">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-base">
              <Sparkles className="h-4 w-4 text-primary" />
              AI ile Tanıma
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {isOnline ? (
              <Button
                variant="outline"
                className="w-full h-16 justify-start gap-4"
                onClick={() => {
                  setUnifiedDialogTab("ai");
                  setUnifiedDialogOpen(true);
                }}
              >
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                  <Sparkles className="h-5 w-5 text-primary" />
                </div>
                <div className="text-left">
                  <p className="font-medium">AI ile Ekle</p>
                  <p className="text-xs text-muted-foreground">
                    Fotoğraf veya yazı ile yiyecek tanıt
                  </p>
                </div>
              </Button>
            ) : (
              <div className="flex flex-col items-center gap-4 py-6">
                <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-warning/10">
                  <WifiOff className="h-8 w-8 text-warning" />
                </div>
                <div className="text-center">
                  <p className="font-medium text-foreground">Çevrimdışı</p>
                  <p className="mt-1 text-sm text-muted-foreground">
                    AI tanıma için internet bağlantısı gerekli
                  </p>
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Recent Foods */}
        <FoodListSection
          title="Son Kullanılanlar"
          icon="history"
          foods={recentFoods}
          loading={recentLoading}
          emptyMessage="Henüz yiyecek eklemediniz"
          onSelect={handleFoodSelect}
        />

        {/* Favorite Foods */}
        <FoodListSection
          title="En Çok Yenenler"
          icon="star"
          foods={favorites}
          loading={favoritesLoading}
          emptyMessage="Henüz yiyecek eklemediniz"
          onSelect={handleFoodSelect}
        />

        {/* Add Methods */}
        <Tabs defaultValue="search" className="w-full">
          <TabsList className="grid w-full grid-cols-2 bg-secondary">
            <TabsTrigger value="search" className="gap-1.5">
              <Search className="h-4 w-4" />
              <span>Ara</span>
            </TabsTrigger>
            <TabsTrigger value="barcode" className="gap-1.5">
              <ScanBarcode className="h-4 w-4" />
              <span>Barkod</span>
            </TabsTrigger>
          </TabsList>

          {/* Search Tab */}
          <TabsContent value="search" className="mt-4">
            <Card className="border-none bg-card shadow-lg">
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Yiyecek Ara</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                  <Input
                    placeholder="Yiyecek adı veya marka..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="h-12 pl-10 bg-secondary"
                  />
                </div>

                {searchQuery.length >= 2 && (
                  <div className="space-y-2">
                    {searchLoading ? (
                      <div className="flex items-center justify-center py-6">
                        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
                      </div>
                    ) : searchResults.length > 0 ? (
                      searchResults.map((result) => (
                        <button
                          key={result.id}
                          onClick={() => handleSearchResultSelect(result)}
                          className="flex w-full items-center justify-between rounded-lg bg-secondary p-3 text-left transition-colors hover:bg-muted"
                        >
                          <div className="flex-1 min-w-0">
                            <p className="font-medium text-foreground truncate">{result.name}</p>
                            <p className="text-sm text-muted-foreground">
                              {result.brand && <span className="mr-2">{result.brand}</span>}
                              100g • {result.calories} kcal
                            </p>
                          </div>
                          <div className="ml-3 text-right text-xs text-muted-foreground">
                            <p>P: {result.protein_g}g</p>
                            <p>K: {result.carbs_g}g</p>
                            <p>Y: {result.fat_g}g</p>
                          </div>
                        </button>
                      ))
                    ) : (
                      <p className="py-4 text-center text-sm text-muted-foreground">
                        Sonuç bulunamadı
                      </p>
                    )}
                  </div>
                )}

                {searchQuery.length < 2 && (
                  <div className="py-8 text-center">
                    <p className="text-sm text-muted-foreground">
                      Veritabanından yiyecek ara
                    </p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      En az 2 karakter girin
                    </p>
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          {/* Barcode Tab */}
          <TabsContent value="barcode" className="mt-4">
            <Card className="border-none bg-card shadow-lg">
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Barkod Tara</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="flex flex-col items-center gap-4 py-8">
                  <div className="flex h-24 w-24 items-center justify-center rounded-2xl bg-primary/10">
                    <ScanBarcode className="h-12 w-12 text-primary" />
                  </div>
                  <div className="text-center">
                    <p className="font-medium text-foreground">Kamera ile Tara</p>
                    <p className="mt-1 text-sm text-muted-foreground">
                      Ürün barkodunu kameraya göster
                    </p>
                  </div>
                  <Button size="lg" className="w-full max-w-xs">
                    Kamerayı Aç
                  </Button>
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>

        {/* Manual Entry Option */}
        <Card className="border-none bg-card shadow-lg">
          <CardContent className="p-4">
            <button
              className="flex w-full items-center gap-3 text-left"
              onClick={() => setManualDialogOpen(true)}
            >
              <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-accent">
                <Pencil className="h-6 w-6 text-accent-foreground" />
              </div>
              <div>
                <p className="font-semibold text-foreground">Manuel Giriş</p>
                <p className="text-sm text-muted-foreground">
                  Besin değerlerini kendin gir
                </p>
              </div>
            </button>
          </CardContent>
        </Card>
      </div>

      {/* Unified Food Dialog */}
      <UnifiedFoodDialog
        open={unifiedDialogOpen}
        onOpenChange={setUnifiedDialogOpen}
        defaultMealType={selectedMeal}
        defaultTab={unifiedDialogTab}
        onSubmit={handleUnifiedSubmit}
      />

      {/* Add From Food Dialog */}
      <AddFromFoodDialog
        open={addDialogOpen}
        onOpenChange={setAddDialogOpen}
        food={selectedFood}
        defaultMealType={selectedMeal}
        onSubmit={handleAddFromFood}
      />

      {/* Manual Entry Dialog */}
      <AddMealDialog
        open={manualDialogOpen}
        onOpenChange={setManualDialogOpen}
        defaultMealType={selectedMeal}
        onSubmit={handleManualSubmit}
      />
    </AppLayout>
  );
};

export default AddPage;

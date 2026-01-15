import { useState, useRef, useEffect } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Checkbox } from "@/components/ui/checkbox";
import { MEAL_TYPES, type MealType } from "@/lib/constants";
import {
  Loader2,
  RefreshCw,
  Check,
  AlertCircle,
  Search,
  Sparkles,
  X,
  Plus,
  Camera,
  ImagePlus,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useFoodSearch, FoodSearchResult } from "@/hooks/useFoodSearch";
import { useOnlineStatus } from "@/hooks/useOnlineStatus";
import { ScrollArea } from "@/components/ui/scroll-area";
import { useTranslation } from "react-i18next";

interface RecognizedFood {
  name: string;
  amount_g_ml: number;
  calories_per_100g: number;
  protein_g_per_100g: number;
  carbs_g_per_100g: number;
  fat_g_per_100g: number;
  // Extended nutrition data (per 100g)
  saturated_fat_g_per_100g?: number;
  trans_fat_g_per_100g?: number;
  sugars_g_per_100g?: number;
  fiber_g_per_100g?: number;
  salt_g_per_100g?: number;
  nova_score?: number;
  nutri_score?: string;
  confidence: number;
  selected?: boolean;
  food_id?: string;
}

interface UnifiedFoodDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultMealType?: MealType;
  defaultTab?: "search" | "ai";
  onSubmit: (foods: Array<{
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
    source: "text" | "photo" | "manual";
    food_id?: string | null;
  }>) => Promise<{ error: Error | null }>;
}

export function UnifiedFoodDialog({
  open,
  onOpenChange,
  defaultMealType = "lunch",
  defaultTab = "search",
  onSubmit,
}: UnifiedFoodDialogProps) {
  const { t } = useTranslation();
  const [mode, setMode] = useState<"search" | "ai">(defaultTab);
  const [step, setStep] = useState<"input" | "analyzing" | "results" | "manual">("input");
  const [mealType, setMealType] = useState<MealType>(defaultMealType);
  const [searchQuery, setSearchQuery] = useState("");
  const [inputText, setInputText] = useState("");
  const [imageData, setImageData] = useState<string | null>(null);
  const [recognizedFoods, setRecognizedFoods] = useState<RecognizedFood[]>([]);
  const [description, setDescription] = useState("");
  const [analyzing, setAnalyzing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Manual entry state
  const [selectedFood, setSelectedFood] = useState<FoodSearchResult | null>(null);
  const [manualAmount, setManualAmount] = useState(100);

  const isOnline = useOnlineStatus();
  const { results: searchResults, loading: searchLoading } = useFoodSearch(searchQuery);
  const inputRef = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const cameraInputRef = useRef<HTMLInputElement>(null);

  // Update mealType when defaultMealType changes
  useEffect(() => {
    setMealType(defaultMealType);
  }, [defaultMealType]);

  // Focus input when dialog opens
  useEffect(() => {
    if (open && step === "input") {
      setTimeout(() => inputRef.current?.focus(), 100);
    }
  }, [open, step]);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      const reader = new FileReader();
      reader.onloadend = () => {
        setImageData(reader.result as string);
        setError(null);
      };
      reader.readAsDataURL(file);
    }
  };

  const analyzeWithAI = async () => {
    // Need either photo or text
    if (!imageData && !inputText.trim()) {
      setError(t('dialogs.textOrPhotoRequired'));
      return;
    }

    if (!isOnline) {
      setError(t('dialogs.aiRequiresInternet'));
      return;
    }

    setStep("analyzing");
    setAnalyzing(true);
    setError(null);

    try {
      let data;

      if (imageData) {
        // Use photo recognition
        const response = await supabase.functions.invoke("recognize-food", {
          body: {
            image_base64: imageData,
            additional_text: inputText || undefined,
          },
        });
        if (response.error) throw response.error;
        if (response.data.error) throw new Error(response.data.error);
        data = response.data;
      } else {
        // Use text recognition
        const response = await supabase.functions.invoke("recognize-food-text", {
          body: { text: inputText },
        });
        if (response.error) throw response.error;
        if (response.data.error) throw new Error(response.data.error);
        data = response.data;
      }

      const foods = (data.foods || []).map((food: any) => ({
        name: food.name,
        amount_g_ml: food.amount_g_ml || 100,
        calories_per_100g: food.calories_per_100g || food.calories || 0,
        protein_g_per_100g: food.protein_g_per_100g || food.protein_g || 0,
        carbs_g_per_100g: food.carbs_g_per_100g || food.carbs_g || 0,
        fat_g_per_100g: food.fat_g_per_100g || food.fat_g || 0,
        // Extended nutrition data
        saturated_fat_g_per_100g: food.saturated_fat_g_per_100g,
        trans_fat_g_per_100g: food.trans_fat_g_per_100g,
        sugars_g_per_100g: food.sugars_g_per_100g,
        fiber_g_per_100g: food.fiber_g_per_100g,
        salt_g_per_100g: food.salt_g_per_100g,
        nova_score: food.nova_score,
        nutri_score: food.nutri_score,
        confidence: food.confidence || 70,
        selected: true,
      }));

      setRecognizedFoods(foods);
      setDescription(data.description || "");
      setStep("results");
    } catch (err) {
      console.error("Recognition error:", err);
      setError(err instanceof Error ? err.message : t('dialogs.analysisFailed'));
      setStep("input");
    } finally {
      setAnalyzing(false);
    }
  };

  const retryAnalysis = () => {
    setRecognizedFoods([]);
    setDescription("");
    analyzeWithAI();
  };

  const toggleFoodSelection = (index: number) => {
    setRecognizedFoods(prev =>
      prev.map((food, i) =>
        i === index ? { ...food, selected: !food.selected } : food
      )
    );
  };

  const updateFood = (index: number, updates: Partial<RecognizedFood>) => {
    setRecognizedFoods(prev =>
      prev.map((food, i) =>
        i === index ? { ...food, ...updates } : food
      )
    );
  };

  const selectSearchResult = (food: FoodSearchResult) => {
    setSelectedFood(food);
    setManualAmount(food.serving_size_g || 100);
    setStep("manual");
  };

  const handleSaveManual = async () => {
    if (!selectedFood) return;

    setSaving(true);

    const calculatedCalories = Math.round((selectedFood.calories / 100) * manualAmount);
    const calculatedProtein = Math.round((selectedFood.protein_g / 100) * manualAmount * 10) / 10;
    const calculatedCarbs = Math.round((selectedFood.carbs_g / 100) * manualAmount * 10) / 10;
    const calculatedFat = Math.round((selectedFood.fat_g / 100) * manualAmount * 10) / 10;

    const result = await onSubmit([{
      custom_name: selectedFood.name + (selectedFood.brand ? ` (${selectedFood.brand})` : ""),
      meal_type: mealType,
      amount_g_ml: manualAmount,
      calculated_kcal: calculatedCalories,
      calculated_protein: calculatedProtein,
      calculated_carbs: calculatedCarbs,
      calculated_fat: calculatedFat,
      source: "manual",
      food_id: selectedFood.id,
    }]);

    setSaving(false);

    if (!result.error) {
      toast.success(t('dialogs.foodAdded'));
      resetDialog();
      onOpenChange(false);
    } else {
      toast.error(t('dialogs.saveFailed') + ": " + result.error.message);
    }
  };

  const handleSave = async () => {
    const selectedFoods = recognizedFoods.filter(f => f.selected);
    if (selectedFoods.length === 0) {
      toast.error(t('dialogs.selectAtLeastOne'));
      return;
    }

    setSaving(true);

    const foodsToSave = selectedFoods.map(food => ({
      custom_name: food.name,
      meal_type: mealType,
      amount_g_ml: food.amount_g_ml,
      calculated_kcal: Math.round((food.calories_per_100g / 100) * food.amount_g_ml),
      calculated_protein: Math.round((food.protein_g_per_100g / 100) * food.amount_g_ml * 10) / 10,
      calculated_carbs: Math.round((food.carbs_g_per_100g / 100) * food.amount_g_ml * 10) / 10,
      calculated_fat: Math.round((food.fat_g_per_100g / 100) * food.amount_g_ml * 10) / 10,
      source: imageData ? "photo" as const : "text" as const,
      food_id: food.food_id || null,
    }));

    const result = await onSubmit(foodsToSave);
    setSaving(false);

    if (!result.error) {
      toast.success(`${selectedFoods.length} ${t('dialogs.foodsAdded')}`);
      resetDialog();
      onOpenChange(false);
    } else {
      toast.error(t('dialogs.saveFailed') + ": " + result.error.message);
    }
  };

  const resetDialog = () => {
    setMode(defaultTab);
    setStep("input");
    setSearchQuery("");
    setInputText("");
    setImageData(null);
    setRecognizedFoods([]);
    setDescription("");
    setError(null);
    setSelectedFood(null);
    setManualAmount(100);
  };

  const handleOpenChange = (newOpen: boolean) => {
    if (!newOpen) {
      resetDialog();
    }
    onOpenChange(newOpen);
  };

  const getConfidenceColor = (confidence: number) => {
    if (confidence >= 80) return "text-green-500";
    if (confidence >= 50) return "text-yellow-500";
    return "text-red-500";
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {mode === "search" ? (
              <>
                <Search className="h-5 w-5 text-primary" />
                {t('dialogs.searchFood')}
              </>
            ) : (
              <>
                <Sparkles className="h-5 w-5 text-primary" />
                {t('dialogs.addWithAI')}
              </>
            )}
          </DialogTitle>
        </DialogHeader>

        {/* Input Step */}
        {step === "input" && (
          <div className="space-y-4">
            {/* Mode Toggle */}
            <div className="flex gap-2 p-1 rounded-lg bg-muted">
              <Button
                variant={mode === "search" ? "secondary" : "ghost"}
                size="sm"
                className="flex-1"
                onClick={() => setMode("search")}
              >
                <Search className="mr-2 h-4 w-4" />
                {t('dialogs.search')}
              </Button>
              <Button
                variant={mode === "ai" ? "secondary" : "ghost"}
                size="sm"
                className="flex-1"
                onClick={() => setMode("ai")}
                disabled={!isOnline}
              >
                <Sparkles className="mr-2 h-4 w-4" />
                AI
              </Button>
            </div>

            {/* Meal Type Selection */}
            <div className="space-y-2">
              <Label>{t('dialogs.meal')}</Label>
              <Select value={mealType} onValueChange={(v) => setMealType(v as MealType)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(Object.keys(MEAL_TYPES) as MealType[]).map((type) => (
                    <SelectItem key={type} value={type}>
                      {MEAL_TYPES[type].icon} {MEAL_TYPES[type].label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {mode === "search" ? (
              <>
                {/* Search Input */}
                <div className="space-y-2">
                  <Label htmlFor="searchFood">{t('dialogs.foodName')}</Label>
                  <div className="relative">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                    <Input
                      ref={inputRef}
                      id="searchFood"
                      value={searchQuery}
                      onChange={(e) => setSearchQuery(e.target.value)}
                      placeholder={t('dialogs.searchPlaceholder')}
                      className="pl-10"
                    />
                    {searchQuery && (
                      <Button
                        variant="ghost"
                        size="sm"
                        className="absolute right-1 top-1/2 -translate-y-1/2 h-7 w-7 p-0"
                        onClick={() => setSearchQuery("")}
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </div>

                {/* Search Results */}
                {searchQuery.length >= 2 && (
                  <div className="space-y-2">
                    <Label>{t('dialogs.results')}</Label>
                    <ScrollArea className="h-64 rounded-lg border">
                      {searchLoading ? (
                        <div className="flex items-center justify-center h-20">
                          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
                        </div>
                      ) : searchResults.length > 0 ? (
                        <div className="divide-y">
                          {searchResults.map((food) => (
                            <button
                              key={food.id}
                              className="w-full p-3 text-left hover:bg-muted/50 transition-colors"
                              onClick={() => selectSearchResult(food)}
                            >
                              <div className="flex items-center justify-between">
                                <div>
                                  <p className="font-medium text-sm">{food.name}</p>
                                  {food.brand && (
                                    <p className="text-xs text-muted-foreground">{food.brand}</p>
                                  )}
                                </div>
                                <Plus className="h-4 w-4 text-muted-foreground" />
                              </div>
                              <div className="flex gap-3 mt-1 text-xs text-muted-foreground">
                                <span>{food.calories} kcal</span>
                                <span>{food.protein_g}g P</span>
                                <span>{food.carbs_g}g K</span>
                                <span>{food.fat_g}g Y</span>
                                <span className="text-muted-foreground/60">(100g)</span>
                              </div>
                            </button>
                          ))}
                        </div>
                      ) : (
                        <div className="flex flex-col items-center justify-center h-32 text-center p-4">
                          <p className="text-sm text-muted-foreground">
                            {t('dialogs.noResults')}
                          </p>
                          {isOnline && (
                            <Button
                              variant="link"
                              size="sm"
                              onClick={() => {
                                setMode("ai");
                                setInputText(searchQuery);
                              }}
                            >
                              <Sparkles className="mr-1 h-3 w-3" />
                              {t('dialogs.analyzeWithAI')}
                            </Button>
                          )}
                        </div>
                      )}
                    </ScrollArea>
                  </div>
                )}

                {!isOnline && (
                  <p className="text-xs text-warning text-center">
                    {t('dialogs.offlineMode')}
                  </p>
                )}
              </>
            ) : (
              <>
                {/* AI Mode - Photo + Text */}

                {/* Photo Section */}
                <div className="space-y-2">
                  <Label>
                    {t('dialogs.photo')} <span className="text-muted-foreground text-xs">({t('dialogs.optional')})</span>
                  </Label>
                  {imageData ? (
                    <div className="relative rounded-lg overflow-hidden border border-border">
                      <img
                        src={imageData}
                        alt="Seçilen yemek"
                        className="w-full h-32 object-cover"
                      />
                      <Button
                        variant="secondary"
                        size="sm"
                        className="absolute top-2 right-2"
                        onClick={() => setImageData(null)}
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ) : (
                    <div className="flex gap-2">
                      <Button
                        variant="outline"
                        className="flex-1 h-16 flex-col gap-1"
                        onClick={() => cameraInputRef.current?.click()}
                      >
                        <Camera className="h-5 w-5" />
                        <span className="text-xs">{t('dialogs.takePhoto')}</span>
                      </Button>
                      <Button
                        variant="outline"
                        className="flex-1 h-16 flex-col gap-1"
                        onClick={() => fileInputRef.current?.click()}
                      >
                        <ImagePlus className="h-5 w-5" />
                        <span className="text-xs">{t('dialogs.selectFromGallery')}</span>
                      </Button>
                    </div>
                  )}
                  <input
                    ref={cameraInputRef}
                    type="file"
                    accept="image/*"
                    capture="environment"
                    className="hidden"
                    onChange={handleFileSelect}
                  />
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={handleFileSelect}
                  />
                </div>

                {/* Text Input */}
                <div className="space-y-2">
                  <Label htmlFor="foodText">
                    {t('dialogs.whatDidYouEat')} <span className="text-muted-foreground text-xs">{imageData ? `(${t('dialogs.optional')} ${t('dialogs.additionalInfo')})` : `(${t('dialogs.required')})`}</span>
                  </Label>
                  <Textarea
                    id="foodText"
                    value={inputText}
                    onChange={(e) => setInputText(e.target.value)}
                    placeholder={imageData
                      ? t('dialogs.photoAdditionalHint')
                      : `${t('dialogs.example')} 2 dilim ekmek, 1 yumurta, 1 bardak süt...`
                    }
                    rows={3}
                  />
                  <p className="text-xs text-muted-foreground">
                    {imageData
                      ? t('dialogs.portionHint')
                      : t('dialogs.photoOrTextRequired')
                    }
                  </p>
                </div>

                {error && (
                  <div className="flex items-center gap-2 p-3 rounded-lg bg-destructive/10 text-destructive text-sm">
                    <AlertCircle className="h-4 w-4" />
                    {error}
                  </div>
                )}

                <DialogFooter>
                  <Button variant="outline" onClick={() => handleOpenChange(false)}>
                    {t('dialogs.cancel')}
                  </Button>
                  <Button
                    onClick={analyzeWithAI}
                    disabled={(!imageData && !inputText.trim()) || !isOnline}
                  >
                    <Sparkles className="mr-2 h-4 w-4" />
                    {t('dialogs.analyzeWithAI')}
                  </Button>
                </DialogFooter>
              </>
            )}
          </div>
        )}

        {/* Manual Entry Step */}
        {step === "manual" && selectedFood && (
          <div className="space-y-4">
            <div className="p-4 rounded-lg bg-muted/50 border">
              <p className="font-medium">{selectedFood.name}</p>
              {selectedFood.brand && (
                <p className="text-sm text-muted-foreground">{selectedFood.brand}</p>
              )}
              <div className="flex gap-3 mt-2 text-xs text-muted-foreground">
                <span>{selectedFood.calories} kcal</span>
                <span>{selectedFood.protein_g}g P</span>
                <span>{selectedFood.carbs_g}g K</span>
                <span>{selectedFood.fat_g}g Y</span>
                <span>(100g başına)</span>
              </div>
            </div>

            {/* Meal Type */}
            <div className="space-y-2">
              <Label>Öğün</Label>
              <Select value={mealType} onValueChange={(v) => setMealType(v as MealType)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(Object.keys(MEAL_TYPES) as MealType[]).map((type) => (
                    <SelectItem key={type} value={type}>
                      {MEAL_TYPES[type].icon} {MEAL_TYPES[type].label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Amount */}
            <div className="space-y-2">
              <Label>{t('dialogs.amountGram')}</Label>
              <Input
                type="number"
                value={manualAmount}
                onChange={(e) => setManualAmount(Number(e.target.value))}
                min={1}
              />
              {selectedFood.serving_size_g && (
                <p className="text-xs text-muted-foreground">
                  {t('dialogs.suggestedPortion')}: {selectedFood.serving_size_g}g
                </p>
              )}
            </div>

            {/* Calculated Preview */}
            <div className="p-3 rounded-lg bg-primary/5 border border-primary/10">
              <p className="text-xs text-muted-foreground mb-1">
                {manualAmount}g {t('dialogs.calculatedValues')}:
              </p>
              <div className="flex justify-between text-sm font-medium">
                <span>{Math.round((selectedFood.calories / 100) * manualAmount)} kcal</span>
                <span>{Math.round((selectedFood.protein_g / 100) * manualAmount * 10) / 10}g P</span>
                <span>{Math.round((selectedFood.carbs_g / 100) * manualAmount * 10) / 10}g K</span>
                <span>{Math.round((selectedFood.fat_g / 100) * manualAmount * 10) / 10}g Y</span>
              </div>
            </div>

            <DialogFooter className="flex-col sm:flex-row gap-2">
              <Button variant="ghost" onClick={() => {
                setSelectedFood(null);
                setStep("input");
              }}>
                {t('dialogs.back')}
              </Button>
              <Button onClick={handleSaveManual} disabled={saving || manualAmount <= 0}>
                {saving ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <Check className="mr-2 h-4 w-4" />
                )}
                {t('dialogs.save')}
              </Button>
            </DialogFooter>
          </div>
        )}

        {/* Analyzing Step */}
        {step === "analyzing" && (
          <div className="flex flex-col items-center justify-center py-12 space-y-4">
            {imageData ? (
              <div className="relative">
                <img
                  src={imageData}
                  alt="Analiz ediliyor"
                  className="w-32 h-32 rounded-lg object-cover opacity-50"
                />
                <div className="absolute inset-0 flex items-center justify-center">
                  <Loader2 className="h-8 w-8 animate-spin text-primary" />
                </div>
              </div>
            ) : (
              <Loader2 className="h-12 w-12 animate-spin text-primary" />
            )}
            <div className="text-center">
              <p className="font-medium">{t('dialogs.aiAnalyzing')}</p>
              <p className="text-sm text-muted-foreground">
                {t('dialogs.recognizing')}
              </p>
            </div>
          </div>
        )}

        {/* Results Step */}
        {step === "results" && (
          <div className="space-y-4">
            {/* Image Preview */}
            {imageData && (
              <div className="rounded-lg overflow-hidden border border-border">
                <img
                  src={imageData}
                  alt="Analiz edilen yemek"
                  className="w-full h-32 object-cover"
                />
              </div>
            )}

            {/* Original Text */}
            {inputText && !imageData && (
              <div className="p-3 rounded-lg bg-muted/50 text-sm">
                <p className="text-muted-foreground mb-1">{t('dialogs.inputText')}:</p>
                <p>{inputText}</p>
              </div>
            )}

            {/* Description */}
            {description && (
              <p className="text-sm text-muted-foreground bg-muted/50 p-3 rounded-lg">
                {description}
              </p>
            )}

            {/* Meal Type */}
            <div className="space-y-2">
              <Label>Öğün</Label>
              <Select value={mealType} onValueChange={(v) => setMealType(v as MealType)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(Object.keys(MEAL_TYPES) as MealType[]).map((type) => (
                    <SelectItem key={type} value={type}>
                      {MEAL_TYPES[type].icon} {MEAL_TYPES[type].label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Recognized Foods */}
            <div className="space-y-2">
              <Label>{t('dialogs.recognizedFoods')} ({recognizedFoods.length})</Label>
              <div className="space-y-3 max-h-60 overflow-y-auto">
                {recognizedFoods.map((food, index) => (
                  <div
                    key={index}
                    className={cn(
                      "p-3 rounded-lg border transition-colors",
                      food.selected
                        ? "bg-card border-primary/50"
                        : "bg-muted/30 border-border opacity-60"
                    )}
                  >
                    <div className="flex items-start gap-3">
                      <Checkbox
                        checked={food.selected}
                        onCheckedChange={() => toggleFoodSelection(index)}
                        className="mt-1"
                      />
                      <div className="flex-1 space-y-2">
                        <div className="flex items-center justify-between">
                          <Input
                            value={food.name}
                            onChange={(e) => updateFood(index, { name: e.target.value })}
                            className="font-medium h-8"
                          />
                          <span className={cn("text-xs ml-2", getConfidenceColor(food.confidence))}>
                            %{food.confidence}
                          </span>
                        </div>
                        <div className="grid grid-cols-5 gap-1 text-xs">
                          <div>
                            <Label className="text-xs text-muted-foreground">{t('dialogs.amount')} (g)</Label>
                            <Input
                              type="number"
                              value={food.amount_g_ml}
                              onChange={(e) => updateFood(index, { amount_g_ml: Number(e.target.value) })}
                              className="h-7 text-xs"
                            />
                          </div>
                          <div>
                            <Label className="text-xs text-muted-foreground">{t('dialogs.calPer100g')}</Label>
                            <Input
                              type="number"
                              value={food.calories_per_100g}
                              onChange={(e) => updateFood(index, { calories_per_100g: Number(e.target.value) })}
                              className="h-7 text-xs"
                            />
                          </div>
                          <div>
                            <Label className="text-xs text-muted-foreground">{t('dialogs.proPer100g')}</Label>
                            <Input
                              type="number"
                              value={food.protein_g_per_100g}
                              onChange={(e) => updateFood(index, { protein_g_per_100g: Number(e.target.value) })}
                              className="h-7 text-xs"
                            />
                          </div>
                          <div>
                            <Label className="text-xs text-muted-foreground">{t('dialogs.carbPer100g')}</Label>
                            <Input
                              type="number"
                              value={food.carbs_g_per_100g}
                              onChange={(e) => updateFood(index, { carbs_g_per_100g: Number(e.target.value) })}
                              className="h-7 text-xs"
                            />
                          </div>
                          <div>
                            <Label className="text-xs text-muted-foreground">{t('dialogs.fatPer100g')}</Label>
                            <Input
                              type="number"
                              value={food.fat_g_per_100g}
                              onChange={(e) => updateFood(index, { fat_g_per_100g: Number(e.target.value) })}
                              className="h-7 text-xs"
                            />
                          </div>
                        </div>
                        {/* Calculated totals */}
                        <div className="mt-2 p-2 bg-muted/50 rounded text-xs text-muted-foreground">
                          <span className="font-medium">{t('dialogs.total')}: </span>
                          {Math.round((food.calories_per_100g / 100) * food.amount_g_ml)} kcal,
                          {" "}{Math.round((food.protein_g_per_100g / 100) * food.amount_g_ml * 10) / 10}g {t('dialogs.protein')},
                          {" "}{Math.round((food.carbs_g_per_100g / 100) * food.amount_g_ml * 10) / 10}g {t('dialogs.carbs')},
                          {" "}{Math.round((food.fat_g_per_100g / 100) * food.amount_g_ml * 10) / 10}g {t('dialogs.fat')}
                        </div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {error && (
              <div className="flex items-center gap-2 p-3 rounded-lg bg-destructive/10 text-destructive text-sm">
                <AlertCircle className="h-4 w-4" />
                {error}
              </div>
            )}

            <DialogFooter className="flex-col sm:flex-row gap-2">
              <Button
                variant="outline"
                onClick={retryAnalysis}
                disabled={analyzing}
                className="w-full sm:w-auto"
              >
                <RefreshCw className={cn("mr-2 h-4 w-4", analyzing && "animate-spin")} />
                {t('dialogs.reanalyze')}
              </Button>
              <div className="flex gap-2 w-full sm:w-auto">
                <Button variant="ghost" onClick={() => setStep("input")}>
                  {t('dialogs.back')}
                </Button>
                <Button
                  onClick={handleSave}
                  disabled={saving || recognizedFoods.filter(f => f.selected).length === 0}
                  className="flex-1 sm:flex-none"
                >
                  {saving ? (
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  ) : (
                    <Check className="mr-2 h-4 w-4" />
                  )}
                  {t('dialogs.save')} ({recognizedFoods.filter(f => f.selected).length})
                </Button>
              </div>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

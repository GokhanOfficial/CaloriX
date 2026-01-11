import { useState, useRef, useEffect, useCallback } from "react";
import { useAuth } from "@/contexts/AuthContext";
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
import { MEAL_TYPES, type MealType } from "@/lib/constants";
import {
  Loader2,
  ScanBarcode,
  Camera,
  ImagePlus,
  RefreshCw,
  Check,
  X,
  AlertCircle,
  Sparkles,
  Edit,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useOnlineStatus } from "@/hooks/useOnlineStatus";
import { BrowserMultiFormatReader, NotFoundException } from "@zxing/library";

interface FoodData {
  name: string;
  brand?: string;
  barcode?: string;
  amount_g_ml: number;
  serving_size_g?: number;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  // Extended nutrition data
  saturated_fat_g?: number;
  trans_fat_g?: number;
  sugars_g?: number;
  fiber_g?: number;
  salt_g?: number;
  nova_score?: number;
  nutri_score?: string;
  confidence?: number;
  fromDb?: boolean;
}

interface BarcodeScanDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultMealType?: MealType;
  onSubmit: (foods: Array<{
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
    source: "barcode" | "photo";
    food_id?: string | null;
  }>) => Promise<{ error: Error | null }>;
}

export function BarcodeScanDialog({
  open,
  onOpenChange,
  defaultMealType = "lunch",
  onSubmit,
}: BarcodeScanDialogProps) {
  const [step, setStep] = useState<"scan" | "notFound" | "analyzing" | "result">("scan");
  const [mealType, setMealType] = useState<MealType>(defaultMealType);
  const [scanning, setScanning] = useState(false);
  const [barcodeValue, setBarcodeValue] = useState("");
  const [manualBarcode, setManualBarcode] = useState("");
  const [foodData, setFoodData] = useState<FoodData | null>(null);
  const [imageData, setImageData] = useState<string | null>(null);
  const [additionalText, setAdditionalText] = useState("");
  const [analyzing, setAnalyzing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [foodId, setFoodId] = useState<string | null>(null);

  const isOnline = useOnlineStatus();
  const videoRef = useRef<HTMLVideoElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const readerRef = useRef<BrowserMultiFormatReader | null>(null);

  // Start barcode scanning
  const startScanning = useCallback(async () => {
    if (!videoRef.current || scanning) return;

    try {
      setScanning(true);
      setError(null);

      const reader = new BrowserMultiFormatReader();
      readerRef.current = reader;

      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment" },
      });
      streamRef.current = stream;

      await reader.decodeFromStream(stream, videoRef.current, (result, err) => {
        if (result) {
          const code = result.getText();
          setBarcodeValue(code);
          stopScanning();
          lookupBarcode(code);
        }
        if (err && !(err instanceof NotFoundException)) {
          console.error("Scan error:", err);
        }
      });
    } catch (err) {
      console.error("Camera error:", err);
      setError("Kamera erişimi sağlanamadı. Lütfen izin verin.");
      setScanning(false);
    }
  }, [scanning]);

  // Stop scanning
  const stopScanning = useCallback(() => {
    if (readerRef.current) {
      readerRef.current.reset();
      readerRef.current = null;
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    }
    setScanning(false);
  }, []);

  // Lookup barcode in DB
  const lookupBarcode = async (code: string) => {
    // Stop camera when barcode is found
    stopScanning();
    
    setStep("analyzing");
    setAnalyzing(true);
    setError(null);

    try {
      // First, check local database
      const { data: food, error: dbError } = await supabase
        .from("foods")
        .select(`
          id,
          name,
          brand,
          barcode,
          serving_size_g,
          food_nutrition (
            kcal,
            protein_g,
            carbs_g,
            fat_g
          )
        `)
        .eq("barcode", code)
        .maybeSingle();

      if (dbError) throw dbError;

      if (food && food.food_nutrition) {
        const nutrition = food.food_nutrition as { kcal: number; protein_g: number; carbs_g: number; fat_g: number };
        setFoodData({
          name: food.name,
          brand: food.brand || undefined,
          barcode: food.barcode || undefined,
          amount_g_ml: food.serving_size_g || 100,
          serving_size_g: food.serving_size_g || 100,
          calories: nutrition.kcal,
          protein_g: nutrition.protein_g,
          carbs_g: nutrition.carbs_g,
          fat_g: nutrition.fat_g,
          fromDb: true,
        });
        setFoodId(food.id);
        setStep("result");
      } else {
        // Product not found
        setBarcodeValue(code);
        setStep("notFound");
      }
    } catch (err) {
      console.error("Lookup error:", err);
      setStep("notFound");
    } finally {
      setAnalyzing(false);
    }
  };

  // Handle manual barcode entry
  const handleManualSearch = () => {
    if (manualBarcode.trim()) {
      lookupBarcode(manualBarcode.trim());
    }
  };

  // Handle file select for product image
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

  // Analyze image with AI
  const analyzeWithAI = async () => {
    if (!imageData && !additionalText.trim()) {
      setError("Lütfen bir fotoğraf veya açıklama girin");
      return;
    }

    if (!isOnline) {
      setError("AI analizi için internet bağlantısı gerekli");
      return;
    }

    setStep("analyzing");
    setAnalyzing(true);
    setError(null);

    try {
      let data;
      let fnError;

      // Use image recognition if image is available, otherwise use text recognition
      if (imageData) {
        const result = await supabase.functions.invoke("recognize-food", {
          body: {
            image_base64: imageData,
            additional_text: additionalText || `Barkod: ${barcodeValue}`,
          },
        });
        data = result.data;
        fnError = result.error;
      } else {
        // Text-only recognition
        const result = await supabase.functions.invoke("recognize-food-text", {
          body: {
            text: additionalText || `Barkod numarası: ${barcodeValue}. Bu barkoda sahip ürünün besin değerlerini tahmin et.`,
          },
        });
        data = result.data;
        fnError = result.error;
      }

      if (fnError) throw fnError;
      if (data.error) throw new Error(data.error);

      const foods = data.foods || [];
      if (foods.length > 0) {
        const firstFood = foods[0];
        setFoodData({
          name: firstFood.name,
          barcode: barcodeValue || undefined,
          amount_g_ml: firstFood.amount_g_ml || 100,
          // Use per_100g values from AI
          calories: firstFood.calories_per_100g || firstFood.calories || 0,
          protein_g: firstFood.protein_g_per_100g || firstFood.protein_g || 0,
          carbs_g: firstFood.carbs_g_per_100g || firstFood.carbs_g || 0,
          fat_g: firstFood.fat_g_per_100g || firstFood.fat_g || 0,
          // Extended nutrition data
          saturated_fat_g: firstFood.saturated_fat_g_per_100g,
          trans_fat_g: firstFood.trans_fat_g_per_100g,
          sugars_g: firstFood.sugars_g_per_100g,
          fiber_g: firstFood.fiber_g_per_100g,
          salt_g: firstFood.salt_g_per_100g,
          nova_score: firstFood.nova_score,
          nutri_score: firstFood.nutri_score,
          confidence: firstFood.confidence,
          fromDb: false,
        });
        setStep("result");
      } else {
        setError("Yiyecek tanınamadı. Lütfen farklı bir fotoğraf deneyin.");
        setStep("notFound");
      }
    } catch (err) {
      console.error("AI analysis error:", err);
      setError(err instanceof Error ? err.message : "Analiz başarısız oldu");
      setStep("notFound");
    } finally {
      setAnalyzing(false);
    }
  };

  // Update food data
  const updateFoodData = (updates: Partial<FoodData>) => {
    setFoodData((prev) => (prev ? { ...prev, ...updates } : null));
  };

  // Save food entry
  const handleSave = async () => {
    if (!foodData) return;

    setSaving(true);

    try {
      // If it's a new food (not from DB), save to foods table first
      let finalFoodId = foodId;

      if (!foodData.fromDb && barcodeValue) {
        // Get current user
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) throw new Error("Kullanıcı oturumu bulunamadı");

        // Create new food entry
        const { data: newFood, error: foodError } = await supabase
          .from("foods")
          .insert({
            name: foodData.name,
            brand: foodData.brand || null,
            barcode: barcodeValue,
            serving_size_g: foodData.serving_size_g || foodData.amount_g_ml,
            source: imageData ? "photo" : "barcode",
            created_by: user.id,
          })
          .select("id")
          .single();

        if (foodError) throw foodError;

        // Create nutrition entry
        if (newFood) {
          finalFoodId = newFood.id;
          await supabase.from("food_nutrition").insert({
            food_id: newFood.id,
            kcal: foodData.calories,
            protein_g: foodData.protein_g,
            carbs_g: foodData.carbs_g,
            fat_g: foodData.fat_g,
            saturated_fat_g: foodData.saturated_fat_g,
            trans_fat_g: foodData.trans_fat_g,
            sugars_g: foodData.sugars_g,
            fiber_g: foodData.fiber_g,
            salt_g: foodData.salt_g,
            nova_score: foodData.nova_score,
            nutri_score: foodData.nutri_score,
          });
        }
      }

      // Save meal entry
      const result = await onSubmit([
        {
          custom_name: foodData.name + (foodData.brand ? ` (${foodData.brand})` : ""),
          meal_type: mealType,
          amount_g_ml: foodData.amount_g_ml,
          calculated_kcal: Math.round((foodData.calories / 100) * foodData.amount_g_ml),
          calculated_protein: Math.round((foodData.protein_g / 100) * foodData.amount_g_ml * 10) / 10,
          calculated_carbs: Math.round((foodData.carbs_g / 100) * foodData.amount_g_ml * 10) / 10,
          calculated_fat: Math.round((foodData.fat_g / 100) * foodData.amount_g_ml * 10) / 10,
          source: barcodeValue ? "barcode" : "photo",
          food_id: finalFoodId,
        },
      ]);

      if (result.error) throw result.error;

      toast.success("Yiyecek eklendi");
      resetDialog();
      onOpenChange(false);
    } catch (err) {
      console.error("Save error:", err);
      toast.error("Kayıt başarısız: " + (err instanceof Error ? err.message : "Bilinmeyen hata"));
    } finally {
      setSaving(false);
    }
  };

  // Reset dialog
  const resetDialog = () => {
    stopScanning();
    setStep("scan");
    setBarcodeValue("");
    setManualBarcode("");
    setFoodData(null);
    setImageData(null);
    setAdditionalText("");
    setError(null);
    setFoodId(null);
  };

  // Handle dialog close
  const handleOpenChange = (newOpen: boolean) => {
    if (!newOpen) {
      resetDialog();
    }
    onOpenChange(newOpen);
  };

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopScanning();
    };
  }, [stopScanning]);

  // Auto-start scanning when dialog opens
  useEffect(() => {
    if (open && step === "scan" && !scanning) {
      const timer = setTimeout(() => {
        startScanning();
      }, 300);
      return () => clearTimeout(timer);
    }
  }, [open, step, scanning, startScanning]);

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <ScanBarcode className="h-5 w-5 text-primary" />
            Barkod ile Ekle
          </DialogTitle>
        </DialogHeader>

        {/* Scan Step */}
        {step === "scan" && (
          <div className="space-y-4">
            {/* Meal Type Selection */}
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

            {/* Camera View */}
            <div className="space-y-2">
              <Label>Barkod Tara</Label>
              <div className="relative aspect-video rounded-lg overflow-hidden bg-muted border border-border">
                <video
                  ref={videoRef}
                  className="w-full h-full object-cover"
                  autoPlay
                  playsInline
                  muted
                />
                {scanning && (
                  <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                    <div className="w-64 h-32 border-2 border-primary rounded-lg animate-pulse" />
                  </div>
                )}
                {!scanning && (
                  <div className="absolute inset-0 flex items-center justify-center bg-muted">
                    <Button onClick={startScanning}>
                      <Camera className="mr-2 h-4 w-4" />
                      Kamerayı Başlat
                    </Button>
                  </div>
                )}
              </div>
            </div>

            {/* Manual Barcode Entry */}
            <div className="space-y-2">
              <Label>veya Elle Girin</Label>
              <div className="flex gap-2">
                <Input
                  placeholder="Barkod numarası..."
                  value={manualBarcode}
                  onChange={(e) => setManualBarcode(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && handleManualSearch()}
                />
                <Button onClick={handleManualSearch} disabled={!manualBarcode.trim()}>
                  Ara
                </Button>
              </div>
            </div>

            {error && (
              <div className="flex items-center gap-2 p-3 rounded-lg bg-destructive/10 text-destructive text-sm">
                <AlertCircle className="h-4 w-4" />
                {error}
              </div>
            )}

            <DialogFooter>
              <Button variant="outline" onClick={() => handleOpenChange(false)}>
                İptal
              </Button>
            </DialogFooter>
          </div>
        )}

        {/* Not Found Step */}
        {step === "notFound" && (
          <div className="space-y-4">
            <div className="p-4 rounded-lg bg-warning/10 border border-warning/20 text-center">
              <AlertCircle className="h-8 w-8 text-warning mx-auto mb-2" />
              <p className="font-medium">Ürün Bulunamadı</p>
              <p className="text-sm text-muted-foreground mt-1">
                {barcodeValue && `Barkod: ${barcodeValue}`}
              </p>
            </div>

            <p className="text-sm text-muted-foreground text-center">
              Ürün etiketinin fotoğrafını çekin veya bilgileri yazın, AI analiz etsin.
            </p>

            {/* Image Capture */}
            {imageData ? (
              <div className="space-y-2">
                <Label>Seçilen Fotoğraf</Label>
                <div className="relative rounded-lg overflow-hidden border border-border">
                  <img
                    src={imageData}
                    alt="Ürün etiketi"
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
              </div>
            ) : (
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  className="flex-1"
                  onClick={() => {
                    const input = document.createElement("input");
                    input.type = "file";
                    input.accept = "image/*";
                    input.capture = "environment";
                    input.onchange = (e) => handleFileSelect(e as any);
                    input.click();
                  }}
                >
                  <Camera className="mr-2 h-4 w-4" />
                  Fotoğraf Çek
                </Button>
                <Button
                  variant="outline"
                  className="flex-1"
                  onClick={() => fileInputRef.current?.click()}
                >
                  <ImagePlus className="mr-2 h-4 w-4" />
                  Galeriden Seç
                </Button>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={handleFileSelect}
                />
              </div>
            )}

            {/* Additional Text */}
            <div className="space-y-2">
              <Label htmlFor="productInfo">Ürün Bilgisi</Label>
              <Textarea
                id="productInfo"
                value={additionalText}
                onChange={(e) => setAdditionalText(e.target.value)}
                placeholder="Ürün adı, markası, besin değerleri..."
                rows={3}
              />
            </div>

            {error && (
              <div className="flex items-center gap-2 p-3 rounded-lg bg-destructive/10 text-destructive text-sm">
                <AlertCircle className="h-4 w-4" />
                {error}
              </div>
            )}

            <DialogFooter className="flex-col sm:flex-row gap-2">
              <Button variant="ghost" onClick={() => setStep("scan")}>
                Geri
              </Button>
              <Button
                onClick={analyzeWithAI}
                disabled={(!imageData && !additionalText.trim()) || !isOnline}
              >
                <Sparkles className="mr-2 h-4 w-4" />
                AI ile Analiz Et
              </Button>
            </DialogFooter>
          </div>
        )}

        {/* Analyzing Step */}
        {step === "analyzing" && (
          <div className="flex flex-col items-center justify-center py-12 space-y-4">
            <Loader2 className="h-12 w-12 animate-spin text-primary" />
            <div className="text-center">
              <p className="font-medium">
                {barcodeValue ? "Ürün Aranıyor..." : "AI Analiz Ediyor..."}
              </p>
              <p className="text-sm text-muted-foreground">
                {barcodeValue
                  ? `Barkod: ${barcodeValue}`
                  : "Besin değerleri hesaplanıyor"}
              </p>
            </div>
          </div>
        )}

        {/* Result Step */}
        {step === "result" && foodData && (
          <div className="space-y-4">
            {/* Product Info */}
            <div className="p-4 rounded-lg bg-muted/50 border border-border">
              {foodData.fromDb && (
                <div className="flex items-center gap-1 text-xs text-green-600 mb-2">
                  <Check className="h-3 w-3" />
                  Veritabanından bulundu
                </div>
              )}
              {barcodeValue && (
                <p className="text-xs text-muted-foreground mb-1">
                  Barkod: {barcodeValue}
                </p>
              )}
              {foodData.confidence && (
                <p className="text-xs text-muted-foreground mb-1">
                  AI Güven: %{foodData.confidence}
                </p>
              )}
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

            {/* Editable Food Info */}
            <div className="space-y-3">
              <div className="space-y-2">
                <Label>Ürün Adı</Label>
                <Input
                  value={foodData.name}
                  onChange={(e) => updateFoodData({ name: e.target.value })}
                />
              </div>

              {foodData.brand !== undefined && (
                <div className="space-y-2">
                  <Label>Marka</Label>
                  <Input
                    value={foodData.brand || ""}
                    onChange={(e) => updateFoodData({ brand: e.target.value })}
                    placeholder="Marka (isteğe bağlı)"
                  />
                </div>
              )}

              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-2">
                  <Label>Miktar (g)</Label>
                  <Input
                    type="number"
                    value={foodData.amount_g_ml}
                    onChange={(e) => updateFoodData({ amount_g_ml: Number(e.target.value) })}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Porsiyon (g)</Label>
                  <Input
                    type="number"
                    value={foodData.serving_size_g || foodData.amount_g_ml}
                    onChange={(e) => updateFoodData({ serving_size_g: Number(e.target.value) })}
                  />
                </div>
              </div>

              <p className="text-xs text-muted-foreground flex items-center gap-1">
                <Edit className="h-3 w-3" />
                Besin değerleri 100g başına
              </p>

              {/* Primary macros */}
              <div className="grid grid-cols-4 gap-2">
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Kalori</Label>
                  <Input
                    type="number"
                    value={foodData.calories}
                    onChange={(e) => updateFoodData({ calories: Number(e.target.value) })}
                    className="h-9"
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Protein</Label>
                  <Input
                    type="number"
                    value={foodData.protein_g}
                    onChange={(e) => updateFoodData({ protein_g: Number(e.target.value) })}
                    className="h-9"
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Karb</Label>
                  <Input
                    type="number"
                    value={foodData.carbs_g}
                    onChange={(e) => updateFoodData({ carbs_g: Number(e.target.value) })}
                    className="h-9"
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Yağ</Label>
                  <Input
                    type="number"
                    value={foodData.fat_g}
                    onChange={(e) => updateFoodData({ fat_g: Number(e.target.value) })}
                    className="h-9"
                  />
                </div>
              </div>

              {/* Extended nutrition - collapsible */}
              <details className="group">
                <summary className="text-xs text-muted-foreground cursor-pointer hover:text-foreground flex items-center gap-1">
                  <span className="group-open:rotate-90 transition-transform">▶</span>
                  Detaylı Besin Değerleri
                </summary>
                <div className="mt-3 space-y-3">
                  {/* Fat breakdown */}
                  <div className="grid grid-cols-2 gap-2">
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">Doymuş Yağ (g)</Label>
                      <Input
                        type="number"
                        step="0.1"
                        value={foodData.saturated_fat_g ?? ""}
                        onChange={(e) => updateFoodData({ saturated_fat_g: e.target.value ? Number(e.target.value) : undefined })}
                        className="h-9"
                        placeholder="—"
                      />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">Trans Yağ (g)</Label>
                      <Input
                        type="number"
                        step="0.1"
                        value={foodData.trans_fat_g ?? ""}
                        onChange={(e) => updateFoodData({ trans_fat_g: e.target.value ? Number(e.target.value) : undefined })}
                        className="h-9"
                        placeholder="—"
                      />
                    </div>
                  </div>

                  {/* Carb breakdown & fiber */}
                  <div className="grid grid-cols-2 gap-2">
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">Şeker (g)</Label>
                      <Input
                        type="number"
                        step="0.1"
                        value={foodData.sugars_g ?? ""}
                        onChange={(e) => updateFoodData({ sugars_g: e.target.value ? Number(e.target.value) : undefined })}
                        className="h-9"
                        placeholder="—"
                      />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">Lif (g)</Label>
                      <Input
                        type="number"
                        step="0.1"
                        value={foodData.fiber_g ?? ""}
                        onChange={(e) => updateFoodData({ fiber_g: e.target.value ? Number(e.target.value) : undefined })}
                        className="h-9"
                        placeholder="—"
                      />
                    </div>
                  </div>

                  {/* Salt */}
                  <div className="grid grid-cols-2 gap-2">
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">Tuz (g)</Label>
                      <Input
                        type="number"
                        step="0.01"
                        value={foodData.salt_g ?? ""}
                        onChange={(e) => updateFoodData({ salt_g: e.target.value ? Number(e.target.value) : undefined })}
                        className="h-9"
                        placeholder="—"
                      />
                    </div>
                  </div>

                  {/* Scores */}
                  <div className="grid grid-cols-2 gap-2">
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">NOVA Skoru (1-4)</Label>
                      <Input
                        type="number"
                        min="1"
                        max="4"
                        value={foodData.nova_score ?? ""}
                        onChange={(e) => updateFoodData({ nova_score: e.target.value ? Number(e.target.value) : undefined })}
                        className="h-9"
                        placeholder="—"
                      />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">Nutri-Score (A-E)</Label>
                      <Input
                        type="text"
                        maxLength={1}
                        value={foodData.nutri_score ?? ""}
                        onChange={(e) => updateFoodData({ nutri_score: e.target.value.toUpperCase() || undefined })}
                        className="h-9"
                        placeholder="—"
                      />
                    </div>
                  </div>
                </div>
              </details>

              {/* Calculated values preview */}
              <div className="p-3 rounded-lg bg-primary/5 border border-primary/10">
                <p className="text-xs text-muted-foreground mb-1">
                  {foodData.amount_g_ml}g için hesaplanan değerler:
                </p>
                <div className="flex justify-between text-sm">
                  <span>{Math.round((foodData.calories / 100) * foodData.amount_g_ml)} kcal</span>
                  <span>{Math.round((foodData.protein_g / 100) * foodData.amount_g_ml * 10) / 10}g P</span>
                  <span>{Math.round((foodData.carbs_g / 100) * foodData.amount_g_ml * 10) / 10}g K</span>
                  <span>{Math.round((foodData.fat_g / 100) * foodData.amount_g_ml * 10) / 10}g Y</span>
                </div>
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
                onClick={() => {
                  setFoodData(null);
                  setStep("scan");
                }}
              >
                <RefreshCw className="mr-2 h-4 w-4" />
                Yeniden Tara
              </Button>
              <Button onClick={handleSave} disabled={saving}>
                {saving ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <Check className="mr-2 h-4 w-4" />
                )}
                Kaydet
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

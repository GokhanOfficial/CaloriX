import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Loader2 } from "lucide-react";
import { type MealType, MEAL_TYPES } from "@/lib/constants";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

interface FoodData {
  food_id: string | null;
  name: string;
  brand: string | null;
  serving_size_g: number | null;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
}

interface AddFromFoodDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  food: FoodData | null;
  defaultMealType: MealType;
  onSubmit: (entry: {
    food_id: string | null;
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
  }) => Promise<{ error: Error | null }>;
}

export function AddFromFoodDialog({
  open,
  onOpenChange,
  food,
  defaultMealType,
  onSubmit,
}: AddFromFoodDialogProps) {
  const [mealType, setMealType] = useState<MealType>(defaultMealType);
  const [amount, setAmount] = useState(food?.serving_size_g?.toString() || "100");
  const [saving, setSaving] = useState(false);

  if (!food) return null;

  const amountNum = parseFloat(amount) || 0;
  const calculated = {
    kcal: Math.round((food.calories * amountNum) / 100),
    protein: Math.round((food.protein_g * amountNum) / 100 * 10) / 10,
    carbs: Math.round((food.carbs_g * amountNum) / 100 * 10) / 10,
    fat: Math.round((food.fat_g * amountNum) / 100 * 10) / 10,
  };

  const handleSave = async () => {
    setSaving(true);
    const result = await onSubmit({
      food_id: food.food_id,
      custom_name: food.name,
      meal_type: mealType,
      amount_g_ml: amountNum,
      calculated_kcal: calculated.kcal,
      calculated_protein: calculated.protein,
      calculated_carbs: calculated.carbs,
      calculated_fat: calculated.fat,
    });
    setSaving(false);

    if (!result.error) {
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Yiyecek Ekle</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 pt-2">
          {/* Food Name */}
          <div>
            <p className="font-medium text-foreground">{food.name}</p>
            {food.brand && (
              <p className="text-sm text-muted-foreground">{food.brand}</p>
            )}
          </div>

          {/* Meal Type */}
          <div className="space-y-1.5">
            <Label>Öğün</Label>
            <Select value={mealType} onValueChange={(v) => setMealType(v as MealType)}>
              <SelectTrigger className="h-11 bg-secondary">
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
          </div>

          {/* Amount */}
          <div className="space-y-1.5">
            <Label>Miktar (g)</Label>
            <Input
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="h-11 bg-secondary"
              min={1}
            />
          </div>

          {/* Nutrition Info */}
          <div className="rounded-lg bg-secondary p-3">
            <p className="text-sm font-medium text-muted-foreground mb-2">
              Besin Değerleri (100g için)
            </p>
            <div className="grid grid-cols-4 gap-2 text-center text-sm">
              <div>
                <p className="text-muted-foreground">Kalori</p>
                <p className="font-medium">{food.calories}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Protein</p>
                <p className="font-medium">{food.protein_g}g</p>
              </div>
              <div>
                <p className="text-muted-foreground">Karb</p>
                <p className="font-medium">{food.carbs_g}g</p>
              </div>
              <div>
                <p className="text-muted-foreground">Yağ</p>
                <p className="font-medium">{food.fat_g}g</p>
              </div>
            </div>
          </div>

          {/* Calculated Values */}
          <div className="rounded-lg bg-primary/10 p-3">
            <p className="text-sm font-medium text-primary mb-2">
              Hesaplanan ({amountNum}g için)
            </p>
            <div className="grid grid-cols-4 gap-2 text-center text-sm">
              <div>
                <p className="text-muted-foreground">Kalori</p>
                <p className="font-medium text-primary">{calculated.kcal}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Protein</p>
                <p className="font-medium text-primary">{calculated.protein}g</p>
              </div>
              <div>
                <p className="text-muted-foreground">Karb</p>
                <p className="font-medium text-primary">{calculated.carbs}g</p>
              </div>
              <div>
                <p className="text-muted-foreground">Yağ</p>
                <p className="font-medium text-primary">{calculated.fat}g</p>
              </div>
            </div>
          </div>

          {/* Save Button */}
          <Button
            onClick={handleSave}
            disabled={saving || amountNum <= 0}
            className="w-full h-11"
          >
            {saving ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Kaydediliyor...
              </>
            ) : (
              "Kaydet"
            )}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

import { useState } from "react";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { MEAL_TYPES, type MealType } from "@/lib/constants";
import { Loader2 } from "lucide-react";

interface AddMealDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultMealType?: MealType;
  onSubmit: (data: {
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
  }) => Promise<{ error: Error | null }>;
}

export function AddMealDialog({
  open,
  onOpenChange,
  defaultMealType = "breakfast",
  onSubmit,
}: AddMealDialogProps) {
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState({
    name: "",
    mealType: defaultMealType,
    amount: "",
    calories: "",
    protein: "",
    carbs: "",
    fat: "",
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    const result = await onSubmit({
      custom_name: formData.name,
      meal_type: formData.mealType,
      amount_g_ml: parseFloat(formData.amount) || 0,
      calculated_kcal: parseFloat(formData.calories) || 0,
      calculated_protein: parseFloat(formData.protein) || 0,
      calculated_carbs: parseFloat(formData.carbs) || 0,
      calculated_fat: parseFloat(formData.fat) || 0,
    });

    setLoading(false);

    if (!result.error) {
      // Reset form
      setFormData({
        name: "",
        mealType: defaultMealType,
        amount: "",
        calories: "",
        protein: "",
        carbs: "",
        fat: "",
      });
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Yiyecek Ekle</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="name">Yiyecek Adı</Label>
            <Input
              id="name"
              value={formData.name}
              onChange={(e) =>
                setFormData((prev) => ({ ...prev, name: e.target.value }))
              }
              placeholder="Örn: Tavuk Göğsü"
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="mealType">Öğün</Label>
            <Select
              value={formData.mealType}
              onValueChange={(value) =>
                setFormData((prev) => ({ ...prev, mealType: value as MealType }))
              }
            >
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

          <div className="space-y-2">
            <Label htmlFor="amount">Miktar (g/ml)</Label>
            <Input
              id="amount"
              type="number"
              value={formData.amount}
              onChange={(e) =>
                setFormData((prev) => ({ ...prev, amount: e.target.value }))
              }
              placeholder="100"
              required
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="calories">Kalori (kcal)</Label>
              <Input
                id="calories"
                type="number"
                value={formData.calories}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, calories: e.target.value }))
                }
                placeholder="0"
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="protein">Protein (g)</Label>
              <Input
                id="protein"
                type="number"
                step="0.1"
                value={formData.protein}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, protein: e.target.value }))
                }
                placeholder="0"
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="carbs">Karbonhidrat (g)</Label>
              <Input
                id="carbs"
                type="number"
                step="0.1"
                value={formData.carbs}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, carbs: e.target.value }))
                }
                placeholder="0"
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="fat">Yağ (g)</Label>
              <Input
                id="fat"
                type="number"
                step="0.1"
                value={formData.fat}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, fat: e.target.value }))
                }
                placeholder="0"
                required
              />
            </div>
          </div>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
            >
              İptal
            </Button>
            <Button type="submit" disabled={loading}>
              {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Ekle
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

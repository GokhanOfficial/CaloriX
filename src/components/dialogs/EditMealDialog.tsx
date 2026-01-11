import { useState, useEffect } from "react";
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
import { Loader2, Trash2 } from "lucide-react";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

interface EditMealEntry {
  id: string;
  name: string;
  mealType: MealType;
  amount: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
}

interface EditMealDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  entry: EditMealEntry | null;
  onSubmit: (data: {
    id: string;
    custom_name: string;
    meal_type: MealType;
    amount_g_ml: number;
    calculated_kcal: number;
    calculated_protein: number;
    calculated_carbs: number;
    calculated_fat: number;
  }) => Promise<{ error: Error | null }>;
  onDelete: (id: string) => Promise<{ error: Error | null }>;
}

export function EditMealDialog({
  open,
  onOpenChange,
  entry,
  onSubmit,
  onDelete,
}: EditMealDialogProps) {
  const [loading, setLoading] = useState(false);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [formData, setFormData] = useState({
    name: "",
    mealType: "breakfast" as MealType,
    amount: "",
    // Per 100g values
    caloriesPer100: "",
    proteinPer100: "",
    carbsPer100: "",
    fatPer100: "",
  });

  // Update form when entry changes
  useEffect(() => {
    if (entry) {
      // Calculate per-100g values from the entry's total values
      const amount = entry.amount || 100;
      setFormData({
        name: entry.name,
        mealType: entry.mealType,
        amount: String(entry.amount),
        caloriesPer100: String(Math.round((entry.calories / amount) * 100)),
        proteinPer100: String(Math.round((entry.protein / amount) * 100 * 10) / 10),
        carbsPer100: String(Math.round((entry.carbs / amount) * 100 * 10) / 10),
        fatPer100: String(Math.round((entry.fat / amount) * 100 * 10) / 10),
      });
    }
  }, [entry]);

  // Calculate current totals based on amount and per-100g values
  const currentAmount = parseFloat(formData.amount) || 0;
  const calculatedCalories = Math.round(
    (parseFloat(formData.caloriesPer100) || 0) * currentAmount / 100
  );
  const calculatedProtein = Math.round(
    (parseFloat(formData.proteinPer100) || 0) * currentAmount / 100 * 10
  ) / 10;
  const calculatedCarbs = Math.round(
    (parseFloat(formData.carbsPer100) || 0) * currentAmount / 100 * 10
  ) / 10;
  const calculatedFat = Math.round(
    (parseFloat(formData.fatPer100) || 0) * currentAmount / 100 * 10
  ) / 10;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!entry) return;

    setLoading(true);

    const result = await onSubmit({
      id: entry.id,
      custom_name: formData.name,
      meal_type: formData.mealType,
      amount_g_ml: currentAmount,
      calculated_kcal: calculatedCalories,
      calculated_protein: calculatedProtein,
      calculated_carbs: calculatedCarbs,
      calculated_fat: calculatedFat,
    });

    setLoading(false);

    if (!result.error) {
      onOpenChange(false);
    }
  };

  const handleDelete = async () => {
    if (!entry) return;

    setLoading(true);
    const result = await onDelete(entry.id);
    setLoading(false);

    if (!result.error) {
      setDeleteDialogOpen(false);
      onOpenChange(false);
    }
  };

  if (!entry) return null;

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Yiyeceği Düzenle</DialogTitle>
          </DialogHeader>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="edit-name">Yiyecek Adı</Label>
              <Input
                id="edit-name"
                value={formData.name}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, name: e.target.value }))
                }
                placeholder="Örn: Tavuk Göğsü"
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="edit-mealType">Öğün</Label>
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
              <Label htmlFor="edit-amount">Miktar (g/ml)</Label>
              <Input
                id="edit-amount"
                type="number"
                value={formData.amount}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, amount: e.target.value }))
                }
                placeholder="100"
                required
              />
            </div>

            <div className="bg-muted/50 rounded-lg p-3 space-y-3">
              <p className="text-sm font-medium text-muted-foreground">
                100g başına besin değerleri
              </p>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label htmlFor="edit-caloriesPer100" className="text-xs">
                    Kalori (kcal)
                  </Label>
                  <Input
                    id="edit-caloriesPer100"
                    type="number"
                    value={formData.caloriesPer100}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, caloriesPer100: e.target.value }))
                    }
                    placeholder="0"
                    required
                  />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="edit-proteinPer100" className="text-xs">
                    Protein (g)
                  </Label>
                  <Input
                    id="edit-proteinPer100"
                    type="number"
                    step="0.1"
                    value={formData.proteinPer100}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, proteinPer100: e.target.value }))
                    }
                    placeholder="0"
                    required
                  />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="edit-carbsPer100" className="text-xs">
                    Karbonhidrat (g)
                  </Label>
                  <Input
                    id="edit-carbsPer100"
                    type="number"
                    step="0.1"
                    value={formData.carbsPer100}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, carbsPer100: e.target.value }))
                    }
                    placeholder="0"
                    required
                  />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="edit-fatPer100" className="text-xs">
                    Yağ (g)
                  </Label>
                  <Input
                    id="edit-fatPer100"
                    type="number"
                    step="0.1"
                    value={formData.fatPer100}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, fatPer100: e.target.value }))
                    }
                    placeholder="0"
                    required
                  />
                </div>
              </div>
            </div>

            {/* Calculated totals preview */}
            <div className="bg-primary/10 rounded-lg p-3">
              <p className="text-sm font-medium text-foreground mb-1">
                Hesaplanan toplam ({currentAmount}g)
              </p>
              <p className="text-sm text-muted-foreground">
                {calculatedCalories} kcal • P: {calculatedProtein}g • K: {calculatedCarbs}g • Y: {calculatedFat}g
              </p>
            </div>

            <DialogFooter className="flex-col gap-2 sm:flex-row">
              <Button
                type="button"
                variant="destructive"
                onClick={() => setDeleteDialogOpen(true)}
                className="w-full sm:w-auto"
              >
                <Trash2 className="mr-2 h-4 w-4" />
                Sil
              </Button>
              <div className="flex gap-2 w-full sm:w-auto">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => onOpenChange(false)}
                  className="flex-1"
                >
                  İptal
                </Button>
                <Button type="submit" disabled={loading} className="flex-1">
                  {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                  Kaydet
                </Button>
              </div>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Yiyeceği Sil</AlertDialogTitle>
            <AlertDialogDescription>
              "{entry.name}" kaydını silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>İptal</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
              {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Sil
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

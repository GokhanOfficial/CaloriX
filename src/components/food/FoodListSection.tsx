import { Star, History, Loader2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

interface FoodItem {
  id: string;
  food_id: string | null;
  name: string;
  brand: string | null;
  serving_size_g: number | null;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
}

interface FoodListSectionProps {
  title: string;
  icon: "star" | "history";
  foods: FoodItem[];
  loading: boolean;
  emptyMessage: string;
  onSelect: (food: FoodItem) => void;
}

export function FoodListSection({
  title,
  icon,
  foods,
  loading,
  emptyMessage,
  onSelect,
}: FoodListSectionProps) {
  const Icon = icon === "star" ? Star : History;

  return (
    <Card className="border-none bg-card shadow-lg">
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base">
          <Icon className={cn("h-4 w-4", icon === "star" ? "text-yellow-500" : "text-primary")} />
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>
        {loading ? (
          <div className="flex items-center justify-center py-6">
            <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
          </div>
        ) : foods.length === 0 ? (
          <p className="py-4 text-center text-sm text-muted-foreground">
            {emptyMessage}
          </p>
        ) : (
          <div className="space-y-2">
            {foods.map((food) => (
              <button
                key={food.id}
                onClick={() => onSelect(food)}
                className="flex w-full items-center justify-between rounded-lg bg-secondary p-3 text-left transition-colors hover:bg-muted"
              >
                <div className="flex-1 min-w-0">
                  <p className="font-medium text-foreground truncate">
                    {food.name}
                  </p>
                  <p className="text-sm text-muted-foreground">
                    {food.brand && <span className="mr-2">{food.brand}</span>}
                    100g • {food.calories} kcal
                  </p>
                </div>
                <div className="ml-3 text-right text-xs text-muted-foreground">
                  <p>P: {food.protein_g}g</p>
                  <p>K: {food.carbs_g}g</p>
                  <p>Y: {food.fat_g}g</p>
                </div>
              </button>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

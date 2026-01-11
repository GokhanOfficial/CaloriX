import { Plus, ChevronDown, ChevronUp } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { MEAL_TYPES, type MealType } from "@/lib/constants";
import { cn } from "@/lib/utils";

interface MealEntry {
  id: string;
  name: string;
  amount: number;
  unit: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
}

interface MealSectionProps {
  mealType: MealType;
  entries?: MealEntry[];
  onAddEntry?: () => void;
  onEditEntry?: (id: string) => void;
  onDeleteEntry?: (id: string) => void;
}

export function MealSection({
  mealType,
  entries = [],
  onAddEntry,
  onEditEntry,
}: MealSectionProps) {
  const [isExpanded, setIsExpanded] = useState(true);
  const meal = MEAL_TYPES[mealType];

  const totalCalories = Math.round(entries.reduce((sum, e) => sum + e.calories, 0));
  const totalProtein = Math.round(entries.reduce((sum, e) => sum + e.protein, 0) * 10) / 10;
  const totalCarbs = Math.round(entries.reduce((sum, e) => sum + e.carbs, 0) * 10) / 10;
  const totalFat = Math.round(entries.reduce((sum, e) => sum + e.fat, 0) * 10) / 10;

  return (
    <Card className="border-none bg-card shadow-lg overflow-hidden">
      <CardHeader
        className="flex-row items-center justify-between p-4 cursor-pointer"
        onClick={() => setIsExpanded(!isExpanded)}
      >
        <div className="flex items-center gap-3">
          <span className="text-2xl">{meal.icon}</span>
          <div>
            <h3 className="font-semibold text-foreground">{meal.label}</h3>
            {entries.length > 0 && (
              <p className="text-sm text-muted-foreground">
                {totalCalories} kcal • P: {totalProtein}g • K: {totalCarbs}g • Y: {totalFat}g
              </p>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-primary hover:bg-primary/10"
            onClick={(e) => {
              e.stopPropagation();
              onAddEntry?.();
            }}
          >
            <Plus className="h-5 w-5" />
          </Button>
          {isExpanded ? (
            <ChevronUp className="h-5 w-5 text-muted-foreground" />
          ) : (
            <ChevronDown className="h-5 w-5 text-muted-foreground" />
          )}
        </div>
      </CardHeader>
      
      {isExpanded && (
        <CardContent className="p-0">
          {entries.length === 0 ? (
            <div className="border-t border-border p-4 text-center">
              <p className="text-sm text-muted-foreground">Henüz kayıt yok</p>
              <Button
                variant="ghost"
                size="sm"
                className="mt-2 text-primary"
                onClick={onAddEntry}
              >
                <Plus className="mr-1 h-4 w-4" />
                Yiyecek Ekle
              </Button>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {entries.map((entry) => (
                <button
                  key={entry.id}
                  className="flex w-full items-center justify-between p-4 text-left transition-colors hover:bg-muted/50"
                  onClick={() => onEditEntry?.(entry.id)}
                >
                  <div>
                    <p className="font-medium text-foreground">{entry.name}</p>
                    <p className="text-sm text-muted-foreground">
                      {entry.amount} {entry.unit}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="font-semibold text-foreground">{Math.round(entry.calories)} kcal</p>
                    <p className="text-xs text-muted-foreground">
                      P: {Math.round(entry.protein * 10) / 10}g • K: {Math.round(entry.carbs * 10) / 10}g • Y: {Math.round(entry.fat * 10) / 10}g
                    </p>
                  </div>
                </button>
              ))}
            </div>
          )}
        </CardContent>
      )}
    </Card>
  );
}

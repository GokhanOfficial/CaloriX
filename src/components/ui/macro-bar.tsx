import * as React from "react";
import { cn } from "@/lib/utils";
import { calculateProgress } from "@/lib/calculations";

interface MacroBarProps {
  label: string;
  current: number;
  target: number;
  unit?: string;
  color: 'protein' | 'carbs' | 'fat';
  className?: string;
}

export function MacroBar({
  label,
  current,
  target,
  unit = 'g',
  color,
  className,
}: MacroBarProps) {
  // **Sıfıra bölme koruması (P1).** `current / target` korumasız
  // hesaplanıyordu. `target` 0 geldiğinde:
  //   * `0 / 0` → `NaN` → `width: NaN%` → tarayıcı **çubuğu hiç çizmiyor**
  //   * `>0 / 0` → `Infinity` → `Math.min(100, Infinity)` = 100 → hedefi 0 olan
  //     makroda çubuk **dolu** görünüyor (kullanıcı "hedefi geçtim" sanıyor)
  //   * hedef negatif → `-%400` (CSS geçersiz, çubuk kayboluyor)
  // `target` 0, `profiles.protein_target_g` yazı hatasıyla bozulduğunda
  // ya da hedef kaydı henüz oluşmamış bir profilde mümkün. Flutter tarafı
  // `Calculations.progress` üç katmanlı savunma yapıyor; web'de
  // `calculateProgress` **hiç kullanılmıyordu** — bileşenler kendi
  // bölmesini yapıyordu. Artık tek kaynak kullanılıyor.
  const percentage = calculateProgress(current, target);
  const isOver = current > target;

  const colorClasses = {
    protein: 'bg-macro-protein',
    carbs: 'bg-macro-carbs',
    fat: 'bg-macro-fat',
  };

  const textColorClasses = {
    protein: 'text-macro-protein',
    carbs: 'text-macro-carbs',
    fat: 'text-macro-fat',
  };

  return (
    <div className={cn("space-y-1.5", className)}>
      <div className="flex items-center justify-between text-sm">
        <span className={cn("font-medium", textColorClasses[color])}>{label}</span>
        <span className="text-muted-foreground">
          <span className={cn("font-semibold", isOver ? "text-destructive" : "text-foreground")}>
            {current}
          </span>
          <span className="mx-0.5">/</span>
          <span>{target}{unit}</span>
        </span>
      </div>
      <div className="h-2 w-full overflow-hidden rounded-full bg-muted">
        <div
          className={cn(
            "h-full rounded-full transition-all duration-500 ease-out",
            isOver ? "bg-destructive" : colorClasses[color]
          )}
          style={{ width: `${percentage}%` }}
        />
      </div>
    </div>
  );
}

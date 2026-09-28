import * as React from "react";
import { cn } from "@/lib/utils";
import { calculateProgress } from "@/lib/calculations";

interface CircularProgressProps {
  value: number;
  max: number;
  size?: number;
  strokeWidth?: number;
  className?: string;
  showValue?: boolean;
  label?: string;
  color?: 'primary' | 'macro-protein' | 'macro-carbs' | 'macro-fat' | 'macro-calories';
  /**
   * Ekran okuyucu metni. `role="progressbar"` + `aria-valuenow/min/max`
   * yalnız görsel halkayı anlatır; yüzde metni okunmaz.
   */
  ariaLabel?: string;
}

export function CircularProgress({
  value,
  max,
  size = 120,
  strokeWidth = 8,
  className,
  showValue = true,
  label,
  color = 'primary',
  ariaLabel,
}: CircularProgressProps) {
  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  // `calculateProgress` 0/negatif/NaN hedefte 0 döner ve 0..100'e kırpar
  // (`Math.min(100, (value / max) * 100)` korumasız sürümde `max = 0`
  // iken `NaN`/`Infinity` üretiyordu → halka ya hiç çizilmiyor ya da
  // tamamen dolu görünüyordu). Flutter `Calculations.progress` ile aynı.
  const percentage = calculateProgress(value, max);
  const offset = circumference - (percentage / 100) * circumference;

  const colorClasses = {
    primary: 'stroke-primary',
    'macro-protein': 'stroke-macro-protein',
    'macro-carbs': 'stroke-macro-carbs',
    'macro-fat': 'stroke-macro-fat',
    'macro-calories': 'stroke-macro-calories',
  };

  return (
    <div
      className={cn("relative inline-flex items-center justify-center", className)}
      // Erişilebilirlik: görsel halka için `role="progressbar"`; `aria-valuetext`
      // yüzdeyi okur (`aria-valuenow` sadece ham sayı verir ve 0'a bölünmüş
      // durumda anlamsız kalır).
      role="progressbar"
      aria-label={ariaLabel ?? label ?? 'İlerleme'}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={percentage}
      aria-valuetext={`%${percentage}`}
    >
      <svg width={size} height={size} className="-rotate-90" aria-hidden="true">
        {/* Background circle */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          strokeWidth={strokeWidth}
          className="fill-none stroke-muted"
        />
        {/* Progress circle */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          className={cn("fill-none transition-all duration-500 ease-out", colorClasses[color])}
          style={{
            strokeDasharray: circumference,
            strokeDashoffset: offset,
          }}
        />
      </svg>
      {showValue && (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-2xl font-bold text-foreground">{value}</span>
          {label && <span className="text-xs text-muted-foreground">{label}</span>}
        </div>
      )}
    </div>
  );
}

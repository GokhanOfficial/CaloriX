import { useState, useEffect, useRef } from "react";
import { Droplets, Plus, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { WATER_QUICK_ADD, DEFAULT_GOALS } from "@/lib/constants";
import { calculateProgress } from "@/lib/calculations";
import { cn } from "@/lib/utils";
import { CustomWaterDialog } from "@/components/dialogs/CustomWaterDialog";
import { useTranslation } from "react-i18next";

interface WaterTrackerProps {
  current?: number;
  target?: number;
  onAdd?: (amount: number) => void;
}

export function WaterTracker({
  current = 0,
  target = DEFAULT_GOALS.water,
  onAdd,
}: WaterTrackerProps) {
  const { t } = useTranslation();
  // Sıfıra bölme koruması: `target = 0` iken `(current / target) * 100`
  // → `Infinity` (veya `0/0` → `NaN`) → `Progress value={NaN}` radix
  // `Progress` bileşeninde `translateX(-NaN%)` üretiyor ve çubuk kayboluyordu.
  // `calculateProgress` tek kaynak (Flutter `Calculations.progress` ile aynı).
  const percentage = calculateProgress(current, target);
  const remaining = target > 0 ? Math.max(0, target - current) : 0;
  const [displayValue, setDisplayValue] = useState(current);
  const [isAnimating, setIsAnimating] = useState(false);
  const [customDialogOpen, setCustomDialogOpen] = useState(false);
  const prevValueRef = useRef(current);

  // Animate the value change
  //
  // **`requestAnimationFrame` iptali (P1).** `rafId` saklanmıyordu; su
  // ekleme animasyonu sürerken bileşen çözülürse (`Index` → `AnalyticsPage`
  // geçişi, ya da su kaydının tamamlanıp ekranın yeniden render edilmesi)
  // kalan kareler `setDisplayValue` çağırıyor — React 18'de bu artık
  // sessizce yutulmuyor, konsola uyarı basıyor ve bellekte kalmış bir
  // animasyon döngüsü bırakıyor. Cleanup `cancelAnimationFrame` ile
  // döngüyü durdurur.
  useEffect(() => {
    if (current === prevValueRef.current) return;

    setIsAnimating(true);
    const startValue = prevValueRef.current;
    const endValue = current;
    const duration = 400; // ms
    const startTime = Date.now();
    let rafId = 0;

    const animate = () => {
      const elapsed = Date.now() - startTime;
      const progress = Math.min(elapsed / duration, 1);

      // Easing function (ease-out)
      const eased = 1 - Math.pow(1 - progress, 3);
      const currentValue = Math.round(startValue + (endValue - startValue) * eased);

      setDisplayValue(currentValue);

      if (progress < 1) {
        rafId = requestAnimationFrame(animate);
      } else {
        setIsAnimating(false);
        prevValueRef.current = current;
      }
    };

    rafId = requestAnimationFrame(animate);

    return () => {
      cancelAnimationFrame(rafId);
    };
  }, [current]);

  return (
    <Card className="border-none bg-card shadow-lg overflow-hidden">
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div
              className={cn(
                "flex h-10 w-10 items-center justify-center rounded-full bg-info/10 transition-transform duration-300",
                isAnimating && "scale-110"
              )}
            >
              <Droplets
                className={cn(
                  "h-5 w-5 text-info transition-all duration-300",
                  isAnimating && "animate-pulse"
                )}
              />
            </div>
            <div>
              <p className="font-semibold text-foreground">{t('dashboard.waterTracker')}</p>
              <p className="text-sm text-muted-foreground">
                {remaining > 0 ? t('dashboard.mlRemaining', { amount: remaining }) : t('dashboard.goalReached')}
              </p>
            </div>
          </div>
          <div className="text-right">
            <p
              className={cn(
                "text-lg font-bold text-foreground transition-all duration-300",
                isAnimating && "text-info scale-105"
              )}
            >
              {displayValue} <span className="text-sm font-normal text-muted-foreground">/ {target} ml</span>
            </p>
          </div>
        </div>

        <Progress
          value={percentage}
          className="mt-4 h-2 transition-all duration-500"
        />

        <div className="mt-4 flex gap-2">
          {WATER_QUICK_ADD.map((amount) => (
            <Button
              key={amount}
              variant="outline"
              size="sm"
              className={cn(
                "flex-1 gap-1 text-xs transition-all duration-200",
                "hover:bg-info/10 hover:text-info hover:border-info",
                "active:scale-95"
              )}
              onClick={() => onAdd?.(amount)}
            >
              <Plus className="h-3 w-3" />
              {amount >= 1000 ? `${amount / 1000}L` : `${amount}ml`}
            </Button>
          ))}
          <Button
            variant="outline"
            size="sm"
            className={cn(
              "flex-1 gap-1 text-xs transition-all duration-200",
              "hover:bg-info/10 hover:text-info hover:border-info",
              "active:scale-95"
            )}
            onClick={() => setCustomDialogOpen(true)}
          >
            <Pencil className="h-3 w-3" />
            {t('dashboard.custom')}
          </Button>
        </div>

        <CustomWaterDialog
          open={customDialogOpen}
          onOpenChange={setCustomDialogOpen}
          onSubmit={(amount) => onAdd?.(amount)}
        />
      </CardContent>
    </Card>
  );
}

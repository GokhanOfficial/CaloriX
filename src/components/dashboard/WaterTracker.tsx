import { useState, useEffect, useRef } from "react";
import { Droplets, Plus, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { WATER_QUICK_ADD, DEFAULT_GOALS } from "@/lib/constants";
import { cn } from "@/lib/utils";
import { CustomWaterDialog } from "@/components/dialogs/CustomWaterDialog";

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
  const percentage = Math.min(100, (current / target) * 100);
  const remaining = Math.max(0, target - current);
  const [displayValue, setDisplayValue] = useState(current);
  const [isAnimating, setIsAnimating] = useState(false);
  const [customDialogOpen, setCustomDialogOpen] = useState(false);
  const prevValueRef = useRef(current);

  // Animate the value change
  useEffect(() => {
    if (current !== prevValueRef.current) {
      setIsAnimating(true);
      const startValue = prevValueRef.current;
      const endValue = current;
      const duration = 400; // ms
      const startTime = Date.now();

      const animate = () => {
        const elapsed = Date.now() - startTime;
        const progress = Math.min(elapsed / duration, 1);
        
        // Easing function (ease-out)
        const eased = 1 - Math.pow(1 - progress, 3);
        const currentValue = Math.round(startValue + (endValue - startValue) * eased);
        
        setDisplayValue(currentValue);

        if (progress < 1) {
          requestAnimationFrame(animate);
        } else {
          setIsAnimating(false);
          prevValueRef.current = current;
        }
      };

      requestAnimationFrame(animate);
    }
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
              <p className="font-semibold text-foreground">Su Takibi</p>
              <p className="text-sm text-muted-foreground">
                {remaining > 0 ? `${remaining} ml kaldı` : "Hedef tamamlandı! 🎉"}
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
            Özel
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

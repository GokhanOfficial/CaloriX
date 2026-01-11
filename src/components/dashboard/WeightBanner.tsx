import { Scale, ChevronRight, AlertCircle } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface WeightBannerProps {
  lastWeight?: number;
  lastWeighDate?: Date;
  reminderDays?: number;
  onLogWeight?: () => void;
}

export function WeightBanner({
  lastWeight,
  lastWeighDate,
  reminderDays = 7,
  onLogWeight,
}: WeightBannerProps) {
  const daysSinceWeigh = lastWeighDate
    ? Math.floor((Date.now() - lastWeighDate.getTime()) / (1000 * 60 * 60 * 24))
    : null;

  const isOverdue = daysSinceWeigh !== null && daysSinceWeigh >= reminderDays;

  return (
    <Card
      className={cn(
        "border-none shadow-lg cursor-pointer transition-all hover:shadow-glow",
        isOverdue ? "bg-warning/10 border-warning/30" : "bg-card"
      )}
      onClick={onLogWeight}
    >
      <CardContent className="flex items-center justify-between p-4">
        <div className="flex items-center gap-3">
          <div
            className={cn(
              "flex h-10 w-10 items-center justify-center rounded-full",
              isOverdue ? "bg-warning/20" : "bg-primary/10"
            )}
          >
            {isOverdue ? (
              <AlertCircle className="h-5 w-5 text-warning" />
            ) : (
              <Scale className="h-5 w-5 text-primary" />
            )}
          </div>
          <div>
            <p className="font-semibold text-foreground">
              {lastWeight ? `${lastWeight} kg` : "Kilo Gir"}
            </p>
            <p className="text-sm text-muted-foreground">
              {isOverdue
                ? `${daysSinceWeigh} gündür tartılmadın`
                : lastWeighDate
                ? `Son tartı: ${daysSinceWeigh} gün önce`
                : "Kilonu kaydet"}
            </p>
          </div>
        </div>
        <Button variant="ghost" size="icon" className="text-muted-foreground">
          <ChevronRight className="h-5 w-5" />
        </Button>
      </CardContent>
    </Card>
  );
}

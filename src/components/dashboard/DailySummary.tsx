import { CircularProgress } from "@/components/ui/circular-progress";
import { MacroBar } from "@/components/ui/macro-bar";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { DEFAULT_GOALS } from "@/lib/constants";
import { useTranslation } from "react-i18next";

interface DailySummaryProps {
  calories?: { current: number; target: number };
  protein?: { current: number; target: number };
  carbs?: { current: number; target: number };
  fat?: { current: number; target: number };
}

export function DailySummary({
  calories = { current: 0, target: DEFAULT_GOALS.calories },
  protein = { current: 0, target: DEFAULT_GOALS.protein },
  carbs = { current: 0, target: DEFAULT_GOALS.carbs },
  fat = { current: 0, target: DEFAULT_GOALS.fat },
}: DailySummaryProps) {
  const { t } = useTranslation();
  const remaining = calories.target - calories.current;

  return (
    <Card className="border-none bg-card shadow-lg">
      <CardHeader className="pb-2">
        <CardTitle className="text-lg font-semibold">{t('dashboard.dailySummary')}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Calories Circle */}
        <div className="flex flex-col items-center gap-4">
          <div className="relative">
            <CircularProgress
              value={calories.current}
              max={calories.target}
              size={160}
              strokeWidth={12}
              color="macro-calories"
              showValue={false}
            />
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <span className="text-3xl font-bold text-foreground">{remaining}</span>
              <span className="text-sm text-muted-foreground">{t('dashboard.remaining')}</span>
            </div>
          </div>
          <div className="flex items-center gap-6 text-sm">
            <div className="text-center">
              <p className="font-semibold text-foreground">{calories.target}</p>
              <p className="text-muted-foreground">{t('dashboard.target')}</p>
            </div>
            <div className="h-8 w-px bg-border" />
            <div className="text-center">
              <p className="font-semibold text-foreground">{calories.current}</p>
              <p className="text-muted-foreground">{t('dashboard.consumed')}</p>
            </div>
          </div>
        </div>

        {/* Macro Bars */}
        <div className="space-y-4">
          <MacroBar
            label={t('settings.goals.protein')}
            current={protein.current}
            target={protein.target}
            color="protein"
          />
          <MacroBar
            label={t('settings.goals.carbs')}
            current={carbs.current}
            target={carbs.target}
            color="carbs"
          />
          <MacroBar
            label={t('settings.goals.fat')}
            current={fat.current}
            target={fat.target}
            color="fat"
          />
        </div>
      </CardContent>
    </Card>
  );
}

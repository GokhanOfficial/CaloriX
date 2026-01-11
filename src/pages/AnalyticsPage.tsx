import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Skeleton } from "@/components/ui/skeleton";
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  BarChart,
  Bar,
  LineChart,
  Line,
  ReferenceLine,
  ComposedChart,
  Legend,
} from "recharts";
import { useAnalyticsData } from "@/hooks/useAnalyticsData";
import { useProfile } from "@/contexts/ProfileContext";
import { DEFAULT_GOALS } from "@/lib/constants";
import { Flame, Droplets, Scale, TrendingUp, TrendingDown, Target } from "lucide-react";

type Period = "week" | "month" | "3months";

const AnalyticsPage = () => {
  const [period, setPeriod] = useState<Period>("week");
  const { dailyStats, weightTrend, averages, loading } = useAnalyticsData(period);
  const { profile } = useProfile();

  // Get targets from profile or use defaults
  const targets = {
    calories: profile?.daily_calorie_target || DEFAULT_GOALS.calories,
    protein: profile?.protein_target_g || DEFAULT_GOALS.protein,
    carbs: profile?.carbs_target_g || DEFAULT_GOALS.carbs,
    fat: profile?.fat_target_g || DEFAULT_GOALS.fat,
    water: profile?.daily_water_target_ml || DEFAULT_GOALS.water,
  };

  // Calculate macro percentages for charts (normalized to 100% target)
  const macroChartData = dailyStats.map((day) => ({
    ...day,
    proteinPercent: Math.round((day.protein / targets.protein) * 100),
    carbsPercent: Math.round((day.carbs / targets.carbs) * 100),
    fatPercent: Math.round((day.fat / targets.fat) * 100),
    caloriesPercent: Math.round((day.calories / targets.calories) * 100),
  }));

  // Weight change calculation
  const firstWeight = weightTrend[0]?.weight;
  const lastWeight = weightTrend[weightTrend.length - 1]?.weight;
  const weightChange = lastWeight && firstWeight ? lastWeight - firstWeight : 0;
  const weightChangePercent = firstWeight ? ((weightChange / firstWeight) * 100).toFixed(1) : "0";

  // Average percentage vs target
  const avgCaloriesPercent = Math.round((averages.avgCalories / targets.calories) * 100);
  const avgProteinPercent = Math.round((averages.avgProtein / targets.protein) * 100);
  const avgCarbsPercent = Math.round((averages.avgCarbs / targets.carbs) * 100);
  const avgFatPercent = Math.round((averages.avgFat / targets.fat) * 100);
  const avgWaterPercent = Math.round((averages.avgWater / targets.water) * 100);

  if (loading) {
    return (
      <AppLayout title="Analiz">
        <div className="container max-w-lg space-y-4 px-4 py-4">
          <Skeleton className="h-10 w-full" />
          <div className="grid grid-cols-2 gap-3">
            <Skeleton className="h-24" />
            <Skeleton className="h-24" />
            <Skeleton className="h-24" />
            <Skeleton className="h-24" />
          </div>
          <Skeleton className="h-64 w-full" />
          <Skeleton className="h-64 w-full" />
        </div>
      </AppLayout>
    );
  }

  return (
    <AppLayout title="Analiz">
      <div className="container max-w-lg space-y-4 px-4 py-4">
        {/* Period Tabs */}
        <Tabs value={period} onValueChange={(v) => setPeriod(v as Period)} className="w-full">
          <TabsList className="grid w-full grid-cols-3 bg-secondary">
            <TabsTrigger value="week">Hafta</TabsTrigger>
            <TabsTrigger value="month">Ay</TabsTrigger>
            <TabsTrigger value="3months">3 Ay</TabsTrigger>
          </TabsList>
        </Tabs>

        {/* Average Stats Cards */}
        <div className="grid grid-cols-2 gap-3">
          <Card className="border-none bg-card shadow-lg">
            <CardContent className="p-4">
              <div className="flex items-center gap-2 mb-2">
                <Flame className="h-4 w-4 text-primary" />
                <span className="text-xs text-muted-foreground">Ort. Kalori</span>
              </div>
              <p className="text-xl font-bold text-foreground">{averages.avgCalories}</p>
              <div className="flex items-center gap-1 mt-1">
                <span className={`text-xs ${avgCaloriesPercent >= 90 && avgCaloriesPercent <= 110 ? 'text-success' : avgCaloriesPercent < 90 ? 'text-warning' : 'text-destructive'}`}>
                  %{avgCaloriesPercent}
                </span>
                <span className="text-xs text-muted-foreground">/ hedef</span>
              </div>
            </CardContent>
          </Card>

          <Card className="border-none bg-card shadow-lg">
            <CardContent className="p-4">
              <div className="flex items-center gap-2 mb-2">
                <Droplets className="h-4 w-4 text-blue-400" />
                <span className="text-xs text-muted-foreground">Ort. Su</span>
              </div>
              <p className="text-xl font-bold text-foreground">{averages.avgWater} ml</p>
              <div className="flex items-center gap-1 mt-1">
                <span className={`text-xs ${avgWaterPercent >= 80 ? 'text-success' : 'text-warning'}`}>
                  %{avgWaterPercent}
                </span>
                <span className="text-xs text-muted-foreground">/ hedef</span>
              </div>
            </CardContent>
          </Card>

          <Card className="border-none bg-card shadow-lg">
            <CardContent className="p-4">
              <div className="flex items-center gap-2 mb-2">
                <Target className="h-4 w-4 text-macro-protein" />
                <span className="text-xs text-muted-foreground">Ort. Protein</span>
              </div>
              <p className="text-xl font-bold text-foreground">{averages.avgProtein}g</p>
              <div className="flex items-center gap-1 mt-1">
                <span className={`text-xs ${avgProteinPercent >= 90 ? 'text-success' : 'text-warning'}`}>
                  %{avgProteinPercent}
                </span>
                <span className="text-xs text-muted-foreground">/ hedef</span>
              </div>
            </CardContent>
          </Card>

          <Card className="border-none bg-card shadow-lg">
            <CardContent className="p-4">
              <div className="flex items-center gap-2 mb-2">
                <Scale className="h-4 w-4 text-success" />
                <span className="text-xs text-muted-foreground">Kilo Değişimi</span>
              </div>
              <p className="text-xl font-bold text-foreground">
                {weightChange > 0 ? '+' : ''}{weightChange.toFixed(1)} kg
              </p>
              <div className="flex items-center gap-1 mt-1">
                {weightChange < 0 ? (
                  <TrendingDown className="h-3 w-3 text-success" />
                ) : weightChange > 0 ? (
                  <TrendingUp className="h-3 w-3 text-warning" />
                ) : null}
                <span className={`text-xs ${weightChange <= 0 ? 'text-success' : 'text-warning'}`}>
                  %{weightChangePercent}
                </span>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Calories Chart */}
        <Card className="border-none bg-card shadow-lg">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center justify-between">
              <span>Kalori Takibi</span>
              <span className="text-xs text-muted-foreground font-normal">
                Hedef: {targets.calories} kcal
              </span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={200}>
              <ComposedChart data={macroChartData}>
                <defs>
                  <linearGradient id="colorCalories" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <XAxis
                  dataKey="dayLabel"
                  axisLine={false}
                  tickLine={false}
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 10 }}
                  interval={period === "week" ? 0 : "preserveStartEnd"}
                />
                <YAxis
                  hide
                  domain={[0, Math.max(150, ...macroChartData.map((d) => d.caloriesPercent + 20))]}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: "hsl(var(--card))",
                    border: "1px solid hsl(var(--border))",
                    borderRadius: "8px",
                  }}
                  formatter={(value: number, name: string) => {
                    if (name === "caloriesPercent") {
                      return [`%${value} (${macroChartData.find(d => d.caloriesPercent === value)?.calories || 0} kcal)`, "Kalori"];
                    }
                    return [value, name];
                  }}
                />
                <ReferenceLine
                  y={100}
                  stroke="hsl(var(--success))"
                  strokeDasharray="5 5"
                  strokeWidth={2}
                  label={{
                    value: "100%",
                    position: "right",
                    fill: "hsl(var(--success))",
                    fontSize: 10,
                  }}
                />
                <Area
                  type="monotone"
                  dataKey="caloriesPercent"
                  stroke="hsl(var(--primary))"
                  strokeWidth={2}
                  fill="url(#colorCalories)"
                  name="caloriesPercent"
                />
              </ComposedChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        {/* Macros Chart with Target Line */}
        <Card className="border-none bg-card shadow-lg">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center justify-between">
              <span>Makro Takibi (Hedefe Göre %)</span>
              <span className="text-xs text-muted-foreground font-normal">
                Çizgi = %100 hedef
              </span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={macroChartData} barGap={2}>
                <XAxis
                  dataKey="dayLabel"
                  axisLine={false}
                  tickLine={false}
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 10 }}
                  interval={period === "week" ? 0 : "preserveStartEnd"}
                />
                <YAxis
                  hide
                  domain={[0, Math.max(150, ...macroChartData.flatMap((d) => [d.proteinPercent, d.carbsPercent, d.fatPercent]), 20)]}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: "hsl(var(--card))",
                    border: "1px solid hsl(var(--border))",
                    borderRadius: "8px",
                  }}
                  formatter={(value: number, name: string) => {
                    const labels: Record<string, string> = {
                      proteinPercent: "Protein",
                      carbsPercent: "Karbonhidrat",
                      fatPercent: "Yağ",
                    };
                    return [`%${value}`, labels[name] || name];
                  }}
                />
                <ReferenceLine
                  y={100}
                  stroke="hsl(var(--success))"
                  strokeDasharray="5 5"
                  strokeWidth={2}
                />
                <Bar dataKey="proteinPercent" fill="hsl(210, 100%, 56%)" radius={[4, 4, 0, 0]} maxBarSize={20} />
                <Bar dataKey="carbsPercent" fill="hsl(38, 92%, 50%)" radius={[4, 4, 0, 0]} maxBarSize={20} />
                <Bar dataKey="fatPercent" fill="hsl(340, 82%, 52%)" radius={[4, 4, 0, 0]} maxBarSize={20} />
              </BarChart>
            </ResponsiveContainer>
            <div className="mt-3 flex justify-center gap-4">
              <div className="flex items-center gap-2">
                <div className="h-3 w-3 rounded-full" style={{ backgroundColor: "hsl(210, 100%, 56%)" }} />
                <span className="text-xs text-muted-foreground">P: {targets.protein}g</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="h-3 w-3 rounded-full" style={{ backgroundColor: "hsl(38, 92%, 50%)" }} />
                <span className="text-xs text-muted-foreground">K: {targets.carbs}g</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="h-3 w-3 rounded-full" style={{ backgroundColor: "hsl(340, 82%, 52%)" }} />
                <span className="text-xs text-muted-foreground">Y: {targets.fat}g</span>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Macro Averages Detail */}
        <Card className="border-none bg-card shadow-lg">
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Ortalama Makro Değerleri</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Protein</span>
                <span className="font-medium text-foreground">{averages.avgProtein}g / {targets.protein}g</span>
              </div>
              <div className="h-2 bg-secondary rounded-full overflow-hidden">
                <div
                  className="h-full rounded-full transition-all"
                  style={{
                    width: `${Math.min(avgProteinPercent, 100)}%`,
                    backgroundColor: "hsl(210, 100%, 56%)",
                  }}
                />
              </div>
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Karbonhidrat</span>
                <span className="font-medium text-foreground">{averages.avgCarbs}g / {targets.carbs}g</span>
              </div>
              <div className="h-2 bg-secondary rounded-full overflow-hidden">
                <div
                  className="h-full rounded-full transition-all"
                  style={{
                    width: `${Math.min(avgCarbsPercent, 100)}%`,
                    backgroundColor: "hsl(38, 92%, 50%)",
                  }}
                />
              </div>
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Yağ</span>
                <span className="font-medium text-foreground">{averages.avgFat}g / {targets.fat}g</span>
              </div>
              <div className="h-2 bg-secondary rounded-full overflow-hidden">
                <div
                  className="h-full rounded-full transition-all"
                  style={{
                    width: `${Math.min(avgFatPercent, 100)}%`,
                    backgroundColor: "hsl(340, 82%, 52%)",
                  }}
                />
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Weight Trend */}
        {weightTrend.length > 0 && (
          <Card className="border-none bg-card shadow-lg">
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Kilo Değişimi</CardTitle>
            </CardHeader>
            <CardContent>
              <ResponsiveContainer width="100%" height={180}>
                <LineChart data={weightTrend}>
                  <XAxis
                    dataKey="dateLabel"
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 10 }}
                    interval="preserveStartEnd"
                  />
                  <YAxis hide domain={["dataMin - 1", "dataMax + 1"]} />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: "hsl(var(--card))",
                      border: "1px solid hsl(var(--border))",
                      borderRadius: "8px",
                    }}
                    formatter={(value: number) => [`${value} kg`, "Kilo"]}
                  />
                  <Line
                    type="monotone"
                    dataKey="weight"
                    stroke="hsl(var(--success))"
                    strokeWidth={2}
                    dot={{ fill: "hsl(var(--success))", strokeWidth: 0, r: 3 }}
                    activeDot={{ r: 6, fill: "hsl(var(--success))" }}
                  />
                </LineChart>
              </ResponsiveContainer>
              <div className="mt-4 flex justify-between text-sm">
                <div>
                  <p className="text-muted-foreground">İlk Kayıt</p>
                  <p className="font-semibold text-foreground">{firstWeight?.toFixed(1) || "-"} kg</p>
                </div>
                <div className="text-center">
                  <p className="text-muted-foreground">Değişim</p>
                  <p className={`font-semibold ${weightChange <= 0 ? 'text-success' : 'text-warning'}`}>
                    {weightChange > 0 ? '+' : ''}{weightChange.toFixed(1)} kg
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-muted-foreground">Son Kayıt</p>
                  <p className="font-semibold text-foreground">{lastWeight?.toFixed(1) || "-"} kg</p>
                </div>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Data Summary */}
        <Card className="border-none bg-card shadow-lg">
          <CardContent className="p-4">
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">Veri bulunan gün sayısı</span>
              <span className="font-medium text-foreground">
                {averages.daysWithData} / {averages.totalDays} gün
              </span>
            </div>
          </CardContent>
        </Card>
      </div>
    </AppLayout>
  );
};

export default AnalyticsPage;

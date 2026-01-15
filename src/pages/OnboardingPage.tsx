import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { useProfile } from "@/contexts/ProfileContext";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Progress } from "@/components/ui/progress";
import { useToast } from "@/hooks/use-toast";
import {
  Loader2,
  ChevronLeft,
  ChevronRight,
  User,
  Ruler,
  Activity,
  Target,
  Sparkles,
  Check
} from "lucide-react";
import { z } from "zod";
import {
  calculateBMR,
  calculateTDEE,
  calculateTargetCalories,
  calculateMacros,
  calculateBMI,
  getBMICategory
} from "@/lib/calculations";
import { ACTIVITY_LEVELS, GOALS, HEALTH_DISCLAIMER, type ActivityLevel, type Goal } from "@/lib/constants";
import { cn } from "@/lib/utils";
import { useTranslation } from "react-i18next";

const TOTAL_STEPS = 5;

// Validation schemas
const personalInfoSchema = z.object({
  displayName: z.string().min(2, "İsim en az 2 karakter olmalı").max(50),
  birthDate: z.string().refine((date) => {
    const age = calculateAge(new Date(date));
    return age >= 13 && age <= 120;
  }, "Yaş 13-120 arasında olmalı"),
  gender: z.enum(["male", "female", "other"]),
});

const bodyInfoSchema = z.object({
  heightCm: z.number().min(100, "Boy en az 100 cm olmalı").max(250, "Boy en fazla 250 cm olabilir"),
  currentWeightKg: z.number().min(30, "Kilo en az 30 kg olmalı").max(300, "Kilo en fazla 300 kg olabilir"),
  targetWeightKg: z.number().min(30, "Hedef kilo en az 30 kg olmalı").max(300, "Hedef kilo en fazla 300 kg olabilir"),
});

function calculateAge(birthDate: Date): number {
  const today = new Date();
  let age = today.getFullYear() - birthDate.getFullYear();
  const monthDiff = today.getMonth() - birthDate.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
    age--;
  }
  return age;
}

export default function OnboardingPage() {
  const [step, setStep] = useState(1);
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isCalculating, setIsCalculating] = useState(false);
  const [hasCalculated, setHasCalculated] = useState(false);

  // Form state
  const [displayName, setDisplayName] = useState("");
  const [birthDate, setBirthDate] = useState("");
  const [gender, setGender] = useState<"male" | "female" | "other">("male");
  const [heightCm, setHeightCm] = useState<number>(170);
  const [currentWeightKg, setCurrentWeightKg] = useState<number>(70);
  const [targetWeightKg, setTargetWeightKg] = useState<number>(70);
  const [activityLevel, setActivityLevel] = useState<ActivityLevel>("moderate");
  const [goal, setGoal] = useState<Goal>("maintain");

  // Calculated values
  const [calculatedGoals, setCalculatedGoals] = useState<{
    bmr: number;
    tdee: number;
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
    bmi: number;
    waterTarget: number;
    explanation?: string;
  } | null>(null);

  const [errors, setErrors] = useState<Record<string, string>>({});

  const { user } = useAuth();
  const { profile, refetch: refetchProfile } = useProfile();
  const navigate = useNavigate();
  const { toast } = useToast();
  const { t } = useTranslation();

  // Load existing profile data
  useEffect(() => {
    async function loadProfile() {
      if (!user) return;

      setIsLoading(true);
      const { data, error } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", user.id)
        .single();

      if (data && !error) {
        if (data.onboarding_completed) {
          navigate("/", { replace: true });
          return;
        }

        if (data.display_name) setDisplayName(data.display_name);
        if (data.birth_date) setBirthDate(data.birth_date);
        if (data.gender) setGender(data.gender as "male" | "female" | "other");
        if (data.height_cm) setHeightCm(Number(data.height_cm));
        if (data.current_weight_kg) setCurrentWeightKg(Number(data.current_weight_kg));
        if (data.target_weight_kg) setTargetWeightKg(Number(data.target_weight_kg));
        if (data.activity_level) setActivityLevel(data.activity_level as ActivityLevel);
        if (data.goal) setGoal(data.goal as Goal);
      }
      setIsLoading(false);
    }

    loadProfile();
  }, [user, navigate]);

  // Calculate goals using AI when moving to step 5
  const calculateWithAI = async (): Promise<boolean> => {
    if (!birthDate || !heightCm || !currentWeightKg) return false;

    setIsCalculating(true);

    try {
      const age = calculateAge(new Date(birthDate));
      const bmi = calculateBMI(currentWeightKg, heightCm);

      const { data, error } = await supabase.functions.invoke('calculate-macros', {
        body: {
          age,
          gender,
          height_cm: heightCm,
          current_weight_kg: currentWeightKg,
          target_weight_kg: targetWeightKg,
          activity_level: activityLevel,
          goal,
        },
      });

      if (error) {
        console.error('AI calculation error:', error);
        // Fallback to local calculation
        const genderForCalc = gender === "other" ? "male" : gender;
        const bmr = calculateBMR({ weight: currentWeightKg, height: heightCm, age, gender: genderForCalc });
        const tdee = calculateTDEE(bmr, activityLevel);
        const targetCalories = calculateTargetCalories(tdee, goal);
        const macros = calculateMacros(targetCalories);
        const calculatedWater = Math.round(currentWeightKg * 33);

        setCalculatedGoals({
          bmr,
          tdee,
          calories: targetCalories,
          protein: macros.protein,
          carbs: macros.carbs,
          fat: macros.fat,
          bmi,
          waterTarget: calculatedWater,
        });

        toast({
          title: "Bilgi",
          description: "AI hesaplama yapılamadı, yerel formüller kullanıldı",
        });
      } else {
        setCalculatedGoals({
          bmr: data.bmr,
          tdee: data.tdee,
          calories: data.daily_calorie_target,
          protein: data.protein_target_g,
          carbs: data.carbs_target_g,
          fat: data.fat_target_g,
          bmi,
          waterTarget: data.daily_water_target_ml,
          explanation: data.explanation,
        });

        toast({
          title: "AI Hesaplama Tamamlandı ✨",
          description: data.explanation || "Hedefleriniz hesaplandı",
        });
      }

      setHasCalculated(true);
      return true;
    } catch (err) {
      console.error('Error calculating with AI:', err);
      // Fallback to local calculation
      const age = calculateAge(new Date(birthDate));
      const genderForCalc = gender === "other" ? "male" : gender;
      const bmr = calculateBMR({ weight: currentWeightKg, height: heightCm, age, gender: genderForCalc });
      const tdee = calculateTDEE(bmr, activityLevel);
      const targetCalories = calculateTargetCalories(tdee, goal);
      const macros = calculateMacros(targetCalories);
      const bmi = calculateBMI(currentWeightKg, heightCm);
      const calculatedWater = Math.round(currentWeightKg * 33);

      setCalculatedGoals({
        bmr,
        tdee,
        calories: targetCalories,
        protein: macros.protein,
        carbs: macros.carbs,
        fat: macros.fat,
        bmi,
        waterTarget: calculatedWater,
      });

      setHasCalculated(true);
      return true;
    } finally {
      setIsCalculating(false);
    }
  };

  const validateStep = (stepNumber: number): boolean => {
    setErrors({});

    try {
      switch (stepNumber) {
        case 1:
          personalInfoSchema.parse({ displayName, birthDate, gender });
          return true;
        case 2:
          bodyInfoSchema.parse({ heightCm, currentWeightKg, targetWeightKg });
          return true;
        case 3:
        case 4:
        case 5:
          return true;
        default:
          return true;
      }
    } catch (error) {
      if (error instanceof z.ZodError) {
        const newErrors: Record<string, string> = {};
        error.errors.forEach((err) => {
          if (err.path[0]) {
            newErrors[err.path[0].toString()] = err.message;
          }
        });
        setErrors(newErrors);
      }
      return false;
    }
  };

  const handleNext = async () => {
    if (validateStep(step)) {
      const nextStep = step + 1;

      // Trigger AI calculation only once when moving from step 4 to step 5 (summary)
      if (nextStep === TOTAL_STEPS && !hasCalculated) {
        setStep(nextStep);
        await calculateWithAI();
      } else {
        setStep(Math.min(nextStep, TOTAL_STEPS));
      }
    }
  };

  const handleBack = () => {
    // Reset calculation state if going back from step 5
    if (step === 5) {
      setHasCalculated(false);
      setCalculatedGoals(null);
    }
    setStep((prev) => Math.max(prev - 1, 1));
  };

  const handleComplete = async () => {
    if (!user || !calculatedGoals) return;

    setIsSaving(true);

    const { error } = await supabase
      .from("profiles")
      .update({
        display_name: displayName,
        birth_date: birthDate,
        gender,
        height_cm: heightCm,
        current_weight_kg: currentWeightKg,
        target_weight_kg: targetWeightKg,
        activity_level: activityLevel,
        goal,
        bmr: calculatedGoals.bmr,
        tdee: calculatedGoals.tdee,
        daily_calorie_target: calculatedGoals.calories,
        protein_target_g: calculatedGoals.protein,
        carbs_target_g: calculatedGoals.carbs,
        fat_target_g: calculatedGoals.fat,
        daily_water_target_ml: calculatedGoals.waterTarget,
        onboarding_completed: true,
        updated_at: new Date().toISOString(),
      })
      .eq("id", user.id);

    setIsSaving(false);

    if (error) {
      toast({
        title: "Hata",
        description: "Profil kaydedilirken bir hata oluştu",
        variant: "destructive",
      });
      return;
    }

    // Refetch profile to update context state
    await refetchProfile();

    toast({
      title: "Hoş Geldiniz! 🎉",
      description: "Profiliniz başarıyla oluşturuldu",
    });

    navigate("/", { replace: true });
  };

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  const progress = (step / TOTAL_STEPS) * 100;

  return (
    <div className="min-h-screen bg-background p-4">
      <div className="max-w-lg mx-auto">
        {/* Header */}
        <div className="text-center mb-6 pt-4">
          <h1 className="text-3xl font-bold text-gradient mb-2">CaloriX</h1>
          <p className="text-muted-foreground text-sm">
            Profilinizi oluşturalım
          </p>
        </div>

        {/* Progress */}
        <div className="mb-6">
          <div className="flex justify-between text-xs text-muted-foreground mb-2">
            <span>Adım {step} / {TOTAL_STEPS}</span>
            <span>{Math.round(progress)}%</span>
          </div>
          <Progress value={progress} className="h-2" />
        </div>

        {/* Step Content */}
        <Card className="glass animate-fade-in">
          {/* Step 1: Personal Info */}
          {step === 1 && (
            <>
              <CardHeader>
                <div className="flex items-center gap-2 text-primary mb-2">
                  <User className="h-5 w-5" />
                  <span className="text-sm font-medium">Kişisel Bilgiler</span>
                </div>
                <CardTitle>Sizi Tanıyalım</CardTitle>
                <CardDescription>
                  Temel bilgilerinizi girin
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="displayName">İsminiz</Label>
                  <Input
                    id="displayName"
                    placeholder="Adınız"
                    value={displayName}
                    onChange={(e) => setDisplayName(e.target.value)}
                  />
                  {errors.displayName && (
                    <p className="text-xs text-destructive">{errors.displayName}</p>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="birthDate">Doğum Tarihi</Label>
                  <Input
                    id="birthDate"
                    type="date"
                    value={birthDate}
                    onChange={(e) => setBirthDate(e.target.value)}
                    max={new Date().toISOString().split("T")[0]}
                  />
                  {errors.birthDate && (
                    <p className="text-xs text-destructive">{errors.birthDate}</p>
                  )}
                </div>

                <div className="space-y-2">
                  <Label>Cinsiyet</Label>
                  <RadioGroup
                    value={gender}
                    onValueChange={(v) => setGender(v as "male" | "female" | "other")}
                    className="flex gap-4"
                  >
                    <div className="flex items-center space-x-2">
                      <RadioGroupItem value="male" id="male" />
                      <Label htmlFor="male" className="cursor-pointer">Erkek</Label>
                    </div>
                    <div className="flex items-center space-x-2">
                      <RadioGroupItem value="female" id="female" />
                      <Label htmlFor="female" className="cursor-pointer">Kadın</Label>
                    </div>
                    <div className="flex items-center space-x-2">
                      <RadioGroupItem value="other" id="other" />
                      <Label htmlFor="other" className="cursor-pointer">Diğer</Label>
                    </div>
                  </RadioGroup>
                </div>
              </CardContent>
            </>
          )}

          {/* Step 2: Body Measurements */}
          {step === 2 && (
            <>
              <CardHeader>
                <div className="flex items-center gap-2 text-primary mb-2">
                  <Ruler className="h-5 w-5" />
                  <span className="text-sm font-medium">Vücut Ölçüleri</span>
                </div>
                <CardTitle>Boy ve Kilo</CardTitle>
                <CardDescription>
                  Mevcut ve hedef değerlerinizi girin
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="height">Boy (cm)</Label>
                  <Input
                    id="height"
                    type="number"
                    placeholder="170"
                    value={heightCm || ""}
                    onChange={(e) => setHeightCm(Number(e.target.value))}
                    min={100}
                    max={250}
                  />
                  {errors.heightCm && (
                    <p className="text-xs text-destructive">{errors.heightCm}</p>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="currentWeight">Mevcut Kilo (kg)</Label>
                  <Input
                    id="currentWeight"
                    type="number"
                    step="0.1"
                    placeholder="70"
                    value={currentWeightKg || ""}
                    onChange={(e) => setCurrentWeightKg(Number(e.target.value))}
                    min={30}
                    max={300}
                  />
                  {errors.currentWeightKg && (
                    <p className="text-xs text-destructive">{errors.currentWeightKg}</p>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="targetWeight">Hedef Kilo (kg)</Label>
                  <Input
                    id="targetWeight"
                    type="number"
                    step="0.1"
                    placeholder="65"
                    value={targetWeightKg || ""}
                    onChange={(e) => setTargetWeightKg(Number(e.target.value))}
                    min={30}
                    max={300}
                  />
                  {errors.targetWeightKg && (
                    <p className="text-xs text-destructive">{errors.targetWeightKg}</p>
                  )}
                </div>

                {calculatedGoals && (
                  <div className="p-3 rounded-lg bg-secondary/50 border border-border">
                    <p className="text-sm text-muted-foreground">
                      <span className="font-medium text-foreground">BMI:</span>{" "}
                      {calculatedGoals.bmi} - {" "}
                      <span className={cn(
                        "font-medium",
                        getBMICategory(calculatedGoals.bmi).color === "success" && "text-success",
                        getBMICategory(calculatedGoals.bmi).color === "warning" && "text-warning",
                        getBMICategory(calculatedGoals.bmi).color === "destructive" && "text-destructive",
                        getBMICategory(calculatedGoals.bmi).color === "info" && "text-info"
                      )}>
                        {t(getBMICategory(calculatedGoals.bmi).labelKey)}
                      </span>
                    </p>
                  </div>
                )}
              </CardContent>
            </>
          )}

          {/* Step 3: Activity Level */}
          {step === 3 && (
            <>
              <CardHeader>
                <div className="flex items-center gap-2 text-primary mb-2">
                  <Activity className="h-5 w-5" />
                  <span className="text-sm font-medium">Aktivite Seviyesi</span>
                </div>
                <CardTitle>Ne Kadar Aktifsiniz?</CardTitle>
                <CardDescription>
                  Günlük aktivite seviyenizi seçin
                </CardDescription>
              </CardHeader>
              <CardContent>
                <RadioGroup
                  value={activityLevel}
                  onValueChange={(v) => setActivityLevel(v as ActivityLevel)}
                  className="space-y-3"
                >
                  {Object.entries(ACTIVITY_LEVELS).map(([key, level]) => (
                    <div
                      key={key}
                      className={cn(
                        "flex items-center space-x-3 p-3 rounded-lg border transition-colors cursor-pointer",
                        activityLevel === key
                          ? "border-primary bg-primary/5"
                          : "border-border hover:border-primary/50"
                      )}
                      onClick={() => setActivityLevel(key as ActivityLevel)}
                    >
                      <RadioGroupItem value={key} id={key} />
                      <div className="flex-1">
                        <Label htmlFor={key} className="cursor-pointer font-medium">
                          {level.label}
                        </Label>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          {key === "sedentary" && "Masa başı iş, az hareket"}
                          {key === "light" && "Hafif egzersiz, haftada 1-3 gün"}
                          {key === "moderate" && "Orta egzersiz, haftada 3-5 gün"}
                          {key === "active" && "Yoğun egzersiz, haftada 6-7 gün"}
                          {key === "veryActive" && "Çok yoğun egzersiz veya fiziksel iş"}
                        </p>
                      </div>
                    </div>
                  ))}
                </RadioGroup>
              </CardContent>
            </>
          )}

          {/* Step 4: Goal */}
          {step === 4 && (
            <>
              <CardHeader>
                <div className="flex items-center gap-2 text-primary mb-2">
                  <Target className="h-5 w-5" />
                  <span className="text-sm font-medium">Hedef</span>
                </div>
                <CardTitle>Hedefiniz Nedir?</CardTitle>
                <CardDescription>
                  Kilo hedefinizi belirleyin
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <RadioGroup
                  value={goal}
                  onValueChange={(v) => setGoal(v as Goal)}
                  className="space-y-3"
                >
                  {Object.entries(GOALS).map(([key, g]) => (
                    <div
                      key={key}
                      className={cn(
                        "flex items-center space-x-3 p-4 rounded-lg border transition-colors cursor-pointer",
                        goal === key
                          ? "border-primary bg-primary/5"
                          : "border-border hover:border-primary/50"
                      )}
                      onClick={() => setGoal(key as Goal)}
                    >
                      <RadioGroupItem value={key} id={`goal-${key}`} />
                      <div className="flex-1">
                        <Label htmlFor={`goal-${key}`} className="cursor-pointer font-medium text-base">
                          {g.label}
                        </Label>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          {key === "lose" && "Günlük 500 kcal açık (haftada ~0.5 kg)"}
                          {key === "maintain" && "Mevcut kilonuzu koruyun"}
                          {key === "gain" && "Günlük 500 kcal fazla (haftada ~0.5 kg)"}
                        </p>
                      </div>
                    </div>
                  ))}
                </RadioGroup>
              </CardContent>
            </>
          )}

          {/* Step 5: Summary */}
          {step === 5 && (
            <>
              {isCalculating ? (
                <>
                  <CardHeader>
                    <div className="flex items-center gap-2 text-primary mb-2">
                      <Sparkles className="h-5 w-5 animate-pulse" />
                      <span className="text-sm font-medium">AI Hesaplıyor</span>
                    </div>
                    <CardTitle>Hedefleriniz Hesaplanıyor...</CardTitle>
                    <CardDescription>
                      AI, verilerinize göre en uygun hedefleri belirliyor
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <div className="flex flex-col items-center justify-center py-12 gap-6">
                      <div className="relative">
                        <Loader2 className="h-16 w-16 animate-spin text-primary" />
                        <Sparkles className="h-6 w-6 text-primary absolute -top-1 -right-1 animate-pulse" />
                      </div>
                      <div className="text-center space-y-2">
                        <p className="text-sm text-muted-foreground">
                          Kalori, makro besinler ve su hedefi hesaplanıyor...
                        </p>
                        <p className="text-xs text-muted-foreground/70">
                          Bu işlem birkaç saniye sürebilir
                        </p>
                      </div>
                    </div>
                  </CardContent>
                </>
              ) : calculatedGoals ? (
                <>
                  <CardHeader>
                    <div className="flex items-center gap-2 text-primary mb-2">
                      <Sparkles className="h-5 w-5" />
                      <span className="text-sm font-medium">AI ile Hesaplandı</span>
                    </div>
                    <CardTitle>Hedefleriniz Hazır! 🎉</CardTitle>
                    <CardDescription>
                      {calculatedGoals.explanation || "AI tarafından hesaplanan günlük hedefleriniz"}
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    {/* Calculated Goals */}
                    <div className="grid grid-cols-2 gap-3">
                      <div className="p-3 rounded-lg bg-secondary/50 border border-border text-center">
                        <p className="text-2xl font-bold text-primary">{calculatedGoals.calories}</p>
                        <p className="text-xs text-muted-foreground">Kalori (kcal)</p>
                      </div>
                      <div className="p-3 rounded-lg bg-secondary/50 border border-border text-center">
                        <p className="text-2xl font-bold text-[hsl(var(--macro-protein))]">{calculatedGoals.protein}g</p>
                        <p className="text-xs text-muted-foreground">Protein</p>
                      </div>
                      <div className="p-3 rounded-lg bg-secondary/50 border border-border text-center">
                        <p className="text-2xl font-bold text-[hsl(var(--macro-carbs))]">{calculatedGoals.carbs}g</p>
                        <p className="text-xs text-muted-foreground">Karbonhidrat</p>
                      </div>
                      <div className="p-3 rounded-lg bg-secondary/50 border border-border text-center">
                        <p className="text-2xl font-bold text-[hsl(var(--macro-fat))]">{calculatedGoals.fat}g</p>
                        <p className="text-xs text-muted-foreground">Yağ</p>
                      </div>
                    </div>

                    {/* Additional Info */}
                    <div className="p-3 rounded-lg bg-card border border-border space-y-2">
                      <div className="flex justify-between text-sm">
                        <span className="text-muted-foreground">BMR (Bazal Metabolizma)</span>
                        <span className="font-medium">{calculatedGoals.bmr} kcal</span>
                      </div>
                      <div className="flex justify-between text-sm">
                        <span className="text-muted-foreground">TDEE (Günlük Harcama)</span>
                        <span className="font-medium">{calculatedGoals.tdee} kcal</span>
                      </div>
                      <div className="flex justify-between text-sm">
                        <span className="text-muted-foreground">Su Hedefi</span>
                        <span className="font-medium">{calculatedGoals.waterTarget} ml</span>
                      </div>
                    </div>

                    {/* Health Disclaimer */}
                    <div className="p-3 rounded-lg bg-warning/10 border border-warning/30">
                      <p className="text-xs text-warning-foreground">
                        ⚠️ {HEALTH_DISCLAIMER.trim()}
                      </p>
                    </div>

                    <p className="text-xs text-muted-foreground text-center">
                      Bu değerleri daha sonra Ayarlar'dan değiştirebilirsiniz.
                    </p>
                  </CardContent>
                </>
              ) : (
                <>
                  <CardHeader>
                    <CardTitle>Hesaplama Başarısız</CardTitle>
                    <CardDescription>
                      Lütfen geri dönüp tekrar deneyin
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <div className="text-center py-8">
                      <p className="text-sm text-muted-foreground">Hedefler hesaplanamadı</p>
                    </div>
                  </CardContent>
                </>
              )}
            </>
          )}

          {/* Navigation Buttons */}
          <div className="p-6 pt-0 flex gap-3">
            {step > 1 && (
              <Button
                variant="outline"
                onClick={handleBack}
                disabled={isSaving}
                className="flex-1"
              >
                <ChevronLeft className="mr-1 h-4 w-4" />
                Geri
              </Button>
            )}

            {step < TOTAL_STEPS ? (
              <Button onClick={handleNext} disabled={isCalculating} className="flex-1">
                {isCalculating ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Hesaplanıyor...
                  </>
                ) : (
                  <>
                    İleri
                    <ChevronRight className="ml-1 h-4 w-4" />
                  </>
                )}
              </Button>
            ) : (
              <Button
                onClick={handleComplete}
                disabled={isSaving || isCalculating || !calculatedGoals}
                className="flex-1"
              >
                {isSaving ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Kaydediliyor...
                  </>
                ) : (
                  <>
                    <Check className="mr-2 h-4 w-4" />
                    Tamamla
                  </>
                )}
              </Button>
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}

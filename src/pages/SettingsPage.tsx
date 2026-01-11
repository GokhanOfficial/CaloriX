import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { AppLayout } from "@/components/layout/AppLayout";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import { Input } from "@/components/ui/input";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  User,
  Target,
  Bell,
  Download,
  Upload,
  Info,
  ChevronRight,
  Moon,
  Sun,
  Loader2,
  Sparkles,
  Scale,
  LogOut,
  KeyRound,
} from "lucide-react";
import { useTheme } from "@/hooks/useTheme";
import { useProfile } from "@/contexts/ProfileContext";
import { HEALTH_DISCLAIMER, ACTIVITY_LEVELS, GOALS, type ActivityLevel, type Goal } from "@/lib/constants";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import {
  calculateBMI,
  getBMICategory,
} from "@/lib/calculations";
import { supabase } from "@/integrations/supabase/client";
import { NotificationPreferences } from "@/components/notifications/NotificationPreferences";
import { useDataExport } from "@/hooks/useDataExport";

function calculateAge(birthDate: Date): number {
  const today = new Date();
  let age = today.getFullYear() - birthDate.getFullYear();
  const monthDiff = today.getMonth() - birthDate.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
    age--;
  }
  return age;
}

const SettingsPage = () => {
  const { theme, setTheme } = useTheme();
  const { profile, updateProfile } = useProfile();
  const { signOut } = useAuth();
  const { toast } = useToast();
  const navigate = useNavigate();
  const { exportData, importData, isExporting, isImporting } = useDataExport();

  // Dialog states
  const [personalInfoOpen, setPersonalInfoOpen] = useState(false);
  const [goalsOpen, setGoalsOpen] = useState(false);
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [importDialogOpen, setImportDialogOpen] = useState(false);
  const [passwordDialogOpen, setPasswordDialogOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  // Form states for personal info
  const [displayName, setDisplayName] = useState(profile?.display_name || "");
  const [birthDate, setBirthDate] = useState(profile?.birth_date || "");
  const [gender, setGender] = useState<"male" | "female" | "other">((profile?.gender as "male" | "female" | "other") || "male");
  const [heightCm, setHeightCm] = useState(profile?.height_cm || 170);
  const [currentWeightKg, setCurrentWeightKg] = useState(profile?.current_weight_kg || 70);
  const [targetWeightKg, setTargetWeightKg] = useState(profile?.target_weight_kg || 70);

  // Form states for goals
  const [activityLevel, setActivityLevel] = useState<ActivityLevel>((profile?.activity_level as ActivityLevel) || "moderate");
  const [goal, setGoal] = useState<Goal>((profile?.goal as Goal) || "maintain");
  const [dailyCalorieTarget, setDailyCalorieTarget] = useState(profile?.daily_calorie_target || 2000);
  const [proteinTarget, setProteinTarget] = useState(profile?.protein_target_g || 150);
  const [carbsTarget, setCarbsTarget] = useState(profile?.carbs_target_g || 200);
  const [fatTarget, setFatTarget] = useState(profile?.fat_target_g || 65);
  const [waterTarget, setWaterTarget] = useState(profile?.daily_water_target_ml || 2500);

  // Notification settings
  const [pushEnabled, setPushEnabled] = useState(profile?.push_notifications_enabled ?? true);
  const [emailEnabled, setEmailEnabled] = useState(profile?.email_notifications_enabled ?? true);
  const [weighInFrequency, setWeighInFrequency] = useState(profile?.weigh_in_frequency_days || 7);
  const [autoRecalculate, setAutoRecalculate] = useState(profile?.auto_recalculate_macros ?? true);

  const openPersonalInfo = () => {
    setDisplayName(profile?.display_name || "");
    setBirthDate(profile?.birth_date || "");
    setGender((profile?.gender as "male" | "female" | "other") || "male");
    setHeightCm(profile?.height_cm || 170);
    setCurrentWeightKg(profile?.current_weight_kg || 70);
    setTargetWeightKg(profile?.target_weight_kg || 70);
    setPersonalInfoOpen(true);
  };

  const openGoals = () => {
    setActivityLevel((profile?.activity_level as ActivityLevel) || "moderate");
    setGoal((profile?.goal as Goal) || "maintain");
    setDailyCalorieTarget(profile?.daily_calorie_target || 2000);
    setProteinTarget(profile?.protein_target_g || 150);
    setCarbsTarget(profile?.carbs_target_g || 200);
    setFatTarget(profile?.fat_target_g || 65);
    setWaterTarget(profile?.daily_water_target_ml || 2500);
    setGoalsOpen(true);
  };

  const openNotifications = () => {
    setPushEnabled(profile?.push_notifications_enabled ?? true);
    setEmailEnabled(profile?.email_notifications_enabled ?? true);
    setWeighInFrequency(profile?.weigh_in_frequency_days || 7);
    setAutoRecalculate(profile?.auto_recalculate_macros ?? true);
    setNotificationsOpen(true);
  };

  const [isRecalculating, setIsRecalculating] = useState(false);

  const recalculateMacros = async () => {
    if (!birthDate) {
      toast({ title: "Hata", description: "Doğum tarihi gerekli", variant: "destructive" });
      return;
    }
    
    setIsRecalculating(true);
    
    try {
      const age = calculateAge(new Date(birthDate));
      
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
      
      if (error) throw error;
      
      setDailyCalorieTarget(data.daily_calorie_target);
      setProteinTarget(data.protein_target_g);
      setCarbsTarget(data.carbs_target_g);
      setFatTarget(data.fat_target_g);
      // Also update water target from AI calculation
      if (data.daily_water_target_ml) {
        setWaterTarget(data.daily_water_target_ml);
      }
      
      toast({
        title: "AI Hesaplama Tamamlandı",
        description: data.explanation || `Günlük kalori: ${data.daily_calorie_target} kcal, Su: ${data.daily_water_target_ml} ml`,
      });
    } catch (error) {
      console.error('AI macro calculation error:', error);
      toast({
        title: "Hata",
        description: "AI hesaplama başarısız oldu",
        variant: "destructive",
      });
    } finally {
      setIsRecalculating(false);
    }
  };

  const savePersonalInfo = async () => {
    setIsLoading(true);
    
    const updates: Record<string, unknown> = {
      display_name: displayName,
      birth_date: birthDate,
      gender,
      height_cm: heightCm,
      current_weight_kg: currentWeightKg,
      target_weight_kg: targetWeightKg,
    };
    
    // If auto-recalculate is on and weight changed, use AI to recalculate macros
    if (autoRecalculate && profile?.current_weight_kg !== currentWeightKg && birthDate) {
      try {
        const age = calculateAge(new Date(birthDate));
        
        const { data, error: aiError } = await supabase.functions.invoke('calculate-macros', {
          body: {
            age,
            gender,
            height_cm: heightCm,
            current_weight_kg: currentWeightKg,
            target_weight_kg: targetWeightKg,
            activity_level: profile?.activity_level || "moderate",
            goal: profile?.goal || "maintain",
            previous_weight_kg: profile.current_weight_kg,
            previous_macros: {
              daily_calorie_target: profile.daily_calorie_target,
              protein_target_g: profile.protein_target_g,
              carbs_target_g: profile.carbs_target_g,
              fat_target_g: profile.fat_target_g,
            },
          },
        });
        
        if (!aiError && data) {
          updates.bmr = data.bmr;
          updates.tdee = data.tdee;
          updates.daily_calorie_target = data.daily_calorie_target;
          updates.protein_target_g = data.protein_target_g;
          updates.carbs_target_g = data.carbs_target_g;
          updates.fat_target_g = data.fat_target_g;
          
          toast({
            title: "AI Makro Güncelleme",
            description: data.explanation || "Makrolar kilo değişimine göre güncellendi",
          });
        }
      } catch (aiError) {
        console.error('AI recalculation failed:', aiError);
      }
    }
    
    const { error } = await updateProfile(updates as any);
    setIsLoading(false);
    
    if (error) {
      toast({ title: "Hata", description: "Bilgiler kaydedilemedi", variant: "destructive" });
    } else {
      toast({ title: "Başarılı", description: "Kişisel bilgileriniz güncellendi" });
      setPersonalInfoOpen(false);
    }
  };

  const saveGoals = async () => {
    setIsLoading(true);
    
    const { error } = await updateProfile({
      activity_level: activityLevel,
      goal,
      daily_calorie_target: dailyCalorieTarget,
      protein_target_g: proteinTarget,
      carbs_target_g: carbsTarget,
      fat_target_g: fatTarget,
      daily_water_target_ml: waterTarget,
    } as any);
    
    setIsLoading(false);
    
    if (error) {
      toast({ title: "Hata", description: "Hedefler kaydedilemedi", variant: "destructive" });
    } else {
      toast({ title: "Başarılı", description: "Hedefleriniz güncellendi" });
      setGoalsOpen(false);
    }
  };

  const saveNotifications = async () => {
    setIsLoading(true);
    
    const { error } = await updateProfile({
      push_notifications_enabled: pushEnabled,
      email_notifications_enabled: emailEnabled,
      weigh_in_frequency_days: weighInFrequency,
      auto_recalculate_macros: autoRecalculate,
    } as any);
    
    setIsLoading(false);
    
    if (error) {
      toast({ title: "Hata", description: "Ayarlar kaydedilemedi", variant: "destructive" });
    } else {
      toast({ title: "Başarılı", description: "Bildirim ayarları güncellendi" });
      setNotificationsOpen(false);
    }
  };

  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [isChangingPassword, setIsChangingPassword] = useState(false);

  const handleChangePassword = async () => {
    if (newPassword.length < 6) {
      toast({ title: "Hata", description: "Parola en az 6 karakter olmalı", variant: "destructive" });
      return;
    }
    if (newPassword !== confirmPassword) {
      toast({ title: "Hata", description: "Parolalar eşleşmiyor", variant: "destructive" });
      return;
    }

    setIsChangingPassword(true);
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    setIsChangingPassword(false);

    if (error) {
      toast({ title: "Hata", description: error.message, variant: "destructive" });
    } else {
      toast({ title: "Başarılı", description: "Parolanız güncellendi" });
      setPasswordDialogOpen(false);
      setNewPassword("");
      setConfirmPassword("");
    }
  };

  const handleSignOut = async () => {
    await signOut();
    navigate("/auth");
  };

  const bmi = profile?.current_weight_kg && profile?.height_cm 
    ? calculateBMI(profile.current_weight_kg, profile.height_cm) 
    : null;

  const settingsSections = [
    {
      title: "Profil",
      items: [
        {
          icon: User,
          label: "Kişisel Bilgiler",
          description: `${profile?.display_name || "İsim yok"} • ${profile?.height_cm || "-"} cm • ${profile?.current_weight_kg || "-"} kg`,
          action: openPersonalInfo,
        },
        {
          icon: Target,
          label: "Hedefler",
          description: `${profile?.daily_calorie_target || "-"} kcal • P:${profile?.protein_target_g || "-"}g K:${profile?.carbs_target_g || "-"}g Y:${profile?.fat_target_g || "-"}g`,
          action: openGoals,
        },
      ],
    },
    {
      title: "Uygulama",
      items: [
        {
          icon: Bell,
          label: "Bildirimler",
          description: `${profile?.push_notifications_enabled ? "Push açık" : "Push kapalı"} • ${profile?.email_notifications_enabled ? "E-posta açık" : "E-posta kapalı"}`,
          action: openNotifications,
        },
      ],
    },
    {
      title: "Veri",
      items: [
        {
          icon: Download,
          label: isExporting ? "Dışa Aktarılıyor..." : "Verileri Dışa Aktar",
          description: "JSON formatında yedekle",
          action: exportData,
        },
        {
          icon: Upload,
          label: isImporting ? "İçe Aktarılıyor..." : "Verileri İçe Aktar",
          description: "Yedekten geri yükle",
          action: () => setImportDialogOpen(true),
        },
      ],
    },
    {
      title: "Hesap",
      items: [
        {
          icon: KeyRound,
          label: "Parola Değiştir",
          description: "Hesap parolanızı güncelleyin",
          action: () => setPasswordDialogOpen(true),
        },
        {
          icon: LogOut,
          label: "Çıkış Yap",
          description: "Hesabınızdan çıkış yapın",
          action: handleSignOut,
          destructive: true,
        },
      ],
    },
    {
      title: "Hakkında",
      items: [
        {
          icon: Info,
          label: "Uygulama Hakkında",
          description: "Versiyon 1.0.0",
          action: () => navigate("/about"),
        },
      ],
    },
  ];

  return (
    <AppLayout title="Ayarlar">
      <div className="container max-w-lg space-y-4 px-4 py-4">
        {/* Theme Toggle */}
        <Card className="border-none bg-card shadow-lg">
          <CardContent className="flex items-center justify-between p-4">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary/10">
                {theme === "dark" ? (
                  <Moon className="h-5 w-5 text-primary" />
                ) : (
                  <Sun className="h-5 w-5 text-primary" />
                )}
              </div>
              <div>
                <p className="font-semibold text-foreground">Koyu Tema</p>
                <p className="text-sm text-muted-foreground">
                  {theme === "dark" ? "Aktif" : "Pasif"}
                </p>
              </div>
            </div>
            <Switch
              checked={theme === "dark"}
              onCheckedChange={(checked) => setTheme(checked ? "dark" : "light")}
            />
          </CardContent>
        </Card>

        {/* Settings Sections */}
        {settingsSections.map((section) => (
          <Card key={section.title} className="border-none bg-card shadow-lg">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                {section.title}
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {section.items.map((item, index) => (
                <div key={item.label}>
                  <button
                    onClick={item.action}
                    className={cn(
                      "flex w-full items-center justify-between p-4 text-left transition-colors hover:bg-muted/50",
                      (item as any).destructive && "hover:bg-destructive/10"
                    )}
                  >
                    <div className="flex items-center gap-3">
                      <item.icon className={cn(
                        "h-5 w-5",
                        (item as any).destructive ? "text-destructive" : "text-muted-foreground"
                      )} />
                      <div>
                        <p className={cn(
                          "font-medium",
                          (item as any).destructive ? "text-destructive" : "text-foreground"
                        )}>{item.label}</p>
                        <p className="text-sm text-muted-foreground">{item.description}</p>
                      </div>
                    </div>
                    <ChevronRight className={cn(
                      "h-5 w-5",
                      (item as any).destructive ? "text-destructive" : "text-muted-foreground"
                    )} />
                  </button>
                  {index < section.items.length - 1 && <Separator />}
                </div>
              ))}
            </CardContent>
          </Card>
        ))}

        {/* Health Disclaimer */}
        <Card className="border border-warning/30 bg-warning/5">
          <CardContent className="p-4">
            <p className="text-xs leading-relaxed text-muted-foreground">
              {HEALTH_DISCLAIMER}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Personal Info Dialog */}
      <Dialog open={personalInfoOpen} onOpenChange={setPersonalInfoOpen}>
        <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Kişisel Bilgiler</DialogTitle>
            <DialogDescription>
              Profil bilgilerinizi güncelleyin
            </DialogDescription>
          </DialogHeader>
          
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="name">İsim</Label>
              <Input
                id="name"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
              />
            </div>
            
            <div className="space-y-2">
              <Label htmlFor="birthDate">Doğum Tarihi</Label>
              <Input
                id="birthDate"
                type="date"
                value={birthDate}
                onChange={(e) => setBirthDate(e.target.value)}
              />
            </div>
            
            <div className="space-y-2">
              <Label>Cinsiyet</Label>
              <RadioGroup
                value={gender}
                onValueChange={(v) => setGender(v as "male" | "female" | "other")}
                className="flex gap-4"
              >
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="male" id="edit-male" />
                  <Label htmlFor="edit-male">Erkek</Label>
                </div>
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="female" id="edit-female" />
                  <Label htmlFor="edit-female">Kadın</Label>
                </div>
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="other" id="edit-other" />
                  <Label htmlFor="edit-other">Diğer</Label>
                </div>
              </RadioGroup>
            </div>
            
            <div className="grid grid-cols-3 gap-3">
              <div className="space-y-2">
                <Label htmlFor="height">Boy (cm)</Label>
                <Input
                  id="height"
                  type="number"
                  value={heightCm}
                  onChange={(e) => setHeightCm(Number(e.target.value))}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="weight">Kilo (kg)</Label>
                <Input
                  id="weight"
                  type="number"
                  step="0.1"
                  value={currentWeightKg}
                  onChange={(e) => setCurrentWeightKg(Number(e.target.value))}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="targetWeight">Hedef (kg)</Label>
                <Input
                  id="targetWeight"
                  type="number"
                  step="0.1"
                  value={targetWeightKg}
                  onChange={(e) => setTargetWeightKg(Number(e.target.value))}
                />
              </div>
            </div>

            {bmi && (
              <div className="p-3 rounded-lg bg-secondary/50 border border-border">
                <p className="text-sm">
                  <span className="font-medium">BMI:</span> {calculateBMI(currentWeightKg, heightCm)} - {" "}
                  <span className={cn(
                    "font-medium",
                    getBMICategory(calculateBMI(currentWeightKg, heightCm)).color === "success" && "text-success",
                    getBMICategory(calculateBMI(currentWeightKg, heightCm)).color === "warning" && "text-warning",
                    getBMICategory(calculateBMI(currentWeightKg, heightCm)).color === "destructive" && "text-destructive"
                  )}>
                    {getBMICategory(calculateBMI(currentWeightKg, heightCm)).label}
                  </span>
                </p>
              </div>
            )}
          </div>
          
          <DialogFooter>
            <Button variant="outline" onClick={() => setPersonalInfoOpen(false)}>İptal</Button>
            <Button onClick={savePersonalInfo} disabled={isLoading}>
              {isLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : "Kaydet"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Goals Dialog */}
      <Dialog open={goalsOpen} onOpenChange={setGoalsOpen}>
        <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Hedefler</DialogTitle>
            <DialogDescription>
              Kalori ve makro hedeflerinizi düzenleyin
            </DialogDescription>
          </DialogHeader>
          
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Aktivite Seviyesi</Label>
              <RadioGroup
                value={activityLevel}
                onValueChange={(v) => setActivityLevel(v as ActivityLevel)}
                className="space-y-2"
              >
                {Object.entries(ACTIVITY_LEVELS).map(([key, level]) => (
                  <div
                    key={key}
                    className={cn(
                      "flex items-center space-x-3 p-2 rounded-lg border cursor-pointer",
                      activityLevel === key ? "border-primary bg-primary/5" : "border-border"
                    )}
                    onClick={() => setActivityLevel(key as ActivityLevel)}
                  >
                    <RadioGroupItem value={key} id={`activity-${key}`} />
                    <Label htmlFor={`activity-${key}`} className="cursor-pointer text-sm">
                      {level.label}
                    </Label>
                  </div>
                ))}
              </RadioGroup>
            </div>

            <div className="space-y-2">
              <Label>Hedef</Label>
              <RadioGroup
                value={goal}
                onValueChange={(v) => setGoal(v as Goal)}
                className="flex gap-2"
              >
                {Object.entries(GOALS).map(([key, g]) => (
                  <div
                    key={key}
                    className={cn(
                      "flex-1 flex items-center justify-center p-2 rounded-lg border cursor-pointer text-center",
                      goal === key ? "border-primary bg-primary/5" : "border-border"
                    )}
                    onClick={() => setGoal(key as Goal)}
                  >
                    <RadioGroupItem value={key} id={`goal-${key}`} className="sr-only" />
                    <Label htmlFor={`goal-${key}`} className="cursor-pointer text-xs">
                      {g.label}
                    </Label>
                  </div>
                ))}
              </RadioGroup>
            </div>

            <Button 
              variant="outline" 
              className="w-full" 
              onClick={recalculateMacros}
              disabled={isRecalculating}
            >
              {isRecalculating ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Sparkles className="mr-2 h-4 w-4" />
              )}
              {isRecalculating ? "AI Hesaplıyor..." : "AI ile Hedefleri Hesapla"}
            </Button>

            <Separator />

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <Label htmlFor="calories">Kalori (kcal)</Label>
                <Input
                  id="calories"
                  type="number"
                  value={dailyCalorieTarget}
                  onChange={(e) => setDailyCalorieTarget(Number(e.target.value))}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="water">Su (ml)</Label>
                <Input
                  id="water"
                  type="number"
                  step="250"
                  value={waterTarget}
                  onChange={(e) => setWaterTarget(Number(e.target.value))}
                />
              </div>
            </div>

            <div className="grid grid-cols-3 gap-3">
              <div className="space-y-2">
                <Label htmlFor="protein">Protein (g)</Label>
                <Input
                  id="protein"
                  type="number"
                  value={proteinTarget}
                  onChange={(e) => setProteinTarget(Number(e.target.value))}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="carbs">Karb (g)</Label>
                <Input
                  id="carbs"
                  type="number"
                  value={carbsTarget}
                  onChange={(e) => setCarbsTarget(Number(e.target.value))}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="fat">Yağ (g)</Label>
                <Input
                  id="fat"
                  type="number"
                  value={fatTarget}
                  onChange={(e) => setFatTarget(Number(e.target.value))}
                />
              </div>
            </div>
          </div>
          
          <DialogFooter>
            <Button variant="outline" onClick={() => setGoalsOpen(false)}>İptal</Button>
            <Button onClick={saveGoals} disabled={isLoading}>
              {isLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : "Kaydet"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Notifications Dialog */}
      <Dialog open={notificationsOpen} onOpenChange={setNotificationsOpen}>
        <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Bildirim Ayarları</DialogTitle>
            <DialogDescription>
              Her bildirim türü için kanal ve zamanlama ayarlarını yapın
            </DialogDescription>
          </DialogHeader>
          
          <div className="py-4">
            <NotificationPreferences />
          </div>
          
          <DialogFooter>
            <Button onClick={() => setNotificationsOpen(false)}>Kapat</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Import Data Dialog */}
      <Dialog open={importDialogOpen} onOpenChange={setImportDialogOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Verileri İçe Aktar</DialogTitle>
            <DialogDescription>
              Daha önce dışa aktardığınız JSON dosyasını seçin. Mevcut verileriniz korunacak, sadece yeni kayıtlar eklenecek.
            </DialogDescription>
          </DialogHeader>
          
          <div className="py-4">
            <div className="border-2 border-dashed border-border rounded-lg p-8 text-center">
              <Upload className="mx-auto h-10 w-10 text-muted-foreground mb-3" />
              <Label
                htmlFor="import-file"
                className="cursor-pointer text-primary hover:underline"
              >
                {isImporting ? "İçe aktarılıyor..." : "Dosya Seçin"}
              </Label>
              <input
                id="import-file"
                type="file"
                accept=".json"
                className="hidden"
                disabled={isImporting}
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) {
                    importData(file).then(() => {
                      setImportDialogOpen(false);
                    });
                  }
                }}
              />
              <p className="text-xs text-muted-foreground mt-2">
                Sadece CaloriX JSON yedek dosyaları desteklenir
              </p>
            </div>
          </div>
          
          <DialogFooter>
            <Button variant="outline" onClick={() => setImportDialogOpen(false)}>
              İptal
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Password Change Dialog */}
      <Dialog open={passwordDialogOpen} onOpenChange={setPasswordDialogOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Parola Değiştir</DialogTitle>
            <DialogDescription>
              Yeni parolanızı girin
            </DialogDescription>
          </DialogHeader>
          
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="newPassword">Yeni Parola</Label>
              <Input
                id="newPassword"
                type="password"
                placeholder="En az 6 karakter"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
              />
            </div>
            
            <div className="space-y-2">
              <Label htmlFor="confirmPassword">Parola Tekrar</Label>
              <Input
                id="confirmPassword"
                type="password"
                placeholder="Parolayı tekrar girin"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
              />
            </div>
          </div>
          
          <DialogFooter>
            <Button variant="outline" onClick={() => setPasswordDialogOpen(false)}>
              İptal
            </Button>
            <Button onClick={handleChangePassword} disabled={isChangingPassword}>
              {isChangingPassword && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Kaydet
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AppLayout>
  );
};

export default SettingsPage;

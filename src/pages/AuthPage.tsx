import { useState, useEffect } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useToast } from "@/hooks/use-toast";
import { Loader2, Mail, Lock, User, ArrowLeft, CheckCircle, RefreshCw } from "lucide-react";
import { z } from "zod";
import { supabase } from "@/integrations/supabase/client";
import { PollinationsCredit } from "@/components/common/PollinationsCredit";

const emailSchema = z.string().email("Geçerli bir e-posta adresi giriniz");
const passwordSchema = z.string().min(6, "Şifre en az 6 karakter olmalıdır");

type AuthView = "auth" | "forgot-password" | "pending-verification" | "reset-password";

export default function AuthPage() {
  const [searchParams] = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [errors, setErrors] = useState<{ email?: string; password?: string }>({});
  const [view, setView] = useState<AuthView>("auth");
  const [pendingEmail, setPendingEmail] = useState("");

  const { user, isEmailVerified, isPasswordRecovery, clearPasswordRecovery, signIn, signUp, signOut, resetPassword, resendVerificationEmail } = useAuth();
  const navigate = useNavigate();
  const { toast } = useToast();

  // Handle password recovery flow
  useEffect(() => {
    if (isPasswordRecovery) {
      setView("reset-password");
    }
  }, [isPasswordRecovery]);

  // Check URL params for email verification
  useEffect(() => {
    if (searchParams.get("verified") === "true" && user && isEmailVerified) {
      toast({
        title: "E-posta Doğrulandı!",
        description: "Hesabınız başarıyla doğrulandı.",
      });
      navigate("/", { replace: true });
    }
  }, [searchParams, user, isEmailVerified, navigate, toast]);

  // Redirect if already logged in and verified (but not in password recovery mode)
  useEffect(() => {
    if (view === "reset-password") return; // Don't redirect during password reset

    if (user && isEmailVerified && !isPasswordRecovery) {
      navigate("/", { replace: true });
    } else if (user && !isEmailVerified && !isPasswordRecovery) {
      setView("pending-verification");
      setPendingEmail(user.email || "");
    }
  }, [user, isEmailVerified, isPasswordRecovery, navigate, view]);

  const validateForm = () => {
    const newErrors: { email?: string; password?: string } = {};

    const emailResult = emailSchema.safeParse(email);
    if (!emailResult.success) {
      newErrors.email = emailResult.error.errors[0].message;
    }

    const passwordResult = passwordSchema.safeParse(password);
    if (!passwordResult.success) {
      newErrors.password = passwordResult.error.errors[0].message;
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSignIn = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validateForm()) return;

    setIsLoading(true);
    const { error } = await signIn(email, password);
    setIsLoading(false);

    if (error) {
      let message = "Giriş yapılırken bir hata oluştu";
      if (error.message.includes("Invalid login credentials")) {
        message = "E-posta veya şifre hatalı";
      } else if (error.message.includes("Email not confirmed")) {
        message = "Lütfen e-posta adresinizi doğrulayın";
        setPendingEmail(email);
        setView("pending-verification");
        return;
      }
      toast({
        title: "Giriş Başarısız",
        description: message,
        variant: "destructive",
      });
    }
  };

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validateForm()) return;

    setIsLoading(true);
    const { error } = await signUp(email, password, displayName);
    setIsLoading(false);

    if (error) {
      let message = "Kayıt olurken bir hata oluştu";
      if (error.message.includes("User already registered")) {
        message = "Bu e-posta adresi zaten kayıtlı";
      } else if (error.message.includes("Password should be")) {
        message = "Şifre en az 6 karakter olmalıdır";
      }
      toast({
        title: "Kayıt Başarısız",
        description: message,
        variant: "destructive",
      });
    } else {
      toast({
        title: "Kayıt Başarılı!",
        description: "Doğrulama e-postası gönderildi.",
      });
      setPendingEmail(email);
      setView("pending-verification");
    }
  };

  const handleForgotPassword = async (e: React.FormEvent) => {
    e.preventDefault();

    const emailResult = emailSchema.safeParse(email);
    if (!emailResult.success) {
      setErrors({ email: emailResult.error.errors[0].message });
      return;
    }

    setIsLoading(true);
    const { error } = await resetPassword(email);
    setIsLoading(false);

    if (error) {
      toast({
        title: "Hata",
        description: "Şifre sıfırlama e-postası gönderilemedi",
        variant: "destructive",
      });
    } else {
      toast({
        title: "E-posta Gönderildi",
        description: "Şifre sıfırlama bağlantısı e-posta adresinize gönderildi",
      });
      setView("auth");
    }
  };

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault();

    if (newPassword.length < 6) {
      toast({ title: "Hata", description: "Şifre en az 6 karakter olmalı", variant: "destructive" });
      return;
    }
    if (newPassword !== confirmPassword) {
      toast({ title: "Hata", description: "Şifreler eşleşmiyor", variant: "destructive" });
      return;
    }

    setIsLoading(true);
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    setIsLoading(false);

    if (error) {
      toast({
        title: "Hata",
        description: error.message,
        variant: "destructive",
      });
    } else {
      clearPasswordRecovery();
      toast({
        title: "Başarılı",
        description: "Şifreniz güncellendi",
      });
      navigate("/", { replace: true });
    }
  };

  const handleResendVerification = async () => {
    setIsLoading(true);
    const { error } = await resendVerificationEmail();
    setIsLoading(false);

    if (error) {
      toast({
        title: "Hata",
        description: "Doğrulama e-postası gönderilemedi",
        variant: "destructive",
      });
    } else {
      toast({
        title: "E-posta Gönderildi",
        description: "Yeni doğrulama e-postası gönderildi",
      });
    }
  };

  const handleSignOutAndBack = async () => {
    await signOut();
    setView("auth");
    setPendingEmail("");
  };

  // Pending Verification View
  if (view === "pending-verification") {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background p-4">
        <div className="w-full max-w-md animate-fade-in">
          <div className="text-center mb-8">
            <div className="flex flex-col items-center justify-center mb-2">
              <img src="/logo.png" alt="CaloriX Logo" className="w-20 h-20 mb-4 object-contain" />
              <h1 className="text-4xl font-bold text-gradient">CaloriX</h1>
            </div>
          </div>

          <Card className="glass">
            <CardHeader className="text-center">
              <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-primary/10">
                <Mail className="h-8 w-8 text-primary" />
              </div>
              <CardTitle>E-posta Doğrulaması Bekleniyor</CardTitle>
              <CardDescription>
                <span className="font-medium text-foreground">{pendingEmail}</span> adresine bir doğrulama e-postası gönderdik.
                Lütfen gelen kutunuzu kontrol edin ve doğrulama bağlantısına tıklayın.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="rounded-lg bg-muted/50 p-4 text-center">
                <p className="text-sm text-muted-foreground">
                  E-posta gelmediyse spam klasörünüzü kontrol edin veya yeniden gönderin.
                </p>
              </div>

              <Button
                variant="outline"
                className="w-full"
                onClick={handleResendVerification}
                disabled={isLoading}
              >
                {isLoading ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <RefreshCw className="mr-2 h-4 w-4" />
                )}
                Yeniden Gönder
              </Button>

              <Button
                variant="ghost"
                className="w-full"
                onClick={handleSignOutAndBack}
              >
                <ArrowLeft className="mr-2 h-4 w-4" />
                Farklı bir hesapla giriş yap
              </Button>

              <PollinationsCredit className="pt-4" />
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  // Reset Password View
  if (view === "reset-password") {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background p-4">
        <div className="w-full max-w-md animate-fade-in">
          <div className="text-center mb-8">
            <div className="flex flex-col items-center justify-center mb-2">
              <img src="/logo.png" alt="CaloriX Logo" className="w-20 h-20 mb-4 object-contain" />
              <h1 className="text-4xl font-bold text-gradient">CaloriX</h1>
            </div>
          </div>

          <Card className="glass">
            <CardHeader>
              <CardTitle>Yeni Şifre Belirle</CardTitle>
              <CardDescription>
                Hesabınız için yeni bir şifre belirleyin
              </CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleResetPassword} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="new-password">Yeni Şifre</Label>
                  <div className="relative">
                    <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                    <Input
                      id="new-password"
                      type="password"
                      placeholder="••••••••"
                      value={newPassword}
                      onChange={(e) => setNewPassword(e.target.value)}
                      className="pl-10"
                      disabled={isLoading}
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="confirm-password">Şifre Tekrar</Label>
                  <div className="relative">
                    <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                    <Input
                      id="confirm-password"
                      type="password"
                      placeholder="••••••••"
                      value={confirmPassword}
                      onChange={(e) => setConfirmPassword(e.target.value)}
                      className="pl-10"
                      disabled={isLoading}
                    />
                  </div>
                </div>

                <Button type="submit" className="w-full" disabled={isLoading}>
                  {isLoading ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Kaydediliyor...
                    </>
                  ) : (
                    "Şifreyi Güncelle"
                  )}
                </Button>
              </form>

              <PollinationsCredit className="pt-6" />
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  // Forgot Password View
  if (view === "forgot-password") {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background p-4">
        <div className="w-full max-w-md animate-fade-in">
          <div className="text-center mb-8">
            <div className="flex flex-col items-center justify-center mb-2">
              <img src="/logo.png" alt="CaloriX Logo" className="w-20 h-20 mb-4 object-contain" />
              <h1 className="text-4xl font-bold text-gradient">CaloriX</h1>
            </div>
          </div>

          <Card className="glass">
            <CardHeader>
              <Button
                variant="ghost"
                size="sm"
                className="w-fit -ml-2 mb-2"
                onClick={() => setView("auth")}
              >
                <ArrowLeft className="mr-2 h-4 w-4" />
                Geri
              </Button>
              <CardTitle>Şifremi Unuttum</CardTitle>
              <CardDescription>
                E-posta adresinizi girin, şifre sıfırlama bağlantısı göndereceğiz
              </CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleForgotPassword} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="forgot-email">E-posta</Label>
                  <div className="relative">
                    <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                    <Input
                      id="forgot-email"
                      type="email"
                      placeholder="ornek@email.com"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      className="pl-10"
                      disabled={isLoading}
                    />
                  </div>
                  {errors.email && (
                    <p className="text-xs text-destructive">{errors.email}</p>
                  )}
                </div>

                <Button type="submit" className="w-full" disabled={isLoading}>
                  {isLoading ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Gönderiliyor...
                    </>
                  ) : (
                    "Şifre Sıfırlama Bağlantısı Gönder"
                  )}
                </Button>
              </form>

              <PollinationsCredit className="pt-6" />
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  // Main Auth View (Sign In / Sign Up)
  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <div className="w-full max-w-md animate-fade-in">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="flex flex-col items-center justify-center mb-2">
            <img src="/logo.png" alt="CaloriX Logo" className="w-24 h-24 mb-4 object-contain" />
            <h1 className="text-4xl font-bold text-gradient">CaloriX</h1>
          </div>
          <p className="text-muted-foreground">
            Kalori ve makro takibi için akıllı asistanınız
          </p>
        </div>

        <Card className="glass">
          <Tabs defaultValue="signin" className="w-full">
            <CardHeader className="pb-4">
              <TabsList className="grid w-full grid-cols-2">
                <TabsTrigger value="signin">Giriş Yap</TabsTrigger>
                <TabsTrigger value="signup">Kayıt Ol</TabsTrigger>
              </TabsList>
            </CardHeader>

            <CardContent className="space-y-4">
              {/* Sign In Tab */}
              <TabsContent value="signin" className="space-y-4 mt-0">
                <CardDescription className="text-center">
                  Hesabınıza giriş yapın
                </CardDescription>
                <form onSubmit={handleSignIn} className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="signin-email">E-posta</Label>
                    <div className="relative">
                      <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                      <Input
                        id="signin-email"
                        type="email"
                        placeholder="ornek@email.com"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        className="pl-10"
                        disabled={isLoading}
                      />
                    </div>
                    {errors.email && (
                      <p className="text-xs text-destructive">{errors.email}</p>
                    )}
                  </div>

                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <Label htmlFor="signin-password">Şifre</Label>
                      <button
                        type="button"
                        onClick={() => setView("forgot-password")}
                        className="text-xs text-primary hover:underline"
                      >
                        Şifremi Unuttum
                      </button>
                    </div>
                    <div className="relative">
                      <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                      <Input
                        id="signin-password"
                        type="password"
                        placeholder="••••••••"
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                        className="pl-10"
                        disabled={isLoading}
                      />
                    </div>
                    {errors.password && (
                      <p className="text-xs text-destructive">{errors.password}</p>
                    )}
                  </div>

                  <Button
                    type="submit"
                    className="w-full"
                    disabled={isLoading}
                  >
                    {isLoading ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        Giriş yapılıyor...
                      </>
                    ) : (
                      "Giriş Yap"
                    )}
                  </Button>
                </form>
              </TabsContent>

              {/* Sign Up Tab */}
              <TabsContent value="signup" className="space-y-4 mt-0">
                <CardDescription className="text-center">
                  Yeni hesap oluşturun
                </CardDescription>
                <form onSubmit={handleSignUp} className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="signup-name">İsim (Opsiyonel)</Label>
                    <div className="relative">
                      <User className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                      <Input
                        id="signup-name"
                        type="text"
                        placeholder="Adınız"
                        value={displayName}
                        onChange={(e) => setDisplayName(e.target.value)}
                        className="pl-10"
                        disabled={isLoading}
                      />
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="signup-email">E-posta</Label>
                    <div className="relative">
                      <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                      <Input
                        id="signup-email"
                        type="email"
                        placeholder="ornek@email.com"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        className="pl-10"
                        disabled={isLoading}
                      />
                    </div>
                    {errors.email && (
                      <p className="text-xs text-destructive">{errors.email}</p>
                    )}
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="signup-password">Şifre</Label>
                    <div className="relative">
                      <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                      <Input
                        id="signup-password"
                        type="password"
                        placeholder="••••••••"
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                        className="pl-10"
                        disabled={isLoading}
                      />
                    </div>
                    {errors.password && (
                      <p className="text-xs text-destructive">{errors.password}</p>
                    )}
                  </div>

                  <Button
                    type="submit"
                    className="w-full"
                    disabled={isLoading}
                  >
                    {isLoading ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        Kayıt olunuyor...
                      </>
                    ) : (
                      "Kayıt Ol"
                    )}
                  </Button>
                </form>
              </TabsContent>

              {/* Health Disclaimer */}
              <div className="pt-4 border-t border-border">
                <p className="text-xs text-muted-foreground text-center">
                  ⚠️ Bu uygulama yalnızca bilgi amaçlıdır ve tıbbi tavsiye niteliği taşımaz.
                  Beslenme ve sağlık konularında profesyonel destek alınız.
                </p>
              </div>

              {/* Pollinations Credit */}
              <PollinationsCredit className="pt-4" />
            </CardContent>
          </Tabs>
        </Card>
      </div>
    </div>
  );
}

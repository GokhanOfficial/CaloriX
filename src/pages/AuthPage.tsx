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

import { useTranslation } from "react-i18next";
import { LanguageSelector } from "@/components/LanguageSelector";

const emailSchema = z.string().email();
const passwordSchema = z.string().min(6);

type AuthView = "auth" | "forgot-password" | "pending-verification" | "reset-password";

export default function AuthPage() {
  const { t } = useTranslation();
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
        title: t('auth.messages.emailVerified'),
        description: t('auth.messages.emailVerifiedDesc'),
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
      newErrors.email = t('auth.validation.invalidEmail');
    }

    const passwordResult = passwordSchema.safeParse(password);
    if (!passwordResult.success) {
      newErrors.password = t('auth.validation.passwordLength');
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
      let message = t('common.error');
      if (error.message.includes("Invalid login credentials")) {
        message = t('auth.validation.invalidLogin');
      } else if (error.message.includes("Email not confirmed")) {
        message = t('auth.validation.emailNotConfirmed');
        setPendingEmail(email);
        setView("pending-verification");
        return;
      }
      toast({
        title: t('common.error'),
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
      let message = t('common.error');
      if (error.message.includes("User already registered")) {
        message = t('auth.validation.userAlreadyRegistered');
      } else if (error.message.includes("Password should be")) {
        message = t('auth.validation.passwordLength');
      }
      toast({
        title: "Kayıt Başarısız",
        description: message,
        variant: "destructive",
      });
    } else {
      toast({
        title: t('auth.messages.signUpSuccess'),
        description: t('auth.messages.verificationSent'),
      });
      setPendingEmail(email);
      setView("pending-verification");
    }
  };

  const handleForgotPassword = async (e: React.FormEvent) => {
    e.preventDefault();

    const emailResult = emailSchema.safeParse(email);
    if (!emailResult.success) {
      setErrors({ email: t('auth.validation.invalidEmail') });
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
        title: t('common.success'),
        description: t('auth.messages.resetEmailSent'),
      });
      setView("auth");
    }
  };

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault();

    if (newPassword.length < 6) {
      toast({ title: t('common.error'), description: t('auth.validation.passwordLength'), variant: "destructive" });
      return;
    }
    if (newPassword !== confirmPassword) {
      toast({ title: t('common.error'), description: t('auth.validation.passwordMismatch'), variant: "destructive" });
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
        title: t('common.success'),
        description: t('auth.messages.passwordUpdated'),
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
        title: t('common.success'),
        description: t('auth.messages.verificationSent'),
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
      <div className="min-h-screen flex items-center justify-center bg-background p-4 relative">
        <div className="absolute top-4 right-4 z-50">
          <LanguageSelector />
        </div>
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
                  {t('auth.pendingVerification.spamNote')}
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
                {t('common.resend')}
              </Button>

              <Button
                variant="ghost"
                className="w-full"
                onClick={handleSignOutAndBack}
              >
                <ArrowLeft className="mr-2 h-4 w-4" />
                {t('auth.pendingVerification.differentAccount')}
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
      <div className="min-h-screen flex items-center justify-center bg-background p-4 relative">
        <div className="absolute top-4 right-4 z-50">
          <LanguageSelector />
        </div>
        <div className="w-full max-w-md animate-fade-in">
          <div className="text-center mb-8">
            <div className="flex flex-col items-center justify-center mb-2">
              <img src="/logo.png" alt="CaloriX Logo" className="w-20 h-20 mb-4 object-contain" />
              <h1 className="text-4xl font-bold text-gradient">CaloriX</h1>
            </div>
          </div>

          <Card className="glass">
            <CardHeader>
              <CardTitle>{t('auth.resetPasswordTitle')}</CardTitle>
              <CardDescription>
                {t('auth.resetPasswordDesc')}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleResetPassword} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="new-password">{t('auth.newPassword')}</Label>
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
                  <Label htmlFor="confirm-password">{t('auth.confirmPassword')}</Label>
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
                      {t('auth.button.saving')}
                    </>
                  ) : (
                    t('auth.updatePassword')
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
      <div className="min-h-screen flex items-center justify-center bg-background p-4 relative">
        <div className="absolute top-4 right-4 z-50">
          <LanguageSelector />
        </div>
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
                {t('common.back')}
              </Button>
              <CardTitle>{t('auth.forgotPasswordTitle')}</CardTitle>
              <CardDescription>
                {t('auth.forgotPasswordDesc')}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleForgotPassword} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="forgot-email">{t('auth.email')}</Label>
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
                      {t('auth.button.sending')}
                    </>
                  ) : (
                    t('auth.sendResetLink')
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
    <div className="min-h-screen flex items-center justify-center bg-background p-4 relative">
      <div className="absolute top-4 right-4 z-50">
        <LanguageSelector />
      </div>
      <div className="w-full max-w-md animate-fade-in">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="flex flex-col items-center justify-center mb-2">
            <img src="/logo.png" alt="CaloriX Logo" className="w-24 h-24 mb-4 object-contain" />
            <h1 className="text-4xl font-bold text-gradient">CaloriX</h1>
          </div>
          <p className="text-muted-foreground">
            {t('auth.tagline')}
          </p>
        </div>

        <Card className="glass">
          <Tabs defaultValue="signin" className="w-full">
            <CardHeader className="pb-4">
              <TabsList className="grid w-full grid-cols-2">
                <TabsTrigger value="signin">{t('auth.signInTab')}</TabsTrigger>
                <TabsTrigger value="signup">{t('auth.signUpTab')}</TabsTrigger>
              </TabsList>
            </CardHeader>

            <CardContent className="space-y-4">
              {/* Sign In Tab */}
              <TabsContent value="signin" className="space-y-4 mt-0">
                <CardDescription className="text-center">
                  {t('auth.signInDesc')}
                </CardDescription>
                <form onSubmit={handleSignIn} className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="signin-email">{t('auth.email')}</Label>
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
                      <Label htmlFor="signin-password">{t('auth.password')}</Label>
                      <button
                        type="button"
                        onClick={() => setView("forgot-password")}
                        className="text-xs text-primary hover:underline"
                      >
                        {t('auth.forgotPassword')}
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
                        {t('auth.button.signingIn')}
                      </>
                    ) : (
                      t('auth.signIn')
                    )}
                  </Button>
                </form>
              </TabsContent>

              {/* Sign Up Tab */}
              <TabsContent value="signup" className="space-y-4 mt-0">
                <CardDescription className="text-center">
                  {t('auth.signUpDesc')}
                </CardDescription>
                <form onSubmit={handleSignUp} className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="signup-name">{t('auth.nameOptional')}</Label>
                    <div className="relative">
                      <User className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                      <Input
                        id="signup-name"
                        type="text"
                        placeholder={t('auth.name')}
                        value={displayName}
                        onChange={(e) => setDisplayName(e.target.value)}
                        className="pl-10"
                        disabled={isLoading}
                      />
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="signup-email">{t('auth.email')}</Label>
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
                    <Label htmlFor="signup-password">{t('auth.password')}</Label>
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
                        {t('auth.button.signingUp')}
                      </>
                    ) : (
                      t('auth.signUp')
                    )}
                  </Button>
                </form>
              </TabsContent>

              {/* Health Disclaimer */}
              <div className="pt-4 border-t border-border">
                <p className="text-xs text-muted-foreground text-center">
                  {t('common.healthDisclaimer')}
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

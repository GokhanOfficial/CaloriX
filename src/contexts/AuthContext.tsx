import { createContext, useContext, useEffect, useState, ReactNode } from "react";
import { User, Session } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";

interface AuthContextType {
  user: User | null;
  session: Session | null;
  loading: boolean;
  isEmailVerified: boolean;
  isPasswordRecovery: boolean;
  clearPasswordRecovery: () => void;
  signUp: (email: string, password: string, displayName?: string) => Promise<{ error: Error | null }>;
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>;
  signOut: () => Promise<void>;
  resetPassword: (email: string) => Promise<{ error: Error | null }>;
  resendVerificationEmail: () => Promise<{ error: Error | null }>;
  /** `signOut` uçuşta mı — butonu disabled yapmak için. */
  signingOut: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [isPasswordRecovery, setIsPasswordRecovery] = useState(false);
  // `signOut`'ta `loading` yeniden **true** yapılmıyordu. `ProtectedRoute`
  // `!loading && !user` koşuluyla yönlendirdiği için çoğu akışta sorun
  // görünmese de `onAuthStateChange('SIGNED_OUT')` ile `user` null olduğu
  // anda `loading` de düşüyor; aradaki `await supabase.auth.signOut()`
  // penceresinde ekran hâlâ oturumlu kullanıcıyı gösterip veri isteği
  // atabiliyordu. Aynı pencere `AuthProvider`'ın iki kez `setUser(null)`
  // çağırdığı "çift render" sıçramasını da üretiyordu.
  const [signingOut, setSigningOut] = useState(false);

  const isEmailVerified = user?.email_confirmed_at != null;

  const clearPasswordRecovery = () => {
    setIsPasswordRecovery(false);
  };

  useEffect(() => {
    let disposed = false;

    // Set up auth state listener FIRST
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        if (disposed) return;
        setSession(session);
        setUser(session?.user ?? null);
        setLoading(false);

        // Detect password recovery event
        if (event === 'PASSWORD_RECOVERY') {
          setIsPasswordRecovery(true);
        }
      }
    );

    // THEN check for existing session.
    //
    // `getSession()` async: depodan okunan ve **süresi dolmuş** bir oturum
    // için token yenileme isteği yapar, bu sırada `onAuthStateChange` yeni
    // oturumu (`SIGNED_IN`/`TOKEN_REFRESHED`) yayınlayabilir. `getSession()`
    // sözü eski oturumla çözülürse (aşağıdaki `disposed` kontrolü olmadan)
    // `setSession(eski)` yazılıp `TOKEN_REFRESHED` sonucunu **eziyordu**.
    // `getSession` ayrıca reddedebiliyordu (bozuk localStorage, özel
    // `storageKey`); o durumda `loading` hiç düşmüyor ve uygulama sonsuza
    // dek splash ekranında kalıyordu.
    supabase.auth.getSession()
      .then(({ data: { session } }) => {
        if (disposed) return;
        setSession(session);
        setUser(session?.user ?? null);
        setLoading(false);
      })
      .catch(() => {
        if (disposed) return;
        setSession(null);
        setUser(null);
        setLoading(false);
      });

    return () => {
      disposed = true;
      subscription.unsubscribe();
    };
  }, []);

  const signUp = async (email: string, password: string, displayName?: string) => {
    const redirectUrl = `${window.location.origin}/auth?verified=true`;
    
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: redirectUrl,
        data: {
          display_name: displayName || email.split("@")[0],
        },
      },
    });
    
    return { error: error as Error | null };
  };

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    
    return { error: error as Error | null };
  };

  const signOut = async () => {
    setSigningOut(true);
    try {
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
    } catch (error) {
      // Hata yutuluyordu: `signOut` başarısız olsa bile `onAuthStateChange`
      // tetiklenmediği için kullanıcı "çıkış yapmış" sanıyordu. Yutulan
      // hata P1 sınıfı (kullanıcıyı yanlış bilgilendiren sessiz hata).
      console.error('Sign out failed:', error);
    } finally {
      setSigningOut(false);
    }
  };

  const resetPassword = async (email: string) => {
    const redirectUrl = `${window.location.origin}/auth?reset=true`;
    
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: redirectUrl,
    });
    
    return { error: error as Error | null };
  };

  const resendVerificationEmail = async () => {
    if (!user?.email) {
      return { error: new Error("No email found") };
    }
    
    const redirectUrl = `${window.location.origin}/auth?verified=true`;
    
    const { error } = await supabase.auth.resend({
      type: 'signup',
      email: user.email,
      options: {
        emailRedirectTo: redirectUrl,
      },
    });
    
    return { error: error as Error | null };
  };

  return (
    <AuthContext.Provider value={{ 
      user, 
      session, 
      loading, 
      isEmailVerified,
      isPasswordRecovery,
      clearPasswordRecovery,
      signUp, 
      signIn, 
      signOut, 
      resetPassword,
      resendVerificationEmail,
      // Çağıranlar `await signOut()` sonrası `setSigningOut(false)` bekliyordu;
      // yeni bayrak ikinci render'ı tetikler.
      signingOut,
    }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}

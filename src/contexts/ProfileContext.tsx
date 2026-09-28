import { createContext, useContext, useState, useEffect, useRef, ReactNode, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export interface UserProfile {
  id: string;
  display_name: string | null;
  email: string | null;
  avatar_url: string | null;
  birth_date: string | null;
  gender: string | null;
  height_cm: number | null;
  current_weight_kg: number | null;
  target_weight_kg: number | null;
  activity_level: string | null;
  goal: string | null;
  bmr: number | null;
  tdee: number | null;
  daily_calorie_target: number | null;
  protein_target_g: number | null;
  carbs_target_g: number | null;
  fat_target_g: number | null;
  daily_water_target_ml: number | null;
  weigh_in_frequency_days: number | null;
  push_notifications_enabled: boolean | null;
  email_notifications_enabled: boolean | null;
  onboarding_completed: boolean | null;
  auto_recalculate_macros: boolean | null;
  created_at: string;
  updated_at: string;
}

interface ProfileContextType {
  profile: UserProfile | null;
  loading: boolean;
  error: Error | null;
  refetch: () => Promise<void>;
  updateProfile: (updates: Partial<UserProfile>) => Promise<{ error: Error | null }>;
}

const ProfileContext = createContext<ProfileContextType | undefined>(undefined);

export function ProfileProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  /**
   * Uçuştaki isteği geçersiz kılmak için sayaç.
   *
   * `user` değiştiğinde iki sorun vardı:
   *  1. `A`'nın profili `B`'nin ekranında bir kare kalıyordu (state sıfırlanmıyor).
   *  2. `A`'nın isteği `B`'ninkinden **sonra** çözülürse `setProfile(A)`
   *     `B`'nin verisini eziyordu (race condition).
   *
   * Async fonksiyon `useEffect` cleanup'ına fonksiyon **döndüremez**
   * (dönen değer bir Promise'dir), bu yüzden sayaç kullanılıyor: her
   * `fetchProfile` çağrısı sayacı artırır, çözülme anında kendi
   * jetonuyla karşılaştırır; eşleşmiyorsa state'e hiç dokunmaz.
   */
  const requestIdRef = useRef(0);

  const fetchProfile = useCallback(async () => {
    const requestId = ++requestIdRef.current;

    if (!user) {
      setProfile(null);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);

    try {
      const { data, error } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", user.id)
        .single();

      if (requestId !== requestIdRef.current) return;
      if (error) throw error;
      setProfile(data as UserProfile);
      setError(null);
    } catch (err) {
      if (requestId !== requestIdRef.current) return;
      setError(err as Error);
    } finally {
      if (requestId === requestIdRef.current) setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    fetchProfile();
  }, [fetchProfile]);

  const refetch = async () => {
    setLoading(true);
    await fetchProfile();
  };

  const updateProfile = async (updates: Partial<UserProfile>): Promise<{ error: Error | null }> => {
    if (!user) return { error: new Error("Not authenticated") };

    try {
      const { error } = await supabase
        .from("profiles")
        .update({
          ...updates,
          updated_at: new Date().toISOString(),
        })
        .eq("id", user.id);

      if (error) throw error;
      
      // Update local state immediately
      setProfile(prev => prev ? { ...prev, ...updates } : null);
      
      return { error: null };
    } catch (err) {
      return { error: err as Error };
    }
  };

  return (
    <ProfileContext.Provider value={{ profile, loading, error, refetch, updateProfile }}>
      {children}
    </ProfileContext.Provider>
  );
}

export function useProfile() {
  const context = useContext(ProfileContext);
  if (context === undefined) {
    throw new Error("useProfile must be used within a ProfileProvider");
  }
  return context;
}

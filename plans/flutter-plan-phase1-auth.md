# Faz 1 — Auth + Onboarding + Profil

> Master plan: `flutter-plan-master.md` | Web referansı: `src/pages/AuthPage.tsx`, `src/pages/OnboardingPage.tsx`, `src/contexts/AuthContext.tsx`, `src/contexts/ProfileContext.tsx`

## Amaç
E-posta/şifre kayıt, giriş, e-posta doğrulama, şifre sıfırlama; onboarding akışı; profil verisi.

## 1. AuthRepository (`lib/data/repositories/auth_repository.dart`)
Web `AuthContext.tsx`'in Dart karşılığı:
- `signUp(email, password, displayName?)` → `supabase.auth.signUp(...)`, `emailRedirectTo` web ile aynı mantık
- `signIn(email, password)`
- `signOut()`
- `resetPassword(email)` → deep link redirect
- `resendVerificationEmail()`
- Stream: `authStateChanges` → Riverpod `StreamProvider<AuthState>`

## 2. Router redirect mantığı (`core/router/app_router.dart`)
```
oturum yok            → /auth
oturum var, onboarding tamamlanmamış (profiles onboarding_completed=false) → /onboarding
oturum var + tamam    → talep edilen route
PASSWORD_RECOVERY eventi → /auth (yeni şifre formu)
```

## 3. AuthPage (`features/auth/`)
Web'deki `AuthPage.tsx` sekmelerinin karşılığı:
- Giriş formu (e-posta + şifre)
- Kayıt formu (+ görünen ad)
- "Şifremi unuttum" akışı
- "Doğrulama e-postasını tekrar gönder"
- Form validasyonu + hata/başarı mesajları (web'deki toast'ların SnackBar karşılığı)

## 4. Deep link (şifre sıfırlama)
- `AndroidManifest.xml`'e intent-filter: `io.supabase.calorix://reset-callback`
- Web build'de: `https://<host>/#/auth` (hash router veya go_router web URL stratejisi)
- `supabase_flutter` PASSWORD_RECOVERY eventini otomatik yakalar

## 5. Onboarding (`features/onboarding/`)
Web `OnboardingPage.tsx` adımlarının karşılığı (mevcut alanlar `profiles` tablosuna göre):
- Adım adım: cinsiyet, doğum tarihi/yaş, boy, kilo, aktivite seviyesi, hedef (kilo verme/koruma/alma), hedef kilo
- Son adımda `calculate-macros` Edge Function çağrısı → günlük kalori/makro hedefleri hesaplanır ve `user_settings`'e yazılır (web'deki akışın aynısı — önce web kodundaki çağrı imzası okunacak)
- `profiles.onboarding_completed = true`

## 6. Profil katmanı
- `ProfileRepository` — `profiles` tablosu CRUD
- `profileProvider` — Riverpod, oturum açıkken profili yükler ve cache'ler (web `ProfileContext` karşılığı)
- Model: `lib/data/models/profile.dart` (json_serializable)

## 7. user_settings & user_roles
- `UserSettings` modeli + repository (hedefler: daily_calorie_goal, protein/carbs/fat hedefleri, su hedefi vb. — `supabase/types.ts`'ten birebir)
- Rol kontrolü (admin) gerekirse `user_roles` okunur (Faz 3'te ayarlarda kullanılabilir)

## Teslim kriterleri
- [ ] Kayıt → doğrulama e-postası → giriş akışı Android'de uçtan uca çalışıyor
- [ ] Şifre sıfırlama e-postası → deep link → yeni şifre formu çalışıyor
- [ ] Onboarding tamamlanınca `user_settings`'te hesaplanmış hedefler oluşuyor
- [ ] Uygulama yeniden başlatıldığında oturum kalıcı (persistSession karşılığı varsayılan açık)
- [ ] Web'de aynı hesapla açıldığında profil/ayarlar birebir aynı görünüyor
- [ ] Unit test: AuthRepository (mocktail ile mock SupabaseClient)

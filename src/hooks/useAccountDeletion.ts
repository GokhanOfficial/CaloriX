import { useCallback, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import {
  AccountDeletionError,
  mapHttpError,
  parseSuccessResponse,
  validatePassword,
  type AccountDeletionResult,
} from '@/lib/accountDeletion';

/**
 * Web PWA için hesap silme akışı (KVKK / Google Play zorunluluğu).
 *
 * ## Sunucu hazır, arayüz eksikti
 *
 * `supabase/functions/delete-account` A1r3/A1r4/A1r5 tarafından yazıldı ve
 * test edildi; Flutter arayüzü A4r4b'de geldi
 * (`flutter_app/lib/features/settings/widgets/delete_account_dialog.dart`).
 * **React PWA'da hiçbir giriş noktası yoktu** → web kullanıcısı hesabını
 * elle silmek zorundaydı, KVKK "sil" eksikti. Bu hook o giriş noktasını
 * sağlar.
 *
 * ## Neden `functions.invoke` (elle `fetch` değil)
 *
 * `delete-account/index.ts`:
 *  - yalnızca `POST`;
 *  - `readJsonBody` **yalnızca** `application/json` (ya da hiç başlık yok)
 *    kabul eder → `text/plain` **415**;
 *  - `requireUserContext` JWT'yi sunucu tarafında doğrular.
 *
 * `supabase.functions.invoke` gövde verildiğinde `Content-Type:
 * application/json` başlığını ve `Authorization: Bearer <token>`'ı
 * **kendisi** ekler. Elle `fetch` yalnızca 415 riski değil, JWT'yi elle
 * taşıma zorunluluğu yüzünden **token sızıntısı** riski de taşır.
 * Supabase client'ın `fetch`'i zaten `fetchWithAuth` ile değiştirilmiştir
 * (bkz. `integrations/supabase/functions.ts` yorumu).
 *
 * ## Hata gövdesi nasıl okunur?
 *
 * `functions.invoke` non-2xx'te `FunctionsHttpError` **fırlatmaz**;
 * `{ data: null, error, response }` döner ve `error.context` `Response`'tır.
 * Gövdeyi oradan okuyup [mapHttpError]'a veriyoruz. Ağ hatasında `response`
 * `undefined` olur ve `status: 0` → `network`.
 *
 * ## Parola hiçbir koşulda loglanmaz
 *
 * `console.error` yalnızca **HTTP durum kodunu** raporlar; parola, sunucu
 * metni veya hata nesnesi gövde **loglanmaz**. Bu, `AppLog.scrubPii`'nin
 * maskelemesine ek olarak bir savunma derinliği katmanıdır (aynı kural
 * Flutter `AccountRepository`'de de var).
 */
export function useAccountDeletion() {
  const { user, signOut } = useAuth();
  const navigate = useNavigate();
  const [isDeleting, setIsDeleting] = useState(false);
  const [error, setError] = useState<AccountDeletionError | null>(null);

  /**
   * Hesabı ve tüm kişisel verisini kalıcı olarak siler.
   *
   * @param password kullanıcının **mevcut** parolası. Sunucu bunu
   *   `signInWithPassword` ile doğrular; oturum JWT'si tek başına
   *   **yetmez** (XSS ile alınan bir oturum başkasının hesabını silemez).
   *
   * @returns başarı durumunda [AccountDeletionResult] (tam veya kısmi).
   *   Hata durumunda [AccountDeletionError] **fırlatır**; çağıran `kind`
   *   alanına göre mesaj gösterir.
   */
  const deleteAccount = useCallback(
    async (password: string): Promise<AccountDeletionResult> => {
      if (!user) {
        throw new AccountDeletionError('unauthorized', null);
      }
      // Çift gönderim kapısı: sunucu kotası **2/saat**; iki tık "kota
      // doldu" ekranına götürür ve kullanıcı ikinci denemeyi bile yapamaz.
      if (isDeleting) {
        throw new AccountDeletionError('network', null);
      }

      // Boş/çok uzun parola gönderilmez → kota korunur.
      const invalid = validatePassword(password);
      if (invalid) throw invalid;

      setIsDeleting(true);
      setError(null);
      try {
        const { data, error: invokeError, response } = await supabase.functions.invoke(
          'delete-account',
          // Gövde **yalnızca** `password`. `userId` eklemek işe yaramaz
          // (`readJsonBody` yok sayar) ve gereksiz PI'dır.
          { body: { password: password.trim() } },
        );

        if (invokeError) {
          // Yalnızca **durum kodu** loglanır — parola ve sunucu metni yok.
          const status =
            typeof response?.status === 'number' ? response.status : 0;
          console.error(`Account deletion request failed (HTTP ${status})`);
          // Hata gövdesi: `response.json()` — `FunctionsHttpError.context`
          // elde yoksa boş kalır ve `mapHttpError` yalnızca durum koduna
          // bakar (bilinen davranış, kırılgan bağ değil).
          let body: unknown = null;
          try {
            body = response ? await response.clone().json() : null;
          } catch {
            body = null;
          }
          const mapped = mapHttpError(status, body);
          setError(mapped);
          throw mapped;
        }

        const result = parseSuccessResponse(data);
        if (result.partial) {
          // `auth.admin.deleteUser()` BAŞARISIZ ⇒ hesap hâlâ duruyor.
          // Kullanıcı yeniden denemelidir; "başarıyla silindi" demek yanlış.
          console.error('Account deletion partially completed; retry recommended');
        }
        return result;
      } finally {
        setIsDeleting(false);
      }
    },
    [user, isDeleting],
  );

  /**
   * Tam silme sonrası oturumu düşürür ve `/auth`'a yönlendirir.
   *
   * Sıra Flutter `_finishDeletion` ile aynı:
   *  1. `signOut()` — sunucu auth kaydını zaten sildi; çağırmak cihazdaki
   *     JWT'yi de atar.
   *  2. `navigate('/auth')` — `signOut` hata verirse bile kullanıcının
   *     giriş ekranında kaldığını garanti eder.
   */
  const finishDeletion = useCallback(async () => {
    await signOut();
    navigate('/auth');
  }, [signOut, navigate]);

  return { deleteAccount, finishDeletion, isDeleting, error, clearError: () => setError(null) };
}

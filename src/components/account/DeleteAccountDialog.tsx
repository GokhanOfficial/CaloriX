import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { AlertTriangle, Loader2, Lock } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';
import { useAccountDeletion } from '@/hooks/useAccountDeletion';
import type { AccountDeletionErrorKind } from '@/lib/accountDeletion';

/**
 * Hesap silme diyaloğu — web PWA giriş noktası (KVKK / Google Play).
 *
 * ## Flutter ile hizalama
 *
 * `flutter_app/lib/features/settings/widgets/delete_account_dialog.dart`:
 *  - **iki aşamalı** onay: uyarı diyaloğu → parola alanı. Tek tıklamayla
 *    geri alınamaz bir işlem kazara veri kaybı üretir (Google Play
 *    politikası ve KVKK Madde 11 bilinçli onay ister). Bu yüzden ikinci
 *    aşama zorunludur.
 *  - Hata mesajı `kind`'e göre seçilir, **sunucunun ham Türkçe metni
 *    asla gösterilmez** (12 dilde tutarsız olur ve tablo/kolon adı
 *    sızdırabilir). Burada da aynı: yalnızca **anlam** taşınır.
 *  - `partial` (kısmi silme) → **başarı gibi gösterilmez**; düğme yeniden
 *    etkinleşir, alan temizlenir, kullanıcı yeniden dener.
 *  - Hatalı parolada alan **temizlenir** ve odak alana döner: kullanıcının
 *    yanlış parolayı tekrar tekrar göndermesi kotayı (2/saat) tüketir.
 *  - Boş parola gönderilmez (`validatePassword`).
 *
 * Tam UX (cihaz temizliği, widget sıfırlama) Flutter'da var; web PWA'da
 * görev tanımı "en küçük giriş noktası, çalışan ve doğru mesajları
 * gösteren akış yeterli" diyor — bu yüzden cihaz temizliği yoktur
 * (web'de `home_widget`/paylaşılan tercih deposu da yok).
 */
export function DeleteAccountDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const { t } = useTranslation();
  const { toast } = useToast();
  const { deleteAccount, finishDeletion, isDeleting, error, clearError } = useAccountDeletion();
  const [password, setPassword] = useState('');

  const messageFor = (kind: AccountDeletionErrorKind): string => {
    switch (kind) {
      case 'wrongPassword':
        return t('settings.deleteAccount.messages.wrongPassword');
      case 'rateLimited':
        return t('settings.deleteAccount.messages.rateLimited');
      case 'invalidRequest':
        return t('settings.deleteAccount.messages.invalidRequest');
      case 'unauthorized':
        return t('settings.deleteAccount.messages.unauthorized');
      case 'network':
        return t('settings.deleteAccount.messages.network');
      default:
        return t('settings.deleteAccount.messages.failed');
    }
  };

  const handleOpenChange = (next: boolean) => {
    // Yükleme sırasında kapatma **kilitlenir**: kullanıcı istek uçarken
    // diyaloğu kapatırsa durum takibi kaybolur ve "başarı" gösterilmeden
    // oturum açık kalır.
    if (isDeleting) return;
    if (!next) {
      setPassword('');
      clearError();
    }
    onOpenChange(next);
  };

  const handleSubmit = async () => {
    if (isDeleting) return;
    try {
      const result = await deleteAccount(password);
      if (result.partial) {
        // Hesap hâlâ duruyor — "başarı" demek yanlış olur.
        toast({
          title: t('common.error'),
          description: t('settings.deleteAccount.messages.partial'),
          variant: 'destructive',
        });
        setPassword('');
        return;
      }
      // Tam silme → oturumu düşür + giriş ekranına dön.
      await finishDeletion();
    } catch (err) {
      const kind = (err as { kind?: AccountDeletionErrorKind }).kind ?? 'unknown';
      toast({ title: t('common.error'), description: messageFor(kind), variant: 'destructive' });
      // Parola hatalıysa alanı temizle: yanlış parolayı tekrar göndermek
      // kotayı (2/saat) tüketir. Ağ hatasında alan **korunur** — kullanıcı
      // aynı doğru parolayı yeniden deneyebilmelidir.
      if (kind === 'wrongPassword') {
        setPassword('');
        document.getElementById('delete-account-password')?.focus();
      }
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-destructive">
            <AlertTriangle className="h-5 w-5" aria-hidden="true" />
            {t('settings.deleteAccount.title')}
          </DialogTitle>
          <DialogDescription>
            {t('settings.deleteAccount.warning')}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          <ul className="space-y-1 text-sm text-muted-foreground">
            {[
              t('settings.deleteAccount.data.meals'),
              t('settings.deleteAccount.data.water'),
              t('settings.deleteAccount.data.weight'),
              t('settings.deleteAccount.data.chat'),
              t('settings.deleteAccount.data.favorites'),
              t('settings.deleteAccount.data.settings'),
              t('settings.deleteAccount.data.notifications'),
            ].map((item) => (
              <li key={item}>• {item}</li>
            ))}
          </ul>

          <p className="rounded-lg bg-destructive/10 border border-destructive/20 p-3 text-sm font-semibold text-destructive">
            {t('settings.deleteAccount.irreversible')}
          </p>

          {error && (
            <p role="alert" className="text-sm text-destructive">
              {messageFor(error.kind)}
            </p>
          )}

          <div className="space-y-2">
            <Label htmlFor="delete-account-password" className="flex items-center gap-2">
              <Lock className="h-4 w-4" aria-hidden="true" />
              {t('settings.deleteAccount.passwordLabel')}
            </Label>
            <Input
              id="delete-account-password"
              type="password"
              autoComplete="current-password"
              // Parola alanında otomatik düzeltme/öneri kapalı: klavye
              // parolayı sözlüğe yazabilir.
              autoCorrect="off"
              autoCapitalize="none"
              spellCheck={false}
              disabled={isDeleting}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  void handleSubmit();
                }
              }}
              placeholder={t('settings.deleteAccount.passwordRequired')}
            />
          </div>

          {isDeleting && (
            <p className="flex items-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
              {t('settings.deleteAccount.deleting')}
            </p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => handleOpenChange(false)} disabled={isDeleting}>
            {t('common.cancel')}
          </Button>
          <Button variant="destructive" onClick={handleSubmit} disabled={isDeleting}>
            {isDeleting && <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" />}
            {t('settings.deleteAccount.confirm')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default DeleteAccountDialog;

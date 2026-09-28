import { useCallback, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';
import { APP_VERSION } from '@/lib/constants';
import { localDateFromIso } from '@/lib/import/backupImport';
import {
  ImportFormatError,
  ImportValidationError,
  ImportWriteError,
  importBackup,
} from '@/lib/import/backupRestore';

export { localDateFromIso };

/**
 * Kullanıcıya gösterilebilir, **içerik sızdırmayan** hata etiketi.
 *
 * `SyntaxError` → dosya JSON değil (beklenen en yaygın senaryo: kullanıcı
 * yanlış dosyayı seçti). Diğer her şey için sınıf adı — dosya yolu, tablo
 * adı ya da kısıt adı taşımaz.
 */
function errorName(error: unknown): string {
  if (error instanceof SyntaxError) return 'geçersiz JSON biçimi';
  if (error instanceof Error && error.name) return error.name;
  return 'bilinmeyen hata';
}

export interface ExportData {
  version: string;
  exportedAt: string;
  profile: Record<string, unknown> | null;
  mealEntries: Record<string, unknown>[];
  waterEntries: Record<string, unknown>[];
  weightEntries: Record<string, unknown>[];
  /** Kullanıcının kendi gıdaları; `food_nutrition` iç içe gelir. */
  foods: Record<string, unknown>[];
  favoriteFoods: Record<string, unknown>[];
  recentFoods: Record<string, unknown>[];
  notificationPreferences: Record<string, unknown>[];
}

export function useDataExport() {
  const { user } = useAuth();
  const { toast } = useToast();
  const [isExporting, setIsExporting] = useState(false);
  const [isImporting, setIsImporting] = useState(false);

  const exportData = useCallback(async () => {
    if (!user) {
      toast({ title: 'Hata', description: 'Oturum açmanız gerekiyor', variant: 'destructive' });
      return;
    }

    setIsExporting(true);

    try {
      // Kullanıcının gıdaları (besin satırları iç içe) paralel okunur.
      const [
        profileRes,
        mealEntriesRes,
        waterEntriesRes,
        weightEntriesRes,
        foodsRes,
        favoriteFoodsRes,
        recentFoodsRes,
        notificationPrefsRes,
      ] = await Promise.all([
        supabase.from('profiles').select('*').eq('id', user.id).single(),
        // Yumuşak silinmiş satırlar **dışa aktarılmaz**: içe aktarım
        // `deleted_at` dolu satırları zaten yok sayıyor, ama yedekte
        // taşınmaları kullanıcıyı "sildiğim kayıt geri geldi" yanılgısına
        // sokar.
        supabase.from('meal_entries').select('*').eq('user_id', user.id).is('deleted_at', null),
        supabase.from('water_entries').select('*').eq('user_id', user.id).is('deleted_at', null),
        supabase.from('weight_entries').select('*').eq('user_id', user.id).is('deleted_at', null),
        supabase.from('foods').select('*, food_nutrition(*)').eq('created_by', user.id),
        supabase.from('favorite_foods').select('*').eq('user_id', user.id),
        supabase.from('recent_foods').select('*').eq('user_id', user.id),
        supabase.from('notification_preferences').select('*').eq('user_id', user.id),
      ]);

      // Hatalar **sessizce yutulmaz**: `?? []` ile boş liste dönen bir
      // export, kullanıcıya eksiksiz bir yedekmiş gibi gösterilirdi.
      const failures: string[] = [];
      if (profileRes.error) failures.push('profil');
      if (mealEntriesRes.error) failures.push('öğünler');
      if (waterEntriesRes.error) failures.push('su kayıtları');
      if (weightEntriesRes.error) failures.push('kilo kayıtları');
      if (foodsRes.error) failures.push('gıdalar');
      if (favoriteFoodsRes.error) failures.push('favoriler');
      if (recentFoodsRes.error) failures.push('son kullanılanlar');
      if (notificationPrefsRes.error) failures.push('bildirim ayarları');

      if (failures.length > 0) {
        console.error('Export: sorgu hataları', failures, {
          profile: profileRes.error,
          meals: mealEntriesRes.error,
          water: waterEntriesRes.error,
          weight: weightEntriesRes.error,
          foods: foodsRes.error,
          favorites: favoriteFoodsRes.error,
          recents: recentFoodsRes.error,
          notifications: notificationPrefsRes.error,
        });
        toast({
          title: 'Dışa Aktarma Eksik',
          description: `Şu bölümler okunamadı: ${failures.join(', ')}. Yedek eksik içerikle oluşturuldu — geri yüklemede bu bölümler boş kalabilir.`,
          variant: 'destructive',
        });
      }

      const payload: ExportData = {
        version: APP_VERSION,
        exportedAt: new Date().toISOString(),
        profile: profileRes.data,
        mealEntries: mealEntriesRes.data ?? [],
        waterEntries: waterEntriesRes.data ?? [],
        weightEntries: weightEntriesRes.data ?? [],
        foods: foodsRes.data ?? [],
        favoriteFoods: favoriteFoodsRes.data ?? [],
        recentFoods: recentFoodsRes.data ?? [],
        notificationPreferences: notificationPrefsRes.data ?? [],
      };

      const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `calorix-backup-${localDateFromIso(new Date().toISOString())}.json`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);

      if (failures.length === 0) {
        toast({
          title: 'Dışa Aktarma Başarılı',
          description: `${mealEntriesRes.data?.length || 0} öğün, ${waterEntriesRes.data?.length || 0} su kaydı, ${weightEntriesRes.data?.length || 0} kilo kaydı dışa aktarıldı.`,
        });
      }
    } catch (error) {
      console.error('Export error:', error);
      toast({ title: 'Hata', description: 'Veriler dışa aktarılamadı', variant: 'destructive' });
    } finally {
      setIsExporting(false);
    }
  }, [user, toast]);

  const importData = useCallback(async (file: File) => {
    if (!user) {
      toast({ title: 'Hata', description: 'Oturum açmanız gerekiyor', variant: 'destructive' });
      return;
    }

    setIsImporting(true);

    try {
      const text = await file.text();

      // Üç fazlı akış: ön-uçu doğrulama (ağ yok) → varlık kontrolü (yalnız
      // GET) → toplu + telafili yazma. Tek bir ölümcül ihlalde **hiçbir
      // istek atılmaz**; yazma hatasında o turda yazılanlar `id` ile
      // fiziksel olarak silinir ve `counts` her zaman dolu döner.
      const { report, issues } = await importBackup(user.id, text);
      const { counts } = report;

      const skippedTotal = Object.values(report.skipped).reduce((a, b) => a + b, 0);
      const coercedTotal = Object.values(report.coerced).reduce((a, b) => a + b, 0);

      const details = [
        `${counts.meal_entries} öğün`,
        `${counts.water_entries} su`,
        `${counts.weight_entries} kilo`,
        `${counts.foods} gıda`,
        `${counts.favorite_foods} favori`,
        `${counts.recent_foods} son kullanılan`,
      ].join(', ');

      // Atlanan/düzeltilen satırlar **görünür** olmalı: eski sürümde
      // yedekten satır kayboldu ve kullanıcı bunu öğrenemiyordu.
      const notes: string[] = [];
      if (skippedTotal > 0) {
        notes.push(
          `${skippedTotal} satır atlandı` +
            ` (${Object.entries(report.skipped)
              .map(([t, n]) => `${t}: ${n}`)
              .join(', ')})`,
        );
      }
      if (coercedTotal > 0) {
        notes.push(
          `${coercedTotal} alan güvenli varsayılana çekildi` +
            ` (${Object.entries(report.coerced)
              .map(([t, n]) => `${t}: ${n}`)
              .join(', ')})`,
        );
      }

      toast({
        title: 'İçe Aktarma Tamamlandı',
        description: `${details}.${notes.length ? ' ' + notes.join('. ') + '.' : ''}`,
      });

      if (issues.length > 0) {
        console.info('Import: atlanan/düzeltilen satırlar', issues);
      }
    } catch (error) {
      // `error.message` **kullanıcıya doğrudan gösterilmiyor**.
      // `JSON.parse` hatası dosya yolunu (`/home/kullanici/.../backup.json`)
      // sızdırır; Supabase `PostgrestError.message` ise tablo/kolon
      // adlarını ve kısıt adlarını (örn. `meal_entries_amount_g_ml_check`)
      // içerebilir. Yalnızca **kendi** metnimiz kullanılıyor.
      console.error('Import error:', error);

      if (error instanceof ImportFormatError) {
        toast({
          title: 'Hata',
          description:
            'Dosya geçerli bir CaloriX yedeği değil (JSON okunamadı ya da sürüm damgası eksik).',
          variant: 'destructive',
        });
        return;
      }

      if (error instanceof ImportValidationError) {
        // Ön-uçu: **hiçbir kayıt yazılmadı**. Bu mesaj önemli çünkü
        // kullanıcı aksi halde yarım veriyle kaldığını sanar.
        toast({
          title: 'Yedek Doğrulanamadı — Hiçbir Kayıt Eklenmedi',
          description: `${error.summary} Toplam ${error.totalIssues} sorun bulundu. Dosyayı düzeltip tekrar deneyin.`,
          variant: 'destructive',
        });
        return;
      }

      if (error instanceof ImportWriteError) {
        const { report } = error;
        const added = report.counts.meal_entries + report.counts.water_entries +
          report.counts.weight_entries + report.counts.foods;
        const rolled =
          report.rolledBack === true
            ? 'Eklenen kayıtlar geri alındı, veriniz değişmedi.'
            : `Eklenen kayıtlar geri alınamadı (${Object.entries(report.survivors)
                .map(([t, n]) => `${t}: ${n}`)
                .join(', ')}).`;
        toast({
          title: `İçe Aktarma "${error.stage}" Adımında Durdu`,
          description: `${added} kayıt eklenmişti. ${rolled}`,
          variant: 'destructive',
        });
        return;
      }

      toast({
        title: 'Hata',
        description: `Yedek dosyası içe aktarılamadı (${errorName(error)}). Dosyanın CaloriX tarafından dışa aktarılmış olduğundan emin olun.`,
        variant: 'destructive',
      });
    } finally {
      setIsImporting(false);
    }
  }, [user, toast]);

  return {
    exportData,
    importData,
    isExporting,
    isImporting,
  };
}

import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';
import {
  NOTIFICATION_TYPES,
  applyMasterSwitches,
  buildPreferenceRow,
  normalizePreference,
  type NotificationType,
  type PreferenceDraft,
} from '@/lib/notificationPreferences';

export type { NotificationType };

/**
 * Profil seviyesi **master** anahtarlar (`profiles.push_notifications_enabled`
 * / `email_notifications_enabled`).
 *
 * Neden gerekli: `send-notification/index.ts:423-424`
 * `preference?.push_enabled ?? profile.push_notifications_enabled` okuyor ve
 * `??` **yalnız `NULL` üstüne düşer**. Satır bir kez yazıldıktan sonra profil
 * master anahtarı **hiç okunmaz** → kullanıcı üstteki anahtarı kapatır,
 * bildirim yine gider. Flutter bu hatanın karşılığını
 * `NotificationPreferencesRepository.applyMasterSwitches` (AND) ile çözdü;
 * web'de de **aynı** bileşim uygulanır.
 */
export interface MasterSwitches {
  push: boolean;
  email: boolean;
}

export interface NotificationPreference extends PreferenceDraft {
  id: string;
  notification_type: NotificationType;
}

export interface Notification {
  id: string;
  title: string;
  message: string;
  type: string;
  is_read: boolean;
  created_at: string;
}

/**
 * Bir tipin **sunucu tarafı** varsayılanı.
 *
 * ⭐ Değerler Flutter `defaultServerPreference`
 * (`notification_preferences_repository.dart:72-123`) ile **birebir aynıdır**;
 * iki istemci farklı varsayılan üretirse aynı kullanıcı web'de ve
 * Flutter'da farklı davranış görür.
 *
 * **Eski hata (P1, A1r8/A4r8 ölçümü):** buradaki `interval_hours: 0` değerleri
 * DB CHECK'i `notification_preferences_hours_range` ihlal ediyordu
 * (`interval_hours BETWEEN 1 AND 24`) → web'de sunucu bildirim tercihi
 * **kaydedilemiyordu**. Flutter'da olduğu gibi `1` (ve `goal_achieved`
 * için `24`) yazılıyor; ayrıntılı gerekçe `lib/notificationPreferences.ts`.
 *
 * `weekly_summary` `push_enabled: false` kalır: sunucu haftalık özeti
 * e-posta kanalına yollar (Flutter ile aynı).
 */
const NOTIFICATION_DEFAULTS: Record<NotificationType, PreferenceDraft> = {
  weigh_in: { push_enabled: true, email_enabled: true, start_hour: 9, end_hour: 9, interval_hours: 1, summary_day: 1, summary_hour: 9 },
  daily_log: { push_enabled: true, email_enabled: false, start_hour: 18, end_hour: 18, interval_hours: 1, summary_day: 1, summary_hour: 9 },
  water: { push_enabled: true, email_enabled: false, start_hour: 9, end_hour: 21, interval_hours: 3, summary_day: 1, summary_hour: 9 },
  goal_achieved: { push_enabled: true, email_enabled: false, start_hour: 0, end_hour: 23, interval_hours: 24, summary_day: 1, summary_hour: 9 },
  weekly_summary: { push_enabled: false, email_enabled: true, start_hour: 9, end_hour: 9, interval_hours: 1, summary_day: 1, summary_hour: 9 },
};

export const NOTIFICATION_LABELS: Record<NotificationType, { title: string; description: string }> = {
  weigh_in: { title: 'Tartılma Hatırlatıcısı', description: 'Düzenli aralıklarla tartılma hatırlatması' },
  daily_log: { title: 'Günlük Kayıt', description: '24 saat kayıt yoksa motive edici hatırlatma' },
  water: { title: 'Su İçme Hatırlatıcısı', description: 'Belirli saatlerde su içme hatırlatması' },
  goal_achieved: { title: 'Hedef Başarısı', description: 'Günlük hedefe ulaştığında bildirim' },
  weekly_summary: { title: 'Haftalık Özet', description: 'Haftalık ilerleme raporu' },
};

/**
 * Kullanıcıya **görünür** hata durumu.
 *
 * A6r3 aktarımı: `fetchPreferences`/`subscribeToPush` hata halinde
 * `console.error` + `return` yapıyordu → ekranda eski veri kalıyor,
 * kullanıcı hatayı göremiyor, push aboneliği sessizce başarısız oluyordu.
 * Bu tip hem "hangi işlem" bilgisini (etiket + mesaj) hem de
 * `retry`'yi taşır; çağıran ekran `error` + `retry` gösterir.
 */
export interface NotificationError {
  /** Hata üreten işlem. Kullanıcıya gösterilir (iç ayrıntı taşımaz). */
  operation: 'preferences' | 'notifications' | 'push';
  /** İçerik sızdırmayan tek satırlık açıklama. */
  message: string;
  /**
   * Kullanıcıya **gösterilmeyen** ayrıntı (konsola gider). Tablo/kolon
   * adları ve kısıt adları burada bulunabilir.
   */
  detail?: unknown;
}

export function useNotifications() {
  const { user } = useAuth();
  const { toast } = useToast();
  const [preferences, setPreferences] = useState<NotificationPreference[]>([]);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [pushPermission, setPushPermission] = useState<NotificationPermission>('default');
  /**
   * Görünür hata. `null` → sorun yok.
   *
   * Önceki davranış: `console.error` + `return` → kullanıcı eski (ya da
   * hiç yüklenmemiş) veriyi "güncel" sanıyordu, ayar kaydedemiyordu ve
   * nedenini öğrenemiyordu.
   */
  const [error, setError] = useState<NotificationError | null>(null);

  // Check push notification permission
  useEffect(() => {
    if ('Notification' in window) {
      setPushPermission(Notification.permission);
    }
  }, []);

  // Subscribe to push notifications.
  // `useRef` ile paylaşılır: hem `requestPushPermission` hem de dışarıdan
  // tetiklenebilen yollar aynı örneği kullanmalı (fonk. referansı değil).
  const subscribeToPushRef = useRef<() => Promise<boolean>>(async () => false);

  // Request push notification permission
  const requestPushPermission = useCallback(async () => {
    if (!('Notification' in window)) {
      setError({
        operation: 'push',
        message: 'Tarayıcınız bildirimleri desteklemiyor.',
      });
      toast({ title: 'Hata', description: 'Tarayıcınız bildirimleri desteklemiyor', variant: 'destructive' });
      return false;
    }

    const permission = await Notification.requestPermission();
    setPushPermission(permission);

    if (permission === 'granted') {
      // Abonelik gerçekten kuruldu mu? `subscribeToPush` artık
      // başarısızlığı **görünür** kılıyor; eskiden `requestPushPermission`
      // izni aldığı için `true` dönüyor, abonelik sessizce başarısız
      // olsa bile anahtar "açık" görünüyordu.
      return await subscribeToPushRef.current();
    }

    setError({
      operation: 'push',
      message: 'Bildirim izni verilmedi. Tarayıcı ayarlarından izin verebilirsiniz.',
    });
    return false;
  }, [toast]);

  // Subscribe to push notifications
  const subscribeToPush = useCallback(async () => {
    if (!user || !('serviceWorker' in navigator)) {
      // Sessiz `return` yerine görünür hata: "push açıldı" görünen bir
      // anahtar, aboneliğin hiç oluşmadığı anlamına gelmemeli.
      setError({
        operation: 'push',
        message: 'Bu tarayıcıda push bildirimleri desteklenmiyor.',
      });
      return false;
    }

    try {
      const registration = await navigator.serviceWorker.ready;

      // Get VAPID public key from environment
      const vapidPublicKey = import.meta.env.VITE_VAPID_PUBLIC_KEY;

      if (!vapidPublicKey) {
        // Daha önce `console.warn` + `return`: kullanıcı anahtarı açıyor,
        // abonelik hiç oluşmuyor, hiçbir bildirim gelmiyor ve **neden
        // belli olmuyor**. Şimdi ayar hatası olarak görünür.
        setError({
          operation: 'push',
          message: 'Push bildirimleri için VAPID anahtarı tanımlı değil (VITE_VAPID_PUBLIC_KEY).',
        });
        return false;
      }

      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey) as BufferSource,
      });

      const subscriptionJson = subscription.toJSON();

      // Save subscription to database
      const { error } = await supabase.from('push_subscriptions').upsert({
        user_id: user.id,
        endpoint: subscriptionJson.endpoint!,
        p256dh: subscriptionJson.keys?.p256dh || '',
        auth: subscriptionJson.keys?.auth || '',
      }, {
        onConflict: 'user_id,endpoint',
      });

      if (error) throw error;
      setError(null);
      return true;
    } catch (err) {
      // `console.error` **korunuyor** (ayrıntı oraya), ama artık
      // kullanıcı da bilgilendiriliyor: abonelik sessizce başarısız
      // olduğunda "bildirim gelmiyor" şikâyeti çözülemez durumdaydı.
      console.error('Error subscribing to push:', err);
      setError({
        operation: 'push',
        message: 'Push aboneliği oluşturulamadı. Tekrar deneyebilirsiniz.',
        detail: err,
      });
      return false;
    }
  }, [user]);

  // `subscribeToPush` tanımlandıktan sonra ref'i güncelle; böylece
  // `requestPushPermission` güncel `user`'a bağlı örneği çağırır.
  useEffect(() => {
    subscribeToPushRef.current = subscribeToPush;
  }, [subscribeToPush]);

  // Fetch notification preferences
  const fetchPreferences = useCallback(async () => {
    if (!user) return false;

    const { data, error: queryError } = await supabase
      .from('notification_preferences')
      .select('*')
      .eq('user_id', user.id);

    if (queryError) {
      // Eski davranış: `console.error` + `return` → `preferences`
      // **eskiden yüklenen** (ya da hiç yüklenmemiş) değerde kalıyordu ve
      // ayar ekranı bunu "başarılı" gösteriyordu. Kullanıcı değişikliği
      // kaydedip kaydetmediğini öğrenemiyordu.
      console.error('Error fetching preferences:', queryError);
      setError({
        operation: 'preferences',
        message: 'Bildirim tercihleri yüklenemedi. Ayarları kaydetmeye çalışmadan önce tekrar deneyin.',
        detail: queryError,
      });
      return false;
    }

    // Eksik tipler varsayılanla doldurulur. Satır **okunurken** de
    // normalize edilir: kolonlar nullable olduğu için DB'de `null` gelebilir
    // ve `null` "sunucu varsayılanına düş" demektir; ekranda `NaN`/geçersiz
    // bir değer göstermiyoruz ve **kaydederken** de aynı normalize
    // kuralı uygulanıyor (yoksa `0` yeniden yazılırdı).
    const mergedPrefs = NOTIFICATION_TYPES.map(type => {
      const existing = data?.find(p => p.notification_type === type);
      const fallback = NOTIFICATION_DEFAULTS[type];
      const draft = existing
        ? normalizePreference(type, { ...fallback, ...existing })
        : fallback;
      return {
        id: existing?.id ?? '',
        notification_type: type,
        ...draft,
      } as NotificationPreference;
    });

    setPreferences(mergedPrefs);
    setError((prev) => (prev?.operation === 'preferences' ? null : prev));
    return true;
  }, [user]);

  // Fetch notifications
  const fetchNotifications = useCallback(async () => {
    if (!user) return false;

    const { data, error: queryError } = await supabase
      .from('notifications')
      .select('*')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(50);

    if (queryError) {
      console.error('Error fetching notifications:', queryError);
      setError({
        operation: 'notifications',
        message: 'Bildirimler yüklenemedi.',
        detail: queryError,
      });
      return false;
    }

    setNotifications(data || []);
    setUnreadCount(data?.filter(n => !n.is_read).length || 0);
    setError((prev) => (prev?.operation === 'notifications' ? null : prev));
    return true;
  }, [user]);

  // Update preference
  const updatePreference = useCallback(async (
    type: NotificationType,
    updates: Partial<NotificationPreference>,
    /** Profil master anahtarları — bkz. `applyMasterSwitches` notu. */
    master?: MasterSwitches,
  ): Promise<boolean> => {
    if (!user) return false;

    const existing = preferences.find(p => p.notification_type === type);

    // ⭐ Yazılan satır **daima normalize** edilir (`buildPreferenceRow`).
    // Eski davranış `...updates` dosyasını olduğu gibi gönderiyordu:
    // `interval_hours: 0` yazan bir çağıran (ayarlar ekranı, yedek içe
    // aktarım, gelecekteki bir form) DB CHECK'ine takılıp **kaydı
    // düşürüyordu**. Artık normalize katmanı tek yerde.
    const row = buildPreferenceRow(user.id, type, {
      ...NOTIFICATION_DEFAULTS[type],
      ...(existing ?? {}),
      ...updates,
    });
    const effective = master ? applyMasterSwitches([row], master)[0] : row;

    // Use upsert to handle both insert and update atomically
    const { data, error: writeError } = await supabase
      .from('notification_preferences')
      .upsert(effective, {
        onConflict: 'user_id,notification_type',
        ignoreDuplicates: false,
      })
      .select()
      .single();

    if (writeError) {
      console.error('Error updating preference:', writeError);
      setError({
        operation: 'preferences',
        message: 'Ayarlar kaydedilemedi. Değişikliğiniz DB\'ye ulaşmadı.',
        detail: writeError,
      });
      toast({ title: 'Hata', description: 'Ayarlar kaydedilemedi', variant: 'destructive' });
      return false;
    }

    setError((prev) => (prev?.operation === 'preferences' ? null : prev));

    // Update local state with returned data
    if (data) {
      setPreferences(prev => {
        const index = prev.findIndex(p => p.notification_type === type);
        if (index >= 0) {
          const newPrefs = [...prev];
          newPrefs[index] = data as NotificationPreference;
          return newPrefs;
        } else {
          return [...prev, data as NotificationPreference];
        }
      });
      return true;
    }

    // Optimistic update
    setPreferences(prev => prev.map(p =>
      p.notification_type === type ? { ...p, ...updates } : p
    ));
    return true;
  }, [user, preferences, toast]);

  /**
   * ⭐ Tüm tipler için satırı **tek seferde** yazar (master anahtarlarla
   * birleştirilmiş hâliyle).
   *
   * Neden ayrı fonksiyon? A4r7'nin "her tip için satır yaz" davranışı
   * Flutter'da `upsertAll` ile tek bir "Kaydet" düğmesine bağlıydı. Web'de
   * `NotificationPreferences` bileşeni her anahtarı **anında** kaydediyordu;
   * dolayısıyla `notification_preferences`'ta satır olmayan bir tip
   * (`check-reminders`'ın sessizce kapattığı `water`/`daily_log`/
   * `weekly_summary`) **hiçbir zaman** satır kazanamıyordu.
   *
   * Ayar ekranı "Kaydet" dediğinde bu fonksiyon beş tipin de satırını
   * yazar → sessiz-kapalı davranış kalıcı olarak kapanır.
   *
   * `master` verilirse **AND** bileşimi uygulanır (bkz. `MasterSwitches`).
   * `false` dönen değer en az bir satırın yazılamadığını gösterir;
   * çağıran bunu kullanıcıya **görünür** hata olarak bildirir.
   */
  const saveAllPreferences = useCallback(async (
    drafts: Partial<Record<NotificationType, Partial<PreferenceDraft>>>,
    master: MasterSwitches,
  ): Promise<boolean> => {
    if (!user) return false;

    const rows = applyMasterSwitches(
      NOTIFICATION_TYPES.map(type => buildPreferenceRow(user.id, type, {
        ...NOTIFICATION_DEFAULTS[type],
        ...(preferences.find(p => p.notification_type === type) ?? {}),
        ...(drafts[type] ?? {}),
      })),
      master,
    );

    const results = await Promise.all(
      rows.map(row => supabase
        .from('notification_preferences')
        .upsert(row, { onConflict: 'user_id,notification_type', ignoreDuplicates: false })),
    );

    const failed = results.filter(r => r.error);
    if (failed.length > 0) {
      console.error('Error saving preferences:', failed.map(r => r.error));
      setError({
        operation: 'preferences',
        message: 'Ayarlar kaydedilemedi. Değişikliğiniz DB\'ye ulaşmadı.',
        detail: failed[0].error,
      });
      toast({ title: 'Hata', description: 'Ayarlar kaydedilemedi', variant: 'destructive' });
      return false;
    }

    setError((prev) => (prev?.operation === 'preferences' ? null : prev));
    await fetchPreferences();
    return true;
  }, [user, preferences, toast, fetchPreferences]);

  // Mark notification as read
  // `.eq('user_id', user.id)` RLS'e ek savunma katmanı: bir bildirim id'si
  // yanlışlıkla başka kullanıcınınki olsa bile istek kullanıcı kapsamı dışına
  // çıkmaz (RLS zaten UPDATE'i `auth.uid() = user_id` ile sınırlıyor).
  const markAsRead = useCallback(async (notificationId: string) => {
    if (!user) return;

    const { error } = await supabase
      .from('notifications')
      .update({ is_read: true })
      .eq('id', notificationId)
      .eq('user_id', user.id);

    if (!error) {
      setNotifications(prev => prev.map(n =>
        n.id === notificationId ? { ...n, is_read: true } : n
      ));
      setUnreadCount(prev => Math.max(0, prev - 1));
    }
  }, [user]);

  // Mark all as read
  const markAllAsRead = useCallback(async () => {
    if (!user) return;

    const { error } = await supabase
      .from('notifications')
      .update({ is_read: true })
      .eq('user_id', user.id)
      .eq('is_read', false);

    if (!error) {
      setNotifications(prev => prev.map(n => ({ ...n, is_read: true })));
      setUnreadCount(0);
    }
  }, [user]);

  // Delete notification
  const deleteNotification = useCallback(async (notificationId: string) => {
    if (!user) return;

    const { error } = await supabase
      .from('notifications')
      .delete()
      .eq('id', notificationId)
      .eq('user_id', user.id);

    if (!error) {
      setNotifications(prev => prev.filter(n => n.id !== notificationId));
    }
  }, [user]);

  /**
   * Tüm hata halinde görünür hata durumunu temizler (yeniden denemeden
   * önce çağrılır; aksi hâlde eski hata ekranda kalır).
   */
  const clearError = useCallback(() => setError(null), []);

  /**
   * Hatalı işlemi tekrar dener.
   *
   * `preferences` → tercihleri yeniden çeker **ve** bildirim listesini
   *   de tazeler (biri yüklendiğinde diğerinin göstergesi yanıltıcı olur).
   * `notifications` → yalnızca listeyi tazeler.
   * `push` → abonelik işlemini yeniden dener; tarayıcı izni vermediyse
   *   önce izin istenir.
   */
  const retry = useCallback(async () => {
    if (!user) return;
    const operation = error?.operation ?? 'preferences';
    setError(null);

    if (operation === 'push') {
      if (!('Notification' in window)) {
        setError({ operation: 'push', message: 'Tarayıcınız bildirimleri desteklemiyor.' });
        return;
      }
      if (Notification.permission !== 'granted') {
        const permission = await Notification.requestPermission();
        setPushPermission(permission);
        if (permission !== 'granted') {
          setError({
            operation: 'push',
            message: 'Bildirim izni verilmedi. Tarayıcı ayarlarından izin verebilirsiniz.',
          });
          return;
        }
      }
      await subscribeToPushRef.current();
      return;
    }

    if (operation === 'notifications') {
      await fetchNotifications();
      return;
    }
    await Promise.all([fetchPreferences(), fetchNotifications()]);
  }, [user, error, fetchPreferences, fetchNotifications]);

  // Initial fetch
  useEffect(() => {
    if (user) {
      setLoading(true);
      Promise.all([fetchPreferences(), fetchNotifications()]).finally(() => {
        setLoading(false);
      });
    } else {
      // Oturum kapandı: eski kullanıcının tercihleri ekranda kalıyordu.
      setLoading(false);
      setPreferences([]);
      setNotifications([]);
      setUnreadCount(0);
      setError(null);
    }
  }, [user, fetchPreferences, fetchNotifications]);

  return {
    preferences,
    notifications,
    unreadCount,
    loading,
    error,
    clearError,
    retry,
    pushPermission,
    requestPushPermission,
    updatePreference,
    saveAllPreferences,
    markAsRead,
    markAllAsRead,
    deleteNotification,
    refetch: fetchNotifications,
  };
}

// Helper function to convert VAPID key
function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding)
    .replace(/-/g, '+')
    .replace(/_/g, '/');

  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);

  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

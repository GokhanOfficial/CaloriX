import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';

export type NotificationType = 'weigh_in' | 'daily_log' | 'water' | 'goal_achieved' | 'weekly_summary';

export interface NotificationPreference {
  id: string;
  notification_type: NotificationType;
  push_enabled: boolean;
  email_enabled: boolean;
  start_hour: number;
  end_hour: number;
  interval_hours: number;
  summary_day: number;
  summary_hour: number;
}

export interface Notification {
  id: string;
  title: string;
  message: string;
  type: string;
  is_read: boolean;
  created_at: string;
}

const NOTIFICATION_DEFAULTS: Record<NotificationType, Partial<NotificationPreference>> = {
  weigh_in: { push_enabled: true, email_enabled: true, start_hour: 9, end_hour: 9, interval_hours: 0 },
  daily_log: { push_enabled: true, email_enabled: false, start_hour: 18, end_hour: 18, interval_hours: 0 },
  water: { push_enabled: true, email_enabled: false, start_hour: 9, end_hour: 21, interval_hours: 3 },
  goal_achieved: { push_enabled: true, email_enabled: false, start_hour: 0, end_hour: 23, interval_hours: 0 },
  weekly_summary: { push_enabled: false, email_enabled: true, summary_day: 1, summary_hour: 9 },
};

export const NOTIFICATION_LABELS: Record<NotificationType, { title: string; description: string }> = {
  weigh_in: { title: 'Tartılma Hatırlatıcısı', description: 'Düzenli aralıklarla tartılma hatırlatması' },
  daily_log: { title: 'Günlük Kayıt', description: '24 saat kayıt yoksa motive edici hatırlatma' },
  water: { title: 'Su İçme Hatırlatıcısı', description: 'Belirli saatlerde su içme hatırlatması' },
  goal_achieved: { title: 'Hedef Başarısı', description: 'Günlük hedefe ulaştığında bildirim' },
  weekly_summary: { title: 'Haftalık Özet', description: 'Haftalık ilerleme raporu' },
};

export function useNotifications() {
  const { user } = useAuth();
  const { toast } = useToast();
  const [preferences, setPreferences] = useState<NotificationPreference[]>([]);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [pushPermission, setPushPermission] = useState<NotificationPermission>('default');

  // Check push notification permission
  useEffect(() => {
    if ('Notification' in window) {
      setPushPermission(Notification.permission);
    }
  }, []);

  // Request push notification permission
  const requestPushPermission = useCallback(async () => {
    if (!('Notification' in window)) {
      toast({ title: 'Hata', description: 'Tarayıcınız bildirimleri desteklemiyor', variant: 'destructive' });
      return false;
    }

    const permission = await Notification.requestPermission();
    setPushPermission(permission);

    if (permission === 'granted') {
      await subscribeToPush();
      return true;
    }

    return false;
  }, []);

  // Subscribe to push notifications
  const subscribeToPush = useCallback(async () => {
    if (!user || !('serviceWorker' in navigator)) return;

    try {
      const registration = await navigator.serviceWorker.ready;

      // Get VAPID public key from environment
      const vapidPublicKey = import.meta.env.VITE_VAPID_PUBLIC_KEY;

      if (!vapidPublicKey) {
        console.warn('VAPID public key not configured');
        return;
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

      console.log('Push subscription saved');
    } catch (error) {
      console.error('Error subscribing to push:', error);
    }
  }, [user]);

  // Fetch notification preferences
  const fetchPreferences = useCallback(async () => {
    if (!user) return;

    const { data, error } = await supabase
      .from('notification_preferences')
      .select('*')
      .eq('user_id', user.id);

    if (error) {
      console.error('Error fetching preferences:', error);
      return;
    }

    // Merge with defaults for any missing types
    const allTypes: NotificationType[] = ['weigh_in', 'daily_log', 'water', 'goal_achieved', 'weekly_summary'];
    const mergedPrefs = allTypes.map(type => {
      const existing = data?.find(p => p.notification_type === type);
      if (existing) {
        return existing as NotificationPreference;
      }
      return {
        id: '',
        notification_type: type,
        ...NOTIFICATION_DEFAULTS[type],
      } as NotificationPreference;
    });

    setPreferences(mergedPrefs);
  }, [user]);

  // Fetch notifications
  const fetchNotifications = useCallback(async () => {
    if (!user) return;

    const { data, error } = await supabase
      .from('notifications')
      .select('*')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(50);

    if (error) {
      console.error('Error fetching notifications:', error);
      return;
    }

    setNotifications(data || []);
    setUnreadCount(data?.filter(n => !n.is_read).length || 0);
  }, [user]);

  // Update preference
  const updatePreference = useCallback(async (
    type: NotificationType,
    updates: Partial<NotificationPreference>
  ) => {
    if (!user) return;

    const existing = preferences.find(p => p.notification_type === type);

    // Use upsert to handle both insert and update atomically
    const { data, error } = await supabase
      .from('notification_preferences')
      .upsert({
        user_id: user.id,
        notification_type: type,
        ...(existing?.id ? {} : NOTIFICATION_DEFAULTS[type]), // Apply defaults only for new records conceptually, but upsert will merge
        ...updates,
      }, {
        onConflict: 'user_id,notification_type',
        ignoreDuplicates: false,
      })
      .select()
      .single();

    if (error) {
      console.error('Error updating preference:', error);
      toast({ title: 'Hata', description: 'Ayarlar kaydedilemedi', variant: 'destructive' });
      return;
    }

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
    }

    // Optimistic update
    setPreferences(prev => prev.map(p =>
      p.notification_type === type ? { ...p, ...updates } : p
    ));
  }, [user, preferences, toast]);

  // Mark notification as read
  const markAsRead = useCallback(async (notificationId: string) => {
    const { error } = await supabase
      .from('notifications')
      .update({ is_read: true })
      .eq('id', notificationId);

    if (!error) {
      setNotifications(prev => prev.map(n =>
        n.id === notificationId ? { ...n, is_read: true } : n
      ));
      setUnreadCount(prev => Math.max(0, prev - 1));
    }
  }, []);

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
    const { error } = await supabase
      .from('notifications')
      .delete()
      .eq('id', notificationId);

    if (!error) {
      setNotifications(prev => prev.filter(n => n.id !== notificationId));
    }
  }, []);

  // Initial fetch
  useEffect(() => {
    if (user) {
      setLoading(true);
      Promise.all([fetchPreferences(), fetchNotifications()]).finally(() => {
        setLoading(false);
      });
    }
  }, [user, fetchPreferences, fetchNotifications]);

  return {
    preferences,
    notifications,
    unreadCount,
    loading,
    pushPermission,
    requestPushPermission,
    updatePreference,
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

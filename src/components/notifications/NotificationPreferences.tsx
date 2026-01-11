import { useState } from 'react';
import { Bell, Mail, Smartphone, Clock, ChevronDown, ChevronUp } from 'lucide-react';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { cn } from '@/lib/utils';
import {
  useNotifications,
  NOTIFICATION_LABELS,
  type NotificationType,
  type NotificationPreference,
} from '@/hooks/useNotifications';

const DAYS_OF_WEEK = [
  { value: 0, label: 'Pazar' },
  { value: 1, label: 'Pazartesi' },
  { value: 2, label: 'Salı' },
  { value: 3, label: 'Çarşamba' },
  { value: 4, label: 'Perşembe' },
  { value: 5, label: 'Cuma' },
  { value: 6, label: 'Cumartesi' },
];

interface PreferenceItemProps {
  type: NotificationType;
  preference: NotificationPreference;
  onUpdate: (type: NotificationType, updates: Partial<NotificationPreference>) => void;
  pushPermission: NotificationPermission;
  onRequestPush: () => void;
}

function PreferenceItem({ type, preference, onUpdate, pushPermission, onRequestPush }: PreferenceItemProps) {
  const [isOpen, setIsOpen] = useState(false);
  const label = NOTIFICATION_LABELS[type];
  const showSchedule = type === 'water';
  const showWeeklySummary = type === 'weekly_summary';

  const handlePushToggle = async (enabled: boolean) => {
    if (enabled && pushPermission !== 'granted') {
      await onRequestPush();
    }
    onUpdate(type, { push_enabled: enabled });
  };

  return (
    <div className="border border-border rounded-lg overflow-hidden">
      <Collapsible open={isOpen} onOpenChange={setIsOpen}>
        <div className="p-4">
          <div className="flex items-center justify-between">
            <div className="flex-1">
              <h4 className="font-medium text-foreground">{label.title}</h4>
              <p className="text-sm text-muted-foreground">{label.description}</p>
            </div>
            <CollapsibleTrigger asChild>
              <Button variant="ghost" size="icon" className="ml-2">
                {isOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
              </Button>
            </CollapsibleTrigger>
          </div>

          {/* Quick toggles */}
          <div className="flex gap-4 mt-3">
            <div className="flex items-center gap-2">
              <Smartphone className="h-4 w-4 text-muted-foreground" />
              <Switch
                checked={preference.push_enabled}
                onCheckedChange={handlePushToggle}
                disabled={pushPermission === 'denied'}
              />
              <Label className="text-sm">Push</Label>
            </div>
            <div className="flex items-center gap-2">
              <Mail className="h-4 w-4 text-muted-foreground" />
              <Switch
                checked={preference.email_enabled}
                onCheckedChange={(checked) => onUpdate(type, { email_enabled: checked })}
              />
              <Label className="text-sm">E-posta</Label>
            </div>
          </div>
        </div>

        <CollapsibleContent>
          <Separator />
          <div className="p-4 bg-muted/30 space-y-4">
            {showSchedule && (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1.5">
                    <Label className="text-xs">Başlangıç Saati</Label>
                    <Input
                      type="number"
                      min={0}
                      max={23}
                      value={preference.start_hour}
                      onChange={(e) => onUpdate(type, { start_hour: Number(e.target.value) })}
                      className="h-9"
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label className="text-xs">Bitiş Saati</Label>
                    <Input
                      type="number"
                      min={0}
                      max={23}
                      value={preference.end_hour}
                      onChange={(e) => onUpdate(type, { end_hour: Number(e.target.value) })}
                      className="h-9"
                    />
                  </div>
                </div>
                <div className="space-y-1.5">
                  <Label className="text-xs">Bildirim Aralığı (saat)</Label>
                  <Input
                    type="number"
                    min={1}
                    max={12}
                    value={preference.interval_hours}
                    onChange={(e) => onUpdate(type, { interval_hours: Number(e.target.value) })}
                    className="h-9"
                  />
                  <p className="text-xs text-muted-foreground">
                    {preference.start_hour}:00 ile {preference.end_hour}:00 arası, her {preference.interval_hours} saatte bir
                  </p>
                </div>
              </>
            )}

            {showWeeklySummary && (
              <>
                <div className="space-y-1.5">
                  <Label className="text-xs">Özet Günü</Label>
                  <div className="flex flex-wrap gap-1">
                    {DAYS_OF_WEEK.map((day) => (
                      <Button
                        key={day.value}
                        variant={preference.summary_day === day.value ? 'default' : 'outline'}
                        size="sm"
                        className="h-7 text-xs"
                        onClick={() => onUpdate(type, { summary_day: day.value })}
                      >
                        {day.label.slice(0, 3)}
                      </Button>
                    ))}
                  </div>
                </div>
                <div className="space-y-1.5">
                  <Label className="text-xs">Özet Saati</Label>
                  <Input
                    type="number"
                    min={0}
                    max={23}
                    value={preference.summary_hour}
                    onChange={(e) => onUpdate(type, { summary_hour: Number(e.target.value) })}
                    className="h-9"
                  />
                  <p className="text-xs text-muted-foreground">
                    Her {DAYS_OF_WEEK.find(d => d.value === preference.summary_day)?.label} saat {preference.summary_hour}:00'da
                  </p>
                </div>
              </>
            )}

            {!showSchedule && !showWeeklySummary && (
              <p className="text-sm text-muted-foreground">
                Bu bildirim türü için ek ayar bulunmuyor.
              </p>
            )}
          </div>
        </CollapsibleContent>
      </Collapsible>
    </div>
  );
}

export function NotificationPreferences() {
  const { preferences, updatePreference, pushPermission, requestPushPermission, loading } = useNotifications();

  if (loading) {
    return (
      <div className="flex items-center justify-center h-32">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
      </div>
    );
  }

  const notificationTypes: NotificationType[] = ['weigh_in', 'daily_log', 'water', 'goal_achieved', 'weekly_summary'];

  return (
    <div className="space-y-4">
      {pushPermission === 'denied' && (
        <div className="p-3 rounded-lg bg-destructive/10 border border-destructive/20 text-sm text-destructive">
          <p className="font-medium">Push bildirimleri engellendi</p>
          <p className="text-xs mt-1">Tarayıcı ayarlarından bu site için bildirimlere izin verin.</p>
        </div>
      )}

      {pushPermission === 'default' && (
        <Button variant="outline" className="w-full" onClick={requestPushPermission}>
          <Bell className="mr-2 h-4 w-4" />
          Push Bildirimlerini Etkinleştir
        </Button>
      )}

      <div className="space-y-3">
        {notificationTypes.map((type) => {
          const preference = preferences.find(p => p.notification_type === type);
          if (!preference) return null;

          return (
            <PreferenceItem
              key={type}
              type={type}
              preference={preference}
              onUpdate={updatePreference}
              pushPermission={pushPermission}
              onRequestPush={requestPushPermission}
            />
          );
        })}
      </div>
    </div>
  );
}

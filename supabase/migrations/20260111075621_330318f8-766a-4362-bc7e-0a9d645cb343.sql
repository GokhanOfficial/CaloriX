-- Create notification_preferences table with detailed channel and schedule settings
CREATE TABLE public.notification_preferences (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notification_type text NOT NULL, -- 'weigh_in', 'daily_log', 'water', 'goal_achieved', 'weekly_summary'
  push_enabled boolean DEFAULT true,
  email_enabled boolean DEFAULT true,
  -- Schedule settings (for recurring notifications like water, weigh_in)
  start_hour integer DEFAULT 9, -- Start sending from this hour (0-23)
  end_hour integer DEFAULT 21, -- Stop sending at this hour (0-23)
  interval_hours integer DEFAULT 3, -- Hours between reminders
  -- Weekly summary specific
  summary_day integer DEFAULT 1, -- Day of week for weekly summary (0=Sunday, 1=Monday)
  summary_hour integer DEFAULT 9, -- Hour to send weekly summary
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, notification_type)
);

-- Enable RLS
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- RLS policies
CREATE POLICY "Users can view own notification preferences"
  ON public.notification_preferences FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own notification preferences"
  ON public.notification_preferences FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own notification preferences"
  ON public.notification_preferences FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own notification preferences"
  ON public.notification_preferences FOR DELETE
  USING (auth.uid() = user_id);

-- Trigger for updated_at
CREATE TRIGGER update_notification_preferences_updated_at
  BEFORE UPDATE ON public.notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Add timezone column to profiles for proper scheduling
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'Europe/Istanbul';

-- Add email column to profiles if not exists (needed for email notifications)
-- Already exists per schema check

-- Add last_notification_check for water reminders
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_water_reminder timestamptz;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_daily_log_reminder timestamptz;
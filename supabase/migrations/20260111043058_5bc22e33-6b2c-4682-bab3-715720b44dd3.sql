-- Add auto_recalculate_macros column to profiles table
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS auto_recalculate_macros BOOLEAN DEFAULT true;
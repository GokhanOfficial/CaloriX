-- Enable RLS on notifications table (already enabled in setup, but good practice to ensure)
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Notifications Policies
-- Remove any existing policies that might conflict or be too permissive (though we know there aren't any insert policies yet)
-- We keep the existing select/update/delete policies for users as they are correct.

-- Add policy to allow ONLY service_role to insert notifications
-- This prevents users from flooding the system with fake notifications via the API
CREATE POLICY "Service role can insert notifications" 
ON public.notifications FOR INSERT 
TO service_role 
WITH CHECK (true);

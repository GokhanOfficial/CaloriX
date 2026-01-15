-- Enable RLS on sensitive tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Profiles Policies
DROP POLICY IF EXISTS "Public profiles access" ON public.profiles;
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;

CREATE POLICY "Users can view their own profile" 
ON public.profiles FOR SELECT 
USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" 
ON public.profiles FOR UPDATE 
USING (auth.uid() = id);

CREATE POLICY "Users can insert their own profile" 
ON public.profiles FOR INSERT 
WITH CHECK (auth.uid() = id);

-- Push Subscriptions Policies
DROP POLICY IF EXISTS "Public push subscriptions access" ON public.push_subscriptions;
DROP POLICY IF EXISTS "Users can view their own push subscriptions" ON public.push_subscriptions;
DROP POLICY IF EXISTS "Users can insert their own push subscriptions" ON public.push_subscriptions;
DROP POLICY IF EXISTS "Users can delete their own push subscriptions" ON public.push_subscriptions;

CREATE POLICY "Users can view their own push subscriptions" 
ON public.push_subscriptions FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own push subscriptions" 
ON public.push_subscriptions FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own push subscriptions" 
ON public.push_subscriptions FOR DELETE 
USING (auth.uid() = user_id);

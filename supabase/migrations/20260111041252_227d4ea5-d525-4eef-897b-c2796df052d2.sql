-- Fix overly permissive RLS policies for foods and food_nutrition tables
-- These policies now require the created_by to be set to the current user

-- Drop existing INSERT policies
DROP POLICY IF EXISTS "Authenticated users can add foods" ON public.foods;
DROP POLICY IF EXISTS "Authenticated users can add food nutrition" ON public.food_nutrition;

-- Create new INSERT policies with proper checks
CREATE POLICY "Authenticated users can add foods"
  ON public.foods FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

-- For food_nutrition, ensure the user owns the food they're adding nutrition for
CREATE POLICY "Users can add nutrition for foods they created"
  ON public.food_nutrition FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.foods 
      WHERE id = food_id AND created_by = auth.uid()
    )
  );

-- Also add update policy for food_nutrition
CREATE POLICY "Users can update nutrition for foods they created"
  ON public.food_nutrition FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.foods 
      WHERE id = food_id AND created_by = auth.uid()
    )
  );
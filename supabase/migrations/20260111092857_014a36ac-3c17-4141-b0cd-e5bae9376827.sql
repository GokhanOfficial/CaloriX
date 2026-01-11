-- Add extended nutrition columns
ALTER TABLE public.food_nutrition
ADD COLUMN trans_fat_g numeric NULL,
ADD COLUMN nova_score smallint NULL,
ADD COLUMN nutri_score text NULL;

-- Add comments for documentation
COMMENT ON COLUMN public.food_nutrition.trans_fat_g IS 'Trans fat content per 100g/ml';
COMMENT ON COLUMN public.food_nutrition.nova_score IS 'NOVA food classification: 1=Unprocessed, 2=Processed culinary ingredients, 3=Processed foods, 4=Ultra-processed';
COMMENT ON COLUMN public.food_nutrition.nutri_score IS 'Nutri-Score grade: A (best) to E (worst)';
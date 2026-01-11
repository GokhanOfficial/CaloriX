import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface MacroRequest {
  age: number;
  gender: 'male' | 'female' | 'other';
  height_cm: number;
  current_weight_kg: number;
  target_weight_kg: number;
  activity_level: string;
  goal: string;
  previous_macros?: {
    daily_calorie_target: number;
    protein_target_g: number;
    carbs_target_g: number;
    fat_target_g: number;
  };
  previous_weight_kg?: number;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    const baseUrl = Deno.env.get('OPENAI_BASE_URL') || 'https://gen.pollinations.ai/v1';
    const model = Deno.env.get('OPENAI_MODEL') || 'gpt-5-mini';

    if (!openAIApiKey) {
      console.error('OPENAI_API_KEY is not set');
      return new Response(
        JSON.stringify({ error: 'OpenAI API key not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const body: MacroRequest = await req.json();
    console.log('Received macro calculation request:', JSON.stringify(body));

    const {
      age,
      gender,
      height_cm,
      current_weight_kg,
      target_weight_kg,
      activity_level,
      goal,
      previous_macros,
      previous_weight_kg
    } = body;

    // Build prompt for AI
    let systemPrompt = `Sen bir beslenme ve diyet uzmanısın. Kullanıcının verilerine göre günlük kalori, makro ve su hedeflerini hesaplayacaksın.

Mifflin-St Jeor formülünü temel al ama kişiselleştirilmiş öneriler sun:
- Erkekler için BMR = 10 × ağırlık(kg) + 6.25 × boy(cm) − 5 × yaş + 5
- Kadınlar için BMR = 10 × ağırlık(kg) + 6.25 × boy(cm) − 5 × yaş − 161

Aktivite çarpanları:
- sedentary: 1.2
- light: 1.375
- moderate: 1.55
- active: 1.725
- veryActive: 1.9

Hedef ayarlamaları:
- lose: günlük 500 kalori açığı
- gain: günlük 300 kalori fazlası
- maintain: değişiklik yok

Makro dağılımı:
- Protein: vücut ağırlığı × 1.6-2.2g (hedefe göre ayarla)
- Karbonhidrat: toplam kalorinin %40-50
- Yağ: toplam kalorinin %25-30

Su hedefi hesaplama:
- Temel formül: vücut ağırlığı × 30-35 ml
- Aktivite seviyesine göre artır (active ve veryActive için +500-1000ml)
- Kilo verme hedefi varsa +250ml ekle
- Minimum 2000ml, maksimum 4000ml

JSON formatında yanıt ver:
{
  "daily_calorie_target": number,
  "protein_target_g": number,
  "carbs_target_g": number,
  "fat_target_g": number,
  "daily_water_target_ml": number,
  "bmr": number,
  "tdee": number,
  "explanation": "string (Türkçe kısa açıklama)"
}`;

    let userPrompt = `Kullanıcı bilgileri:
- Yaş: ${age}
- Cinsiyet: ${gender === 'male' ? 'Erkek' : gender === 'female' ? 'Kadın' : 'Belirtilmemiş'}
- Boy: ${height_cm} cm
- Mevcut Kilo: ${current_weight_kg} kg
- Hedef Kilo: ${target_weight_kg} kg
- Aktivite Seviyesi: ${activity_level}
- Hedef: ${goal === 'lose' ? 'Kilo vermek' : goal === 'gain' ? 'Kilo almak' : 'Kiloyu korumak'}`;

    // If there's previous data, include it for comparison
    if (previous_macros && previous_weight_kg) {
      userPrompt += `

Önceki Veriler (kilo değişikliği sonrası güncelleme):
- Önceki Kilo: ${previous_weight_kg} kg
- Önceki Kalori Hedefi: ${previous_macros.daily_calorie_target} kcal
- Önceki Protein: ${previous_macros.protein_target_g}g
- Önceki Karbonhidrat: ${previous_macros.carbs_target_g}g
- Önceki Yağ: ${previous_macros.fat_target_g}g

Kilo ${previous_weight_kg > current_weight_kg ? 'azaldı' : 'arttı'}. Yeni kiloya göre makroları güncelle ve açıklamada ilerlemeyi değerlendir.`;
    }

    console.log(`Sending request to OpenAI with model: ${model}...`);

    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: model,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt }
        ],
        response_format: { type: 'json_object' },
        max_tokens: 500,
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('OpenAI API error:', response.status, errorText);
      return new Response(
        JSON.stringify({ error: `OpenAI API error: ${response.status}` }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const data = await response.json();
    console.log('OpenAI response received');

    const content = data.choices[0]?.message?.content;
    if (!content) {
      console.error('No content in OpenAI response');
      return new Response(
        JSON.stringify({ error: 'No content in response' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const result = JSON.parse(content);
    console.log('Parsed result:', JSON.stringify(result));

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    console.error('Error in calculate-macros function:', error);
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

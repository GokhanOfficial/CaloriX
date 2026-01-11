import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface RecognizeTextRequest {
  text: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    const openAIBaseUrl = Deno.env.get('OPENAI_BASE_URL') || 'https://gen.pollinations.ai/v1';
    const openAIModel = Deno.env.get('OPENAI_MODEL') || 'gpt-5-mini';

    if (!openAIApiKey) {
      console.error('OPENAI_API_KEY is not configured');
      return new Response(
        JSON.stringify({ error: 'OpenAI API key not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const { text } = await req.json() as RecognizeTextRequest;

    if (!text || !text.trim()) {
      return new Response(
        JSON.stringify({ error: 'Text is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('Processing text food recognition...');
    console.log('Input text:', text);
    console.log('Using model:', openAIModel);

    const systemPrompt = `Sen bir besin değeri uzmanısın. Kullanıcının yazdığı yiyecekleri analiz ederek her birinin besin değerlerini tahmin edeceksin.

GÖREV:
1. Metindeki TÜM yiyecekleri tanımla (birden fazla olabilir)
2. Her yiyecek için belirtilen veya tahmini tüketilen miktarı (gram/ml) hesapla
3. Her yiyecek için 100 GRAM başına besin değerlerini ver
4. Her yiyecek için NOVA ve Nutri-Score değerlendirmesi yap

ÖNEMLİ KURALLAR:
- Metinde birden fazla yiyecek varsa HER BİRİNİ AYRI AYRI listele
- Kullanıcı miktar belirtmişse onu kullan, belirtmemişse tipik porsiyon miktarı tahmin et
- Güvenilirlik puanı 0-100 arası ver (miktar belirtilmişse yüksek, tahminse düşük)
- Türkçe yiyecek isimleri kullan
- Türk mutfağı ve yerel ürünleri tanı
- BESİN DEĞERLERİ HER ZAMAN 100 GRAM İÇİN OLMALI

SKORLAR:
- NOVA skoru: 1=İşlenmemiş/minimal işlenmiş, 2=İşlenmiş mutfak malzemeleri, 3=İşlenmiş gıdalar, 4=Ultra işlenmiş gıdalar
- Nutri-Score: A (en sağlıklı) ile E (en az sağlıklı) arası harf

YANIT FORMATI (JSON):
{
  "foods": [
    {
      "name": "Yiyecek adı",
      "amount_g_ml": 150,
      "calories_per_100g": 200,
      "protein_g_per_100g": 15,
      "carbs_g_per_100g": 20,
      "fat_g_per_100g": 8,
      "saturated_fat_g_per_100g": 3,
      "trans_fat_g_per_100g": 0.1,
      "sugars_g_per_100g": 5,
      "fiber_g_per_100g": 2,
      "salt_g_per_100g": 0.5,
      "nova_score": 2,
      "nutri_score": "B",
      "confidence": 85
    }
  ],
  "description": "Genel açıklama ve notlar"
}`;

    const response = await fetch(`${openAIBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: openAIModel,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: `Şu yiyeceklerin besin değerlerini hesapla: ${text}` }
        ],
        response_format: { type: 'json_object' },
        max_tokens: 1500,
        temperature: 0.3,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('OpenAI API error:', response.status, errorText);
      return new Response(
        JSON.stringify({ error: 'AI service error', details: errorText }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const data = await response.json();
    console.log('OpenAI response received');

    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      console.error('No content in OpenAI response');
      return new Response(
        JSON.stringify({ error: 'No response from AI' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const result = JSON.parse(content);
    console.log('Recognized foods from text:', result.foods?.length || 0);

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in recognize-food-text function:', error);
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

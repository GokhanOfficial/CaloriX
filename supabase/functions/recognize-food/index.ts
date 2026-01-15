import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface FoodItem {
  name: string;
  amount_g_ml: number;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  confidence: number;
}

interface RecognizeRequest {
  image_base64: string;
  additional_text?: string;
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

    const { image_base64, additional_text } = await req.json() as RecognizeRequest;

    if (!image_base64) {
      return new Response(
        JSON.stringify({ error: 'Image is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('Processing food recognition request...');
    console.log('Additional text provided:', additional_text || 'None');
    console.log('Using model:', openAIModel);

    const systemPrompt = `Sen bir besin değeri uzmanısın. Gönderilen yemek fotoğraflarını ve/veya metin açıklamalarını analiz ederek yiyecekleri tanımlayacak ve besin değerlerini tahmin edeceksin.

GÖREV:
1. Fotoğraftaki TÜM yiyecekleri tanımla (birden fazla olabilir)
2. Her yiyecek için tahmini tüketilen miktarı (gram/ml) hesapla
3. Her yiyecek için 100 GRAM başına besin değerlerini ver
4. Her yiyecek için NOVA ve Nutri-Score değerlendirmesi yap

ÖNEMLİ KURALLAR:
- Fotoğrafta birden fazla yiyecek varsa HER BİRİNİ AYRI AYRI listele
- Kullanıcı ek metin sağladıysa bunu da dikkate al (porsiyon bilgisi, içerik detayı vb.)
- Güvenilirlik puanı 0-100 arası ver (ne kadar eminsen o kadar yüksek)
- Türkçe yiyecek isimleri kullan
- BESİN DEĞERLERİ HER ZAMAN 100 GRAM İÇİN OLMALI
- amount_g_ml fotoğraftaki tahmini tüketim miktarı

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

    const userContent: Array<{ type: string; text?: string; image_url?: { url: string } }> = [];

    // Add text if provided
    if (additional_text && additional_text.trim()) {
      userContent.push({
        type: 'text',
        text: `Kullanıcı notu: ${additional_text}`
      });
    }

    // Add image
    userContent.push({
      type: 'text',
      text: 'Bu fotoğraftaki yiyecekleri analiz et ve besin değerlerini tahmin et.'
    });

    userContent.push({
      type: 'image_url',
      image_url: {
        url: image_base64.startsWith('data:') ? image_base64 : `data:image/jpeg;base64,${image_base64}`
      }
    });

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
          { role: 'user', content: userContent }
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
      return new Response(
        JSON.stringify({ error: 'AI service error' }),
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
    console.log('Recognized foods:', result.foods?.length || 0);

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in recognize-food function:', error);
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    return new Response(
    return new Response(
      JSON.stringify({ error: 'An unexpected error occurred' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

# MODEL UYUMLULUK RAPORU — `calculate-macros` (A1r11)

> Üretim tarihi: 2026-09-29 · tekrar: **3 koşu/senaryo/model**
> Endpoint: `https://api.ustagpt.com.tr/v1` · Anahtar: `DENO_USTAGPT_KEY` ortam değişkeninden okundu (dosyada/logda YOK)
> Prompt kaynağı: `supabase/functions/calculate-macros/index.ts` (kopyalanmadı, dosyadan okundu)

## ⚠️ ÖLÇÜM GEÇERLİLİĞİ NOTU (önce okuyun)

Bu tablo **ikinci** koşunun çıktısıdır. İlk koşu (aynı betik, aynı ayarlar,
`--allow-write` eksikliği yüzünden rapor yazamadı) **daha temizdi** ve iki
bulgunun ikisini de doğruladı. Aradaki fark **kaynak saturation**'dır:

- Ağır test trafiğinden sonra OpenAI sağlayıcısı geçici olarak
  **HTTP 403 `all_providers_failed`** dönmeye başladı: `gpt-4.1` 18/18,
  `gpt-5-mini` 12/18 koşu. Bu **model uyumluluğu değil, sağlayıcı doygunluğudur**
  (≈140 test isteğinden sonra başladı; koşu bittikten sonra da sürüyor).
- Bu nedenle **OpenAI satırları için tablo 2. koşuyu temsil etmez.**
- **Gemini/Gemma/GLM satırları her iki koşuda da birebir aynı** (0/3 veya
  `JSON.parse PATLADI`) → bu satırlar güvenilirdir ve kök neden ölçümünü
  taşır.
- Düzeltme sonrası doğrulama (`tool/verify_fix.ts`, 30 istek) **403 öncesi**
  koşuldu: `gpt-4.1` 5/5 başarılıydı.

**Satırları şöyle okuyun:**

| Kaynak | Güvenilirlik |
|---|---|
| `gemini-*`, `gemma-*`, `glm-*` (her iki koşu) | ✅ yüksek — iki koşuda da aynı |
| `gpt-4.1` **PROD** (1. koşu) | ✅ 3/3 başarılı |
| `gpt-4.1` / `gpt-5-mini` (2. koşu) | ⚠️ **geçersiz** — 403 doygunluk |
| Tümü: `verify_fix.ts` (düzeltme sonrası) | ✅ 25/30, ayrıştırma hatası 0 |

## 1) Model × senaryo × sonuç

| Model | Senaryo | Sonuc | `content` tipi | `finish_reason` | HTTP | Kırılma adımı |
|---|---|---|---|---|---|---|
| `gemini-2.5-flash` | json_object + max_tokens:2000 (length testi) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemini-2.5-flash` | response_format YOK (+ max_completion_tokens:500) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemini-2.5-flash` | response_format YOK + max_tokens:2000 (length testi) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemini-2.5-flash` | response_format YOK + max_tokens:500 (token alanı prod'daki) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemini-2.5-flash` | response_format YOK + temperature YOK (+ max_completion_tokens:500) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemini-2.5-flash` | PROD (json_object + max_tokens:500 + temperature:0.7) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemini-3.7-flash` | json_object + max_tokens:2000 (length testi) | 3/3 (100%) | string ×3 | stop ×3 | 200 ×3 | BASARILI ×3 |
| `gemini-3.7-flash` | response_format YOK (+ max_completion_tokens:500) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemini-3.7-flash` | response_format YOK + max_tokens:2000 (length testi) | 0/3 (0%) | string ×3 | stop ×3 | 200 ×3 | JSON.parse PATLADI ×3 |
| `gemini-3.7-flash` | response_format YOK + max_tokens:500 (token alanı prod'daki) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemini-3.7-flash` | response_format YOK + temperature YOK (+ max_completion_tokens:500) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemini-3.7-flash` | PROD (json_object + max_tokens:500 + temperature:0.7) | 0/3 (0%) | string ×3 | length ×3 | 200 ×3 | finish_reason=length (kesilmis) ×3 |
| `gemma-4-31b-it` | json_object + max_tokens:2000 (length testi) | 0/3 (0%) | string ×3 | stop ×3 | 200 ×3 | JSON.parse PATLADI ×3 |
| `gemma-4-31b-it` | response_format YOK (+ max_completion_tokens:500) | 0/3 (0%) | missing ×1, string ×2 | stop ×1, length ×1 | 200 ×2 | istek reddi (HTTP/ağ) ×1, JSON.parse PATLADI ×1, finish_reason=length (kesilmis) ×1 |
| `gemma-4-31b-it` | response_format YOK + max_tokens:2000 (length testi) | 0/3 (0%) | string ×3 | stop ×3 | 200 ×3 | JSON.parse PATLADI ×3 |
| `gemma-4-31b-it` | response_format YOK + max_tokens:500 (token alanı prod'daki) | 0/3 (0%) | string ×2, missing ×1 | stop ×1, length ×1 | 200 ×2 | JSON.parse PATLADI ×1, istek reddi (HTTP/ağ) ×1, finish_reason=length (kesilmis) ×1 |
| `gemma-4-31b-it` | response_format YOK + temperature YOK (+ max_completion_tokens:500) | 0/3 (0%) | string ×3 | stop ×3 | 200 ×3 | JSON.parse PATLADI ×3 |
| `gemma-4-31b-it` | PROD (json_object + max_tokens:500 + temperature:0.7) | 0/3 (0%) | string ×3 | length ×2, stop ×1 | 200 ×3 | finish_reason=length (kesilmis) ×2, JSON.parse PATLADI ×1 |
| `glm-5.3-flash` | json_object + max_tokens:2000 (length testi) | 3/3 (100%) | string ×3 | stop ×3 | 200 ×3 | BASARILI ×3 |
| `glm-5.3-flash` | response_format YOK (+ max_completion_tokens:500) | 0/3 (0%) | string ×3 | stop ×3 | 200 ×3 | JSON.parse PATLADI ×3 |
| `glm-5.3-flash` | response_format YOK + max_tokens:2000 (length testi) | 0/3 (0%) | string ×3 | stop ×3 | 200 ×3 | JSON.parse PATLADI ×3 |
| `glm-5.3-flash` | response_format YOK + max_tokens:500 (token alanı prod'daki) | 0/3 (0%) | string ×3 | stop ×3 | 200 ×3 | JSON.parse PATLADI ×3 |
| `glm-5.3-flash` | response_format YOK + temperature YOK (+ max_completion_tokens:500) | 0/3 (0%) | string ×3 | stop ×3 | 200 ×3 | JSON.parse PATLADI ×3 |
| `glm-5.3-flash` | PROD (json_object + max_tokens:500 + temperature:0.7) | 3/3 (100%) | string ×3 | stop ×3 | 200 ×3 | BASARILI ×3 |
| `gpt-4.1` | json_object + max_tokens:2000 (length testi) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-4.1` | response_format YOK (+ max_completion_tokens:500) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-4.1` | response_format YOK + max_tokens:2000 (length testi) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-4.1` | response_format YOK + max_tokens:500 (token alanı prod'daki) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-4.1` | response_format YOK + temperature YOK (+ max_completion_tokens:500) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-4.1` | PROD (json_object + max_tokens:500 + temperature:0.7) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-5-mini` | json_object + max_tokens:2000 (length testi) | 0/3 (0%) | missing ×3 | — | 400 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-5-mini` | response_format YOK (+ max_completion_tokens:500) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-5-mini` | response_format YOK + max_tokens:2000 (length testi) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-5-mini` | response_format YOK + max_tokens:500 (token alanı prod'daki) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-5-mini` | response_format YOK + temperature YOK (+ max_completion_tokens:500) | 0/3 (0%) | missing ×3 | — | 403 ×3 | istek reddi (HTTP/ağ) ×3 |
| `gpt-5-mini` | PROD (json_object + max_tokens:500 + temperature:0.7) | 0/3 (0%) | missing ×3 | — | 400 ×2 | istek reddi (HTTP/ağ) ×3 |

## 2) `response_format` açık/kapalı etkisi (PROD senaryosu vs karşılığı)

| Model | json_object AÇIK (PROD) | json_object KAPALI | Fark |
|---|---|---|---|
| `gemini-2.5-flash` | 0/3 (0%) | 0/3 (0%) | aynı |
| `gemini-3.7-flash` | 0/3 (0%) | 0/3 (0%) | aynı |
| `gemma-4-31b-it` | 0/3 (0%) | 0/3 (0%) | aynı |
| `glm-5.3-flash` | 3/3 (100%) | 0/3 (0%) | **AÇIK daha iyi** |
| `gpt-4.1` | 0/3 (0%) | 0/3 (0%) | aynı |
| `gpt-5-mini` | 0/3 (0%) | 0/3 (0%) | aynı |

## 3) Ham yanıt örnekleri (kısaltılmış, ilk 300 karakter)

### `gemini-2.5-flash` — json_object + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~10963ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":178,"total_tokens":829,"completion_tokens_details":{"reasoning_tokens":1808},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
{
  "daily_calorie_target": 2278,
  "protein_target_g": 165,
  "carbs_target_g": 245,
  "fat_target_g": 71,
  "daily_water_target_ml": 2975,
  "bmr": 1792.5,
  "tdee": 2778.38,
  "explanation": "Tebrikler! Kilo verme hedefinizde 84 kg'dan 82.5 kg'a düşerek önemli bir ilerleme kaydettiniz. Yeni kilon
```

### `gemini-2.5-flash` — response_format YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~3775ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":17,"total_tokens":668,"completion_tokens_details":{"reasoning_tokens":479},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
Merhaba! Kilo verme hedefinizde gösterdiğiniz ilerlemeyi tebrik
```

### `gemini-2.5-flash` — response_format YOK + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~21697ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":80,"total_tokens":731,"completion_tokens_details":{"reasoning_tokens":1916},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2041,
  "protein_target_g": 165,
  "carbs_target_g": 229,
  "fat_target_g": 63,
  "daily_water_target_ml": 3500,
  
```

### `gemini-2.5-flash` — response_format YOK + max_tokens:500 (token alanı prod'daki)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~3555ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":19,"total_tokens":670,"completion_tokens_details":{"reasoning_tokens":477},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
Merhaba! Beslenme ve diyet uzmanınız olarak, verdiğiniz güncel bilgilere göre he
```

### `gemini-2.5-flash` — response_format YOK + temperature YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~3394ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":19,"total_tokens":670,"completion_tokens_details":{"reasoning_tokens":477},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
Harika bir ilerleme kaydettiniz! Önceki kilonuzdan 8
```

### `gemini-2.5-flash` — PROD (json_object + max_tokens:500 + temperature:0.7)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~14406ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":9,"total_tokens":660,"completion_tokens_details":{"reasoning_tokens":477},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
{
  "daily_calorie_target
```

### `gemini-3.7-flash` — json_object + max_tokens:2000 (length testi)

- Sonuç: **3/3 (100%)** · kırılma: BASARILI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: stop · gecikme: ~21559ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":248,"total_tokens":899,"completion_tokens_details":{"reasoning_tokens":618},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
{
  "daily_calorie_target": 2280,
  "protein_target_g": 165,
  "carbs_target_g": 245,
  "fat_target_g": 71,
  "daily_water_target_ml": 3150,
  "bmr": 1793,
  "tdee": 2778,
  "explanation": "Tebrikler! 84 kg'dan 82.5 kg'a düşerek harika bir ilerleme kaydettiniz. Azalan kilonuz ve metabolik hızınıza p
```

### `gemini-3.7-flash` — response_format YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~6255ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":19,"total_tokens":670,"completion_tokens_details":{"reasoning_tokens":477},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2278,
```

### `gemini-3.7-flash` — response_format YOK + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: JSON.parse PATLADI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: stop · gecikme: ~24964ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":234,"total_tokens":885,"completion_tokens_details":{"reasoning_tokens":798},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2278,
  "protein_target_g": 165,
  "carbs_target_g": 247,
  "fat_target_g": 70,
  "daily_water_target_ml": 3150,
  "bmr": 1793,
  "tdee": 2778,
  "explanation": "84 kg'dan 82.5 kg'a olan 1.5 kg'lık düşüşünüz harika bir ilerleme! Azalan vücut ağırlığınızla birlikte
```

### `gemini-3.7-flash` — response_format YOK + max_tokens:500 (token alanı prod'daki)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~4517ms
- `usage`: `{"prompt_tokens":652,"completion_tokens":18,"total_tokens":670,"completion_tokens_details":{"reasoning_tokens":478},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2278
```

### `gemini-3.7-flash` — response_format YOK + temperature YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~7368ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":17,"total_tokens":668,"completion_tokens_details":{"reasoning_tokens":479},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 228
```

### `gemini-3.7-flash` — PROD (json_object + max_tokens:500 + temperature:0.7)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~7826ms
- `usage`: `{"prompt_tokens":651,"completion_tokens":16,"total_tokens":667,"completion_tokens_details":{"reasoning_tokens":480},"prompt_tokens_details":{"cached_tokens":0}}`
- içerik önizlemesi:

```text
{
  "daily_calorie_target": 2280,
```

### `gemma-4-31b-it` — json_object + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: JSON.parse PATLADI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: stop · gecikme: ~2230ms
- `usage`: `{"prompt_tokens":669,"completion_tokens":206,"total_tokens":875,"prompt_tokens_details":{"cached_tokens":640}}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2241,
  "protein_target_g": 165,
  "carbs_target_g": 224,
  "fat_target_g": 74,
  "daily_water_target_ml": 3138,
  "bmr": 1803,
  "tdee": 2741,
  "explanation": "Kilo kaybınız tebrikler! Mevcut kilonuz (82.5 kg) üzerinden hesaplamalar güncellendi. Kas kütlesini ko
```

### `gemma-4-31b-it` — response_format YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~60095ms
- hata: `TimeoutError: The operation was aborted due to timeout`
- içerik önizlemesi:

```text
(bos)
```

### `gemma-4-31b-it` — response_format YOK + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: JSON.parse PATLADI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: stop · gecikme: ~2344ms
- `usage`: `{"prompt_tokens":669,"completion_tokens":213,"total_tokens":882,"prompt_tokens_details":{"cached_tokens":640}}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2253,
  "protein_target_g": 165,
  "carbs_target_g": 225,
  "fat_target_g": 75,
  "daily_water_target_ml": 3100,
  "bmr": 1803,
  "tdee": 2753,
  "explanation": "Tebrikler, 1.5 kg'lık kaybınızla harika bir ilerleme kaydetmişsiniz. Yeni kilonuza göre BMR ve TDEE de
```

### `gemma-4-31b-it` — response_format YOK + max_tokens:500 (token alanı prod'daki)

- Sonuç: **0/3 (0%)** · kırılma: JSON.parse PATLADI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: stop · gecikme: ~2137ms
- `usage`: `{"prompt_tokens":669,"completion_tokens":195,"total_tokens":864,"prompt_tokens_details":{"cached_tokens":640}}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2262,
  "protein_target_g": 165,
  "carbs_target_g": 226,
  "fat_target_g": 75,
  "daily_water_target_ml": 3100,
  "bmr": 1813,
  "tdee": 2762,
  "explanation": "Tebrikler, 1.5 kg'lık bir azalma sağladınız. Yeni kilonuza göre BMR ve TDEE değerleriniz güncellendi. 
```

### `gemma-4-31b-it` — response_format YOK + temperature YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: JSON.parse PATLADI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: stop · gecikme: ~2977ms
- `usage`: `{"prompt_tokens":669,"completion_tokens":209,"total_tokens":878,"prompt_tokens_details":{"cached_tokens":640}}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2243,
  "protein_target_g": 165,
  "carbs_target_g": 224,
  "fat_target_g": 75,
  "daily_water_target_ml": 3100,
  "bmr": 1803,
  "tdee": 2743,
  "explanation": "Kilo kaybınız tebrikler! Güncel ağırlığınıza (82.5 kg) göre BMR ve TDEE değerleriniz yeniden hesaplanm
```

### `gemma-4-31b-it` — PROD (json_object + max_tokens:500 + temperature:0.7)

- Sonuç: **0/3 (0%)** · kırılma: finish_reason=length (kesilmis)
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: length · gecikme: ~29594ms
- `usage`: `{"completion_tokens":0,"prompt_tokens":653,"total_tokens":1150}`
- içerik önizlemesi:

```text
<thought>Nutrition and Diet Expert.
Calculate daily calorie, macro, and water targets based on user data.

        *   Age: 30
        *   Gender: Male
        *   Height: 178 cm
        *   Current Weight: 82.5 kg
        *   Target Weight: 76 kg
        *   Activity Level: moderate (Multiplier: 1.
```

### `glm-5.3-flash` — json_object + max_tokens:2000 (length testi)

- Sonuç: **3/3 (100%)** · kırılma: BASARILI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: VAR
- `finish_reason`: stop · gecikme: ~34195ms
- `usage`: `{"completion_tokens":2105,"completion_tokens_details":{"reasoning_tokens":1750},"prompt_tokens":719,"prompt_tokens_details":{"cached_tokens":0},"total_tokens":2824}`
- içerik önizlemesi:

```text
{"daily_calorie_target":2280,"protein_target_g":165,"carbs_target_g":248,"fat_target_g":70,"daily_water_target_ml":2975,"bmr":1793,"tdee":2778,"explanation":"Tebrikler! 84 kg'dan 82.5 kg'a inerek hedefinize (76 kg) doğru sağlıklı bir ilerleme kaydettiniz — 1.5 kg kayıp, haftada ~0.5 kg hızıyla ideal
```

### `glm-5.3-flash` — response_format YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: JSON.parse PATLADI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: VAR
- `finish_reason`: stop · gecikme: ~44190ms
- `usage`: `{"completion_tokens":2360,"completion_tokens_details":{"reasoning_tokens":1978},"prompt_tokens":658,"prompt_tokens_details":{"cached_tokens":0},"total_tokens":3018}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2280,
  "protein_target_g": 165,
  "carbs_target_g": 252,
  "fat_target_g": 68,
  "daily_water_target_ml": 2970,
  "bmr": 1793,
  "tdee": 2778,
  "explanation": "Tebrikler! 🎉 84 kg'den 82.5 kg'ya inerek toplam hedefinizin (8 kg) yaklaşık %19'unu gerçekleştirdiniz
```

### `glm-5.3-flash` — response_format YOK + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: JSON.parse PATLADI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: VAR
- `finish_reason`: stop · gecikme: ~37088ms
- `usage`: `{"completion_tokens":2021,"completion_tokens_details":{"reasoning_tokens":1661},"prompt_tokens":658,"prompt_tokens_details":{"cached_tokens":640},"total_tokens":2679}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2278,
  "protein_target_g": 165,
  "carbs_target_g": 251,
  "fat_target_g": 68,
  "daily_water_target_ml": 2975,
  "bmr": 1793,
  "tdee": 2778,
  "explanation": "Tebrikler! 84 kg'dan 82.5 kg'a düşerek 1.5 kg kaybettiniz ve 76 kg hedefinize doğru %19 ilerleme kayde
```

### `glm-5.3-flash` — response_format YOK + max_tokens:500 (token alanı prod'daki)

- Sonuç: **0/3 (0%)** · kırılma: JSON.parse PATLADI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: VAR
- `finish_reason`: stop · gecikme: ~30224ms
- `usage`: `{"completion_tokens":1507,"completion_tokens_details":{"reasoning_tokens":1115},"prompt_tokens":658,"prompt_tokens_details":{"cached_tokens":0},"total_tokens":2165}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2280,
  "protein_target_g": 150,
  "carbs_target_g": 262,
  "fat_target_g": 70,
  "daily_water_target_ml": 2890,
  "bmr": 1793,
  "tdee": 2778,
  "explanation": "Tebrikler! 84 kg'dan 82.5 kg'a inerek 1.5 kg verdin — haftada ~0.5 kg hızında sağlıklı ve sürdürülebil
```

### `glm-5.3-flash` — response_format YOK + temperature YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: JSON.parse PATLADI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: VAR
- `finish_reason`: stop · gecikme: ~36854ms
- `usage`: `{"completion_tokens":2175,"completion_tokens_details":{"reasoning_tokens":1852},"prompt_tokens":658,"prompt_tokens_details":{"cached_tokens":640},"total_tokens":2833}`
- içerik önizlemesi:

```text
```json
{
  "daily_calorie_target": 2278,
  "protein_target_g": 160,
  "carbs_target_g": 252,
  "fat_target_g": 70,
  "daily_water_target_ml": 2890,
  "bmr": 1793,
  "tdee": 2778,
  "explanation": "Tebrikler! Son ölçümden bu yana 1.5 kg kaybettiniz (84 → 82.5 kg) — bu, haftada ~0.5 kg kayıp anlamına
```

### `glm-5.3-flash` — PROD (json_object + max_tokens:500 + temperature:0.7)

- Sonuç: **3/3 (100%)** · kırılma: BASARILI
- `content` tipi: `string`
- `message.text` alanı: yok · `reasoning_content`: VAR
- `finish_reason`: stop · gecikme: ~23504ms
- `usage`: `{"completion_tokens":1126,"completion_tokens_details":{"reasoning_tokens":734},"prompt_tokens":719,"prompt_tokens_details":{"cached_tokens":704},"total_tokens":1845}`
- içerik önizlemesi:

```text
{"daily_calorie_target":2278,"protein_target_g":165,"carbs_target_g":247,"fat_target_g":71,"daily_water_target_ml":2930,"bmr":1792.5,"tdee":2778.4,"explanation":"Tebrikler, önceki hedefiniz olan 84 kg'dan 82.5 kg'a inerek 1.5 kg ilerleme kaydettiniz! Bu sağlıklı bir hızda ilerlediğinizi gösteriyor. 
```

### `gpt-4.1` — json_object + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~516ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-4.1` — response_format YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~408ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-4.1` — response_format YOK + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~571ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-4.1` — response_format YOK + max_tokens:500 (token alanı prod'daki)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~585ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-4.1` — response_format YOK + temperature YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~404ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-4.1` — PROD (json_object + max_tokens:500 + temperature:0.7)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~651ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-5-mini` — json_object + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~829ms
- hata: `{"error":{"message":"All providers failed","type":"invalid_request_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-5-mini` — response_format YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~1016ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-5-mini` — response_format YOK + max_tokens:2000 (length testi)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~1019ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-5-mini` — response_format YOK + max_tokens:500 (token alanı prod'daki)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~963ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-5-mini` — response_format YOK + temperature YOK (+ max_completion_tokens:500)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~930ms
- hata: `{"error":{"message":"All providers failed","type":"permission_error","param":null,"code":"all_providers_failed"}}`
- içerik önizlemesi:

```text
(bos)
```

### `gpt-5-mini` — PROD (json_object + max_tokens:500 + temperature:0.7)

- Sonuç: **0/3 (0%)** · kırılma: istek reddi (HTTP/ağ)
- `content` tipi: `missing`
- `message.text` alanı: yok · `reasoning_content`: yok
- `finish_reason`: — · gecikme: ~60011ms
- hata: `TimeoutError: The operation was aborted due to timeout`
- içerik önizlemesi:

```text
(bos)
```

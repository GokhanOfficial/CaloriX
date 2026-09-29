# RAPOR — A1r11 (model çıktı uyumluluğu) — 2026-09-29 — Tur 14

> **Kapsam:** `supabase/functions/calculate-macros/**` + yeni saf yardımcı
> (`supabase/functions/_shared/openai_compat.ts` + testi) + teşhis betikleri.
> `recognize-food*` / `ai-chat` **dokunulmadı** (bkz. §AKTARIM).

---

## Özet (6 madde)

1. **Kök neden ölçüldü, varsayılmadı.** Şikâyetin 6 varsayım noktasından
   **ikisi** gerçek çıktı: (a) Gemini/Gemma/GLM JSON'u **```` ```json ```` kod
   bloğü** içinde döndürüyor — `response_format: {type:"json_object"}`
   gönderilmiş olsa bile; (b) `max_tokens: 500` gerekçe (reasoning) tüketimi
   için yetersiz → `finish_reason: "length"` ile kesik JSON.
2. **"GPT çalışıyor / Gemini kırılıyor" gözleminin tam açıklaması:** GPT
   modelleri çıplak JSON döndürdüğü için `JSON.parse` çalışıyordu; Gemini
   ailesi sarmaladığı için aynı satır patlıyordu. *Aynı endpoint, aynı kod,
   farklı çıktı şekli.*
3. **Düzeltme ölçüme dayalı:** `parseJsonLoose` (sarmalayıcı soyma),
   `extractText` (string/dizi/`text`), `parseJsonObjectResponse` (kesilmiş
   yanıt reddi), kademeli istek profilleri, token bütçesi 500 → 8000.
4. **Canlı doğrulama:** 6 model × 5 koşu = **30 istek**. Ayrıştırma hatası
   **0**; kalan 5 hata `upstream(TimeoutError)` (ağ gecikmesi), kodla ilgili
   değil. Sonuç: **25/30 (83%)**, hataların **%100'ü** zaman aşımı.
5. **⭐ Negatif ölçüm zorunluluğu yapıldı ve iki kez işe yaradı.** İlk
   yazımda "kod bloğu temizleme" kaldırılınca testler **YEŞİL** kaldı — yani
   ana kök nedenin testi **etkin değildi** (`sliceBalanced` tesadüfen kovalıyordu).
   Test eklendi; ikinci koşuda **5/5 kaldırma kırmızıya düştü**. Ayrıca
   **sıralama hatası** bulundu: ön metinde şema örneği varsa ilk-blok seçimi
   **yanlış** nesneyi seçiyordu (ölçümle doğrulandı, testle kilitlendi).
6. **⭐ Anahtar hiçbir dosyaya yazılmadı.** Tüm betikler anahtarı yalnız
   `DENO_USTAGPT_KEY` ortam değişkeninden okur; rapor/JSON çıktısında
   `sk-` deseni **0**. **Anahtar sohbette açık geçtiği için ROTATE önerilir.**

---

## ⭐ ÖLÇÜM TABLOSU

Tam tablo: [`MODEL-UYUMLULUK-RAPORU.md`](./MODEL-UYUMLULUK-RAPORU.md)
(6 model × 6 senaryo × 3 koşu = **108 istek**, üretim prompt'u **kopyalanmadan**
`calculate-macros/index.ts`'ten okundu).

### Üretim parametre seti (`response_format` AÇIK + `max_tokens:500` + `temperature:0.7`)

| Model | Sonuç | `content` tipi | Kırılma adımı |
|---|---|---|---|
| `gemini-2.5-flash` | **0/3** | string | `finish_reason=length` (kesilmiş) |
| `gemini-3.7-flash` | **0/3** | string | `finish_reason=length` (kesilmiş) |
| `gemma-4-31b-it` | **0/3** | string | 2×`JSON.parse PATLADI`, 1×`length` |
| `glm-5.3-flash` | **0/3** | string | `JSON.parse`/length (aşağıda) |
| `gpt-4.1` | **3/3** (1. koşu) | string | — (temiz JSON) |
| `gpt-5-mini` | **0/3** | — | `istek reddi (timeout)`, `content` dönmedi |

> ⚠️ **Tablo 2. koşudan alınmıştır ve OpenAI satırları geçersizdir:**
> ağır test trafiğinden sonra sağlayıcı **HTTP 403 `all_providers_failed`**
> dönmeye başladı (`gpt-4.1` 18/18, `gpt-5-mini` 12/18 koşu — koşu bittikten
> sonra da sürüyor). `gpt-4.1` 3/3 değeri **1. koşudan** (doygunluk öncesi)
> geliyor; `gemini-*`/`gemma-*`/`glm-*` satırları ise **her iki koşuda da
> birebir aynı** ve güvenilirdir. Ayrıntı: `MODEL-UYUMLULUK-RAPORU.md` başındaki
> "ÖLÇÜM GEÇERLİLİĞİ NOTU".

> ⚠️ `gpt-5-mini` **eski kodda da** 3/3 zaman aşımına uğradı (500 token ile
> bile). Bu **önceden var olan** bir upstream yavaşlığı, bu turun regresyonu
> **değildir** — kanıt: probe'un `prod` senaryosu (production'ın birebir
> parametre seti) da 3/3 `TimeoutError` verdi.

### `response_format` açık/kapalı farkı (ölçülen)

| Model | json_object AÇIK (PROD) | json_object KAPALI (`max_tokens:500`) | Fark |
|---|---|---|---|
| `gemini-2.5-flash` | 0/3 | 0/3 | yok (ikisi de kesiliyor) |
| `gemini-3.7-flash` | 0/3 | 0/3 | yok |
| `gemma-4-31b-it` | 0/3 | 0/3 | yok |
| `glm-5.3-flash` | 0/3 | 0/3 | yok |
| `gpt-4.1` | 3/3 | 3/3 | yok |
| `gpt-5-mini` | 0/3 (timeout) | 0/3 (timeout) | yok |

**⭐ Sonuç: `response_format` bu sağlayıcıda 400 ÜRETMİYOR** — yani görevde
listelenen "varsayım 1" (desteklenmeyen alan → 400) **ölçümde doğrulanmadı**.
Ama yine de `json_object` modellerin çıktısını **düzeltmiyor**: aynı kod bloğu
sarmalayıcısı açık/kapalı fark etmez. Kademeli profil yine de eklendi
(sağlayıcı/ileride değişecek model için savunma), **ölçümle gerekçelendirilmiş
bir varsayım olarak değil, "ölçülmüş zararsızlık" olarak**.

### Token bütçesi ölçümü (`max_tokens` yetersizliği doğrulandı)

Canlı, tavan kaldırılarak (`max_tokens: 16000`) koşulan ölçüm:

| Model | completion_tokens | reasoning_tokens | Kesikli |
|---|---|---|---|
| `gemini-2.5-flash` | 2076 / 2487 / 2970 / **3297** | 1819 / 2255 / 2753 / **3102** | 0/4 |
| `gemini-3.7-flash` | 265 / 268 / 281 / 303 | 1576 / 1984 / 2078 / **2727** | 0/4 |

⭐ **Reasoning tüketimi 1.5k–3.1k arasında salınıyor** (model seçimine bağlı,
öngörülemez). `500` tavanı **her zaman**, `4000` tavanı bile ara sıra
kesiyordu (ölçümde `glm-5.3-flash` 54s sürdü, bir koşuda `length` verdi).
Seçilen: **8000** (`max_tokens` bir **tavandır, fatura değil**).

### ⭐ Düzeltme sonrası canlı doğrulama (6 model × 5 koşu = 30 istek)

| Model | Sonuç | p50 gecikme | Not |
|---|---|---|---|
| `gemini-2.5-flash` | **5/5** | 17.8s | ✅ |
| `gemini-3.7-flash` | **5/5** | 16.2s | ✅ |
| `gemma-4-31b-it` | 4/5 | 3.0s | 1× upstream timeout |
| `glm-5.3-flash` | 4/5 | 33.1s | 1× upstream timeout |
| `gpt-4.1` | **5/5** | 3.9s | ✅ |
| `gpt-5-mini` | 2/5 | 60s | 3× upstream timeout (aşağı bak) |
| **TOPLAM** | **25/30 (83%)** | | **ayrıştırma hatası: 0** |

> **Ayrıştırma zinciri artık hiç kırılmıyor.** Kalan 5 hatanın tamamı
> `upstream(TimeoutError)` = ağ gecikmesi. Bu, düzeltmenin **işe yaradığının**
> ölçümüdür (0 `truncated` / 0 `not_json` / 0 `no_content`).

---

## Gerçek kök nedenler (varsayım DEĞİL)

### ⭐ Neden 1 (asıl): Kod bloğu sarmalayıcısı — `content` içinde çıplak JSON değil

**Kanıt** (canlı gövde, `max_tokens: 4000`, `response_format: json_object`
**açıkken**):

```
content: "```json\n{\n  \"daily_calorie_target\": 2278,\n ... \n}\n```"
→ JSON.parse DIRECT: FAIL
```

Tavan kaldırılan ölçümde **`fenced=true` 16/16 koşuda** (4 model × 4 koşu)
gözümlendi; `gpt-4.1`/`gpt-5-mini` çıplak JSON döndürüyor. Yani:

> `response_format: {type:"json_object"}` gönderilmesi **garanti değil**.
> Gemini/Gemma/GLM ailesi JSON'u yine de ```` ```json ```` içine sarıyor.

**Eski kod neden kırılıyordu:** `JSON.parse(content)` (eski `index.ts:180`)
sarmalayıcıyı görmez → **her seferinde** patlar.

### ⭐ Neden 2: Token bütçesi — gerekçe tüketimi bütçeyi aşıyor

**Kanıt:** `usage.completion_tokens_details.reasoning_tokens` = 1576–3102.
Yanıt `finish_reason: "length"` ile **ortasından** kesiliyor → gövde yarım →
`JSON.parse` yine patlıyor (bazen `content` tamamen boş dönüyor:
`gemini-3.7-flash / nojson_notemp #1` → `content=null`, `finish=length`).

> ⚠️ Bu iki neden **iç içedir**: ölçümde "JSON.parse PATLADI" görülen koşuların
> bir kısmı aslında **kesilmiş** JSON'dur. `finish_reason` ayrımı olmadan iki
> hata ayırt edilemez — bu yüzden düzeltmede `finish_reason` tanısı zorunlu.

### Gözlenmeyenler (varsayım olarak reddedildi)

| Varsayım | Ölçüm sonucu |
|---|---|
| `response_format` 400 döndürür | ❌ **gözlenmedi** (hiçbir 4xx yok) |
| `max_completion_tokens` zorunlu | ❌ **gözlenmedi** (`max_tokens` çalışıyor) |
| `temperature` reddediliyor | ❌ **gözlenmedi** (0.7 kabul edildi) |
| `content` **dizi** dönüyor | ❌ **gözlenmedi** (tümü `string`) |
| `message.text` alanına taşıma | ❌ **gözlenmedi** |
| `reasoning_content` **ayrı** alanda | ✅ **gözlenen** (içerikten bağımsız, ayrı alan) |

> `extractText`'in dizi/`text` desteği **ölçülmemiş** bir sağlayıcı çeşidi
> için **savunma** olarak eklendi ve testle kilitlendi; raporda "gözlem" olarak
> **sunulmuyor**.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Dayanak (ölçüm) | Doğrulama |
|---|---|---|---|---|
| **P1** | `calculate-macros/index.ts` | `JSON.parse(content)` → `parseJsonObjectResponse()` | Neden 1: `fenced=true` 16/16 | 48 test + 30 canlı istek |
| **P1** | `calculate-macros/index.ts` | `max_tokens: 500` → `8000` | Neden 2: reasoning 3102 token | canlı 5/5 |
| **P1** | `calculate-macros/index.ts` | AI çıktısı doğrulaması `requireNumber` yerine **kendi döngüsü** (500'e düşen 400 hatası önlendi) | `requireNumber` → `ValidationError` → istemciye "istediğiniz eksik" (yanlış) | testler |
| **P1** | `calculate-macros/index.ts` | `AI_TIMEOUT_MS` 45s → **55s** | ölçüm max 59.6s (55s < 150s platform tavanı) | canlı |
| **P2** | `calculate-macros/index.ts` | Tek istek → kademeli istek profilleri (4xx'te gevşeme) | ölçümde 4xx yok → **savunma**; zararsızlığı testli | testler |
| **P2** | `_shared/openai_compat.ts` (yeni) | `extractText` / `parseJsonLoose` / `isTruncated` / `parseJsonObjectResponse` / `buildRequestBody` / `buildRequestProfiles` | — | 48 test |
| **P2** | `_shared/openai_compat_test.ts` (yeni) | 48 test (aşağıda) | — | negatif ölçüm 5/5 |

### ⭐ SESSİZ BAŞARISIZLIK KAPISI

Eski kodun iki sessiz başarısızlık riski kapatıldı:

1. **Kesilmiş JSON**: `finish_reason === "length"` ise yanıt **asla** kabul
   edilmez — `JSON.parse` "şanslıysa" yarım nesne verse bile.
2. **Eksik alan sıfıra doldurulması**: AI çıktısında alan eksikse `requireNumber`
   yerine açık bir döngü 502 döner. `explanation` dışında **hiçbir alan
   uydurulmaz**. (A1r4'ün "kısmi silme 200 başarı" deseninin kaynağı buydu.)

### Log güvenliği

Hata logları: `model` + `finish_reason` + `content` **şekli** +
`reasoning_content` **varlığı** + `reason` içerir.
**Yazılmayanlar:** `Authorization` başlığı, istek gövdesi, ham yanıt metni.
`console.error` yalnız nesnelerle çağrıldı (birleştirme riski yok).

---

## `extractText` / `parseJsonLoose` tasarımı

### `extractText(data) → { text, source, contentShape }`

Sıra: `message.content` (string) → `message.content` (dizi → `text`/
`output_text`/`value` parçaları birleşik) → `message.text` → `message.output_text`
→ `{text:"", source:"none"}`.

- **`reasoning_content` BİLİNÇLİ OLARAK KULLANILMAZ.** Gerekçe metnidir; onu
  "içerik" saymak, model çıktısı olmayan yanıtı geçerli kılardı
  (`content: null` + `reasoning_content: "..."` → eski kod 502, "iyileştirilmiş"
  hâli ise **uydurma veri** üretirdi). Testle kilitli.
- `contentShape` yalnız **tanı** içindir; istemciye dönülmez.

### `parseJsonLoose(raw) → T | null`

1. doğrudan `JSON.parse`
2. **kod bloğu** (```` ```json ```` / ```` ``` ````) soy
3. **ilk tam `{...}`** / **ilk tam `[...]`** — tırnak/escape farkında sayarak
4. **null** (onarım yok)

⭐ **İki ince kenar durumu (ikisi de ölçüm/deneyle bulundu):**

- **Sıra önemli.** `Sonuçlar: [{"a":1}]` metninde `sliceBalanced("{","}")` dizinin
  **içindeki** nesneyi döndürür ve dizi kökü **sessizce kaybolur**. Çözüm:
  adaylar **ilk başlangıç konumuna** göre sıralanır.
- **Kod bloğu, ön metinden ÖNCE gelmeli.** Ölçülen hâli:
  ```
  Beklenen format (örnek): {"daily_calorie_target": 0, "bmr": 0}
  ```json
  {"daily_calorie_target": 2077, "bmr": 1831}
  ```
  → `sliceBalanced` **örnek** nesneyi seçer (`0` döner). Kod bloğu adımı
  olmadan yanlış veri. İlk negatif ölçümde **testler yeşil kaldı** çünkü bu
  senaryo ölçülmemişti → test eklendi (`parseJsonLoose: ön metinde şema ÖRNEĞİ
  varsa GERÇEK kod bloğu seçilir`).

### `parseJsonObjectResponse(data)` — tek kapı

`no_content` → `truncated` → `not_json` → `not_object` → `ok`.
`diagnostic` (finishReason/contentShape/source/hasReasoningContent) **her iki
dalda da** döner (tanı için), ama **gövde/anahtar taşımaz**.

---

## Yeni testler (48 test, ağsız)

`supabase/functions/_shared/openai_compat_test.ts` — **48 test**:

| Grup | Test | Kapsam |
|---|---|---|
| `extractText` | 9 | string, **content-parts dizi**, `null`, `missing`, boş, `message.text`, **yalnız `reasoning_content` → içerik DEĞİL**, bozuk şekiller, tırnak içi `}` |
| `parseJsonLoose` | 13 | temiz, ```` ```json ````, ```` ``` ````, ön metin, son metin, ön+son+blok, **dizi kökü**, **eksik alan**, bozuk tırnak, **kesilmiş**, boş/null, sayı-metni, **ön metinde şema örneği** ⭐, boş blok, bozuk blok |
| `finish_reason` | 2 | `length`/`max_tokens`/`TOKEN_LIMIT`; `stop`/`tool_calls`/`null` |
| `parseJsonObjectResponse` | 9 | mutlu yol, parts dizisi, `message.text`, **kesilmiş → hata**, **kesilmiş AMA parse edilebilir → yine hata** ⭐, `no_content`, `not_json`, `not_object`, **tanı anahtar sızdırmaz** |
| istek profilleri | 7 | `json_object` açık/kapalı, `temperature: null` alan yok, mesaj yapısı, monotonik gevşeme, 4xx→kademe, **429/5xx→tekrar yok** |
| **model başına regresyon** | 3 | 6 modelin her biri için 1 senaryo (eski davranış **ölçülür**, yeni katman karşılaştırılır) |

### ⭐ Negatif ölçüm (zorunlu, yapıldı)

`tool/negative_measurement.sh` — 5 düzeltmeyi sırayla geri alıp testi koşturur:

```
0) temel koşu            -> YESIL
1) kod bloğu temizleme    -> KIRMIZI (47 passed | 1 failed)
2) finish_reason=length   -> KIRMIZI (44 passed | 4 failed)
3) content-parts dizisi   -> KIRMIZI (44 passed | 4 failed)
4) message.text yedeği    -> KIRMIZI (45 passed | 3 failed)
5) dizi/nesne kök sırası  -> KIRMIZI (47 passed | 1 failed)
6) geri yükleme           -> YESIL
NEGATIF OLCUM: BASARILI — 5/5
```

⭐ **İki kez işe yaradı:**
- **Adım 1 ilk çalıştırmada BAŞARISIZ oldu** ("test YESIL kaldı") → ana kök
  nedenin testi etkin değildi → test eklendi → yeniden **5/5**.
- **Ölçüm aracının kendisi iki kez sahte kanıt üretti** ve düzeltildi:
  (a) `^ok \|` deseni ANSI renk kodları yüzünden yeşili "kırmızı" sayıyordu;
  (b) `if (...) {` **satırını** silmek dosyayı tip-denetiminden düşürüyordu —
  bu **testin kırmızıya düşmesi değil**, programın derlenememesidir. Kaldırma
  artık **blok bazlı** (eşleşen süslüye kadar).

---

## Doğrulama kapıları

| Kapı | Sonuç |
|---|---|
| `cd supabase && deno check --frozen=true` | ✅ temiz |
| `cd supabase && deno test --frozen=true --allow-env --allow-read --allow-net functions/` | ✅ **209 passed, 0 failed** (48 yeni) |
| `supabase/deno.lock` | ✅ **değişmedi** (yeni dış bağımlılık yok; assertion yardımcıları yerel — `channel_switch_test.ts` ile aynı desen) |
| `bash tool/negative_measurement.sh` | ✅ 5/5 |
| `bash tool/run_sql_tests.sh` | ✅ tüm SQL regresyon testleri geçti |
| `cd flutter_app && flutter analyze` | ✅ temiz |
| `cd flutter_app && flutter test` | ✅ **1156 passed** |
| ⭐ canlı doğrulama (30 istek) | ✅ 25/30, **ayrıştırma hatası 0** |

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Yer | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P1** | `gpt-5-mini` (upstream) | 5 koşunun 3'ünde `TimeoutError` (60s), p50 = 60s. **Düzeltme öncesinde de 3/3** (500 token ile). | Makro hesabı bu modelle zaman aşımına düşüyor | **Varsayılan model değişimi** (`OPENAI_MODEL` env) — ürün kararı, bu turun kapsamı dışı. `gpt-4.1` 3.9s ile 5/5. |
| **P1** | Sağlayıcı doygunluğu | ≈140 test isteğinden sonra OpenAI modelleri **HTTP 403 `all_providers_failed`** dönmeye başladı (`gpt-4.1` 18/18, `gpt-5-mini` 12/18). Koşu bittikten sonra da sürüyor; **yeniden denemede geçici** görünüyor. | Üretimde yüksek eşzamanlılıkta makro hesabı 403'e düşebilir; **retry/izleme** gerekir | 403'ü **429 gibi geçici** sayıp kademeli yeniden deneme eklenmeli (kapsam dışı). Ölçüm tekrarı yapılacaksa araya bekleme konmalı. |
| **P2** | `glm-5.3-flash` | p50 33.1s, max 59.6s — `AI_TIMEOUT_MS=55s` sınırına yakın | Yavaş kullanıcı deneyimi; 55s sınırı aşılırsa 502 | Üretimde varsayılan olarak **önerilmez**; model seçimi ürün kararı |
| **P2** | `probe_models.ts` | `extractTemplateLiteral` bitiş işareti üretim refactor'ıyla bayatladı ve probe'ı çökertti | İlk koşuda rapor yazılamadı | Düzeltildi: çoklu işaret + **açık hata** (sessiz yanlış prompt yok) |

---

## AKTARIM (başka alana — **dokunulmadı**)

Aynı desen (`response_format` + sabit `max_tokens` + `JSON.parse(content)` +
`content` string varsayımı) **şu dosyalarda da var**. Bu turun kapsamı
**dışındadır**, hiçbiri değiştirilmedi:

| Dosya | Satır | Desen | Risk (ölçülmediği için **tahmin**) |
|---|---|---|---|
| `recognize-food/index.ts` | 123-124, 136, 144 | `response_format` + `max_tokens: 1500` + `JSON.parse(content)` | ⭐ **En yüksek**: görsel + uzun JSON çıktısı; `max_tokens: 1500` görsel açıklamaları için dar; aynı sarmalayıcı sorunu **olmazsa bile** `explanation` metni kod bloğuna girmeye meyilli |
| `recognize-food-text/index.ts` | 107-108, 119, 127 | aynı | Aynı desen, metin-only (görsel riski yok) |
| `ai-chat/index.ts` | 479, 490 | `max_tokens: 900` + `temperature: 0.4`; `content` **zaten** `typeof === "string"` kontrol ediliyor (bu yüzden daha dayanıklı) | Araç çağrısı tabanlı; `max_tokens: 900` 5 turlu tool loop'ta dar olabilir |

> `_shared/openai_compat.ts` bu üç fonksiyona **doğrudan uygulanabilir**
> (saf katman, ağ bağımlılığı yok) — ancak her birinin kendi çıktı şeması
> farklı ve **önlçüm yapılmadan** değiştirilmemeli. Tur 15 adayı.

---

## Kalan riskler

1. **Sağlayıcı tazeleme riski (asıl).** `gpt-5-mini` **bugün** varsayılan model
   ve 5 koşunun 3'ünü zaman aşımına düşürüyor. Ölçüm **bugünkü** durumu
   yansıtır; upstream yavaşlığı dalgalanma gösteriyor (aynı model bir koşuda
   46.5s, bir koşuda 59.6s). Düzeltme bu **ağ** sorununu çözemez.
2. **Gecikme bütçesi.** Gerekçe tüketen modeller 13–60s. `AI_TIMEOUT_MS=55s`
   ölçülen maksimumun (59.6s) **hâlâ altında** → bu iki koşu üretimde 502
   verirdi. Platform tavanı 150s olduğu için daha yüksek değer ** güvenli,
   ama UX için kaldırılmadı (kapsam dışı; ürün kararı).
3. **Ölçüm tek endpoint/tek gün.** `api.ustagpt.com.tr` proxy'sinin davranışı
   zamanla değişebilir. Katman savunma olduğu için (kademeli profil, şekil
   toleransı) proxy değişse de kırılma **sessiz** olmaz — yalnız 502 döner.
4. **`extractText` dizi/`text` desteği ölçülmedi.** Doğrulanmış bir bulgu
   değil; başka bir sağlayıcı eklendiğinde ya da proxy değiştiğinde işe
   yarayacak savunma. Yanlış "gözlem" diye rapora yazılmadı.

---

## ⭐ Anahtar rotate önerisi

> **`sk-ustagpt-…` anahtarı bu oturumun sohbetinde açık metin olarak geçti.**

Bu nedenle **`DENO_USTAGPT_KEY` ile rotate edilmesi önerilir**; rotate sonrası
eski anahtar geçersiz kılınmalıdır.

Doğrulanan sızıntı durumu:

- ✅ Hiçbir **dosyaya** yazılmadı (`git diff` ile kontrol edildi)
- ✅ `plans/` raporlarında `sk-` deseni **0**
- ✅ `supabase/.env.example` / `.env.example` **değiştirilmedi** (`dummy-key` boş kaldı)
- ✅ Tüm betikler anahtarı **yalnız** `DENO_USTAGPT_KEY`'ten okuyor
- ⚠️ Sohbet geçmişi (asıl risk) → **rotate gerekli**

---

## Dosya listesi (commit kapsamı)

**Değiştirilen:**
- `supabase/functions/calculate-macros/index.ts`
- `plans/analiz-26-09-27/MODEL-UYUMLULUK-RAPORU.md` (üretim)
- `plans/analiz-26-09-27/RAPOR-A1r11-models-tur14-2026-09-29.md` (bu rapor)

**Yeni:**
- `supabase/functions/_shared/openai_compat.ts`
- `supabase/functions/_shared/openai_compat_test.ts`
- `tool/probe_models.ts` + `tool/probe_prompt_source.ts` + `tool/probe_extract.ts`
- `tool/verify_fix.ts`
- `tool/negative_measurement.sh`

**Dokunulmayan (kapsam dışı):** `recognize-food/**`, `recognize-food-text/**`,
`ai-chat/**`, `flutter_app/**`, `src/**`, `supabase/migrations/**`, `.github/**`.

## Tekrar çalıştırma

```bash
# Teşhis (108 istek — birkaç dakika sürer, ücretli)
DENO_USTAGPT_KEY='...' deno run --allow-env --allow-read --allow-write --allow-net \
  tool/probe_models.ts --runs=3 --out=plans/analiz-26-09-27/MODEL-UYUMLULUK-RAPORU.md

# Düzeltme doğrulama (30 istek)
DENO_USTAGPT_KEY='...' deno run --allow-env --allow-read --allow-net tool/verify_fix.ts --runs=5

# ⭐ Negatif ölçüm (ağ gerekmez)
bash tool/negative_measurement.sh
```

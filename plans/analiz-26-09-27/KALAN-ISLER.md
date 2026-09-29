# KALAN İŞLER — Sana Ait (Deploy Öncesi Kontrol Listesi)

**Tarih:** 2026-09-28 · **Kapsam:** 13 tur denetim döngüsü sonrası
**Durum:** Kod tarafı bitti ve doğrulandı. Aşağıdakiler **yalnızca senin
erişebildiğin** ortamlarda yapılacak işler.

> Bu dosya "ajanların yapamadığı işler" listesidir. Her madde **kanıtı**,
> **yapılacak komutu** ve **hata olursa ne olacağını** içerir.

---

## 🔴 KRİTİK — Bu üçü yapılmadan sunucu tarafı çalışmaz

### 1. `INTERNAL_FUNCTION_TOKEN` secret'ını tanımla (Vault)

**Neden:** `check-reminders` ve `send-notification` fonksiyonları artık
**token zorunlu** istiyor. Token yoksa cron job'ı kurulmaz ve sunucu
bildirimlerinin **tamamı** gitmez (`water`, `daily_log`, `weekly_summary`,
`weigh_in`).

Ajan notu: bu token olmadan **anon biri bile** tüm kullanıcı listesine
bildirim tetikleyebiliyordu (P0 açık). Kapatıldı ama karşılığında token şart.

**Adı ve yeri doğru olmalı.** Migration şu ismi ve şemayı bekliyor:
- Vault şeması: `vault.decrypted_secrets`
- Secret adı: **`calorix_internal_function_token`**

**Üret:**
```bash
openssl rand -hex 32
```

**Tanımla** (Supabase SQL Editörü veya `psql` ile):
```sql
select vault.create_secret('calorix_internal_function_token', '<ÜRETİLEN_DEĞER>');
```

**Doğrula:**
```sql
select name, created_at from vault.secrets;
```

| Sonuç | Anlamı |
|---|---|
| `calorix_internal_function_token` listede | ✅ Devam |
| Boş liste | ❌ Token yok → job kurulmayacak |

⚠️ **Sırrı `.env` dosyasına da yaz** — edge function dokümanında
(`.env.example` ve `supabase/.env.example` içinde bu değişken zaten var).
İki yere de yazılmalı: Vault (cron için) + edge function env (HTTP çağrısı için).

---

### 2. `pg_cron` job'ının gerçekten çalıştığını doğrula

**Neden:** Job **kuruldu** ama **gerçek zamanlayıcısı test edilemedi**.
Ajans test ortamında `pg_cron`'u bir shim ile taklit etti — tanım, SQL gövdesi
ve üretilen HTTP isteği doğrulandı, ama **job gerçekten saatte 7 kez tetikleniyor
mu** bilinmiyor. 4 tur boyunca raporlandı; bu, döngünün en eski açık maddesiydi.

**Adım 2a — job var mı?**
```sql
select jobname, schedule, active from cron.job;
```
Beklenen: `check-reminders`, schedule `7-59 * * * *`, `active = true`.

**Adım 2b — job gerçekten koşuyor mu?**
```sql
select jobid, run_at, status, return_message
from cron.job_run_details
order by run_at desc
limit 10;
```
Son birkaç **başarılı** (`status = 'succeeded'`) kayıt görmelisin.

| Belirti | Anlamı |
|---|---|
| Hiç kayıt yok | pg_cron kurulu değil veya job çalışmıyor → `select * from pg_extension where extname in ('pg_cron','pg_net');` |
| `status = 'failed'` | `return_message` sütunundaki mesajı oku (genelde Vault boşluğu veya URL hatası) |
| Kayıt var, `succeeded` | ✅ Zamanlama çalışıyor |

**Adım 2c — HTTP isteği gerçekten atılıyor mu?**
Edge Function logları (Supabase Dashboard → Edge Functions → `check-reminders`
→ Logs). Zamanlanmış çağrılar **token** ile geldiği için log'da
`401` veya `Yetkisiz` **görmemelisin**. `200` veya sessiz geçiş görmelisin.

⚠️ **Sıklık `7-59 * * * *` bilinçli bir seçimdi:**
- 5 dakikada bir (`*/5`) → saatte 12 AI çağrısı → rate-limit kovası tükenir
- Saatte bir (`0 * * * *`) → 09:00 ve 18:00 bildirimleri **1/24 ihtimalle** kaçar

**Beklenmeyen davranış: günde birden fazla aynı bildirim.** Bu, A1r3'ün
`weekly_summary` hatasıydı (damga kolonu yoktu → günde ~12 kez gönderiyordu).
Düzeltildi ama canlıda doğrula: `check-reminders` loglarında
`weekly_summary` günde **en fazla 1** kez görünmeli.

---

### 3. 13 veri bütünlüğü CHECK kısıtını uygulamadan önce doğrula

**Neden:** Bu kısıtlar **mevcut satırları değiştirmeden** eklendi, ama
ihlal varsa migration **`RAISE EXCEPTION` ile duruyor** ve uygulama yarıda kalır.
"Proje frozen, veri yok" varsayımım A1r8 tarafından **çürütüldü** —
`.temp/` içinde gerçek proje referansı var. Yani veri **olabilir**.

**Adım 3a — temiz mi, kontrol et.** Migration
`supabase/migrations/20260928400000_data_integrity_check_constraints.sql`.
Dosyayı aç, içindeki `RAISE EXCEPTION` mesajlarında **çalıştırılması istenen
`SELECT`'leri** sırayla koştur. En az iki tanesi:

```sql
-- nova_score 1-4 dışında değer var mı?
SELECT id, nova_score FROM food_nutrition
WHERE nova_score IS NOT NULL AND (nova_score < 1 OR nova_score > 4);

-- nutri_score A-E dışında değer var mı?
SELECT DISTINCT nutri_score FROM food_nutrition WHERE nutri_score IS NOT NULL;
```

**Adım 3b — `profiles.weigh_in_frequency_days` gerçek istemci hatası bulundu**
Bu sadece tahmin değil, doğrulandı: `notifications_dialog.dart:146` aralık
denetimi yapmıyordu, kullanıcı `-5` yazabiliyordu. Flutter tarafı
düzeltildi (`1b83c2c` ve A4r10 çalışması) ama **eski veri** olabilir:
```sql
SELECT id, weigh_in_frequency_days FROM profiles
WHERE weigh_in_frequency_days IS NOT NULL
  AND (weigh_in_frequency_days < 1 OR weigh_in_frequency_days > 365);
```

| Sonuç | Yapılacak |
|---|---|
| Tüm sorgular boş | ✅ Migration'ı uygula, sorun yok |
| Satır döndü | ⛔ Migration'ı uygulama. Veriyi **kontrol et**, karar ver (düzelt vs. temizle) |

**Adım 3c — migration'ı uyguladıktan sonra**
```sql
-- 13 kısıt yerinde mi?
SELECT conname FROM pg_constraint
WHERE contype = 'c' AND connamespace = 'public'::regnamespace
ORDER BY conname;
```

⚠️ **A1r3/A1r4/A1r8'in eklediği tüm migration'lar sırayla uygulanmalı.**
`supabase/migrations/` altında 19 dosya var. `supabase db reset` ile
sıfırdan deneyebilirsen en iyisi bu (A1r ajanları Docker Postgres ile
doğruladı, sen `supabase` CLI ile yapabilirsin).

---

## 🟠 ÖNEMLİ — Ama acil değil

### 4. `.env` içindeki düz metin DB parolasını rotate et

`.env` dosyasında `SUPABASE_DB_PASSWORD` düz metin duruyor.

**İyi haber:** Git'e **sızmıyor** — `.gitignore`'da ve `git ls-files` ile
doğruladım, izlenen dosya sayısı 0. Yani sürüm geçmişinde değil.

**Neden yine de:** Proje frozen, parolanın ne kadar süredir durduğunu
bilmiyoruz. Bu bir temizlik işi, acil değil.

**Nasıl:** Supabase Dashboard → Project Settings → Database → yeni parola
üret → `.env` güncelle → `supabase db push`/restart.

### 5. VAPID secret'larını doğrula (web push için)

`.env.example` üçünü de tanımlıyor. **Üçü de zorunlu:**
```
VAPID_SUBJECT     = "mailto:ops@calorix.app"   (mailto: veya https: öneki şart)
VAPID_PRIVATE_KEY = base64url ham 32 bayt
VAPID_PUBLIC_KEY  = base64url, 0x04 ile başlayan 65 bayt
```

Üretim:
```bash
openssl ecparam -name prime256v1 -genkey -noout | \
  openssl pkcs8 -topk8 -nocrypt -outform DER | \
  openssl base64 | tr '+/' '-_' | tr -d '=\n'
```

⚠️ **Web PWA'da `VITE_VAPID_PUBLIC_KEY`** de ayrıca tanımlı (istemciye giden
anahtar, `.env.example`'te A6r5 ekledi). Bu ikinci bir dosya, yanlışlıkla
Edge Function anahtarı ile karıştırılırsa push sessizce gitmez.

### 6. Diğer Edge Function secret'ları

`.env.example` ve `supabase/.env.example` içinde tanımlı. Üretimde
Dashboard → Edge Functions → Secrets altında hepsi tanımlı olmalı:
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
`VAPID_*` (yukarıda), `INTERNAL_FUNCTION_TOKEN` (yukarıda),
`OPENAI_API_KEY`, `OPENAI_BASE_URL`.

---

## 🟡 DOĞRULANAMAYAN ALANLAR — dürüstlük notu

Bunlar **test edilemedi**, çünkü ortam/erişim yok. "Çalışıyor" demek dürüst
olmaz. Deploy sonrası smoke test önerilir:

| Alan | Test edilememe nedeni | Nasıl doğrulanır |
|---|---|---|
| Edge function'lar **çalışır halde** | `supabase serve` yok; 164 deno testi **birim düzeyinde** | Deploy et, `check-reminders`'ı elle çağır (token ile) |
| Push gerçek FCM'e gidiyor | Gerçek push servise istek atılmadı | Log'da `Push reddedildi` **olmamalı** |
| `delete-account` gerçek Auth'e karşı | SQL akışı doğrulandı, HTTP yolu denenmedi | Parolayla bir deneme (kendi hesabınla) |
| `pg_cron` gerçek zamanlayıcısı | Shim ile taklit edildi | Yukarıdaki 2b |
| Web `.or()` keyset | Gerçek PostgREST'e karşı koşulamadı (CLI yok) | Sohbet geçmişinde sayfalama |
| Docker/prod imajı | Ortamda docker yok | `docker compose build && up` + `curl localhost:8080/healthz` |
| SQL harness GoTrue/Storage | Shim — gerçek Auth/Storage değil | Canlıda RLS testleri |

---

## ⚙️ KALICI ÜRÜN KARARLARI (bilmen gereken, acil değil)

| Karar | Durum |
|---|---|
| `createFood` arayüzü | Veri katmanı hazır, **UI eksik** → kullanıcı kendi yiyeceğini kaydedemiyor |
| `goal_achieved` bildirimi | Şemada var, kimse göndermiyor → tetikleme koşulu **ürün kararı** gerektiriyor |
| Kilo penceresi | 1 yıla sabitlendi (ürün kararı bekliyor) |
| `photo_url` | Kolon var, kimse yazmıyor. Özellik eklenirse ayrı bucket + tablo gerekir |
| `favorite_foods` | Tablo + arayüz **var**; `recent_foods` tamamen türetiliyor |

---

## ⭐ `gpt-5-mini` timeout'u — kapatıldı, açıklama raporlandı (29.09)

A1r11 ölçümünde `gpt-5-mini` 3/5 istekte `TimeoutError` verdi. **A1r12 bunu
araştırmak için görevlendirildi ve istek `ECONNRESET` ile öldü** (sağlayıcı
bağlantıyı kesti). Kullanıcı bu denemeyi bırakmayı seçti.

**Karar: gpt-5-mini varsayılan model olarak kalıyor.** Gerekçe:
- A1r11'in düzeltme **sonrası** doğrulamasında `gpt-5-mini` **5/5 başarılıydı**
- 3/5 timeout, aynı dönemde OpenAI satırlarında görülen
  `403 all_providers_failed` **doygunluk** etkisiyle aynı pencerede
- A1r11 düzeltme **öncesinde** de 3/3 timeout ölçtü → **regresyon değil**,
  model kaynaklı değil, sağlayıcı kaynaklı
- `AI_TIMEOUT_MS` 45s → 55s olarak zaten yükseltildi

⚠️ **Yine de izle:** Production'da `gpt-5-mini` ile 502 alırsan, sağlayıcı
tarafında geçici doygunluk olabilir. Teşhis:
```sql
select * from cron.job_run_details order by run_at desc limit 5;  -- (varsa)
```
Edge Function log'unda `openai hata durumu: 403 all_providers_failed` görüyorsan
model değil sağlayıcı tarafıdır; `finish_reason=length` görüyorsan token tavanı
konusudur (8000'e çıkarıldı).

**Tekrar ölçmek istersen:** `tool/probe_gpt5.ts` (bu depoda, anahtar içermez,
yalnız `DENO_USTAGPT_KEY` okur) model blokları yerine **tur tur sıralı**
koşar — doygunluk etkisini ayırmak için tasarlandı.

## ✅ DOĞRULANMIŞ DURUM (deploy edebilirsin)

Bunlar **şu an yeşil**, commit'lenmiş, kanıtlanmış:

```
flutter analyze            → No issues found!
flutter test               → 1156 geçiyor
flutter build apk --debug  → başarılı (APK üretildi)
deno check --frozen=true   → 0 hata
deno test --frozen=true    → 164 geçiyor
npm test                   → 142 geçiyor
npx tsc --noEmit           → exit 0
npm run build              → başarılı
node tool/check_i18n.cjs   → ✓ 12 dil, 522 anahtar
node tool/check_versions.cjs → ✓
bash tool/run_sql_tests.sh → ✓ 5 SQL test dosyası geçti
```

---

## Sıralama Önerim

1. **Token'ı üret → Vault'a yaz → `.env`'e yaz** (5 dakika, en kritik)
2. **CHECK sorgularını koştur** (veri temizse 2 dakika, değilse karar gerekir)
3. **Migration'ları uygula** (`supabase db push` veya Dashboard)
4. **Cron doğrulaması** — `cron.job` + `job_run_details` + edge log
5. **Edge function secret'larını Dashboard'da tamamla**
6. **Parola rotasyonu** (zamanı gelince)
7. **Push smoke test** (FCM'e gerçek istek)

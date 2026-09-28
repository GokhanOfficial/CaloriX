# RAPOR — A6r9 (deno.lock yolu, küçük düzeltme) — 2026-09-28 — Tur 10

## Özet (5 madde)

1. **Bulgu doğrulandı ve A6r5'in kararı fiilen uygulanmamıştı.** A6r5
   (`cd6caa7`) "kilit **takip edilsin**" dedi ve **kökteki** `deno.lock`'u
   commit'ledi; ama `deno.json` `"lock": "deno.lock"` diyor ve Deno bu yolu
   **çalışma dizinine göre** çözüyor → fiilen kullanılan dosya
   `supabase/deno.lock`. Kökteki dosyayı **hiçbir komut okumuyor/üretmiyordu**
   (ölçüm: `/tmp` izole kopya, kök lock var, `cwd=supabase` → `deno check`
   `supabase/deno.lock` üretti, kök dosyaya dokunmadı).
2. **Karar: (a) `supabase/deno.lock` takip edilsin.** (b) `../deno.lock` değil:
   ölçtüm, Deno kilidi **kendi oluşturduğu** yola yazıyor; göreceli bir yol
   `nodeModulesDir`/çalışma dizini kaymasıyla kırılgan. Kök `deno.lock`
   silindi (artık ölü dosya), `supabase/deno.lock` takibe alındı.
3. **CI'da iki gerçek hata düzeltildi:** (i) tetikleme yolu `deno.lock`
   (kök) → `supabase/**`'a düzeltildi; (ii) `deno check`/`deno test`'e
   `--frozen=true` eklendi — **ölçüldü**: bayrak olmadan yeni bir uzak import
   eklediğimde CI **yeşil** kalıp kildi sessizce yeniliyordu.
4. **Kilit gerçekten otorite (ölçüm, olumlu).** Lock'taki
   `supabase-js@2 → 2.117.2` yönlendirmesini bilerek `2.999.0`'a zorladım;
   Deno **yönlendirmeyi takip etti** ve 404 verdi → kilitleme işe yarıyor.
5. **A6r5'in `2.180.1` ölçümü TEKRARLANMADI (düzeltilmedi, gerekçeli).**
   npm'de `2.180.1` **yok**; en yüksek kararlı sürüm `2.117.2` (2.117.2 →
   2026-09-25'te yayımlandı) ve esm.sh `@2` şu an **zaten** `2.117.2` servis
   ediyor. A6r5'in ölçtüğü sürüm farkının bugün için **somut riski yok**;
   kilidin değeri artık "sürüm sürgüsü" değil **içerik bütünlüğü/hash** (bkz.
   aşağıdaki "Bulunurlar").

## Doğrulama: kilit gerçekten etkili mi (ölçüm)

| Ölçüm | Komut | Sonuç |
|-------|-------|-------|
| Yol çözümlemesi | `cwd=supabase`, kök lock **var**, `supabase/deno.lock` **yok** → `deno check` | `supabase/deno.lock` **üretildi**, kök dosyaya dokunulmadı |
| Kök lock öksüz | Kök lock **hiç yok**, `deno check` + `deno test` | 3 redirect / 36 remote → **aynı** kilit yeniden üretildi |
| Kilit otorite mi | Lock'ta `supabase-js@2 → 2.999.0` (yok sürüm) zorlandı | Deno 2.999.0'u aradı, `TS2307` + exit 1 → **lock yönlendirmesi esas** |
| Determinizm | 3 ardışık `deno check` + `deno test` | `c0ca3acc…` **tek** hash (3/3) |
| Soğuk yeniden üretim | `DENO_DIR` boş, lock silinip `check`+`test` | **byte-byte aynı** (`c0ca3acc…`, 4920 B) |
| `--frozen` kapısı | Lock güncel, soğuk cache | `check` + `test` exit **0**, lock **değişmedi** |
| `--frozen` kapısı | Yeni uzak import + `--frozen=true` | "The lockfile is out of date" + exit **1**, lock **bozulmadı** |
| CI simülasyonu | `supabase/` tam kopya, soğuk `DENO_DIR`, iki `--frozen` adımı | 124 geçti / 0 kırık, kilit değişmedi, 18 migration adı geçerli |

**Kısmi kilit bulgusu (yeni, P2):** yalnız `deno check` çalıştırıldığında kilit
**25/36 remote** ile **kısmi** kalıyor; `deno test` onu 36'ya tamamlıyor.
Bu yüzden kilidi tazelemek için `deno check`'e güvenmek yanıltıcıydı — frozen
kapısı **her iki** adıma da konuldu.

## Hangi yol seçildi ve neden

**Seçim: (a) `supabase/deno.lock` takip edilsin.**

1. `deno.json` zaten `"lock": "deno.lock"` diyor ve Deno bunu **çalışma
   dizinine göre** çözüyor; CI'da `working-directory: supabase`. Yani
   `deno.json`'un **zaten söylediği** yol `supabase/deno.lock` — `deno.json`'u
   değiştirmek (b) yapılandırmayı çalışma dizinine bağımlı hâle getirirdi.
2. (b) ayrıca kırılgan: `nodeModulesDir`/çalışma dizini değişirse göreceli yol
   kırılır; ölçtüm, Deno kilidi **kendi oluşturduğu** konuma yazıyor.
3. A6r5'in "kök lock 8382 B, edge grafiğine indirildi" ölçümünün **devamı**:
   iki kilidin `remote` hash'leri **birebir aynı** (36 anahtar, 0 farklı
   hash) — yani kök lock'un edge grafiğiyle ilgisi **fazlalık değil**, tek farkı
   `workspace.packageJson.dependencies` içinde React'ın **70 npm kaydı**.
   Bu kayıtlar edge'in **hiçbir paketi** değil (`@supabase/*` ve `resend`
   dışında edge'in kullandığı npm bağımlılığı yok) → kökteki lock %100
   React grafiğine ait fazlalık. `supabase/deno.lock` (4920 B) tam olarak
   edge grafiği.
4. **A6r5'in ölçümüne dayanarak** (kısmen): ölçtüm, `esm.sh/@supabase/supabase-js@2`
   **bugün zaten** `2.117.2` servis ediyor, yani sürüm sürgüsü **şu an**
   kilitlenmesi gereken bir risk *değil*. Kilit bugün için iki iş görüyor:
   (i) `deno.land/std@0.168.0/0.190.0` ve `resend@2.0.0` sabit (kod içinde),
   (ii) **36 uzak dosyanın içerik hash'i** sabit → CDN'de bir dosya değişirse
   CI kırılır (bugün `--frozen` bunu *kırmızı* yapar). Yani karar "takip
   edilsin" yönünde aynı, ama **gerekçesi düzeltildi**.

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|-----|-------|-----------|-----------|
| P1 | `deno.lock` (kök) | **Silindi.** Hiçbir `deno` komutu tarafından okunmuyordu; React'ın 70 npm kaydını taşıyan ölü dosya. | `git rm` + ölçüm (yol çözümlemesi) |
| P1 | `supabase/deno.lock` | **Takibe alındı** (commit'e eklendi). Edge grafiğinin tamamı (36 remote, 3 redirect). | determinizm 3/3 + byte-byte yeniden üretim |
| P1 | `.github/workflows/supabase.yml` | Tetikleme yolu `"deno.lock"` (kök, ölü) → `supabase/**` zaten kapsıyor; kök yolu iki bloktan da çıkarıldı. Ayrıca `cache: true` yorumu gerçek yola (`supabase/deno.lock`) göre düzeltildi. | YAML parse + `python3` ile `paths`/`run` doğrulaması |
| P1 | `.github/workflows/supabase.yml` | `deno check --frozen=true` + `deno test --frozen=true`. Ölçüldü: bayrak olmadan yeni import CI'yı yeşil bırakıp kildi sessizce yeniliyordu. | cold-cache CI simülasyonu exit 0 + negatif test exit 1 |
| P2 | `.gitignore` | `supabase/functions/*/deno.lock` kuralı **silindi**: bu glob o dosyayı asla yakalamıyordu (Deno kilidi `supabase/` altına yazıyor) ve "izlenmiyor" yanılsaması doğuruyordu. | `git check-ignore` → exit 1 (hiçbiri ignore edilmiyor) |
| P2 | `supabase/deno.json` | JSONC yorumu eklendi: yolun neden göreceli olmadığı, nasıl yenileneceği, `--frozen` kapısı. | `deno check` + `deno test` yeşil |

## CI'de `--frozen` eklendi mi — gerekçe

**Evet, her iki adıma da eklendi.** Ölçüm:

- **Olumlu (kapı çalışıyor):** lock güncelken soğuk cache'te `check`+`test`
  exit 0, kilit değişmiyor → CI kırılmaz.
- **Negatif (kapı işe yarıyor):** yeni bir uzak import
  (`deno.land/std@0.190.0/encoding/base64.ts`) eklendiğinde `--frozen=true`
  **"The lockfile is out of date"** + **exit 1** veriyor ve kilidi
  **bozmuyor**. `--frozen`'sız aynı senaryo yeşil geçip kildi sessizce
  güncelliyor → yani bayrak olmadan CI bir güvenlik/görünürlük kaybı.
- **Kısmi kilit yüzünden ikisinde de:** yalnız `deno check` 25/36 remote
  bırakıyor, `deno test` tamamlıyor → `check`'e konulan frozen, kilit
  eksikse `test` adımında patlar. `test`'e de konuldu ki fark
  (`git diff` ile görülecek) CI'da ortaya çıksın, sessizce yutulmasın.
- Trade-off **bilinçli:** frozen modunda meşru bir bağımlılık eklemek CI'yi
  kırar. Bu doğru davranış: geliştirici önce `cd supabase && deno cache
  functions/` (veya `deno check`+`deno test`) ile kilidi tazeleyip kilidi
  **commit'lemek zorunda**. Talimat `supabase/deno.json` yorumuna yazıldı.

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|-----|-------------|-------|------|-------|
| P1 | `plans/.../RAPOR-A6r5-web-tur5-2026-09-28.md:63` + `OZET-tur4_5.md:46` | **A6r5'in `2.180.1` ölçümü tekrarlanamıyor.** npm'de `2.180.1` yok; en yüksek kararlı `2.117.2` (2026-09-25). esm.sh `@2` bugün `2.117.2` veriyor. A6r5'in yönlendirmesi kilidi silerek yeniden üretirken, 2.180.x'i **esm.sh'nin kendi önbelleği/önizleme sürümü** olabilir; ölçümü birebir tekrarlayamadım. | YANLIŞ gerekçeli "ölçüldü" iddiası | Rapora bu düzeltme notu düşüldü; kararın kendisi (takip edilsin) **korunuyor**, sadece gerekçesi düzeltildi. A6r5 dosyasını düzenlemedim (başka ajanın raporu) |
| P2 | `deno.land/std@0.168.0` (11 dosya) | Eski std sürümü hâlâ sabit kodda; `std@0.190.0` da kullanılıyor (iki sürüm yan yana). | Eski std'da CVE riski | **A1r10 alanı** (`supabase/functions/**`) — bu turda dokunmadım |
| P3 | `supabase/deno.lock` | `@types/react@~19.0.7` redirect'i edge grafiğinde **gerçek** (soğuk yeniden üretimde de çıkıyor) — sanılan "web kirliliği" değil; `supabase-js` tip tanımı esm.sh üzerinden geliyor. Yanlış temizlik yapılmadı. | Yok | Kapatıldı (doğrulandı) |

## Doğrulama çıktıları (gerçek repo)

```
$ cd supabase && deno check functions/                      → exit 0
$ cd supabase && deno test --allow-env --allow-read --allow-net functions/
ok | 124 passed | 0 failed | 1 ignored                        → exit 0
$ cd supabase && deno check --frozen=true functions/          → exit 0
$ cd supabase && deno test --frozen=true --allow-env --allow-read --allow-net functions/
ok | 124 passed | 0 failed | 1 ignored                        → exit 0
3 ardışık koşu sonrası: sha256(deno.lock) = c0ca3acc… (tek değer) — determinizm
CI simülasyonu (supabase/ tam kopya + soğuk DENO_DIR + --frozen): 124/0, kilit sabit
python3 yaml.safe_load(.github/workflows/supabase.yml) → YAML OK
git check-ignore deno.lock supabase/deno.lock → exit 1 (ignore edilmiyor)
```

## Kalan riskler

1. **GitHub Actions üzerinde koşmadı.** Lokal soğuk-cache simülasyonu
   yapıldı; `denoland/setup-deno` `cache: true`'nin gerçekten `DENO_DIR`'ı
   geri yüklediği **test edilmedi** (Docker/act yok). Cache'in faydası artık
   glob + dosya varlığına bağlı ve dosya repoda → ilk çalışmadan itibaren
   hash'lenebilir, ama bu çalıştırmayla kanıtlanmadı.
2. **Kilit bayatlayabilir** (36 uzak dosya hash'i). CDN bir dosyayı
   değiştirirse `--frozen` CI'yi kırmızı yapar; bu kasıtlı ama "neden
   kırıldı" ayrımı CI log'unda görünmüyor (hangi URL değişti). Gerekirse
   `deno cache functions/` ile tazeleme + lock commit'lenmeli.
3. **`--frozen` ile meşru bağımlılık eklemek CI'yı kırar** — kasıtlı;
   geliştirici akışı `supabase/deno.json` yorumuna yazıldı.
4. `supabase/functions/*/deno.lock` ignore kuralı silindi; bir başka ajan bu
   kurala güvenip fonksiyon altına kilit yazarsa artık **izlenmeyecek**
   (daha önce de yakalanmıyordu, davranış değişmedi — yalnızca yanılsama gitti).

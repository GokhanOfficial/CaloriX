# KAPANIŞ RAPORU — 13 tur denetim döngüsü (2026-09-27 → 2026-09-28)

Başlangıç: `f30676e` (v1.2.1) · Bitiş: `118b127` · **~60 commit**

## Ölçüm

| | Başlangıç | Kapanış |
|---|---|---|
| Flutter test | 143 (**2 kırık**) | **1156** (~1 skipped) |
| Deno test | 0 (CI'da **hiç çalışmıyordu**) | **164** |
| Web test | **koşucu yoktu** | **142** |
| SQL regresyon | **yoktu** | **5 dosya, 49+ denetim, CI'da** |
| `flutter analyze` | 4 issue | **No issues found** |
| `tsc` | `TS5103` — **derlemiyordu** | **exit 0** |
| `check_versions.cjs` | yok | **yeşil** (iki istemci sabit karşılaştırması) |
| `check_i18n.cjs` | yok | **12 dil, 522 anahtar, 347 kod anahtarı** |
| CI işi | Flutter tek iş | **4 iş** (flutter, react, supabase, sql) |
| Widget | **hiç çalışmıyordu** | Kotlin + Dart + CI derleme kapısı |

## Gerçekten bozuk olan özellikler (kullanıcıya zarar verenler)

1. **`recognize-food` / `recognize-food-text` derlenmiyordu** → AI beslenme tanıma ölüydü.
2. **Web push hiç gitmiyordu** → VAPID imzası üretilmiyordu; sonra gövde de şifrelenmiyordu (RFC 8291 uygulandı).
3. **Widget hiç çalışmıyordu** — Dart tarafı vardı, native yoktu; sonra iki hata: yanlış SharedPreferences dosyası, yanlış sınıf adı çözümü.
4. **Hesap silme hiç yoktu** (KVKK/Play) → edge function + arayüz + yerel temizlik.
5. **`check-reminders` hiç tetiklenmiyordu** (`pg_cron` yok) → sunucu bildirimlerinin tamamı ölü.
6. **Web'de bildirim tercihi kaydedilemiyordu**; kök neden: `saveNotifications` **ölü koddu**.
7. **Yedek/geri yükleme veri bozuluyordu** (iki istemcide): kısmi import, `0`'a çevrilen besin alanı, silinmiş öğünün canlanması.
8. **Favoriler kayboluyordu** (dışa aktarılıyor, içe aktarılmıyordu) → artık var.
9. **Bildirimler UTC'de** planlanıyordu (3 saat kayık), ilk açılışta hiç planlanmıyordu, tam alarm izni kapatılınca sessizce hiç gelmiyordu.

## Hesap hataları (ölçülmüş etki)

- `activity_level` enum → TDEE **%18,4 eksik** (2759 yerine 3382 kcal)
- `Gender.other` web vs Flutter → **257 kcal/gün** fark, kalıcı yazılıyordu
- `bmi(70,-180)=24.2` → imkânsız kayıt "sağlıklı" görünüyordu

## Ölü kod / yarım kalmış yapı

- `workmanager` bağımlılığı, `publishWeekly`, `shouldSendNudge`, `refreshTimeZone`
- `goal_achieved` tercih tipi (kimse göndermiyordu) → UI'dan gizlendi, gerekçelendi
- 63 → 60 orphan çeviri anahtarı (59'u React'te canlı, silinmedi)

## Bu döngünün **metodolojik** bulguları

**1. Ajanlara reçete yazma, davranış tarif et.** 5 brifimde teknik hata vardı
(RFC 8291 HKDF adımları, Postgres `WITH CHECK` fallback'i, `local.properties`
sürümü, React JWT, deno.lock yolu) — hepsi ajanların doğrulamasıyla düzeltildi.

**2. Ajanları kendi kodunu denetlemeye geri çağır.** A1r4 kendi
`delete-account`'ında 3, A1r8 `isAlreadyDeletedAuthError`'da 1, A4r11 P0,
A2r11 P0, A2r13 P1 buldu. Aynı ajan ikinci turda ilk turunun hatasını yakaladı.

**3. ⭐ "Yeşil test ≠ etkin test" — 8 vaka.** Hepsi aynı aile:
| Vaka | Tuzak |
|---|---|
| A4r7b | `tester.tap` ekran dışında → 3 test hiçbir şey ölçmüyor |
| A4r10 | `hitTestOnBinding` ulaşılıyor, tıklama gerçekleşmiyor |
| A5r10 | Test, `0 → 3` düzelten katmandan geçiriliyor → hatayı gizliyor |
| A1r10 | 3 kez yanlış yeşil |
| A4r11 | `'Ekle'` sabiti gerçek metinle uyuşmuyor |
| A2r13 | Sunucu karar ağacı Dart'a **kopyalanmış**, kopya test ediliyor |
| A6r13 ⭐ | **Harness** regresyonları sessizce onarıyordu → BOLA gizleniyordu |
| A6r13 | "Kırpılmış cümle" kapısı 4 denemede 302 FP → **yazılmadı** |

**4. Kanıtsız iyileştirme yapma.** A2r11 ilk ölçümde "%78 hızlanma" dedi,
ısınma olduğunu fark edip düzeltti (gerçek: **%0.00**). A2r13 embed'i ölçtü
(9M öğünde −1.3% = gürültü) → maliyet sıfır, index önermedi. A1r5 ölçmediği
3 index'i eklemedi.

**5. Ölü kod ile eksik özellik ayrımı.** A4r6/A3r6 "ölü" demeyip
"eksik olan tablo değil, **arayüz**" dedi ve silmedi — doğru karar, sonra
arayüz eklendi.

**6. Negatif test ölçümü zorunlu kılındı.** Düzenlemeyi geri al, kırmızı gör,
geri koy. Her turda 2-6 kez yapıldı, **her seferinde gerçek hata çıktı**.

## Kapanmamış / doğrulanmamış riskler

### 🔴 Senin yapman gerekenler (deploy öncesi)
1. **Vault**: `select name from vault.secrets;` → `INTERNAL_FUNCTION_TOKEN` tanımlı mı?
2. **Cron**: `select jobname, schedule from cron.job;` → job var mı? Log'da HTTP çağrısı görünüyor mu?
3. **13 yeni CHECK** canlı veriye karşı doğrulanmadı — migration ihlalde
   `RAISE EXCEPTION` ile duruyor, mesajdaki `SELECT`'leri çalıştır.
4. **`.env`** içinde düz metin DB parolası (gitignored, izlenmiyor — doğruladım).

### 🟡 Kanıtlanamayan alanlar
- Edge function'lar **çalışır halde** denenmedi (124→164 test birim düzeyinde; `supabase serve` yok)
- Push gerçek FCM'e gitmedi; `delete-account` gerçek Supabase Auth'e denenmedi
- `pg_cron`/`pg_net` gerçek zamanlayıcısı shim ile doğrulandı, canlıda değil
- Web `.or()` keyset gerçek PostgREST'e karşı koşulamadı
- Docker/prod imajı derlenmedi (ortamda docker yok)
- SQL harness GoTrue/Storage shim'i — gerçek Auth değil

## Kalan ürün kararları
- `createFood` arayüzü yok (veri katmanı hazır, UI eksik) — A2r13
- `goal_achieved` tetikleme koşulu (hedef kilo? günlük hedef? ödül?) — ürün kararı
- Kilo penceresi 1 yıla sabit
- `photo_url` özelliği eklenirse ayrı bucket + tablo

## Dosyalar
- `plans/analiz-26-09-27/00-INDeks.md` — dizin indeksi
- `PROTOKOL.md` · `OZET-tur1.md` · `OZET-tur3.md` · `OZET-tur4-5.md` · `OZET-tur6-7.md`
- `TRANSFER-defteri.md` — tüm ajanlar arası aktarım geçmişi
- `URUN-KARARLARI.md` — 4 karar, onay durumu
- `DONGULU-DURUM.md` — ajan oturumları ve dersler
- `OPS-tur1-security.md` — dashboard adımları
- `RAPOR-*.md` — 24 ajan raporu (kanıt zincirleri)

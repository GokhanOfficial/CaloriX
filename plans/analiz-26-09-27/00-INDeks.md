# 📚 Dizin indeksi — `plans/analiz-26-09-27/`

**Karar tarihi:** 2026-09-28 (Tur 13, A6r13)
**Kapsam:** 45 dosya / 884 KB — 13 turun çalışma günlüğü.

---

## Karar: **(a) Hepsi kalsın**, ama dizin okunabilir hâle getirildi

Görev iki seçenek sundu: "(a) hepsi kalsın" veya "(b) ajan raporlarını
sil/taşı". **Seçenek (a) seçildi.** Gerekçe:

### Neden silmedik
1. **Raporlar kanıt zinciridir, günlük değil.** 13 turda üretilen
   düzeltmelerin çoğu "buraya bak, ölçtüm, şu iddia yanlış çıktı"
   biçiminde. `RAPOR-A4r3` bir iddiayı test edip **yeşil kaldığını**
   görüp düzeltmeyi **geri aldığını** yazıyor; `RAPOR-A2r13` kendi
   varsayımının yanlış olduğunu kabul ediyor. Bu tür kayıtler ancak
   **yazılı halde** kalırsa "bu kararı neden verdik?" sorusuna cevap
   olur. Silinirse aynı hata 14. turda yeniden üretilir.
2. **Bunlar kanıtlanmış gerçek düzeltmelerin tek senkron kaynağı.**
   `CHANGELOG.md`'deki her madde bir rapora dayanıyor. Rapor silinirse
   changelog'ın "neden" kısmı havada kalır.
3. **Silmek geri alınamaz, taşımak ucuz.** Yanlışlıkla silinen bir
   rapor `git log`'da kalır ama **okunabilirliğini** yitirir; taşınan
   bir rapor hiçbir şey kaybetmez.
4. `PROTOKOL.md`, `OZET-tur*.md`, `TRANSFER-defteri.md`,
   `URUN-KARARLARI.md`, `DONGULU-DURUM.md` görevde de korunacaktı;
   raporları silmek bu kayıtların **atıf yaptığı** nesneleri
   ortadan kaldırırdı.

### Neden "hiç dokunma" da değil
45 dosya düz bir klasörde aranabilir değildi. Bu dosya indeksin
kendisidir: neyin kalıcı kayıt, neyin tur günlüğü olduğunu ayırır.

---

## Kalıcı kayıt (ana ajanın — **korundu**)

| Dosya | Ne |
|------|-----|
| `PROTOKOL.md` | Tüm ajanların uyduğu ortak kurallar, alan sahipliği tablosu, rapor şablonu, doğrulama komutları |
| `TRANSFER-defteri.md` | Ajanlar arası aktarım listesi (P0/P1/P2 + durum). **En canlı dosya** — açık işler burada |
| `URUN-KARARLARI.md` | Onaylanmış 4 ürün kararı (favoriler, bildirim tercihleri, `foods` CASCADE, `photo_url`) |
| `DONGULU-DURUM.md` | Döngü durumu / ana ajanın notları |
| `MASTER-PLAN.md` | Ana ajanın tur planı |
| `OZET-tur1/3/4-5/6-7.md` | Tur bazlı özet — **yeni ajanın okuması gereken asıl giriş noktası** |
| `RAPOR-*.md` (35) | Tur günlüğü — aşağıda |

---

## RAPOR dosyaları — tur sırasıyla

Güncel durum **git log**'dadır; bu raporlar **neden** bilgisini taşır.

### Tur 1 (2026-09-27) — temel
| Dosya | Konu |
|------|------|
| `RAPOR-A1-security-tur1` | Edge auth/CORS, RLS WITH CHECK, BOLA, rate limit, push şifreleme, hesap silme |
| `RAPOR-A1b-push-tur1` | Push: VAPID imzası, RFC 8291 şifreleme, 7 cihaz sınırı |
| `RAPOR-A2-data-tur1` | Veri katmanı ilk tarama |
| `RAPOR-A3-core-tur1` | Widget tazeleme P0, bildirimler UTC, güncelleme süzgeci |
| `RAPOR-A4-features-tur1` | Ekran hataları, yarım kayıt, miktar ≤ 0 kaydedilebilmesi |
| `RAPOR-A5-web-tur1` | React PWA derin tarama |
| `RAPOR-A6-quality-tur1` | `check_i18n`/`check_versions` ilk sürüm, 82 test |

### Tur 2–3 — React CI + i18n genişletme
| Dosya | Konu |
|------|------|
| `RAPOR-A1r2-security-tur2` | 15 tabloda WITH CHECK (ve **iddianın yanlış olduğunun** kanıtı), rate limit tablosu |
| `RAPOR-A2r2-data-tur2` | `activity_level` enum, `AnalyticsAuthRequired` |
| `RAPOR-A4r2-features-tur2` | `isApkUrlSafe` kapısı, 35 çeviri anahtarı |
| `RAPOR-A6r2-quality-tur2` | React CI işi, APK build kapısı, **orphan ratchet = 63** |
| `RAPOR-A1r3-security-tur3` | RFC 8291 Ek A ile birebir doğrulama, haftalık özet damgası |
| `RAPOR-A2r3-data-tur3` | Ölçek, yumuşak silme bütünlüğü |
| `RAPOR-A4r3-features-tur3` | Sohbet `RangeError`, ⭐ **"yeşil kaldı, değişiklik geri alındı"** kaydı |
| `RAPOR-A6r3-quality-tur3` | Widget sözleşme testi, SHA pinleme |

### Tur 4–5 — kısmi import + yedek
| Dosya | Konu |
|------|------|
| `RAPOR-A1r4-security-tur4` | Push `off-by-one` (3993-4058 penceresi), hata sızıntısı, 12/24 saat |
| `RAPOR-A2r4-data-tur4` | Kısmi import imkânsızlaştırma, 4506 → 37 istek |
| `RAPOR-A4r4b-delete-account-tur10` | Hesap silme arayüzü |
| `RAPOR-A5r8-web-tur8` | `Gender.other` 166 kcal farkı, 4 UTC deseni, `check_versions` +6 kapı |
| `RAPOR-A6r5-web-tur5` | Web yedek içe aktarımı |

### Tur 6–9 — widget P0 + şema sözleşmesi
| Dosya | Konu |
|------|------|
| `RAPOR-A3r6-core-tur6` | ⭐ **Widget tazeleme hiç çalışmıyordu**, 4 sessiz bildirim kaybı, DST testleri ölçmüyordu |
| `RAPOR-A4r6-features-tur6` | Dosya bölme (1239→166, 974→580), favori kararı |
| `RAPOR-A1r5-security-tur7` | `foods.created_by` CASCADE, şema sözleşmesi testi, FK parite |
| `RAPOR-A4r7b-favorites-tur10` | ⭐ **Hafta günü tuzağı** (`weekday==7` = Pazar; ilk düzeltmesi de yanlıştı) |
| `RAPOR-A1r8-security-tur8` | 13 CHECK, kova bazlı `dbBypassUntil`, `full_setup` idempotans |
| `RAPOR-A2r9-data-tur9` | BMI negatif kilo, profil savunması |

### Tur 10–13 — ürün kararları + kapatma
| Dosya | Konu |
|------|------|
| `RAPOR-A4r8-notif-prefs-tur10` | ⭐ **Master anahtar gölgelenmesi** (`??` yalnız NULL'a düşer), `start > end` ölü dal |
| `RAPOR-A4r10-features-tur11` | Gıda silme arayüzü, tartılma sıklığı, sessiz `catch` |
| `RAPOR-A4r11-orphan-meal-tur12` | Silinen gıdanın öğünü "Bilinmeyen" oluyordu |
| `RAPOR-A5r10-web-notif-tur11` | Web'de sunucu bildirim tercihi kaydedilemiyordu |
| `RAPOR-A6r9-denolock-tur10` | `supabase/deno.lock` takibe alındı, `--frozen` kapısı |
| `RAPOR-A1r10-security-tur11` | ⭐ **`pg_cron` job'ı 4 turdur eksikti** — sunucu bildirimleri hiç gitmiyordu |
| `RAPOR-A2r11-data-tur11` | `canDelete` ile silme yetkisi |
| `RAPOR-A2r13-data-tur13` | Topluluk gıdası embed'i, `foods` INSERT, gece aralığı |
| `RAPOR-A6r13-quality-tur13` | ⭐ **Bu tur**: i18n değer kapıları, ratchet 63→60, SQL testleri CI'da, yol kapsam denetimi |

### Diğer
| Dosya | Konu |
|------|------|
| `OPS-tur1-security.md` | Operasyon notları (kimlik sızıntısı, frozen proje) |

---

## ⭐ Turlar arası taşınan dersler

Bunlar **hiçbir raporda tek başına durmaz**, 13 turda birikti ve
kaybolması en tehlikeli olan bilgi:

| Ders | Kaynak |
|------|--------|
| **"Yeşil test ≠ etkin test."** Test, üretim kodunun hatayı düzelten fonksiyonundan geçiriliyorsa hatayı gizler. Her yeni kapının negatif ölçümü (kasıtlı hata → kırmızı) yapılmalı. | 7 vaka · `TRANSFER-defteri` tur 8-13 |
| **"Politikada `WITH CHECK` yok" ≠ "açık var".** Postgres `USING`'i fallback olarak yeniden değerlendirir. | A1r2 |
| **Ajanlara reçete yazma, davranışı tarif et.** A1r3'ün brifte yazılan hatalı tarifini reddetmesi, tarayıcının açamayacağı push üretimini önledi. | A1r3 |
| **Kanıtsız index ekleme.** "Index şişmesi, index de işe yaramaz" — A1r5 ölçmediği 3 index'i eklemedi. | A1r5 |
| **Tarih sabitlerini gözle değil testle doğrula.** `DateTime(2024,1,7)` → `weekday==7` = Pazar; A4r7b'nin ilk düzeltmesi de yanlıştı. | A4r7b |
| **"Mantıklı görünen" iddiayı test et; yeşil kalırsa iddiayı bırak.** `(x/10).round()/10 ≡ round(x/100*10)/10` — 200.000 rastgele çiftle doğrulandı, 0 uyuşmazlık. | A4r3 |
| **Ürün kararı ≠ teknik gerçek.** A4r6 favoriler için "eksik olan tablo değil, **arayüz**" dedi ve silmedi. | A4r6 |
| **Kanıtlanmış olmayan kural yazma.** `check_i18n`'de "kırpılmış cümle" kapısı için 4 tasarım denendi, **302 yanlış pozitif** ölçüldü, kapı **yazılmadı**. | A6r13 |

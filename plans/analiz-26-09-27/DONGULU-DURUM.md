# Döngü Durumu — 2026-09-28 (güncel)

Orkestratör: ana ajan. **Kod yazmıyor**, tüm işi alt ajanlara veriyor.
Ajan raporları: `plans/analiz-26-09-27/RAPOR-*.md`.
Kurallar: `/tmp` **kullanılmaz** (testler dahil). Kullanıcı durdurana kadar sürer.

## Tur özeti (8 tur tamamlandı, 9. turda)

| Tur | Ajanlar | Durum |
|---|---|---|
| 1 | A1, A1b, A2, A3, A4, A5, A6 | ✅ 10 commit |
| 2 | A1r2, A2r2, A4r2, A6r2 (+A3r2 tekrar) | ✅ 6 commit |
| 3 | A1r3, A2r3, A3r3, A4r3, A6r3 | ✅ 14 commit |
| 4 | A1r4, A2r4, (+A4r4 başladı) | ✅ 7 commit |
| 5 | A6r5, A2r5 | ✅ 6 commit |
| 6 | A3r6, A4r6 | ✅ 6 commit |
| 7 | A4r7 (başladı), A1r5 | ✅ 3 commit |
| 8 | A5r8, A1r8 | ✅ 3 commit |
| 9 | A2r9 | ✅ 2 commit · **A4r4 ve A4r7 hâlâ çalışıyor** |

## Ölçüm (son doğrulama)
- `flutter test` → **910 test** (Tur 1'de 143'tü, 2 kırıktı)
- `deno test` → **124** (Tur 3'te 19'dü)
- `npm test` → **113** (başlangıçta koşucu yoktu)
- `check_versions.cjs` → ✅ **tamamen yeşil** (A2r9 `bmi` düzeltmesiyle)
- `check_i18n.cjs` → ✅ 12 dil, 469 anahtar
- `flutter analyze` → ⚠️ **4 hata, hepsi A4r7'nin in-flight test dosyasında**
  (`SemanticsFlags.checked` / `CheckedState` bu Flutter sürümünde yok)

## ⏳ Bekleyen ajanlar
| Ajan | Oturum | Alan | Not |
|---|---|---|---|
| A4r4 | `ses_f1af6f6f3ffeU9L3xr9gKeq5ky` | `features/settings` hesap silme arayüzü | Çok uzun sürüyor; edge function hazır, arayüzü yazıyor |
| A4r7 | `ses_f19eaaa0effe3gszZiGi0N4Q21` | favoriler + bildirim tercihleri arayüzü | `analyze` hatası onun dosyasından; commit'lenmedi |

## Bir sonraki tur için izlenmesi gerekenler
1. A4r4/A4r7 bitince tam doğrulama (`flutter analyze` + `flutter test` + `npm` + `deno` + `build apk`).
2. **Kanıtlanmamış iddialar** (birden fazla ajan aynı noktada ısrar etti, hiçbiri
   çalıştırmadı):
   - Edge function'lar **çalışır halde** denenmedi (`supabase serve` yok).
   - `delete-account` gerçek Supabase Auth'e karşı denenmedi.
   - Push, gerçek FCM'e istek atılmadı.
   - Web `.or()` keyset, gerçek PostgREST'e karşı koşulamadı (CLI yok).
   - Docker/prod doğrulaması yapılamadı (docker kurulu değil).
   - SQL testleri CI'a bağlı değil.
   - ⭐ `check-reminders` için `pg_cron` job'ı **yok** → sunucu hatırlatıcıları hiç gitmiyor.
   - ⭐ 13 yeni CHECK canlı veriye karşı doğrulanmadı (migration `RAISE EXCEPTION`
     ile duracak, mesajdaki `SELECT`'ler çalıştırılmalı).
3. **Ürün kararları** (`URUN-KARARLARI.md`): hepsi onaylandı varsayılanıyla
   (1-A, 2-A, 3-A, 4-A) uygulanıyor.

## Metodoloji — turlardan çıkan dersler
1. **Ajanlara reçete yazma, davranış tarif et.** 4 brifimde teknik hata vardı
   (RFC 8291'in 3 HKDF adımı, Postgres `WITH CHECK` fallback davranışı,
   `local.properties` sürümü, React JWT zaten gönderiliyor). Hepsi düzeltildi.
2. **Ajanları kendi kodlarını denetlemeye geri çağır.** A1r4 kendi yazdığı
   `delete-account`'ta 3, A1r8 `isAlreadyDeletedAuthError`'da 1 gerçek hata
   buldu. Tur 6+ bu pratiği zorunlu kıldı.
3. **Negatif test ölçümü zorunlu.** Düzenlemeyi geri al, kırmızı gör, geri koy.
   Yaklaşık her turda 1-3 ajan bunu yaptı ve her seferinde gerçek hata çıktı.
4. **İki taraflı sözleşmeleri metin karşılaştırmasıyla teste bağla.**
   `widget_key_contract_test.dart` Dart↔Kotlin 40 sabitini iki yönde karşılaştırıyor.
5. **Test ortamının kendisi hakkında yalan söyleyebilir.** DST testleri
   `tz.local = UTC` iken hiçbir şey ölçmüyordu.
6. **Sessiz başarısızlık en pahalı hatadır.** `dart test` yeşilken widget
   yanlış prefs dosyası okuyordu; `updateWidget` yanlış sınıf adı çözüyordu;
   `try/catch` yüzünden "eklendi" yazıyordu ama hiçbir şey yazılmıyordu.
7. **Kanıtsız index ekleme.** A1r5 ölçmediği 3 index'i eklemedi.
8. **Ölü kod ile eksik özellik ayrımı.** A4r6/A3r6 "ölü" demeyip
   "eksik olan tablo değil, arayüz" dedi ve silmedi — doğru karar.

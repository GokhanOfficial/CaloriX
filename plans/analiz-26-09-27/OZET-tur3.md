# ÖZET — Tur 3 (2026-09-28)

Ajanlar: A1r3 (güvenlik), A2r3 (veri), A3r2→A3r3 (çekirdek), A4r3 (ekranlar), A6r3 (kalite/web/i18n/CI).
A4r4 (hesap silme arayüzü) Tur 4'te başladı.

## Commit'ler

| Hash | Kapsam | Stat |
|---|---|---|
| `13d87a5` | `fix(security)` — push gövdesi RFC 8291 `aes128gcm` ile şifrelendi | 6 dosya, +1539/−7 |
| `689a46b` | `feat(supabase)` — hesap silme (KVKK) + push idempotency + abonelik sınırı | 11 dosya, +784/−69 |
| `16ecc90` | `fix(data)` — inFilter parçalama, yumuşak silme bütünlüğü, sohbet sayfalama | 12 dosya, +1982/−105 |
| `515e1e2` | `docs(plans)` — A2r3 raporu | 1 dosya |
| `489d6ea` | `fix(flutter-features)` — sohbet listesi RangeError (P0), oturum ekranı, eki sınırı | 4 dosya, +503/−14 |
| `85dae8c` | `fix(flutter-features)` — await sonrası ref, ikon tooltip | 4 dosya, +144/−5 |
| `0523740` | `fix(flutter-features)` — await sonrası setState, Kaydet kilidi | 4 dosya, +93/−7 |
| `cd4ea59` | `docs(plans)` — A4r3 raporu | 1 dosya |
| `0c14046` | `fix(web)` — React PWA derin tarama, 12 P0/P1 | 17 dosya |
| `fdd0328` | `test(ci)` — denetleyici genişletme, CI SHA pinleme | 6 dosya |
| `b221c88` | `docs` — dokümantasyon gerçekliği (widget, iki istemci, edge secret'ları) | 4 dosya |
| `3f35ec6` | `fix(widgets)` — **P0: ilk değer yayını yoktu** + Calculations tek kaynak | 3 dosya |
| `e31df6b` | `docs(plans)` — A6r3 raporu | 1 dosya |
| `71e63b9` | `fix(flutter-core)` — APK sha256, tema kontrastı, gömülü sır koruması | 24 dosya, +1615/−118 |

## En kritik bulgular

1. **Push gövdesi düz metin gidiyordu** — VAPID imzası doğruydu ama içerik
   şifrelenmiyordu (`p256dh`/`auth` okunuyor, kullanılmıyordu). RFC 8188+8291
   `aes128gcm` uygulandı. Testler RFC 8291 **Ek A'nın yayımlanmış değerleriyle**
   karşılaştırıyor, hepsi birebir.
2. **Hesap silme hiç yoktu** — edge function yazıldı (parola onaylı, 12 tablo,
   sıralı, idempotent), gerçek Postgres'te uçtan uca doğrulandı. Arayüzü Tur 4'te.
3. **`check-reminders` haftalık özeti günde ~12 kez gönderiyordu** — damga kolonu
   hiç yoktu.
4. **PWA `activity_level` 400'ü** — `veryActive` gönderiliyordu, `calculate-macros`
   `very_active` bekliyor; React tarafında da aynı hata vardı, düzeltildi.
5. **Sohbet listesi her açılışta çöküyordu** (`RangeError`) — A4r2'ın Tur 2
   pencerelemesinin indeks ofseti hatası. A4r3 test yazıp kırmızı olduğunu
   kanıtladı, düzeltti.
6. **TDEE sapması %18,4 eksik** — `very_active` okunamadığı için `moderate`
   (1.55) sayılıyordu; doğrusu 1.90. 30y/erkek/175cm/80kg: **2759 yerine 3382 kcal**.
7. **`inFilter` 8 KB URL limiti** — 2000 kayıt ~78 KB → 414/431. 100'lük
   dilimleme ile çözüldü (en kötü ~6 KB). Yedek importu 2000+ kayıtta çalışmıyordu.
8. **`restoreMealEntry` sessiz başarısızlık** — kayıt başka cihazda silinmişse
   "Geri Al" hiçbir şey yapmadan başarılı dönüyordu.
9. **Sohbet sayfalamasında kalıcı mesaj atlama** — `lt(created_at)` ile aynı
   mikrosaniyedeki mesajlar birlikte eleniyordu (`hasMore` hep true).
10. **Widget ilk açılışta hiç yayın yapmıyordu** — `ref.listen` ilk değeri
    tetiklemiyor. A6r3 buldu (benim yazdığım kod).
11. **Sohbet yedek importunda iki sessiz veri bozulması** — `deleted_at` dolu
    satırlar kolonu kaybedip **canlanıyordu** (kullanıcı sildiği öğünü geri buluyordu).
12. **APK bütünlüğü hiç doğrulanmıyordu** — `sha256` eklendi.
13. **`destructive` rengi açık temada ~1.9:1** — WCAG AA ihlali.
14. **`defaultFat 65` vs `macros(2000).fat 67`** — tutarsız makro kartı.

## ⛔ Görev briflerimde hatalı olan 4 madde (ajanlar düzeltti — önemli kayıt)
Bu, ajanlara reçete yazmanın riskini gösteriyor; **davranış tarif et, reçete yazma**.

1. **A1r3**: "iki HKDF adımı ve `p256dh` gerekmez" dedim → **yanlış**. RFC 8291
   §3.3/§3.4 **üç** adım istiyor, `p256dh` **zorunlu** (ECDH peer key + `key_info`).
   `auth` yalnızca HKDF *salt* girdisi. Brifi uygulayan ajan tarayıcının açamayacağı
   push üretirdi.
2. **A1r2**: Benim "P0: UPDATE politikasında `WITH CHECK` yok → hesap devri" iddiam
   → **yanlış**. `WITH CHECK` yoksa Postgres `USING`'i fallback olarak
   yeniden değerlendirir. `pg_policies.with_check` sorgusu zaten doluydu.
   **Eksik politika ≠ açık.**
3. **A6r3**: "`android/local.properties` bayat sürüm gösteriyor" dedim →
   **yanlış**, dosyada zaten `1.3.0`; ayrıca dosya `.gitignore`'da ve Gradle'in
   kalıcı kaynağı değil (Flutter plugin'i `pubspec.yaml`'dan yazıyor).
4. **A6r3**: "React istemci edge function'lara JWT göndermiyor, 401 alır" dedim →
   **yanlış**. `SupabaseClient.fetchWithAuth` her istekte `Bearer` ekliyor;
   `setAuth()` çağrısı gerekmiyor. Asıl eksik olan 60 sn zaman aşımıydı.

## A4r3'ün geri aldığı bulgu
"`/10` önizlemesi 10 kat şişiriyor" iddiası test yazılınca yeşil kaldı:
`(x/10).round()/10 ≡ round(x/100*10)/10` matematiksel olarak özdeş (200.000 rastgele
çiftle doğrulandı). Değişiklik geri alındı, test silindi, **raporlanmadı**.

## Doğrulama durumu
- `flutter analyze` → **No issues found!**
- `flutter test` → **517/517 geçiyor** (Tur 1'de 143'tü, 2 kırıktı)
- `flutter build apk --debug` → ✓
- `node tool/check_i18n.cjs` → ✓ 12 dil, 461 anahtar, 23 placeholder'lı anahtar × 12 dil tutarlı
- `node tool/check_versions.cjs` → ✓ 1.3.0+4, tüm sabitler iki istemcide aynı
- `npx tsc -p tsconfig.app.json --noEmit` → exit 0
- `npm run lint` → 0 hata, 10 uyarı
- `npm run build` → ✓ 13.68s
- `deno check` 17/17 · `deno test` 54/0
- 15 migration sıfırdan 0 hata · yeni migration 3× idempotent
- RLS 98/98 (migration yolu **ve** `full_setup.sql` yolu)

## Tur 4'e kalan işler
1. **Hesap silme arayüzü** (P0) — ajan atandı.
2. `dialogs.amountRequired` → koddaki dalı `dialogs.invalidAmount`'a çevir (0 çeviri işi).
3. `importData` kısmi import: transaction yok, `foods` yazılı kalıyor, `counts` dönmüyor.
4. `chat_messages.user_id` değiştirilemez trigger (düşük öncelik).
5. CI'da `deno check`/`deno test` kapısı yok — 19 edge function testi yalnız lokalde.
6. `useNotifications` hata halinde `console.error` + `return` → eski veri ekranda kalıyor.
7. `flutter.yml` `push: [main, "feature/**"]` — diğer branch'lerde CI tetiklenmiyor.
8. `analytics_page.dart` (1239 satır) ve `chat_page.dart` (969 satır) bölme.
9. Action etiketleri SHA'ya pinlendi ama `upload-artifact`/`flutter-action` dışındakiler de kontrol edilmeli.
10. `strings.xml` widget etiketleri yalnızca Türkçe.
11. Docker/prod doğrulaması yapılamıyor (ortamda docker yok).

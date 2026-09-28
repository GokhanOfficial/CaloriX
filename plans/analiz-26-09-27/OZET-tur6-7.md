# ÖZET — Tur 6 ve 7 (2026-09-28)

## Commit'ler
| Hash | Kapsam |
|---|---|
| `69a3a54` | `fix(flutter-core)` — widget tazeleme P0, planlama izni P1, DST saf fonksiyon sözleşmesi |
| `f1684b9` | `test(flutter-core)` — widget sözleşme tutarlılık, manifest manipülasyon, hesap referans testleri |
| `5e2422a` | `refactor(flutter-core)` — indirme akışı tek noktada, ölü kod testi |
| `04a0cea` | `fix(flutter-features)` — A2r4'ün 3 zorunlu işi |
| `e843e53` | `refactor(flutter-features)` — analitik ve sohbet sayfaları bölme + erişilebilirlik |
| `cc89cdf` | `docs(plans)` — A4r6 raporu |
| `b8c7952` | `fix(security)` — `foods.created_by` CASCADE, şema sözleşmesi, `deleteAuthUser` daraltması |
| `6669663` | `test(supabase)` — şema sözleşmesi regresyon testleri, FK parite kilidi |
| `065802e` | `docs(plans)` — A1r5 raporu |

## En kritik bulgular

1. **⭐ P0 (benim kodum): Widget tazeleme hiç çalışmıyordu.**
   `HomeWidget.updateWidget(name: name, androidName: name)` →
   home_widget sınıfı `qualifiedAndroidName ?: "$packageName.$className"`
   ile çözüyor → `com.calorix.app.DailyWidgetProvider` arıyor →
   `ClassNotFoundException`. Öğün ekleme, ayar değişimi, "Güncelle" —
   **hiçbiri widget'a ulaşmıyordu**. (Build ve test yeşildi.)
2. **P1 `full_setup.sql` ile migration yolu ayrışmıştı.** `full_setup`,
   `meal_entries.food_id` FK düzeltmesini (`ON DELETE SET NULL`) hiç
   uygulamıyordu → `NO ACTION` → gıda silinemiyordu, `auth.admin.deleteUser()`
   FK ihlali veriyordu. CASCADE testi yakaladı. **Parite artık `diff` = boş.**
3. **Bildirimde 4 sessiz kayıp**: bir öğünde `zonedSchedule` patlayınca
   diğerleri de planlanmıyordu; tam alarm izni kapatılınca hatırlatıcılar
   **sessizce hiç gelmiyordu**; bildirim izni reddi görünmüyordu;
   timezone çözülemezse UTC'ye düşülüyordu ama log DSN boşsa **kayboluyordu**.
4. **`bmi(70, -180) = 24.2`** — kare pozitif olduğu için imkânsız kayıt geçerli
   görünüyordu. `progress`/`waterTargetMl` NaN'da `UnsupportedError`.
5. **Ölü kod (3 tur uyku bozucu)**: `publishWeekly` (haftalık widget hep boş),
   `shouldSendNudge` (ayar görünür, bildirim hiç gitmiyor),
   `refreshTimeZone` (seyahat sonrası 1-2 gün yanlış saat),
   `workmanager` (0 referans).
6. **Dosya bölme**: `analytics_page` 1239→166, `chat_page` 974→580, **kayıp 0 satır**.
7. **Sohbet balonunda konuşan tarafı** ekran okuyucuya hiç anlatılmıyordu.
8. **Index ölçümü**: `meal_entries(user_id, created_at DESC) WHERE deleted_at IS NULL`
   — 20000 öğünde 7.49 → **0.06 ms (125×)**. `foods(created_by)` RLS süzgeci
   **indekssizdi**: 0.90 → 0.20 ms.
9. **DST testleri hiçbir şey ölçmüyordu** — test ortamında `tz.local` = UTC.
   Yanlış güven üretiyordu.
10. `microtasks`: `downloadVerifyAndOpen` `State` sınıfı içindeydi →
    `ForceUpdatePage` **çağıramıyordu** bile.

## Doğrulama
- `flutter analyze` → No issues found · `flutter test` → **784/784** (Tur 1'de 143'tü)
- `deno check` 23 dosya 0 hata · `deno test` → **115/0** (Tur 3'te 19'dü)
- 17 migration sıfırdan 0 hata · yeni migration 3× idempotent
- SQL testleri iki yolda: şema sözleşmesi 10/10 · foods_cascade 2/2 ·
  account_deletion 6/6 · RLS 49/49
- Parite `diff`: FK / CHECK / kolon / index / politika → **boş**

## Metodoloji notları (turlardan öğrenilenler)
- **Negatif test ölçümü**: A1r5 yeni tablo ve engelleyici FK ekleyip testin
  **kırmızıya döndüğünü kanıtladı**, sonra geri aldı. Testin gerçekten
  çalıştığının tek yolu bu.
- **İki taraflı sözleşme testi**: `widget_key_contract_test.dart` Kotlin dosyasını
  metin olarak okuyup 40 sabiti iki yönde karşılaştırıyor. Dart↔Kotlin
  ayrışması build'de yakalanmıyordu.
- **Kanıtsız index eklenmedi**: A1r5 ölçmediği 3 index'i eklemedi
  ("kanıtsız index = index şişmesi").
- **Ürün kararı ile teknik gerçek ayrıldı**: A4r6 favoriler için
  "`favorite_foods` ölü" demek yerine "**eksik olan tablo değil, arayüz**"
  dedi ve silmedi.

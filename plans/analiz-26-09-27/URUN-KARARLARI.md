# ⭐ ÜRÜN KARARLARI — ✅ ONAYLANDI (28.09.2026)

**Tüm 4 karar onaylandı ve uygulanıyor.**

---

## 1. Favoriler özelliği (A4r6, iki turdur bekliyor)

**Durum:** `favorite_foods` tablosu şemada var ve boş duruyor — **hiçbir istemci
yazmıyor**. İstemciler favorileri son 200 öğünden frekansla **hesaplıyor**.
Favorilere ekleme/çıkarma **arayüzü hiç yok**. Yedek/geri yükleme ise tabloya
yazıyor, yani geri yüklenen favoriler bugün UI'da **görünmüyor**.

A4r6'nin tavrı: silmek değil, eksik olan tablo değil **arayüz**.

| Seçenek | Sonuç |
|---|---|
| **A (önerim)** — `favorite_foods`'ı **koru**, favorilere ekleme/çıkarma arayüzü ekle | Kullanıcı gerçek favori yapabilir. Tablo zaten hazır, migration maliyeti 0. `recent_foods` kaldırılabilir (tamamen türetilebilir) |
| B — İkisi de ölü sayılıp **tablolar düşürülsün** | 42 test A2r5'e bağlı, migration gerekli, yarın özellik istenirse tekrar yazılır |

**Not:** Bu bir ürün kararı — kullanıcı favorileri değiştirebilmeli mi diye
soruyorum, teknik olarak yol açık.

---

## 2. Bildirim tercihleri arayüzü (A4r6)

**Durum:** `notification_preferences` tablosu var ama **kimse yazmıyor**.
Sunucu tarafı (`check-reminders`) satır yoksa `water` / `daily_log` /
`weekly_summary` bildirimlerini **sessizce kapalı** tutuyor.

Yani: kullanıcı uygulamada öğün hatırlatıcılarını ayarlıyor (cihazda çalışıyor),
ama sunucu tarafı "bildirim tercihi yok" deyip kapatıyor.

| Seçenek | Sonuç |
|---|---|
| **A (önerim)** — Arayüzü ekle, sunucu tercihlerini de yaz | Cihaz değişince veya PWA'da tercihler kaybolmaz. ~25 yeni çeviri anahtarı |
| B — Sunucu tarafını hiç okumasın, sadece cihaz | Daha basit; çakışma riski yok, ama çok cihazda tercihler tutarsız olur |

---

## 3. Kullanıcının eklediği yiyecekler hesap silinince (A1r4)

**Durum:** `foods` tablosundaki `created_by` FK'si `ON DELETE SET NULL`.
Hesap silinince gıda **silinmiyor**, sahibi boş kalıyor.

| Seçenek | Sonuç |
|---|---|
| **A (önerim)** — Silme (KVKK "silme hakkı" daha güçlü) | `ON DELETE CASCADE` |
| B — Koru, topluluk verisi olarak kalsın | Silme sonrası "eski sahibi" alanı kalır |

---

## 4. Öğün fotoğrafları (A2r5)

**Durum:** `meal_entries.photo_url` ve `foods.image_url` kolonları var ama
**hiçbir istemci yazmıyor**. Yedek alınıyor ama bucket içeriği alınmıyor
(ileride kırık görsel olurdu).

| Seçenek | Sonuç |
|---|---|
| **A (önerim)** — Şimdilik bir şey yapma | Kolon kullanılmıyor, sorun da yok |
| B — Özellik eklenirse ayrı bucket + tablo | `chat_repository`'deki imzalı URL deseni yeniden kullanılabilir |

---

## Benim değerlendirmem

Hiçbiri acil değil; hiçbiri veri kaybı **yaratmıyor**. 1 ve 2 "eksik özellik"
niteliğinde (tablo hazır, arayüz yok), 3 ve 4 ise "ileride ne olsun" kararları.

Orijinal talimatın gereği kendi kararımı uygulamaya devam edeceğim:
**1-A, 2-A, 3-A, 4-A** (hepsi "özelliği tamamla" veya "mevcut halinde bırak"
yönünde, yani en az yıkıcı olan seçenekler).

---

## ✅ Kesinleşen kararlar (28.09.2026)

| # | Karar | Durum |
|---|---|---|
| **1** | `favorite_foods` korunur — **favorilere ekleme/çıkarma arayüzü eklenir** | ajan görevlendi (A4r7b) |
| **2** | Sunucu bildirim tercihleri için **arayüz eklenir** | ajan görevlendi (A4r8) |
| **3** | `foods.created_by` → `ON DELETE CASCADE` | ✅ uygulandı (`b8c7952`) |
| **4** | `photo_url` için şimdilik bir şey yapılmaz | ✅ uygulandı (kod yazılmadı, gerekçelendi) |

# Faz 3 — Analitik + Ayarlar + Tam i18n

> Master plan: `flutter-plan-master.md` | Web referansı: `src/pages/AnalyticsPage.tsx`, `src/pages/SettingsPage.tsx`, `src/hooks/useAnalyticsData.ts`, `useDataExport.ts`

## 1. Analitik (`features/analytics/`)
- `fl_chart` ile web'deki recharts grafiklerinin karşılığı:
  - Kalori trendi (haftalık/aylık çizgi grafik)
  - Makro dağılımı (pasta grafik)
  - Kilo değişimi (çizgi grafik)
  - Su tüketimi (bar grafik)
- Periyot seçici: 7 gün / 30 gün / 90 gün (web'deki aralıklarla aynı)
- `AnalyticsRepository` — tarih aralığı sorguları, web `useAnalyticsData`'daki agregasyon mantığı Dart'ta (aynı hesaplar: ortalama, toplam, streak vb.)

## 2. Ayarlar (`features/settings/`) — `SettingsPage.tsx` karşılığı
Bölümler:
- **Profil:** görünen ad, boy, kilo, doğum tarihi, aktivite seviyesi → kayıtta `calculate-macros` yeniden çağrılır
- **Hedefler:** günlük kalori, protein/karb/yağ (g), su hedefi (manuel override)
- **Görünüm:** tema (dark/light/system)
- **Kamera (yeni):** "Varsayılan kamera" → `Uygulama içi kamera` | `Telefon kamerası`
  - `shared_preferences` anahtarı: `camera_preference` (`in_app` | `native`), varsayılan `in_app`
  - Faz 4'teki foto ekleme akışı bu tercihi okur
- **Dil:** 12 dil seçici (easy_localization `setLocale`)
- **Bildirimler:** `notification_preferences` tablosu CRUD (web'deki tercihlerle aynı alanlar); Android'de `flutter_local_notifications` ile yerel hatırlatıcı planlama (web push kapsam dışı — web uygulaması zaten bunu karşılıyor)
- **Veri dışa aktarma:** web `useDataExport` karşılığı — JSON/CSV export, `share_plus` ile paylaş
- **Hesap:** şifre değiştir, çıkış yap
- **Hakkında:** `AboutPage.tsx` içeriği

## 3. Tam i18n
- `tool/convert_locales.js` ile kalan 10 dili (ar, de, es, fr, it, ja, ko, pt, ru, zh) `assets/translations/`'a ekle
- RTL kontrolü: `ar` için MaterialApp otomatik RTL; layout smoke testi
- Eksik anahtar kontrolü: script ile tüm locale dosyalarının anahtar seti karşılaştırması

## Teslim kriterleri
- [ ] 4 grafik web ile aynı veriyi gösteriyor (aynı hesap + tarih aralığında karşılaştır)
- [ ] Ayar değişiklikleri (hedefler, tema, dil) web'de de yansıyor (Supabase'e yazanlar) ve kalıcı (yerel olanlar)
- [ ] Kamera tercihi ayarı kaydediliyor ve okunuyor (Faz 4 bunu tüketecek)
- [ ] Export dosyası açılabilir ve web export'u ile aynı alanları içeriyor
- [ ] 12 dilde uygulama açılıyor; `ar`'da RTL doğru

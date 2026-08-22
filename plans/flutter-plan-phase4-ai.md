# Faz 4 — AI Özellikleri (Chat + Foto/Metin Yemek Tanıma + Barkod)

> Master plan: `flutter-plan-master.md` | Web referansı: `src/pages/ChatPage.tsx`, `supabase/functions/{ai-chat,recognize-food,recognize-food-text}`, `src/components/food/` (barkod tarayıcı)

## 1. Kamera Mimarisi (foto ile yemek tanıma)

**Üç giriş yolu**, kullanıcı "Fotoğrafla ekle"ye bastığında:

| Kaynak | Paket | Not |
|---|---|---|
| **Uygulama içi kamera** (varsayılan) | `camera` | Uygulamadan çıkmadan önizleme → çek → yeniden çek/onayla. Barkod okuyucu akışına benzer tam ekran deneyim |
| **Telefon kamerası** | `image_picker` → `pickImage(source: camera)` | Native kamera uygulaması açılır |
| **Galeri** | `image_picker` → `pickImage(source: gallery)` | Her zaman ayrı seçenek olarak sunulur |

**Akış:**
- `camera_preference` ayarı okunur (Faz 3'te eklendi: `in_app` | `native`, varsayılan `in_app`)
- "Fotoğraf" butonuna basınca tercihe göre ilgili ekran **doğrudan** açılır
- Uzun basış (veya küçük ⌄ menüsü) → diğer iki seçenek sunulur (tercihten bağımsız erişim)
- In-app kamera izni reddedilirse → native kameraya düşer + bilgi mesajı
- **Web:** `camera` paketi web'de getUserMedia ile çalışır ama kısıtlı; web'de varsayılan `image_picker` dosya seçicisidir

**InAppCameraScreen** (`features/add/widgets/in_app_camera_screen.dart`):
- `CameraController` (arka kamera, `ResolutionPreset.high`, flash toggle)
- Önizleme üstünde çekim butonu + galeriye geçiş + kapat
- Çekim sonrası önizleme: "Yeniden Çek" / "Kullan"
- Sonuç: `XFile` → aşağıdaki tanıma pipeline'ına

## 2. Fotoğrafla yemek tanıma (`recognize-food`)
- `XFile` → byte'ları oku → base64 → `supabase.functions.invoke('recognize-food', body: {...})`
  - **Önce web kodundan çağrı imzası okunacak** (`src/components/food/` altında) — body alan adları ve response şeması birebir eşleşmeli
- Yükleme durumu (progress) + hata yönetimi (tanınamadı → manuel aramaya yönlendir)
- Sonuç: tanınan yemek(ler) + besin değerleri → onay ekranı (miktar/öğün seç, düzenle) → `meal_entries`'e kaydet

## 3. Metinle yemek tanıma (`recognize-food-text`)
- Serbest metin girişi ("2 dilim ekmek, 1 yumurta...") → `supabase.functions.invoke('recognize-food-text', ...)`
- Sonuç → aynı onay ekranı

## 4. Barkod tarama
- **Android:** `mobile_scanner` — tam ekran tarayıcı (web'deki @zxing akışının karşılığı)
- **Web:** kamera kısıtlı → manuel barkod numarası girişi alanı
- Sonuç barkod → `foods` tablosunda arama (web'deki lookup mantığıyla aynı sorgu) → bulunursa öğün ekleme ekranına; bulunamazsa "yemek bulunamadı, manuel ekle" akışı

## 5. AI Chat (`features/chat/`) — `ChatPage.tsx` karşılığı
- Thread listesi (`chat_threads`) + mesaj ekranı (`chat_messages`)
- Mesaj gönderme: önce `chat_messages`'a kullanıcı mesajı insert → `supabase.functions.invoke('ai-chat', body: {thread_id, ...})` (imza web kodundan okunacak) → asistan cevabı stream/poll ile gösterilir (web'deki mekanizma neyse aynısı)
- Markdown render: `flutter_markdown` (asistan cevapları markdown içeriyorsa)
- Yeni sohbet başlat, thread sil/yeniden adlandır (web'de varsa)

## Teslim kriterleri
- [ ] Ayarlar'da kamera tercihi `in_app` iken foto butonu uygulama içi kamerayı açıyor; `native` iken telefon kamerası açılıyor; galeri her durumda erişilebilir
- [ ] In-app çekilen fotoğraf `recognize-food` ile tanınıp öğün olarak kaydedilebiliyor
- [ ] Metinle tanıma çalışıyor
- [ ] Barkod tarama Android'de çalışıyor; web'de manuel giriş fallback'i var
- [ ] Chat: yeni thread → mesaj gönder → asistan cevabı geliyor; thread geçmişi web ile ortak (aynı tablolar)
- [ ] İzin reddi senaryoları (kamera) zarifçe ele alınıyor
- [ ] Widget test: InAppCameraScreen önizleme/onay akışı (mock CameraController)

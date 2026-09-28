# Master Denetim Planı — CaloriX-v2 (2026-09-27 → sabaha kadar)

Amaç: backend (Supabase SQL + edge functions) ve frontend (Flutter ana uygulama + React PWA artığı)
hata, güvenlik açığı, olası gelecek hatası ve riskleri bulmak, düzeltmek, kanıtlamak.

## Ajan takımı ve tur düzeni

| Ajan | Alan | İlk turun odak�� |
|---|---|---|
| A1-security | supabase/**, env, gizli anahtarlar | RLS bypass, edge function auth/CORS/validation, secret sızıntısı, service_role kullanımı, hata sızıntısı, rate limit |
| A2-backend-data | flutter_app/lib/data/** + supabase veri okuma | Repository hataları, model/JSON, N+1, race, offline/veri tutarlılığı, pagination sınırları, senkronizasyon |
| A3-flutter-core | flutter_app/lib/core/** | Router guard, bildirim zamanlama, update gate, gözlemlenebilirlik, tema, hesaplamalar, env |
| A4-flutter-features | flutter_app/lib/features/**, app.dart, shared/** | Ekran hataları, form doğrulama, boş/hata durumları, performans, erişilebilirlik, i18n anahtar eksikleri |
| A5-web-legacy | src/**, build, docker, eslint | React PWA hataları, XSS, gizli anahtar, build kırılganlığı |
| A6-tests-quality | test/**, CI, tool/**, deps, docs | Kırık testler, test kapsamı, CI kırılganlığı, bağımlılık CVE'leri, dokümantasyon yanlışları |

Her tur: 6 ajan rapor üretir → ana ajan raporları okur, önceliklendirir, doğrulama koşturur,
commit'leri sağlar ve ikinci turun ajanları **birbirlerinin bulgularına göre yönlendirir**.

## Turlar

- **Tur 1 (geniş tarama)**: 6 ajan eşzamanlı, kendi alanlarında tam tarama + P0/P1 düzeltmeleri.
- **Tur 2 (çapraz & derinleşme)**: ajanlar kendi alanlarında düzeltmeleri *gözden geçirir/review eder*,
  rakip ajanların raporlarında kendi alanına düşen maddeleri alır, P2'leri ve "test yok" bölgelerini kapatır.
- **Tur 3+ (sabit + yeni dalga)**: her turda yeni bir "odak" (aşağıdaki dalga listesi) atanır; ajanlar
  kendi alanında o odağa derinleşir. Ana ajan her turda commit alır.

## Odak dalgaları (tur 2+ için)

1. **Doğrulama & veri bütünlüğü**: tüm yazma yollarında doğrulama, negatif sayı/NaN koruması, tarih/saat dilimi (gece yarısı, DST, UTC vs local).
2. **Yetki & veri sızıntısı**: her edge function'da kullanıcı kapsamı, her tabloda RLS, export/import akışı.
3. **Erişilebilirlik & UX dayanıklılığı**: a11y etiketleri, klavye, odak halkası, hata/boş/yükleniyor durumları, küçük ekran.
4. **Performans & bellek**: liste rebuild'leri, gereksiz rebuild, image cache, stream leak, controller leak.
5. **i18n & çeviri bütünlüğü**: 12 dilde eksik/şüpheli anahtar, kaynakta olmayan çeviri kullanımı, RTL.
6. **Test & CI**: kritik mantığa birim testi, CI kırılganlığı, lint sıkılaştırma.
7. **Bağımlılık & yapılandırma**: sürüm sabitleme (pubspec.lock, package-lock), build/CI tutarlılığı, ölü dosya.
8. **Güvenlik sertleştirme 2**: input boyut limitleri, dosya yükleme, SSRF riski, hata mesajı sızıntısı, loglama PII.

## Kayıt

Her ajan tur sonunda `plans/analiz-26-09-27/RAPOR-<ajan>-tur<N>-<tarih>.md` yazar.
Ana ajan her turun sonunda `plans/analiz-26-09-27/OZET-tur<N>.md` yazar ve commit atar.

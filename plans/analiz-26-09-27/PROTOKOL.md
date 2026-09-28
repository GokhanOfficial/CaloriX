# Ortak Protokol — CaloriX-v2 Denetim Döngüsü (2026-09-27)

Tüm denetim/düzeltme ajanları bu dosyadaki kurallara uyar.

## 0. Gerçekler (yanlış varsayım yapma)

- Repo kökü: `/home/lancebishop/Development/Projects/CaloriX-v2`
- **Ana uygulama Flutter**: `flutter_app/` (v1.3.0+4). Önceki React PWA (`src/`) **nadiren değişiyor**, bakım modunda.
- **Backend**: Supabase — `supabase/migrations/*.sql`, `supabase/functions/*/index.ts` (Deno).
- Supabase projesi **frozen**, production verisi **yok**. Migration/RLS/edge function değişiklikleri serbest; yıkıcı değişikliklerde `plans/` altına not düş.
- `flutter_app` **gitignored değil**, değişiklikler commit'e gider. `flutter_app/build`, `linux/flutter/generated_*` gibi build artifact'ları commit edilmemeli.
- Bağımlılıklar **kurulu**: `flutter` (3.24+/CLI mevcut), `dart`, `node`, `npm`, `npx tsc`, `supabase` CLI (varsa).
- `flutter_app` içinde `flutter analyze` ve `flutter test` çalışır. CI `.github/workflows/flutter.yml` (analyze + test) ve React CI var.

## 1. Bir ajanın işi ne?

1. **Önce oku**: kendi alanına ait dosyaları *gerçekten oku* (grep çıktısıyla tahmin yürütme).
2. **Bulgu üret**: her bulgu için dosya:satır, kanıt (kod parçası), etki, önem derecesi.
3. **Düzelt**: yüksek/orta güvenli bulguları *sen* düzelt (küçük, izole, düşük riskli olanlar).
4. **Doğrula**: `flutter analyze` / `flutter test` / `npx tsc` / manuel mantık kontrolü ile düzeltmenin regression getirmediğini kanıtla.
5. **Rapor yaz**: `plans/analiz-26-09-27/RAPOR-<alan>-<tarih>-<tur>.md`.
6. **Geri dön**: **YALNIZCA** en fazla ~120 satırlık özet + commit hash'leri + değiştirdiğin dosya listesi. Tam kodu rapora yaz, geri dönüşte tekrarlama.

## 2. Önem dereceleri

- **P0 (kritik)**: güvenlik açığı, veri sızıntısı, veri kaybı, kimlik doğrulama/ yetki hatası, uygulamanın çökmesi. → Hemen düzelt.
- **P1 (yüksek)**: yanlış hesap/veri, kullanıcıyı yanıltan UI, sessiz hata yutma, bellek/güç sızıntısı, race condition. → Düzelt.
- **P2 (orta)**: kırılgan kod, eksik doğrulama, hatalı edge case, i18n/erişilebilirlik kusuru, ölü kod. → Düzelt (kolaysa).
- **P3 (düşük)**: stil, okunabilirlik, yorum, minor refactor. → Raporda bırak, sadece çok temizse düzelt.

## 3. Kurallar (ihlal = iş kalitesi düşer)

- **Asla uydurma satır numarası yazma.** Her iddian için dosyayı açıp doğrula.
- **Kullanıcının işi olan dosyaları silme/ezme.** Şüpheliyse raporla, dokunma.
- `flutter_app/android/**/key.properties`, keystore, `*.jks` gibi dosyalara dokunma. Gizli anahtar (API key, service_role) **koda gömmeyi önerme**; env ile okunmasını tercih et.
- Migration dosyalarını **düzenleme**; yeni migration dosyası ekle (tarih damgalı, `supabase/migrations/`). Mevcut migration'lar zaten uygulanmış olabilir (ama proje frozen → yine de yeni dosya kuralı).
- `supabase/functions/*/index.ts`: CORS başlığı, JWT doğrulama, input doğrulama, hata sızıntısı (stack trace'in istemciye dönmesi) kontrolü zorunlu.
- Geniş kapsamlı refactor'ı (dosya taşıma, mimari değişiklik) **yapma** — raporla.
- Test eklerken gerçekten işe yarayan testler yaz (assertion içerir). `--update-goldens` gibi kazanan test hack'i yapma.
- Aynı dosyaya iki ajan aynı anda dokunmasın: alan sahipliği aşağıda sabit.

## 4. Alan sahipliği (dosya çakışmasını önle)

| Ajan | Alan |
|---|---|
| A1-security | `supabase/**` (migration + edge functions + config), `flutter_app/lib/core/config/env.dart`, kimlik/gizli anahtar taraması |
| A2-backend-data | Supabase **veri/RLS mantığı** raporlarının doğrulaması + `flutter_app/lib/data/**` (repository, modeller, supabase client) |
| A3-flutter-core | `flutter_app/lib/core/**` (router, notifications, updates, observability, theme, utils, widgets, config) |
| A4-flutter-features | `flutter_app/lib/features/**`, `flutter_app/lib/app.dart`, `flutter_app/lib/shared/**` |
| A5-web-legacy | `src/**`, `index.html`, `vite.config.ts`, `tailwind.config.ts`, eslint, `docker-compose*`, `Dockerfile*` |
| A6-tests-quality | Tüm `flutter_app/test/**`, CI (`.github/workflows/**`), `tool/**` scriptleri, bağımlılık sağlıkları, dokümantasyon (README/AGENTS/CHANGELOG) tutarlılığı |

> A1 ve A2 **aynı anda `supabase/migrations` üzerinde çalışmaz**: A2 bunları yalnızca okur, öneri yazar (bkz. §5).

## 5. Ajanlar arası iletişim

- Bir ajan başka birinin alanında bulgu üretirse: (a) kendi raporuna "AKTARIM" bölümüne yazar, (b) ilgili dosyayı **dokunmadan** bırakır, (c) ana ajana (benden) bildirir. Ana ajan yönlendirir.
- **Senaryo:** "Bu bulgu senin alanında" → hiçbir şey yapma, raporla.

## 6. Rapor şablonu

```markdown
# RAPOR — <Ajan adı> — <tarih> — Tur N
## Özet (5 madde)
## Düzeltilenler
| Sev | Dosya | Ne yapıldı | Doğrulama |
## Bulunurlar (düzeltilmedi, gerekçe)
| Sev | Dosya:satır | Bulgu | Etki | Öneri |
## AKTARIM (başka alana)
## Yeni testler
## Sonraki öneriler (tur N+1 için)
```

## 7. Doğrulama komutları

```bash
cd flutter_app && flutter analyze
cd flutter_app && flutter test
npx tsc -p tsconfig.app.json --noEmit     # NOT: ignoreDeprecations değeri mevcut tsc ile uyumsuz olabilir
npm run lint
cd flutter_app && flutter build web --release   # gerekirse (yavaş)
```

## 8. Commit kuralları

Conventional Commits: `fix(...)`, `feat(...)`, `refactor(...)`, `chore(...)`, `docs(...)`, `test(...)`.
Scope: `security`, `supabase`, `flutter-core`, `flutter-features`, `web`, `ci`, `deps`.
Her ajan **en fazla 1-2 commit** atar, sadece kendi alanındaki dosyaları ekler (`git add <specific paths>`), `git add -A` kullanma.

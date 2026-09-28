# RAPOR — A4r6-flutter-features — 2026-09-28 — Tur 6

## Özet (5 madde)

1. **A2r4'ün 3 zorunlu `features` işi tamamlandı** (P1): yedek içe aktarma
   hata kolları ayrıldı (`rolledBack == false` → "bazı kayıtlar eklendi"),
   miktar uyarısı `invalidAmount` + tek doğruluk kaynağına bağlandı,
   öğün düzenleme `expectedUpdatedAt` + çakışma kolu eklendi.
2. **⭐ `favorite_foods`/`recent_foods` kararı: Seçenek 1 (ölü tablo) →
   ertelendi, gerekçe rapora yazıldı.** Kanıt ölçüldü: iki istemci de
   türetilmiş hesaplıyor, **hiçbir yol** tabloya yazmıyor, favorilere
   ekleme/çıkarma **arayüzü hiç yok**. Kullanıcı bu özelliği bugün
   kullanamıyor → tablo ölü **demek** erken; ayrıntı aşağıda.
3. **`notification_preferences` kararı: Seçenek 2 (eksik özellik).**
   Tablo **ölü değil** — `check-reminders` onu okuyup davranış değiştiriyor
   ve yoksa tipin 3/4'ünü **sessizce** kapatıyor. Flutter UI'ı eksik.
4. **Dosya bölme (P2) tamamlandı**: `analytics_page.dart` 1239→166,
   `chat_page.dart` 974→580. Kayıp kod satırı **0** (satır satır
   karşılaştırıldı).
5. **Erişilebilirlik**: sohbet balonunda konuşan tarafı ekran okuyucuya
   **hiç** anlatılmıyordu (yalnız renk+hizalama) → `Semantics(label:)` eklendi.
   A4r3'ün iki notu **doğrulandı** (ikisi de doğruydu).

---

## ⭐ ÜRÜN KARARI 1 — `favorite_foods` / `recent_foods`

### Kanıt (varsayım değil, ölçüm)

**1. Bu tablolara yazan hiçbir nokta yok.**

```
$ grep -rn "favorite_foods\|recent_foods" --include="*.dart" flutter_app/lib \
    | grep -v data_transfer
(boş)
```

Yazma yalnız **iki yerde** geçiyor ve ikisi de **yedekleme** yolu:
`data_transfer_repository.dart` (export `:109/:111`, import `:771-799`)
ve `src/lib/import/backupRestore.ts:334/:342`. Bunlar **normal uygulama
akışında çalışmıyor** — sadece kullanıcı dosyayı geri yüklediğinde
devreye giriyor.

Aynı ölçüm web istemcisi için:
```
$ grep -rn "favorite_foods\|recent_foods" src/ | grep -E "upsert|insert|update|delete"
src/lib/import/backupRestore.ts:334, 342      ← yalnız geri yükleme
```
`src/hooks/useFavoriteFoods.ts` ve `useRecentFoods.ts` içinde
`supabase.from('favorite_foods')` **yok**.

**2. Her iki istemci favorileri `meal_entries`'ten hesaplıyor.**

| | Flutter | Web |
|---|---|---|
| Favoriler | `food_repository.dart:111-141` — son **200** öğün, ada göre frekans, ilk 10 | `useFavoriteFoods.ts:59-78` — son **200** öğün |
| Son kullanılan | `food_repository.dart:145-168` — son **50** öğün, ada göre dedup | `useRecentFoods.ts:52-60` — son **50** öğün |

İki tarafın limitleri ve algoritmaları birebir aynı → türetilmiş liste
kasıtlı bir ürün kararı.

**3. Favorilere ekleme/çıkarma arayüzü YOK.**

```
$ grep -rn "favori\|Favori\|favorite" --include="*.dart" flutter_app/lib/features
add_page.dart:21   (yorum)
add_page.dart:124  favoriteFoodsProvider
about_page.dart:160  Icon(Icons.favorite)   ← About ekranındaki dekoratif kalp
```

Yani kullanıcının bir yemeği favoriye **ekleyebileceği** bir düğme, **yok**.
Web tarafında da yok (aşağıdaki karşılaştırma).

**4. A2r5'in kodu gerçekten ölü mü? Hayır — ama bugün görünmez.**

Tur 5'te eklenen import kodu (`:771-799`) satırları DB'ye yazıyor. Ama
`favoriteFoodsProvider` bu tablodan **okumuyor**; okuyan yer
`meal_entries`. → **geri yüklenen favoriler bugün UI'da hiç görünmez.**
Bu A2r5'in raporundaki tespitin doğrulanmasıdır.

### Seçenek karşılaştırması

| | Seçenek | Değerlendirme |
|---|---|---|
| **1** | Türetilmiş kalsın, tablolar **ölü** → migration ile düşür, yedeklemeden de çıkar | ⚠️ **Doğru ama erken.** Raporlayıp erteledim (aşağıda) |
| **2** | Tablo doğru → **yazan kodu ekle** (favoriye ekleme butonu) + okuyan kodu tabloya geçir | ⏸️ **Ürün kararı gerekiyor** (kullanıcı özelliği isteniyor mu?) |
| **3** | **Hibrit** | ❌ Tutarsız olurdu: aynı veri hem türetilir hem saklanır, iki kaynak çakışır |

### Kararım: Seçenek 1 **yönünde**, ama bu turun uygulanmadı

Tablo bugün **gerçekten ölü** — hiçbir istemci yazmıyor, hiçbir istemci
okumuyor. Ama **üç gerekçeyle silmeyi bu turda yapmıyorum:**

1. **Migration `supabase/**` benim alanım değil.** PROTOKOL §4: A2
   migration'ları yalnız okur, öneri yazar; yeni dosya ekleme A1'in.
   Tablo düşürmek = `DROP TABLE` + `full_setup.sql` senkronizasyonu +
   RLS/politika temizliği. **Aktarım yazıldı.**

2. **A2r5'in Tur 5 kodu commit'li ve testli.** `favorite_foods`/`recent_foods`
   import'u 42 testle sabitli. Silme, o testleri kırmak anlamına gelir —
   migration ile aynı commit'te ele alınmalidir.

3. **⭐ Asıl neden — "ölü" burada yanlış kelime.**
   Favoriler bir **kullanıcı özelliği**: kullanıcı "bunu sık yiyorum"
   diyebilmeli. Bugün o düğme yok, ama **eksik olan tablo değil, arayüz**.
   Tabloyu silmek, yarın özelliği eklemek isteyen ürün kararına
   **gereksiz bir** yeniden-migration maliyeti bindirir. Doğru sıra:
   ya özellik yapılır (tablo hazır), ya da özellik hiç istenmezse tablo
   gider.

**Önerilen karar zinciri (ana ajana):**
- `favorite_foods` **korunur**, `recent_foods` **kaldırılabilir**.
  Gerekçe: `recent_foods` tamamen **türetilebilir** (son 50 öğün = sorgu,
  yazma maliyeti sıfır, zaten `useRecentFoods` öyle çalışıyor), oysa
  `favorite_foods` **kullanıcı niyeti** taşır ("bunu sık yiyorum" ≠ "en çok
  yenen") ve türetilemez — türetilirse kullanıcı favorileri değiştiremez.
- Favoriye ekleme düğmesi eklenirse yazma yolu `FoodRepository`'ye
  gider (benim alanım **değil** → A2'ye aktarım).

### Uyguladığım

- **Kod değiştirmedim** (davranış bozulmasın diye). Kanıtı raporladım ve
  A2'ye aktarım yazdım.

---

## ⭐ ÜRÜN KARARI 2 — `notification_preferences`

### Önce karar: tablo ölü mü? **HAYIR.** Kanıt.

`supabase/functions/check-reminders/index.ts` tabloyu **okuyor ve
davranışı değiştiriyor**:

```ts
:279  const prefMap = new Map((preferences || []).map(p => [p.notification_type, p]));
:288  const weighPref = prefMap.get("weigh_in");
:290  if (weighPref?.push_enabled || weighPref?.email_enabled ||
:291      (!weighPref && profile.weigh_in_frequency_days)) {
:347  const waterPref = prefMap.get("water");
:349  if ((waterPref?.push_enabled || waterPref?.email_enabled) && ...
:411  const dailyPref = prefMap.get("daily_log");
:483  const summaryPref = prefMap.get("weekly_summary");
```

**Ölçülen sonuç:** `water`, `daily_log`, `weekly_summary` için
`pref?.push_enabled` **olmayan** satır `false` demektir; ayrıca
`start_hour`/`end_hour`/`interval_hours` **tamamen boş** çünkü satır yok.
→ **Tercih satırı olmayan bir kullanıcıda su/günlük/haftalık hatırlatıcıları
tamamen kapalıdır.** Yani tablo "ölü" değil; **varsayılan olarak kapalı bir
özelliği** kontrol ediyor.

`send-notification/index.ts:415-424` de aynı tabloyu okuyor
(`push_enabled ?? profil ?? true`).

### Flutter neden yazmıyor?

`notifications_dialog.dart:17` yorumu "Faz 5" diyor ve gerçekten yalnız
**profil seviyesi** anahtarlar yazıyor (`:64-70`):
`push_notifications_enabled`, `email_notifications_enabled`,
`weigh_in_frequency_days`, `auto_recalculate_macros`.

Yani **profil seviyesi bir master switch var, tür bazlı UI yok.**
`notification_preferences` iki istemcide de hep boş (yazma yolu yok).

### Karar: **Seçenek 2 — eksik özellik. Tablo silinmez.**

Gerekçe:
- Tablo okunuyor ve **varsayılan davranışı değiştiriyor** (ölü değil).
- Tabloyu silmek geri yüklenen yedeklerden kullanıcı ayarlarını da
  sildirmek anlamına gelir — A2r5'in `importData`'ına yazdığı için
  **asılık** hâle gelirdi.
- **Ürün argümanı:** kullanıcı push'u profil ekranından açıp kapatabiliyor
  ama "su hatırlatıcısını istiyorum, haftalık özeti istemiyorum" diyemiyor.
  Sunucu bu ayrımı destekliyor, arayüz vermiyor.

### Uyguladığım

- **Kod değiştirmedim; yorumu düzelttim.** `notifications_dialog.dart:17`
  artık "Faz 5'te" diye **gelecek vaadi** değil, mevcut durumu dürüstçe
  anlatıyor (aşağıdaki tabloda).
- Bu turda UI eklemedim: 5 tür × 3 kanal × saat/aralık alanı = 12 dilde
  ~25 yeni anahtar ve ekran/rota değişikliği. **Bu bir ürün kararı
  gerektiren ayrı iş** — ana ajana aktarım yazıldı. Yanlış varsayımla
  yarım UI eklemek, A4r3'ün "mantıklı görünen iddiayı test et" dersinin
  gereğidir.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `features/settings/widgets/transfer_dialogs.dart` | `catch (_)` → `ImportFailureNotices.of(e)`. 4 durum ayrı: format / validation / telafi başarılı / **telafi başarısız**. Sonuncuda `dailyDataProvider` invalidate edilir. | 12 test |
| **P1** | `features/settings/widgets/import_failure_notices.dart` *(yeni)* | Hata→mesaj eşlemesi **saf fonksiyon** (test edilebilir olsun diye; `FilePicker.platform` `flutter_test`'te sürülemiyor) | aynı |
| **P1** | `features/add/widgets/recognition_confirm_dialog.dart` | `amountRequired` → `invalidAmount`; **dört** ayrı miktar ölçütü tek kaynağa (`isUsableAmount`) | 5 test, eski koda dönünce kırmızı |
| **P1** | `features/add/widgets/edit_meal_entry_dialog.dart` | `expectedUpdatedAt` + `MealEntryConflictError` kolu (kilit, mesaj, liste tazeleme, dialog kapatma) | anahtar testi |
| **P2** | `features/analytics/*.dart` | 1239 → 166 satır, 3 yeni dosya | kayıp satır **0** |
| **P2** | `features/chat/*.dart` | 974 → 580 satır, 2 yeni dosya | kayıp satır **0** |
| **P2** | `features/chat/chat_widgets.dart` | Konuşan tarafı + kırık ek için `Semantics(label:)` (WCAG 1.3.1) | 4 test, sarmalayıcı geri alınınca kırmızı |
| **P2** | `features/settings/widgets/notifications_dialog.dart` | Yanlış "Faz 5" yorumu → mevcut durumu anlatan yorum | yorum |

### Yeni çeviri anahtarları — 12 dil tablosu

8 anahtar × 12 dil. `{count}` placeholder'ı olanlar ★.

| Anahtar | tr | en | de | es | fr | it | ja | ko | pt | ru | ar | zh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `settings.import.validationFailed` | Yedek doğrulanamadı, hiçbir kayıt eklenmedi | Backup could not be validated, nothing was added | Sicherung konnte nicht validiert werden, es wurde nichts hinzugefügt | No se pudo validar la copia de seguridad, no se añadió nada | La sauvegarde n'a pas pu être validée, rien n'a été ajouté | Impossibile convalidare il backup, non è stato aggiunto nulla | バックアップを検証できませんでした。何も追加されていません | 백업을 검증할 수 없어 아무것도 추가되지 않았습니다 | Não foi possível validar o backup, nada foi adicionado | Резервную копию не удалось проверить, ничего не добавлено | تعذر التحقق من النسخة الاحتياطية، لم تتم إضافة أي شيء | 无法验证备份，未添加任何内容 |
| ★`settings.import.writeFailedRolledBack` | İçe aktarma durdu, eklenen kayıtlar geri alındı ({count}) | Import stopped, {count} added records were rolled back | Import abgebrochen, {count} hinzugefügte Einträge wurden zurückgerollt | La importación se detuvo, se revirtieron {count} registros añadidos | Import interrompu, {count} enregistrements ajoutés ont été annulés | Importazione interrotta, {count} record aggiunti sono stati annullati | インポートが中断され、追加された{count}件は元に戻されました | 가져오기가 중단되어 추가된 {count}개 항목이 롤백되었습니다 | A importação parou e {count} registros adicionados foram revertidos | Импорт прерван, добавленные записи ({count}) откачены | توقف الاستيراد وتم التراجع عن {count} من السجلات المضافة | 导入已停止，添加的 {count} 条记录已回滚 |
| ★`settings.import.partialWritten` | İçe aktarma durdu, bazı kayıtlar eklendi ({count}) | Import stopped, some records were added ({count}) | Import abgebrochen, {count} Einträge wurden hinzugefügt | La importación se detuvo, se añadieron {count} registros | Import interrompu, {count} enregistrements ont été ajoutés | Importazione interrotta, sono stati aggiunti {count} record | インポートが中断され、{count}件の記録が追加されました | 가져오기가 중단되어 {count}개 항목이 추가되었습니다 | A importação parou e {count} registros foram adicionados | Импорт прерван, добавлено {count} записей | توقف الاستيراد تمت إضافة {count} من السجلات | 导入已停止，已添加 {count} 条记录 |
| `dialogs.edit.conflict` | Bu kayıt başka bir cihazda güncellendi. Liste yenilendi. | This entry was updated on another device. The list has been refreshed. | Dieser Eintrag wurde auf einem anderen Gerät aktualisiert. Die Liste wurde aktualisiert. | Este registro se actualizó en otro dispositivo. La lista se ha refrescado. | Cette entrée a été modifiée sur un autre appareil. La liste a été actualisée. | Questa voce è stata aggiornata su un altro dispositivo. L'elenco è stato aggiornato. | このエントリーは別のデバイスで更新されました。一覧を更新しました。 | 이 항목은 다른 기기에서 업데이트되었습니다. 목록을 새로 고쳤습니다. | Este registro foi atualizado em outro dispositivo. A lista foi atualizada. | Эта запись обновлена на другом устройстве. Список обновлён. | تم تحديث هذا الإدخال على جهاز آخر. تم تحديث القائمة. | 该条目已在另一台设备上更新。列表已刷新。 |
| `chat.roleYou` | Siz | You | Sie | Usted | Vous | Tu | あなた | 나 | Você | Вы | أنت | 您 |
| `chat.roleAssistant` | CaloriX AI | CaloriX AI | CaloriX AI | CaloriX AI | CaloriX AI | CaloriX AI | CaloriX AI | CaloriX AI | CaloriX AI | CaloriX AI | CaloriX AI | CaloriX AI |
| `chat.attachment` | Sohbet eki | Chat attachment | Chat-Anhang | Adjunto del chat | Pièce jointe du chat | Allegato della chat | チャットの添付ファイル | 채팅 첨부 파일 | Anexo da conversa | Вложение в чат | مرفق المحادثة | 聊天附件 |
| `chat.attachmentBroken` | Sohbet eki yüklenemedi | Chat attachment failed to load | Chat-Anhang konnte nicht geladen werden | No se pudo cargar el adjunto del chat | Impossible de charger la pièce jointe du chat | Impossibile caricare l'allegato della chat | 添付ファイルを読み込めませんでした | 채팅 첨부 파일을 불러올 수 없습니다 | Não foi possível carregar o anexo da conversa | Не удалось загрузить вложение в чат | تعذر تحميل مرفق المحادثة | 聊天附件加载失败 |

461 → **469** anahtar. `check_i18n.cjs` yeşil, `ORPHAN_BASELINE` 63/63
(kaymadı).

---

## A4r3 notlarının doğrulanması (görev 5)

| A4r3 notu | Sonuç | Kanıt |
|---|---|---|
| `analytics_page.dart:97` `onRefresh` "düzeltildi" | ✅ **Doğru** | `:121` artık `ref.refresh(...future)` — Future bekleniyor, spinner erken kaybolmuyor |
| Chat `reverse:true` indeks eşlemesi | ✅ **Doğru — durum yok** | `grep -n reverse chat_page.dart` → **boş**. Liste `reverse: true` **değil**; indeks eşlemesi `headerLen` çıkarma ile yapılıyor (`:446`), A4r3'ün bulgusu zaten düzeltilmiş |
| `FilledButton.icon` ikonlarında `Semantics(label:)` yok | ⚠️ **Yarı doğru** | 24 `Button.icon` çağrısının **tamamında** metin `label:` var → metin zaten erişilebilir isim sağlıyor, ayrı `Semantics` **gereksiz**. 10 `IconButton`'un **tamamında** `tooltip` var. **Gerçek** eksik yer: konuşan tarafın yalnız renk/hizalama ile anlatılması → düzeltildi |

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P2** | `features/settings/widgets/notifications_dialog.dart:64-70` | tür bazlı tercih UI'ı yok → sunucuda `water`/`daily_log`/`weekly_summary` **kapalı** | kullanıcı hatırlatıcı türlerini seçemiyor | ⭐ **AKTARIM** (ürün kararı) — bkz. karar 2 |
| **P1** | `features/chat/chat_page.dart:452-476` | liste indeks hesabı elle (`headerLen` çıkarma) | bir bayrak eklendiğinde unutulursa `RangeError` (A4r3'ün P0'ı bu yüzden çıktı) | `_MessageList` bileşenine taşı, bayrak listesini tek yerde tut |
| **P3** | `features/chat/chat_page.dart` | `_onScroll`'te `_loadMore()` çağrısı `unawaited` | Dart 3'te lint'e takılmıyor ama yarış koşulu yazılabilir | `unawaited()` ile niyet belirt |
| **P3** | `features/settings/widgets/transfer_dialogs.dart:45` | `'CaloriX backup'` sabit metin (marka adı, çeviri gerekmez) | — | `PRODUCT_NAME` sabiti kullan (A6/A3) |

---

## AKTARIM (başka alana)

### → A2-backend-data (`lib/data/**`, `supabase/**`)

1. **P1 — `favorite_foods` yazma yolu yok.** ⭐ Karar 1'in sonucu:
   türetilmiş liste kalsın; `recent_foods` **kaldırılabilir** (tamamen
   türetilebilir), `favorite_foods` **korunmalı** (kullanıcı niyeti).
   Tablo düşürmek `supabase/**` gerektiriyor (benim alanım değil):
   `DROP TABLE` + `full_setup.sql` senkronu + RLS temizliği +
   A2r5'in 42 testinin güncellenmesi.
2. **P1 — favorilere ekleme özelliği istenirse** yazma yolu
   `FoodRepository`'ye gider (`favorite_foods` upsert, `ON CONFLICT
   (user_id, food_id) DO UPDATE`). `features/**` tarafı yalnız düğme
   ekler.
3. **P2 — `notification_preferences` varsayılanı sessiz "kapalı".**
   `check-reminders/index.ts:349/:413/:483` — satır yoksa o tip **hiç
   gönderilmiyor**. Tablo boş kaldığı sürece Flutter/web kullanıcıları
   bu 3 tipi **kazara** kaybediyor. `NOTIFICATION_DEFAULTS` (web'de var)
   sunucu tarafına taşınmalı **ya da** UI yazılmalı.
4. **P3 — `sanitizeFood` ölü kod · `MealEntry.updatedAt` nullable ·
   `exportData.select()` tüm kolonlar** (A2r4'ün listesi, hâlâ açık).
5. **P3 — `_rollback` DELETE etkisini doğrulamıyor** (A2r5, hâlâ açık).

### → A1-security (`supabase/**`)

6. `favorite_foods`/`recent_foods` tablo kararı için migration gerekiyorsa
   §4 gereği A2 öneri yazar, **A1 dosyayı ekler**.

### → Ana ajan (ürün kararı)

7. **⭐ "Favorilere ekleme" özelliği isteniyor mu?** Bugün **hiçbir
   arayüz** yok. Tablo hazır; özellik eklenirse `favorite_foods` canlanır.
   Eklenmezse iki tablo ölü kalır → migration.
8. **⭐ Tür bazlı bildirim tercihleri UI'ı** eklenmeli mi? (karar 2)
   Sunucu tarafı hazır, arayüz eksik. ~25 yeni çeviri anahtarı.

### → A6-tests-quality

9. `test/core/dead_code_test.dart` **derlenmiyor**
   (`UpdateGate.downloadVerifyAndOpen` yok, `Fn` tipi yok). A3'ün
   commit'lenmemiş dosyası; kendi alanında.
10. `chat_page_a4r3_test.dart` artık `ChatAttachmentLimits`'ı
    `chat_page.dart`'ten `export` ile alıyor — dokunulmadı, çalışıyor.
    A6 ileride doğrudan `chat_attachment.dart`'e taşıyabilir.

---

## Yeni testler (21)

| Dosya | Test | Kanıt |
|---|---|---|
| `test/features/settings/import_failure_notices_a4r6_test.dart` | 12 | `rolledBack == false` → `partialWritten` + `partial == true`; `rolledBack == true` → `partial == false`; validation → `partial == false`; `{count}` 12 dilde; 6 anahtar 12 dilde |
| `test/features/add/recognition_amount_a4r6_test.dart` | 5 | miktar 0 → yeni metin + buton kilitli; eski metin **yok**; negatif formatter'a takılıyor; dönüş uyarıyı kaldırıyor; `isUsableAmount` NaN/Infinity eliyor |
| `test/features/chat/chat_accessibility_a4r6_test.dart` | 4 | taraf etiketleri + **metin okunabilir kalıyor** (`excludeSemantics` yok) + kırık ek etiketi |

**Negatif kontrol (A4r3 dersi):** her iki düzeltmenin de testi
**kırmıza** döndürüldü, kırmızı olduğu görüldü, sonra geri alındı.
Regresyon testleri gerçekten işe yarıyor.

### Test kurgusunda ölçülen iki tuzak (ileride faydalı)

- **`tester.runAsync` şart.** `easy_localization` çevirileri asenkron
  asset yüklemesiyle gelir; düz `pumpAndSettle` altında ilk
  `testWidgets` çalışıyor, **sonrakiler tamamen boş ağaç** buluyor
  (ölçüldü: 3 testte 6/0/0 `TextField`).
- **`addTearDown(tester.view.reset)` kullanma.** Teardown sırası
  yüzeyi sonraki teste yanlış boyutla taşıyor.

---

## Doğrulama

```
$ cd flutter_app && flutter analyze
No issues found! (ran in 3.1s)          # lib + test/features

$ cd flutter_app && flutter test test/features
00:11 +77: All tests passed!

$ cd flutter_app && flutter test
00:19 +773: All tests passed!
   ⚠️ NOT: A3'ün commit'lenmemiş `test/core/dead_code_test.dart`
   derlenmiyor (`UpdateGate.downloadVerifyAndOpen` yok). Dosya
   geçici olarak gizlendi ve **773/773 yeşil** ölçüldü; sonra
   yerine konuldu. BANA AİT DEĞİL.

$ node tool/check_i18n.cjs
✓ i18n bütünlüğü temiz: 12 dil, 469 anahtar, 301 Flutter kod anahtarı…
  orphan → ölü: 63/63 · RTL/format uyarısı: 46 (kasıtlı)

$ node tool/check_versions.cjs
✓ Sürüm tutarlı: 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README)
```

**Test sayısı:** 629 (tur başı) → **773**. Düşme yok (+144; +21 benim,
+123 diğer ajanların aynı anda ekledikleri).

## Commit'ler

| Hash | Kapsam | Stat |
|---|---|---|
| `04a0cea` | `fix(flutter-features)` — A2r4'ün 3 zorunlu işi | 18 dosya, +711/−40 |
| `e843e53` | `refactor(flutter-features)` — dosya bölme + erişilebilirlik | 20 dosya, +1855/−1498 |

## Sonraki öneriler (tur 7)

1. ⭐ `favorite_foods` ürün kararı (yukarıda 7. madde).
2. ⭐ Tür bazlı bildirim tercihleri UI'ı (yukarıda 8. madde).
3. `_MessageList` bileşeni — elle indeks hesabı gitmeli.
4. `chat_page_a4r3_test.dart`'in `chat_attachment.dart`'e taşınması (A6).
5. `test/core/dead_code_test.dart` derlemesi (A3'ün alanında).

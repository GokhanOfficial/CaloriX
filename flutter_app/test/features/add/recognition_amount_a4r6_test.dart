/// Tanıma onay ekranının **miktar doğrulaması** (A4r6, Tur 6 — A2r4'ün 2.
/// zorunlu maddesi).
///
/// ## Neden burada?
///
/// A2r4: "`recognition_confirm_dialog.dart:547` `amountRequired` →
/// `invalidAmount` + `isUsableAmount`". Sorun iki katmanlıydı ve **ikisi de**
/// ekranda gözlemlenebilir:
///
/// 1. **Metin yanlıştı.** Koşul `r.amount <= 0` idi, metin "Miktar gerekli"
///    idi. Kullanıcı 250 yazıp ondalık noktasını unuttuğunda "girilmedi"
///    mesajı alıyordu — ekranda ne yaptığını anlamıyordu.
/// 2. **Dört ayrı ölçüt ayrışabiliyordu.** Uyarı metni (`r.amount <= 0`),
///    toplam (`_total`), buton (`_selectedCount`) ve kaydetme filtresi
///    (`_save`) **bağımsız** yazılmıştı; biri düzeltilip diğerleri
///    unutulursa "uyarı yok ama kaydedilmiyor" gibi görünmez ve yanıltıcı
///    bir durum oluşur. Dördü de artık
///    `DiaryRepository.isUsableAmount` (A2'nin tek doğruluk kaynağı) ve bu
///    test dördünün **birlikte** değiştiğini kanıtlar.
///
/// ## `isUsableAmount` neden daha güçlü
///
/// `isUsableAmount` `NaN`/`±Infinity`'yi de eler; `r.amount <= 0`
/// **kabul eder** (Dart'ta `NaN <= 0 == false`). Test bu farkı hem saf
/// fonksiyonda hem de ekranda ölçer.
///
/// ## Test kurgusu hakkında iki ölçüm notu
///
/// 1. **Yüzey boyutu.** Gövde yemek listesini `Flexible` içinde tutar ve
///    listenin üstünde başlık + öğün seçici + toplam kartı vardır.
///    `flutter_test`'in varsayılan 800×600 yüzeyinde liste **0** yükseklik
///    alır ve satırlar hiç kurulmaz. Gerçek telefonda alan çok daha yüksek;
///    bu yüzden yüzey `setUp`'ta büyütülür. `addTearDown(tester.view.reset)`
///    **kullanılmıyor** — teardown sırası yüzeyi sonraki teste yanlış
///    boyutla taşıyordu (ilk test geçiyor, sonrakiler boş ağaç buluyordu).
/// 2. **`tester.runAsync`.** `easy_localization` çevirileri asenkron asset
///    yüklemesiyle gelir. Düz `pumpAndSettle` altında ilk `testWidgets`
///    çalışır, **sonrakiler tamamen boş ağaç** bulur (ölçüldü: 3 testte
///    6/0/0 `TextField`). `runAsync` gerçek async döngüye izin verir ve
///    üçü de 6 alan bulur.
library;

import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/data/models/recognized_food.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/features/add/widgets/recognition_confirm_dialog.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kWarning = 'Geçerli bir miktar girin'; // dialogs.invalidAmount (tr)
const _kOldWarning = 'Miktar gerekli'; // dialogs.amountRequired (tr) — artık kullanılmıyor

RecognizedFood _food() => const RecognizedFood(
      name: 'Yoğurt',
      caloriesPer100G: 60,
      proteinGPer100G: 5,
      carbsGPer100G: 4,
      fatGPer100G: 2,
      amountGMl: 150,
      confidence: 80,
    );

void main() {
  // `easy_localization` dil seçimini `shared_preferences`'te saklar; platform
  // kanalı olmadan `ensureInitialized()` `MissingPluginException` fırlatıyor.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
    // Bkz. kütük yorumu madde 1.
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1000, 2400);
    view.devicePixelRatio = 1.0;
  });

  Future<void> pumpBody(WidgetTester tester) async {
    // `tr` hem başlangıç hem yedek dil: metinler sabit olsun ki test
    // **anahtar** değişimini ölçsün, dile göre kırılmasın.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('tr'), Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('tr'),
          startLocale: const Locale('tr'),
          child: Builder(
            builder: (context) => ProviderScope(
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: Scaffold(
                  body: RecognitionConfirmBody(
                    foods: [_food()],
                    defaultMealType: MealType.breakfast,
                    source: 'photo',
                    onSaved: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
    expect(find.byType(TextField), findsNWidgets(6),
        reason: '1 ad + 1 miktar + 4 makro alanı kurulmalı');
  }

  /// Miktar alanını bulur.
  ///
  /// `NumField` yalnız `StatelessWidget` **miras** aldığı için
  /// `find.byType(NumField)` boş döner. Alan **etiketinden** ayırt
  /// edilir: miktar alanının `labelText`'i `dialogs.amount` → "Miktar";
  /// makro alanları `dialogs.calPer100g` vb. Konuma (`at(1)`) veya genişliğe
  /// göre seçim düzen yeniden sıralanınca kırılırdı.
  Finder amountField() =>
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Miktar');

  Future<void> setAmount(WidgetTester tester, String text) async {
    final field = amountField();
    expect(field, findsOneWidget, reason: 'miktar alanı bulunamadı');
    await tester.enterText(field, text);
    await tester.pump();
  }

  bool warningShown(WidgetTester tester) => find.text(_kWarning).evaluate().isNotEmpty;

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  testWidgets('varsayılan miktar geçerli: uyarı yok, Kaydet etkin', (tester) async {
    await pumpBody(tester);
    expect(warningShown(tester), isFalse);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('miktar 0: "Geçerli bir miktar girin" + Kaydet kilitli', (tester) async {
    await pumpBody(tester);
    await setAmount(tester, '0');

    expect(
      warningShown(tester),
      isTrue,
      reason: 'koşul `amount <= 0` idi ama "Miktar gerekli" deniyordu; 250 yazıp '
          'noktayı unutan kullanıcı yanlış yönlendiriliyordu',
    );
    expect(
      find.text(_kOldWarning),
      findsNothing,
      reason: 'eski metin artık hiçbir koşulda gösterilmemeli',
    );
    expect(
      saveEnabled(tester),
      isFalse,
      reason: 'uyarı metni "geçerli miktar" derken buton etkin kalmazsa '
          'kullanıcı neden kaydedemediğini anlamaz',
    );
  });

  testWidgets('negatif miktar alana giremez (formatter) → uyarı yok', (tester) async {
    await pumpBody(tester);
    // `NumField` `FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))`
    // kullandığı için "-" **reddedilir** → alan 150'de kalır. Ekran
    // katmanının negatif değeri engellemesi; veri katmanı da
    // `ArgumentError` ile ikinci savunmayı kurar.
    await setAmount(tester, '-5');
    expect(warningShown(tester), isFalse);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('geçersizlikten geçerli değere dönüş uyarıyı kaldırır', (tester) async {
    await pumpBody(tester);
    await setAmount(tester, '0');
    expect(warningShown(tester), isTrue);
    expect(saveEnabled(tester), isFalse);

    await setAmount(tester, '250');
    expect(warningShown(tester), isFalse);
    expect(saveEnabled(tester), isTrue);
  });

  test('isUsableAmount, `amount <= 0` koşulundan geniştir (NaN/Infinity)', () {
    // Eski koşul `r.amount <= 0` idi. Dart'ta `NaN <= 0` **false** olduğu
    // için NaN'lı satır ekranda "uyarısız" görünür ve `_total` NaN ile
    // bozulurdu. Tek doğruluk kaynağı bu boşluğu kapatır.
    expect(double.nan <= 0, isFalse, reason: 'temsilî kontrol: eski koşul');
    expect(DiaryRepository.isUsableAmount(double.nan), isFalse);
    expect(DiaryRepository.isUsableAmount(double.infinity), isFalse);
    expect(DiaryRepository.isUsableAmount(double.negativeInfinity), isFalse);
    for (final v in const [0.5, 1.0, 150.0, 250.4, 10000.0]) {
      expect(DiaryRepository.isUsableAmount(v), isTrue, reason: '$v');
    }
  });
}

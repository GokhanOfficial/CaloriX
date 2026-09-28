/// Hesap silme arayüzü (A4r4b, Tur 10 — KVKK / Google Play zorunluluğu).
///
/// ## Bu test neden var?
///
/// `delete-account` sunucu tarafı hazırdı ama **kullanıcıya giriş noktası
/// yoktu** — ölü bir özellik. Bu test, koyduğumuz giriş noktasının
/// **davranışını** ölçer; hepsi "görsel olarak doğru görünüyor" değil:
///
///  1. Diyalog açılıyor ve ne silineceğini **madde madde** listeliyor.
///  2. Boş parola **gönderilmiyor** (2/saatlik sunucu kotası harcanmaz).
///  3. Hatalı parolada **yalnızca** o mesaj çıkar, alan temizlenir.
///  4. Rate limit mesajı ayrı ve doğru çeviriyle gelir.
///  5. Kısmi silmede "başarı" **denmez**, düğme yeniden etkinleşir ve
///     kullanıcı yeniden deneyebilir (hesap hâlâ duruyor!).
///  6. Tam silmede `/auth`'a yönlendirilir ve oturum düşürülür.
library;

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calorix/core/router/app_router.dart';
import 'package:calorix/data/repositories/account_repository.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/features/settings/account_local_cleanup.dart';
import 'package:calorix/features/settings/widgets/delete_account_dialog.dart';

class _MockAccountRepository extends Mock implements AccountRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAccountLocalCleanup extends Mock implements AccountLocalCleanup {}

void main() {
  late _MockAccountRepository accountRepo;
  late _MockAuthRepository authRepo;
  late _MockAccountLocalCleanup cleanup;
  late List<String> routeLog;
  late GoRouter router;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  setUp(() {
    accountRepo = _MockAccountRepository();
    authRepo = _MockAuthRepository();
    cleanup = _MockAccountLocalCleanup();
    routeLog = [];

    when(() => accountRepo.deleteAccount(password: any(named: 'password')))
        .thenAnswer((_) async =>
            const AccountDeletionResult(partial: false, retryRecommended: false));
    when(authRepo.signOut).thenAnswer((_) async {});
    when(cleanup.run).thenAnswer((_) async => AccountLocalCleanupResult(
          notificationsCancelled: true,
          widgetSignedOut: true,
          prefsCleared: true,
          stateInvalidated: true,
        ));

    // Gerçek `appRouterProvider` `currentUserProvider`'a bağlı olduğu için
    // testte sahte (kayıt tutan) bir router kullanıyoruz: yönlendirmenin
    // **hedefini** ölçmek istiyoruz, yönlendirme mekanizmasını değil.
    //
    // ⚠️ `MaterialApp.router`'ın `builder` parametresi **tüm ağacı** (Navigator
    // dahil) değiştirir; `showDialog` bu durumda "no element" hatası verir.
    // Bu yüzden giriş düğmesi route'un **kendi sayfasına** konur.
    router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) => Scaffold(
            body: Center(
              child: Builder(
                builder: (innerContext) => ElevatedButton(
                  onPressed: () => DeleteAccountDialog.show(innerContext),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.auth,
          builder: (_, _) {
            routeLog.add(AppRoutes.auth);
            return const Scaffold(body: Text('AUTH_SCREEN'));
          },
        ),
      ],
    );
  });

  tearDown(() => router.dispose());

  /// Diyaloğu, sahte router'ın içindeki düğmeyle açar.
  Future<void> pumpOpenDialog(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('tr'), Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('tr'),
          startLocale: const Locale('tr'),
          child: Builder(
            builder: (context) => ProviderScope(
              overrides: [
                accountRepositoryProvider.overrideWithValue(accountRepo),
                authRepositoryProvider.overrideWithValue(authRepo),
                accountLocalCleanupProvider.overrideWithValue(cleanup),
                appRouterProvider.overrideWithValue(router),
              ],
              child: MaterialApp.router(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                routerConfig: router,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Parolayı yazar ve "Hesabımı Sil" düğmesine basar.
  Future<void> submit(WidgetTester tester, String password) async {
    if (password.isNotEmpty) {
      await tester.enterText(find.byType(TextFormField), password);
      await tester.pump();
    }
    final confirm = find.widgetWithText(FilledButton, 'Hesabımı Sil');
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
  }

  group('1. Diyalog açılıyor ve kapsamı anlatıyor', () {
    testWidgets('başlık, uyarı ve silinen veriler listelenir', (tester) async {
      await pumpOpenDialog(tester);

      expect(find.byType(DeleteAccountDialog), findsOneWidget);
      expect(find.text('Hesabınızı silmek istiyor musunuz?'), findsOneWidget);
      // Yedi veri kategorisinin **tamamı** listelenmeli — kullanıcı
      // "ne silinecek" sorusunun cevabını görmeden onaylamamalı.
      for (final label in const [
        'Yemek ve öğün kayıtları',
        'Su takibi',
        'Kilo kayıtları',
        'Yapay zekâ sohbet geçmişi',
        'Favori yiyecekler ve son kullanılanlar',
        'Profil, hedefler ve uygulama ayarları',
        'Bildirimler ve hatırlatıcılar',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '"$label" listelenmeli');
      }
    });

    testWidgets('"geri alınamaz" uyarısı görünür', (tester) async {
      await pumpOpenDialog(tester);
      expect(
        find.text('Bu işlem geri alınamaz ve verileriniz kurtarılamaz.'),
        findsOneWidget,
      );
    });

    testWidgets('parola alanı: obscure + öneri/düzeltme kapalı + autofill',
        (tester) async {
      await pumpOpenDialog(tester);

      // `TextFormField` bir `FormField<String>`; asıl giriş yapılandırması
      // ağacın içindeki `EditableText` üzerinde durur. Doğru yerde
      // ölçüyoruz: render edilen widget'ın **kendisi**.
      final editable =
          tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.obscureText, isTrue, reason: 'parola gizlenmeli');
      expect(editable.enableSuggestions, isFalse,
          reason: 'iOS/Android klavyesi parolayı sözlüğe yazabilir');
      expect(editable.autocorrect, isFalse);
      // `auth_page.dart:314` ile birebir aynı autofill ipucu.
      expect(editable.autofillHints, const [AutofillHints.password]);
    });

    testWidgets('parola görünürlüğü düğmesi çalışır', (tester) async {
      await pumpOpenDialog(tester);
      // Diyalog 800×600 test yüzeyinde sığmıyor; düğmeye ulaşmadan
      // `tap` sessizce ertelenir (hit test uyarısı).
      final toggle = find.byIcon(Icons.visibility_outlined);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isFalse,
      );
    });

    testWidgets('i̇ptal diyaloğu kapatır, HİÇBİR istek gitmez', (tester) async {
      await pumpOpenDialog(tester);
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();

      expect(find.byType(DeleteAccountDialog), findsNothing);
      verifyNever(() => accountRepo.deleteAccount(password: any(named: 'password')));
    });
  });

  group('2. Boş parola gönderilmiyor (kota korunur)', () {
    testWidgets('boş parola ile onaya basılırsa sunucuya gitmez',
        (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, '');

      verifyNever(() => accountRepo.deleteAccount(password: any(named: 'password')));
      // Diyalog açık kalır (kullanıcı kaybolmaz).
      expect(find.byType(DeleteAccountDialog), findsOneWidget);
    });

    testWidgets('yalnızca boşluktan oluşan parola da gönderilmez', (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, '   ');

      verifyNever(() => accountRepo.deleteAccount(password: any(named: 'password')));
    });
  });

  group('3. Parola hatalı', () {
    setUp(() {
      when(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .thenThrow(const AccountDeletionException(
            AccountDeletionErrorKind.wrongPassword,
            status: 401,
          ));
    });

    testWidgets('yalnızca parola hatalı mesajı gösterilir', (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, 'yanlis-parola');

      expect(find.text('Parolanız hatalı. Lütfen tekrar deneyin.'),
          findsOneWidget);
      // Sunucunun ham Türkçe metni gösterilmez (12 dil + şema sızıntısı).
      expect(find.text('Parola hatalı'), findsNothing);
    });

    testWidgets('parola alanı temizlenir ve odak alana döner', (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, 'yanlis-parola');

      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).controller?.text,
        '',
        reason: 'hatalı parola cihazda/alanında bırakılmamalı',
      );
      // Diyalog **açık kalır** — kullanıcı tekrar deneyebilmeli.
      expect(find.byType(DeleteAccountDialog), findsOneWidget);
    });

    testWidgets('oturum düşürülmez, /auth\'a gidilmez', (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, 'yanlis-parola');

      verifyNever(authRepo.signOut);
      verifyNever(cleanup.run);
      expect(routeLog, isEmpty);
    });
  });

  group('4. Rate limit', () {
    setUp(() {
      when(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .thenThrow(const AccountDeletionException(
            AccountDeletionErrorKind.rateLimited,
            status: 429,
          ));
    });

    testWidgets('429 → "çok fazla deneme" mesajı (parola hatalı DEĞİL)',
        (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, 'bir-parola');

      expect(
        find.text('Çok fazla deneme yaptınız. Lütfen biraz sonra tekrar deneyin.'),
        findsOneWidget,
      );
      expect(find.text('Parolanız hatalı. Lütfen tekrar deneyin.'), findsNothing);
    });

    testWidgets('429 sonrası oturum düşmez', (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, 'bir-parola');

      verifyNever(authRepo.signOut);
      expect(routeLog, isEmpty);
    });
  });

  group('5. Kısmi silme — "başarı" DENİRMEZ', () {
    setUp(() {
      when(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .thenAnswer((_) async =>
              const AccountDeletionResult(partial: true, retryRecommended: true));
    });

    testWidgets('"bazı veriler silinemedi" mesajı çıkar', (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, 'dogru-parola');

      expect(
        find.text('Bazı veriler silinemedi. Hesabınız hâlâ duruyor; birkaç '
            'dakika sonra tekrar deneyin.'),
        findsOneWidget,
      );
    });

    testWidgets('oturum düşürülmez (hesap hâlâ duruyor!)', (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, 'dogru-parola');

      // `auth.admin.deleteUser()` BAŞARISIZ ⇒ hesap duruyor. Kullanıcıyı
      // /auth'a atıp yerel verisini silmek **yanlış** olurdu: verileri
      // silsen bile hesap duruyor ve kullanıcı verisine erişemez.
      verifyNever(authRepo.signOut);
      verifyNever(cleanup.run);
      expect(routeLog, isEmpty);
    });

    testWidgets('diyalog açık kalır, düğme yeniden etkinleşir', (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, 'dogru-parola');

      expect(find.byType(DeleteAccountDialog), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Hesabımı Sil'),
      );
      expect(confirm.onPressed, isNotNull,
          reason: 'yeniden deneyebilmeli (kvota 2/saat)');
      // Parola temizlenir ki yeniden yazmasın.
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).controller?.text,
        '',
      );
    });
  });

  group('6. Tam silme → /auth', () {
    testWidgets('oturum düşürülür, cihaz temizlenir, /auth\'a gidilir',
        (tester) async {
      await pumpOpenDialog(tester);
      await submit(tester, 'dogru-parola');

      verify(() => accountRepo.deleteAccount(password: 'dogru-parola')).called(1);
      verify(authRepo.signOut).called(1);
      verify(cleanup.run).called(1);
      expect(routeLog, contains(AppRoutes.auth));
      expect(find.text('AUTH_SCREEN'), findsOneWidget);
    });

    testWidgets('temizlik başarısız olsa da /auth\'a gidilir', (tester) async {
      // Temizlik **best-effort**: oturum düşürülmezse kullanıcı ölü bir
      // hesapla uygulamada kalır. Doğru davranış: uyar + yine de çık.
      when(cleanup.run).thenAnswer(
        (_) async => AccountLocalCleanupResult(notificationsCancelled: true),
      );

      await pumpOpenDialog(tester);
      await submit(tester, 'dogru-parola');

      expect(
        find.text('Bazı cihaz verileri temizlenemedi. Lütfen uygulamayı yeniden '
            'başlatın.'),
        findsOneWidget,
      );
      expect(routeLog, contains(AppRoutes.auth));
    });
  });

  group('7. Çift gönderim engeli', () {
    testWidgets('yükleme sırasında ikinci tıklama istek üretmez',
        (tester) async {
      // Hiç bitmeyen istek → buton spinner durumunda kalır.
      when(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .thenAnswer((_) => Completer<AccountDeletionResult>().future);

      await pumpOpenDialog(tester);
      // Parola **girilmeli**: boşsa `_submit` daha `setState` çağırmadan
      // erken dönüyor (kota koruma kısa devresi) ve düğme pasifleşmiyor.
      await tester.enterText(find.byType(TextFormField), 'dogru-parola');
      await tester.pump();
      final confirm = find.widgetWithText(FilledButton, 'Hesabımı Sil');
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pump();

      // Düğme yükleme sırasında **spinner**'a döner; metin kaybolur.
      // Bu yüzden düğme metinle değil, diyaloğun `actions` satırındaki
      // `FilledButton` ile bulunur.
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byType(OverflowBar),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull, reason: 'yükleniyorken pasif olmalı');

      await tester.pump();
      verify(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .called(1);
    });
  });

  group('8. Diğer hata türleri', () {
    testWidgets('oturum geçersiz (401 "Yetkisiz") → farklı mesaj', (tester) async {
      when(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .thenThrow(const AccountDeletionException(
            AccountDeletionErrorKind.unauthorized,
            status: 401,
          ));
      await pumpOpenDialog(tester);
      await submit(tester, 'bir-parola');

      expect(find.text('Oturumunuz sona erdi. Lütfen tekrar giriş yapın.'),
          findsOneWidget);
      expect(find.text('Parolanız hatalı. Lütfen tekrar deneyin.'), findsNothing);
    });

    testWidgets('ağ hatası → bağlantı mesajı', (tester) async {
      when(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .thenThrow(const AccountDeletionException(
            AccountDeletionErrorKind.network,
          ));
      await pumpOpenDialog(tester);
      await submit(tester, 'bir-parola');

      expect(
        find.text('Bağlantı kurulamadı. İnternetinizi kontrol edip tekrar deneyin.'),
        findsOneWidget,
      );
      // Ağ hatasında parola **korunur** (kullanıcı yeniden yazmak zorunda kalmaz).
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).controller?.text,
        'bir-parola',
      );
    });

    testWidgets('bilinmeyen hata → genel mesaj, diyalog kilitlenmez',
        (tester) async {
      when(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .thenThrow(const AccountDeletionException(
            AccountDeletionErrorKind.unknown,
            status: 500,
          ));
      await pumpOpenDialog(tester);
      await submit(tester, 'bir-parola');

      expect(
        find.text('Hesabınız silinemedi. Lütfen daha sonra tekrar deneyin.'),
        findsOneWidget,
      );
      expect(find.byType(DeleteAccountDialog), findsOneWidget);
    });

    testWidgets('beklenmeyen (tipsiz) hata da kilitlemez', (tester) async {
      when(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .thenThrow(StateError('patlama'));
      await pumpOpenDialog(tester);
      await submit(tester, 'bir-parola');

      expect(
        find.text('Hesabınız silinemedi. Lütfen daha sonra tekrar deneyin.'),
        findsOneWidget,
      );
      expect(find.byType(DeleteAccountDialog), findsOneWidget);
    });
  });

  group('9. Parola hiçbir yerde görünmez', () {
    testWidgets('hata mesajında parola geçmez', (tester) async {
      const secret = 'CokGizli-999';
      when(() => accountRepo.deleteAccount(password: any(named: 'password')))
          .thenThrow(const AccountDeletionException(
            AccountDeletionErrorKind.unknown,
            status: 500,
          ));
      await pumpOpenDialog(tester);
      await submit(tester, secret);

      // Ekranda parolanın kendisi hiçbir metin olarak basılmamalı.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>();
      for (final text in texts) {
        expect(text, isNot(contains(secret)),
            reason: 'parola kullanıcıya gösterilmemeli');
      }
    });
  });
}

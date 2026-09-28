/// Sohbet ekranının **erişilebilirlik** düzeltmesi (A4r6, Tur 6, görev 5).
///
/// ## Bulgu
///
/// `MessageBubble` konuşan tarafı yalnız **hizalama** (sağ/sol) ve renkle
/// anlatıyordu. Görsel olarak netti ama ekran okuyucu (TalkBack/VoiceOver)
/// bu ayrımı **algılayamıyor** — kullanıcı "kimin yazdığı" bilgisini
/// kaybediyor. WCAG 1.3.1 (Anlam ve İşlev) bunu ihlal eder: konuşma
/// içeriği taraf kimliği taşır ama taraf bilgisi yalnız görsel bir
/// kanal üzerinden iletiliyor.
///
/// Aynı sınıf eksik olan ikinci yer: `AttachmentImage` yüklenemeyen
/// kırık görseli `broken_image_outlined` ikonuyla gösteriyordu; ikon
/// dekoratif olduğu için ekran okuyucuya "görsel yüklenemedi" bilgisi
/// hiç ulaşmıyordu.
///
/// ## Çözüm
///
/// `Semantics(label:)` — metin okunabilirliği korunur (`excludeSemantics`
/// **yok**), yalnızca taraf/başlık bilgisi eklenir.
library;

import 'package:calorix/data/models/chat_message.dart';
import 'package:calorix/features/chat/chat_widgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  Widget host(Widget child) => EasyLocalization(
        supportedLocales: const [Locale('tr')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr'),
        startLocale: const Locale('tr'),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(body: child),
          ),
        ),
      );

  /// Balonun semantik ağacını düz metne çevirir (ekran okuyucunun
  /// duyacağı şeyi taklit eder).
  ///
  /// `getSemantics` yalnızca `handleCreateSemantics` açıldığında etiket
  /// üretir; `tester.ensureSemantics()` olmadan `label` **boş** döner
  /// (ölçüldü — ilk yazımda test sessizce yanlış negatif veriyordu).
  String semanticsText(WidgetTester tester) {
    final handle = tester.ensureSemantics();
    try {
      // Asistan balonunda **iki** `Semantics` düğümü olur: konuşan tarafı
      // etiketi (bizim eklediğimiz) ve `Image.network`/ek kutusu gibi
      // alt bileşenlerin kendi düğümleri. Aranan etiket **en dıştaki**
      // düğümdedir; `Semantics(label:)` sarmalayıcısı ilk sırada gelir.
      return tester
          .getSemantics(
            find
                .descendant(
                  of: find.byType(MessageBubble),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .label;
    } finally {
      // `SemanticsHandle` test sonunda açık kalırsa test **hata** fırlatır
      // (ölçüldü) — `try/finally` zorunlu.
      handle.dispose();
    }
  }

  testWidgets('kullanıcı mesajı "Siz" olarak etiketlenir', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(host(
        const MessageBubble(
          message: ChatMessage(
            id: 'm1',
            threadId: 't1',
            userId: 'u1',
            role: 'user',
            content: 'Merhaba',
            createdAt: '2026-09-28T10:00:00Z',
          ),
        ),
      ));
      await tester.pumpAndSettle();
    });

    expect(
      semanticsText(tester),
      contains('Siz'),
      reason: 'ekran okuyucu konuşan tarafı öğrenemiyordu (yalnız hizalama)',
    );
  });

  testWidgets('asistan mesajı "CaloriX AI" olarak etiketlenir', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(host(
        const MessageBubble(
          message: ChatMessage(
            id: 'm2',
            threadId: 't1',
            userId: 'ai',
            role: 'assistant',
            content: 'Merhaba!',
            createdAt: '2026-09-28T10:00:00Z',
          ),
        ),
      ));
      await tester.pumpAndSettle();
    });

    expect(semanticsText(tester), contains('CaloriX AI'));
  });

  testWidgets('mesaj metni okunabilir kalır (excludeSemantics yok)', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(host(
        const MessageBubble(
          message: ChatMessage(
            id: 'm3',
            threadId: 't1',
            userId: 'u1',
            role: 'user',
            content: 'Kaç kalori aldım',
            createdAt: '2026-09-28T10:00:00Z',
          ),
        ),
      ));
      await tester.pumpAndSettle();
    });

    // `excludeSemantics: true` olsaydı mesaj gövdesi ekran okuyucuya
    // **hiç** ulaşmazdı — taraf etiketi eklemek içeriği gizlememeli.
    expect(semanticsText(tester), contains('Kaç kalori aldım'));
  });

  testWidgets('kırık ek etiketi "yüklenemedi" der', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(host(
        const AttachmentImage(
          attachment: ChatAttachment(
            path: 'u1/t1/x.png',
            name: 'x.png',
            type: 'image/png',
            size: 1024,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    });

    final handle = tester.ensureSemantics();
    final label = tester.getSemantics(find.byType(AttachmentImage)).label;
    handle.dispose();
    expect(
      label,
      contains('yüklenemedi'),
      reason: 'kırık görsel yalnız dekoratif ikondu; kullanıcı neden '
          'görsel görmediğini anlayamıyordu',
    );
  });
}

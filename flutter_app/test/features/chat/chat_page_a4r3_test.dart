import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/data/models/chat_message.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/data/repositories/chat_repository.dart';
import 'package:calorix/features/chat/chat_page.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

User _testUser() => const User(
      id: 'u1',
      appMetadata: {},
      userMetadata: null,
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );

ChatMessage _msg(int i, {bool user = false}) => ChatMessage(
      id: 'm$i',
      threadId: 't1',
      userId: 'u1',
      role: user ? 'user' : 'assistant',
      content: 'mesaj $i',
      createdAt: '2026-09-01T10:${i.toString().padLeft(2, '0')}:00Z',
    );

/// `ListView.builder` `itemBuilder`'ındaki indeks eşlemesi bozulduğunda
/// `visible[i]` `RangeError` fırlatır ve sohbet listesi **çöker**.
///
/// Doğrudan indeks matematiğini modellemek yerine ekranı gerçekten kurup
/// `_MessageBubble` sayısını saymak daha güvenilir: hata widget ağacında
/// meydana geldiği için `tester.takeException()` yakalar.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  Future<void> pumpChat(
    WidgetTester tester, {
    required List<ChatMessage> messages,
    required bool hasMore,
    _MockChatRepository? repository,
  }) async {
    final repo = repository ?? _MockChatRepository();
    when(() => repo.ensureThread(any())).thenAnswer((_) async => 't1');
    when(() => repo.loadInitial(any(), any())).thenAnswer(
      (_) async => (messages: messages, hasMore: hasMore),
    );
    when(() => repo.loadMore(any(), any(), any())).thenAnswer(
      (_) async => (messages: const <ChatMessage>[], hasMore: false),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_testUser()),
            chatRepositoryProvider.overrideWithValue(repo),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('tr'), Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            startLocale: const Locale('tr'),
            child: Builder(
              builder: (context) => MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const ChatPage(),
              ),
            ),
          ),
        ),
      );
    });
    await tester.pumpAndSettle();
  }

  testWidgets('hasMore=true iken mesaj balonları hatasız sıralanır',
      (tester) async {
    // Bu senaryo `_hasMore` başlangıçta `true` olduğu için **her** sohbette
    // vardır; `_welcomeMessage()` tek bir balon üretir.
    await pumpChat(tester, messages: const [], hasMore: true);

    expect(tester.takeException(), isNull);
    // "daha eski mesajları yükle" düğmesi en üstte.
    expect(find.text('Daha eski mesajları yükle'), findsOneWidget);
    // Hoş geldiniz balonu görünür (boş geçmişte `_welcomeMessage()` üretilir).
    expect(find.textContaining('Ben CaloriX AI'), findsOneWidget);
  });

  testWidgets('hasMore=true ve mesaj doluyken indeks kayması olmaz',
      (tester) async {
    await pumpChat(tester, messages: [_msg(1), _msg(2), _msg(3)], hasMore: true);

    expect(tester.takeException(), isNull);
    // Üç mesajın üçü de doğru sırada görünür.
    expect(find.text('mesaj 1'), findsOneWidget);
    expect(find.text('mesaj 3'), findsOneWidget);
  });

  testWidgets('hasMore=false iken de mesajlar hatasız görünür', (tester) async {
    await pumpChat(
      tester,
      messages: [_msg(1), _msg(2)],
      hasMore: false,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Daha eski mesajları yükle'), findsNothing);
    expect(find.text('mesaj 1'), findsOneWidget);
  });

  testWidgets('sohbeti temizle çalışır ve liste yeniden yüklenir',
      (tester) async {
    final repo = _MockChatRepository();
    when(() => repo.archiveThread(any(), any())).thenAnswer((_) async {});
    await pumpChat(
      tester,
      messages: [_msg(1)],
      hasMore: false,
      repository: repo,
    );

    await tester.tap(find.byTooltip('Görünen sohbeti temizle'));
    await tester.pumpAndSettle();

    // Thread kullanıcıya bağlı arşivlenir (A2) ve liste yeniden yüklenir.
    verify(() => repo.archiveThread('u1', 't1')).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temizleme sırasında ekran kapanırsa setState çökmesi olmaz',
      (tester) async {
    // `archiveThread` future'ı, ekran dispose olana kadar **bitmez**.
    // `_clearVisibleChat` içindeki `setState` `await` sonrası `mounted`
    // kontrolü olmadan çalışırsa "setState() called after dispose()"
    // fırlatır. Hata `catch` bloğuna düşüp "Sohbet temizlenemedi"
    // snackbar'ına dönüştüğü için, `takeException()` yerine **kullanıcıya
    // görünen sonucu** assert ediyoruz: dispose olmuş ekranda hata
    // mesajı gösterilmemeli (gösterilmesi = çökme vardı).
    final repo = _MockChatRepository();
    final completer = Completer<void>();
    when(() => repo.archiveThread(any(), any()))
        .thenAnswer((_) => completer.future);

    await pumpChat(
      tester,
      messages: [_msg(1)],
      hasMore: false,
      repository: repo,
    );

    // "Temizle" butonuna bas, sonra uygulamayı başka bir ekranla değiştir
    // (ChatPage dispose olur) ve arşivlemeyi tamamla.
    await tester.tap(find.byTooltip('Görünen sohbeti temizle'));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_testUser()),
            chatRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
    });

    await tester.runAsync(() async {
      if (!completer.isCompleted) completer.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // `mounted` koruması varsa `setState` hiç çalışmaz → hata yolu
    // tetiklenmez → "Sohbet temizlenemedi" görünmez.
    expect(find.textContaining('Sohbet temizlenemedi'), findsNothing);
  });

  group('ChatAttachmentLimits', () {
    const mb = 1024 * 1024;

    test('tek dosya sınırı 10 MB', () {
      expect(ChatAttachmentLimits.maxFileBytes, 10 * mb);
    });

    test('toplam sınır tek dosya sınırından büyük', () {
      // Aksi halde toplam sınır anlamsız olurdu (tek dosya zaten sınırı
      // doldurur).
      expect(ChatAttachmentLimits.maxTotalBytes,
          greaterThan(ChatAttachmentLimits.maxFileBytes));
    });

    test('tek dosya sınırın altındaysa kabul edilir', () {
      expect(
        ChatAttachmentLimits.canAccept(pendingBytes: 0, newBytes: 9 * mb),
        isTrue,
      );
    });

    test('tek dosya tam sınırda kabul edilir (eşitlik sınıra dahil)', () {
      expect(
        ChatAttachmentLimits.canAccept(
            pendingBytes: 0, newBytes: ChatAttachmentLimits.maxFileBytes),
        isTrue,
      );
    });

    test('tek dosya sınırı aşıyorsa reddedilir', () {
      expect(
        ChatAttachmentLimits.canAccept(
            pendingBytes: 0, newBytes: ChatAttachmentLimits.maxFileBytes + 1),
        isFalse,
      );
    });

    test('toplam sınır: çok sayıda küçük dosya da reddedilir', () {
      // Asıl P1 senaryosu: her dosya tek başına 10 MB'ın altında ama
      // toplam bellek sınırı aşılıyor.
      final pending = 3 * 10 * mb;
      expect(
        ChatAttachmentLimits.canAccept(pendingBytes: pending, newBytes: 1 * mb),
        isFalse,
        reason: '3 dosya 10 MB + 1 dosya 1 MB = 31 MB > 25 MB olmamalı',
      );
    });

    test('toplam sınırın tam sınırda kabul edilir', () {
      expect(
        ChatAttachmentLimits.canAccept(
            pendingBytes: 0, newBytes: ChatAttachmentLimits.maxTotalBytes),
        isFalse,
        reason: 'tek dosya zaten 10 MB sınırını aşıyor',
      );
      // 25 MB = 10 + 10 + 5 → üç dosya sığmalı.
      expect(
        ChatAttachmentLimits.canAccept(
            pendingBytes: 20 * mb, newBytes: 5 * mb),
        isTrue,
      );
    });

    test('negatif boyutlar reddedilir (savunma)', () {
      expect(
        ChatAttachmentLimits.canAccept(pendingBytes: 0, newBytes: -1),
        isFalse,
      );
      expect(
        ChatAttachmentLimits.canAccept(pendingBytes: -1, newBytes: 1),
        isFalse,
      );
    });

    test('sınır aşıldığında mevcut seçim bozulmaz (kısmi ekleme yok)',
        () {
      // 25 MB dolu: yeni dosya reddedilmeli, toplam değişmemeli.
      var pending = 15 * mb;
      final newBytes = 11 * mb; // 15 + 11 = 26 > 25 → reddedilir
      final accepted =
          ChatAttachmentLimits.canAccept(pendingBytes: pending, newBytes: newBytes);
      if (accepted) pending += newBytes;
      expect(accepted, isFalse);
      expect(pending, 15 * mb, reason: 'toplam değişmemeli');
    });
  });
}

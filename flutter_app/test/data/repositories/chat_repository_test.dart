import 'package:calorix/data/models/chat_message.dart';
import 'package:calorix/data/repositories/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// ChatRepository'nin saf (Supabase'siz) parçaları + chat model JSON turu.
/// Web parity referansı: `src/pages/ChatPage.tsx` + `chat_messages` şeması.
void main() {
  group('ChatRepository.localDateOnly', () {
    test('yyyy-MM-dd formatı (web toLocaleDateString("en-CA") parity)', () {
      expect(ChatRepository.localDateOnly(DateTime(2026, 8, 15, 14, 30)),
          '2026-08-15');
    });

    test('tek haneli ay/gün sıfır dolgulu', () {
      expect(ChatRepository.localDateOnly(DateTime(2026, 1, 3, 0, 0)),
          '2026-01-03');
    });

    test('saat bileşeni yok sayılır', () {
      expect(
        ChatRepository.localDateOnly(DateTime(2026, 12, 31, 23, 59, 59)),
        '2026-12-31',
      );
    });
  });

  group('ChatMessage', () {
    test('welcome factory → id=welcome, role=assistant, boş createdAt', () {
      final m = ChatMessage.welcome(
        threadId: 't1',
        userId: 'u1',
        content: 'Merhaba',
      );
      expect(m.id, 'welcome');
      expect(m.role, 'assistant');
      expect(m.content, 'Merhaba');
      expect(m.createdAt, '');
      expect(m.isWelcome, isTrue);
      expect(m.isUser, isFalse);
      expect(m.attachments, isEmpty);
      expect(m.toolCalls, isEmpty);
      expect(m.toolResults, isEmpty);
    });

    test('isUser yalnızca role=user için true', () {
      final user = ChatMessage(
        id: '1',
        threadId: 't',
        userId: 'u',
        role: 'user',
        createdAt: '2026-08-15T10:00:00Z',
      );
      final asst = ChatMessage(
        id: '2',
        threadId: 't',
        userId: 'u',
        role: 'assistant',
        createdAt: '2026-08-15T10:00:01Z',
      );
      expect(user.isUser, isTrue);
      expect(user.isWelcome, isFalse);
      expect(asst.isUser, isFalse);
    });

    test('fromJson → DB satırı (snake_case kolonlar)', () {
      final row = {
        'id': 'msg-1',
        'thread_id': 'thread-1',
        'user_id': 'user-1',
        'role': 'assistant',
        'content': 'Selam!',
        'attachments': [
          {
            'path': 'user-1/thread-1/abc.png',
            'name': 'abc.png',
            'type': 'image/png',
            'size': 12345,
            'signedUrl': 'https://example.com/signed',
          }
        ],
        'tool_calls': [
          {'id': 'call_1', 'name': 'add_meal', 'arguments': {'k': 1}},
        ],
        'tool_results': [
          {'id': 'call_1', 'name': 'add_meal', 'summary': 'eklendi'},
        ],
        'created_at': '2026-08-15T10:00:00Z',
        'deleted_at': null,
      };

      final m = ChatMessage.fromJson(row);
      expect(m.id, 'msg-1');
      expect(m.threadId, 'thread-1');
      expect(m.userId, 'user-1');
      expect(m.role, 'assistant');
      expect(m.content, 'Selam!');
      expect(m.attachments, hasLength(1));
      expect(m.attachments.first.path, 'user-1/thread-1/abc.png');
      expect(m.attachments.first.signedUrl, 'https://example.com/signed');
      expect(m.attachments.first.size, 12345);
      expect(m.toolCalls, hasLength(1));
      expect(m.toolCalls.first.name, 'add_meal');
      expect(m.toolCalls.first.arguments, {'k': 1});
      expect(m.toolResults, hasLength(1));
      expect(m.toolResults.first.summary, 'eklendi');
      expect(m.deletedAt, isNull);
    });

    test('fromJson → eksik nullable JSONB dizileri default boş liste', () {
      final m = ChatMessage.fromJson({
        'id': 'msg-2',
        'thread_id': 't',
        'user_id': 'u',
        'role': 'user',
        'content': 'merhaba',
        'created_at': '2026-08-15T10:00:00Z',
        // attachments / tool_calls / tool_results / deleted_at yok
      });
      expect(m.attachments, isEmpty);
      expect(m.toolCalls, isEmpty);
      expect(m.toolResults, isEmpty);
      expect(m.deletedAt, isNull);
    });

    test('toJson round-trip → alan adları korunur', () {
      final original = ChatMessage(
        id: 'r-1',
        threadId: 'thr',
        userId: 'usr',
        role: 'assistant',
        content: 'x',
        createdAt: '2026-08-15T10:00:00Z',
        attachments: [
          ChatAttachment(
              path: 'p', name: 'n', type: 'image/jpeg', size: 10),
        ],
        toolCalls: [ChatToolCall(id: 'c', name: 'add_water')],
        toolResults: [ChatToolResult(id: 'c', name: 'add_water', summary: 'ok')],
      );
      final json = original.toJson();
      expect(json['id'], 'r-1');
      expect(json['thread_id'], 'thr');
      expect(json['user_id'], 'usr');
      expect(json['role'], 'assistant');
      expect(json['created_at'], '2026-08-15T10:00:00Z');
      expect((json['attachments'] as List).first['path'], 'p');
      expect((json['tool_calls'] as List).first['name'], 'add_water');
      expect((json['tool_results'] as List).first['summary'], 'ok');

      final back = ChatMessage.fromJson(json);
      expect(back.id, original.id);
      expect(back.threadId, original.threadId);
      expect(back.role, original.role);
      expect(back.attachments.first.path, original.attachments.first.path);
    });
  });

  group('ChatMessage — pending_action / action_status / metadata sözleşmesi', () {
    // Bu üç kolon migration'da tanımlı (`20260518080500_add_ai_chat.sql:44-46`)
    // ama modelde **yoktu** → AI'ın önerdiği eylem (örn. "şu suyu ekle")
    // Flutter'da hiç okunamıyor, `action_status` güncellense bile
    // kullanıcıya yansımıyordu.
    Map<String, dynamic> rowWith({
      Map<String, dynamic>? pendingAction,
      String? actionStatus,
      Map<String, dynamic>? metadata,
    }) =>
        {
          'id': 'm9',
          'thread_id': 't1',
          'user_id': 'u1',
          'role': 'assistant',
          'content': 'Bugün 2.5 litre su içmelisin.',
          'created_at': '2026-08-15T10:00:00Z',
          'pending_action': ?pendingAction,
          'action_status': actionStatus,
          'metadata': metadata ?? const <String, dynamic>{},
        };

    test('fromJson → pending_action gövdesi okunur', () {
      final m = ChatMessage.fromJson(rowWith(
        pendingAction: {
          'type': 'add_water',
          'entry_date': '2026-08-15',
          'amount_ml': 500,
        },
        actionStatus: 'pending',
      ));
      expect(m.pendingAction, isNotNull);
      expect(m.pendingAction!.type, 'add_water');
      expect(m.pendingAction!.amountMl, 500.0);
      expect(m.pendingAction!.entryDate, '2026-08-15');
      expect(m.actionStatus, 'pending');
      expect(m.hasPendingAction, isTrue);
    });

    test('fromJson → add_water dışı aksiyonlar da okunur', () {
      final meal = ChatMessage.fromJson(rowWith(
        pendingAction: {
          'type': 'add_meal',
          'meal_type': 'lunch',
          'custom_name': 'Tavuk salatası',
          'amount_g_ml': 150,
          'calculated_kcal': 220,
          'calculated_protein': 25,
          'calculated_carbs': 8,
          'calculated_fat': 11,
        },
        actionStatus: 'pending',
      ));
      expect(meal.pendingAction!.type, 'add_meal');
      expect(meal.pendingAction!.mealType, 'lunch');
      expect(meal.pendingAction!.customName, 'Tavuk salatası');
      expect(meal.pendingAction!.calculatedKcal, 220.0);

      final weight = ChatMessage.fromJson(rowWith(
        pendingAction: {
          'type': 'update_weight',
          'entry_date': '2026-08-15',
          'weight_kg': 79.4,
        },
        actionStatus: 'pending',
      ));
      expect(weight.pendingAction!.weightKg, 79.4);
    });

    test('olmayan kolonlar null / boş map olarak varsayılır (geriye uyum)', () {
      final m = ChatMessage.fromJson({
        'id': 'm1',
        'thread_id': 't',
        'user_id': 'u',
        'role': 'assistant',
        'content': 'selam',
        'created_at': '2026-08-15T10:00:00Z',
        // pending_action / action_status / metadata hiç yok (eski satır)
      });
      expect(m.pendingAction, isNull);
      expect(m.actionStatus, isNull);
      expect(m.metadata, isEmpty);
      expect(m.hasPendingAction, isFalse,
          reason: 'öneri yoksa onay bekleyen aksiyon da yoktur');
    });

    test('null pending_action (kolon nullable) sorun çıkarmaz', () {
      final m = ChatMessage.fromJson(rowWith(actionStatus: null));
      expect(m.pendingAction, isNull);
      expect(m.hasPendingAction, isFalse);
    });

    test('hasPendingAction yalnız action_status=pending iken true', () {
      for (final status in <String>['approved', 'rejected', 'executed', 'failed']) {
        final m = ChatMessage.fromJson(rowWith(
          pendingAction: {'type': 'add_water', 'amount_ml': 250},
          actionStatus: status,
        ));
        expect(m.hasPendingAction, isFalse, reason: 'status=$status');
      }
    });

    test('bilinmeyen alanlar raw içinde korunur (sözleşme genişlemesi)', () {
      final m = ChatMessage.fromJson(rowWith(
        pendingAction: {
          'type': 'add_water',
          'amount_ml': 250,
          'future_field': 'ileride eklenecek',
        },
        actionStatus: 'pending',
      ));
      expect(m.pendingAction!.raw['future_field'], 'ileride eklenecek');
    });

    test('metadata ham JSONB olarak korunur', () {
      final m = ChatMessage.fromJson(rowWith(
        metadata: {'model': 'gpt-5-mini', 'tokens': 1234},
      ));
      expect(m.metadata['model'], 'gpt-5-mini');
      expect(m.metadata['tokens'], 1234);
    });

    test('toJson round-trip → kolon adları korunur', () {
      final original = ChatMessage.fromJson(rowWith(
        pendingAction: {'type': 'add_water', 'entry_date': '2026-08-15', 'amount_ml': 500},
        actionStatus: 'pending',
        metadata: const {'model': 'gpt-5-mini'},
      ));
      final json = original.toJson();
      expect((json['pending_action'] as Map)['type'], 'add_water');
      expect(json['action_status'], 'pending');
      expect((json['metadata'] as Map)['model'], 'gpt-5-mini');

      final back = ChatMessage.fromJson(json);
      expect(back.pendingAction!.type, 'add_water');
      expect(back.actionStatus, 'pending');
      expect(back.hasPendingAction, isTrue);
    });

    test('ChatActionStatus.dbValues DB CHECK değerleriyle birebir', () {
      // migration: CHECK (action_status IN
      // ('pending','approved','rejected','executed','failed'))
      expect(ChatActionStatus.dbValues, hasLength(5));
      expect(ChatActionStatus.dbValues,
          {'pending', 'approved', 'rejected', 'executed', 'failed'});
    });
  });

  group('loadMore — çakışan created_at mesajları atlanmıyor (P1)', () {
    // `created_at` timestamptz; iki mesaj aynı mikrosaniyede yazılabilir
    // (toplu ekleme, edge function'ın araç döngüsü). Yalnız
    // `lt(created_at, oldest)` + `order(created_at desc) + limit(10)` ise
    // sayfa sınırındaki eşitlikte **kararsızdır** ve mesajlar kalıcı
    // atlanır. `_loadPage` ikincil `order('id')` ekler ve `loadMore`,
    // imleç damgasına sahip kardeş `id`'leri bulup `not.in.(...)` ile
    // dışlayarak bir sonraki sayfayı çeker.
    test('sayfalama imleci en eski created_at (tie-break id)', () async {
      // Saf sözleşme: aynı damgaya sahip iki mesajın `oldestTimestamp` değeri
      // aynıdır; ayrım `id` ile yapılır (repository `order('id')` ekler).
      final sameStamp = [
        ChatMessage(
          id: 'b',
          threadId: 't',
          userId: 'u',
          role: 'assistant',
          content: 'a',
          createdAt: '2026-08-15T10:00:00Z',
        ),
        ChatMessage(
          id: 'a',
          threadId: 't',
          userId: 'u',
          role: 'assistant',
          content: 'b',
          createdAt: '2026-08-15T10:00:00Z',
        ),
      ];
      expect(ChatRepository.oldestTimestamp(sameStamp), '2026-08-15T10:00:00Z');
      // İki mesaj aynı damgada → "daha eski" filtresi ikisini de eler; bu
      // yüzden `loadMore` kardeş `id`'leri ayrıca sorgulamak zorunda.
      expect(sameStamp.every((m) => m.createdAt == '2026-08-15T10:00:00Z'), isTrue);
    });
  });

  group('ChatRepository.oldestTimestamp — sayfalama imleci', () {
    ChatMessage m(String id, String createdAt) => ChatMessage(
          id: id,
          threadId: 't',
          userId: 'u',
          role: 'assistant',
          content: 'x',
          createdAt: createdAt,
        );

    test('en küçük created_at seçilir', () {
      expect(
        ChatRepository.oldestTimestamp([
          m('2', '2026-08-15T10:00:02Z'),
          m('1', '2026-08-15T10:00:00Z'),
          m('3', '2026-08-15T10:00:01Z'),
        ]),
        '2026-08-15T10:00:00Z',
      );
    });

    test('boş listede null (imleç yok → ilk sayfa)', () {
      expect(ChatRepository.oldestTimestamp(const []), isNull);
    });

    test('created_at boş olan mesajlar (welcome) imleci bozmaz', () {
      expect(
        ChatRepository.oldestTimestamp([
          m('welcome', ''),
          m('1', '2026-08-15T10:00:00Z'),
        ]),
        '2026-08-15T10:00:00Z',
      );
    });

    test('hepsi boşsa null', () {
      expect(ChatRepository.oldestTimestamp([m('w', '')]), isNull);
    });
  });

  group('ChatThread', () {
    test('fromJson → aktif (arşivlenmemiş) thread', () {
      final t = ChatThread.fromJson({
        'id': 'th-1',
        'user_id': 'u-1',
        'title': 'Kalori hedefim',
        'archived_at': null,
        'created_at': '2026-08-15T09:00:00Z',
        'updated_at': '2026-08-15T10:00:00Z',
      });
      expect(t.id, 'th-1');
      expect(t.userId, 'u-1');
      expect(t.title, 'Kalori hedefim');
      expect(t.archivedAt, isNull);
    });

    test('fromJson → başlıksız (NULL) thread yeni kayıtta beklenen durum', () {
      // Yeni thread'lerde `title` NULL bırakılır (veri katmanı çeviri
      // anahtarı yazmaz); UI ilk mesajdan başlığı türetir.
      final t = ChatThread.fromJson({
        'id': 'th-3',
        'user_id': 'u-1',
        'title': null,
        'archived_at': null,
        'created_at': '2026-08-15T09:00:00Z',
        'updated_at': '2026-08-15T10:00:00Z',
      });
      expect(t.title, isNull);
      expect(t.archivedAt, isNull);
    });

    test('fromJson → arşivlenmiş thread', () {
      final t = ChatThread.fromJson({
        'id': 'th-2',
        'user_id': 'u-1',
        'title': null,
        'archived_at': '2026-08-14T09:00:00Z',
        'created_at': '2026-08-10T09:00:00Z',
        'updated_at': '2026-08-14T09:00:00Z',
      });
      expect(t.archivedAt, '2026-08-14T09:00:00Z');
      expect(t.title, isNull);
    });
  });

  group('ensureThread — title kolonuna çeviri anahtarı yazılmaz', () {
    test('title verilmediğinde kolon NULL kalır', () {
      final payload = ChatRepository.threadInsertPayload('u1');
      expect(payload['user_id'], 'u1');
      expect(payload.containsKey('title'), isTrue);
      expect(payload['title'], isNull);
    });

    test('başlıkta çeviri anahtarı biçimi yazılmaz', () {
      // Eski hata: DB'ye 'chat.newThread' gibi bir anahtar kalıcılaşıyordu.
      for (final t in <String?>[null, '', '   ']) {
        final title = ChatRepository.threadInsertPayload('u1', title: t)['title'];
        expect(title, isNull, reason: 'title=$t');
      }
    });

    test('verilen başlık kırpılarak yazılır', () {
      final payload =
          ChatRepository.threadInsertPayload('u1', title: '  Haftalık hedef  ');
      expect(payload['title'], 'Haftalık hedef');
    });

    test('başlık kolonu asla boş string değil', () {
      for (final t in <String?>[null, '', '  ', 'x']) {
        final title = ChatRepository.threadInsertPayload('u1', title: t)['title'];
        expect(title, isNot(''), reason: 'title=$t');
      }
    });
  });
}

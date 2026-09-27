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

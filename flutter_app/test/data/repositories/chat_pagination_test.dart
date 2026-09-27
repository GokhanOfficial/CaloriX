import 'dart:convert';

import 'package:calorix/data/repositories/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gerçek `SupabaseClient` + sahte HTTP: **üretilen URL'ler** test edilir.
///
/// Bu, zincir kurmaktan daha güçlüdür: `loadInitial`/`loadMore` için hangi
/// filtrelerin, hangi sıralamanın ve hangi limitin gittiği doğrudan görülür.
SupabaseClient _clientWith(
  Future<http.Response> Function(http.Request) handler,
) =>
    SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      httpClient: MockClient((req) async => handler(req)),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );

http.Response _respond(
  http.BaseRequest request,
  Object? body, {
  int status = 200,
}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

Map<String, dynamic> _msg(String id, String createdAt) => {
      'id': id,
      'thread_id': 't1',
      'user_id': 'u1',
      'role': 'assistant',
      'content': id,
      'created_at': createdAt,
      'attachments': <dynamic>[],
      'tool_calls': <dynamic>[],
      'tool_results': <dynamic>[],
      'pending_action': null,
      'action_status': null,
      'metadata': <String, dynamic>{},
    };

void main() {
  group('mesaj sayfalaması — belirsiz sıralama yok', () {
    late List<Uri> uris;

    setUp(() => uris = <Uri>[]);

    ChatRepository repoReturning(Future<http.Response> Function(http.Request) h) =>
        ChatRepository(_clientWith((req) {
          uris.add(req.url);
          return h(req);
        }));

    test('loadInitial: created_at VE id sıralı, limit uygulanmış', () async {
      final repo = repoReturning((req) async => _respond(req, [
            _msg('m3', '2026-08-15T10:00:03Z'),
            _msg('m2', '2026-08-15T10:00:02Z'),
          ]));

      final page = await repo.loadInitial('u1', 't1');

      final uri = uris.single;
      // `limit` **belirsiz sıralama olmadan** uygulanmamalı: PostgREST
      // sıralaması kararlı değildir, aynı `created_at`'lı satırların hangisinin
      // sayfaya girdiği tanımsız kalır ve `loadMore` imleci takılır.
      // postgrest 2.9.1 `order()` nulls'ı `nullslast` ile ekler.
      expect(uri.queryParameters['order'],
          'created_at.desc.nullslast,id.desc.nullslast');
      expect(uri.queryParameters['limit'], '10');
      expect(uri.queryParameters['deleted_at'], 'is.null');
      expect(uri.queryParameters['thread_id'], 'eq.t1');
      expect(uri.queryParameters['user_id'], 'eq.u1');
      // UI eski→yeni gösterir.
      expect(page.messages.map((m) => m.id), ['m2', 'm3']);
      expect(page.hasMore, isFalse, reason: 'sayfa 10\'dan küçük → devamı yok');
    });

    test('loadInitial: tam sayfa → hasMore true', () async {
      final repo = repoReturning(
        (req) async => _respond(
          req,
          [for (var i = 0; i < 10; i++) _msg('m$i', '2026-08-15T10:00:${i.toString().padLeft(2, '0')}Z')],
        ),
      );
      final page = await repo.loadInitial('u1', 't1');
      expect(page.messages, hasLength(10));
      expect(page.hasMore, isTrue);
    });

    test('loadMore: created_at lt filtresi + ikincil sıralama korunur', () async {
      final repo = repoReturning((req) async => _respond(req, [
            _msg('m1', '2026-08-15T09:00:00Z'),
          ]));

      final page = await repo.loadMore('u1', 't1', '2026-08-15T10:00:00Z');

      // 1. istek: `lt(created_at, oldest)` ile eski sayfa.
      // 2. istek: kardeş `id` taraması (imleç damgasına sahip, listede
      //    bulunmayan satırlar) — yalnız `id` seçilir.
      expect(uris, hasLength(2));
      expect(uris[0].queryParameters['created_at'], 'lt.2026-08-15T10:00:00Z');
      expect(uris[0].queryParameters['order'],
          'created_at.desc.nullslast,id.desc.nullslast');
      expect(uris[1].queryParameters['select'], 'id');
      expect(uris[1].queryParameters['created_at'],
          'eq.2026-08-15T09:00:00Z',
          reason: 'son sayfanın en eski mesajının damgası taranır');
      expect(page.messages.map((m) => m.id), ['m1']);
    });

    test('loadMore: kardeş created_at varsa iki sayfa birleşir', () async {
      // 10 mesajlık ilk sayfa + 3 kardeş + 2 eski mesaj + 2 kardeş sorgusu.
      var call = 0;
      final repo = repoReturning((req) async {
        call++;
        return switch (call) {
          // 1) asıl sayfa: `lt(cursor)`
          1 => _respond(req, [
              _msg('m10', '2026-08-15T10:00:00Z'),
              _msg('m9', '2026-08-15T09:59:59Z'),
            ]),
          // 2) kardeş `id` listesi (a ile b, imleç damgasında)
          2 => _respond(req, [
              {'id': 'a'},
              {'id': 'b'},
            ]),
          // 3) kardeşler hariç, daha eski sayfa
          _ => _respond(req, [
              _msg('x1', '2026-08-15T09:00:01Z'),
              _msg('x2', '2026-08-15T09:00:00Z'),
            ]),
        };
      });

      final page = await repo.loadMore('u1', 't1', '2026-08-15T10:00:01Z');

      // Üç istek: (1) `lt(cursor)` sayfa, (2) kardeş `id`leri,
      // (3) `not.in` ile kardeşler dışlanmış eski sayfa.
      expect(uris, hasLength(3));
      expect(uris[0].queryParameters['created_at'], 'lt.2026-08-15T10:00:01Z');
      expect(uris[1].queryParameters['select'], 'id');
      // Kardeş taraması sayfanın **en eski** mesajının damgasında yapılır.
      // `_loadPage` mesajları eski→yeni döndürdüğü için bu, listenin sonu
      // (`messages.last`): burada m10 (10:00:00Z). m9'in damgasında tarama
      // yapılsaydı a/b bulunamaz ve sayfa atlama devam ederdi.
      expect(uris[1].queryParameters['created_at'], 'eq.2026-08-15T10:00:00Z');
      expect(uris[2].queryParameters['created_at'], 'lt.2026-08-15T10:00:00Z');
      expect(uris[2].queryParameters['id'], 'not.in.(a,b)',
          reason: 'sayfa sınırındaki kardeşler tekrar gelmemeli');
      // Sonuç eski→yeni sıralı, kardeşler **atlanmaz**. (Sunucu yanıtı
      // desc gelir; `_loadPage` eski→yeniye çevirir.)
      expect(page.messages.map((m) => m.id), ['x2', 'x1', 'm9', 'm10']);
      expect(page.hasMore, isFalse);
    });

    test('loadMore: sonuç eski→yeni düzende birleşir', () async {
      var call = 0;
      final repo = repoReturning((req) async {
        call++;
        return switch (call) {
          1 => _respond(req, [_msg('cur', '2026-08-15T10:00:00Z')]),
          2 => _respond(req, [
              {'id': 'b'},
            ]),
          _ => _respond(req, [_msg('old', '2026-08-15T08:00:00Z')]),
        };
      });
      final page = await repo.loadMore('u1', 't1', '2026-08-15T10:00:00Z');
      expect(page.messages.map((m) => m.id), ['old', 'cur']);
    });

    test('loadMore: boş sayfa → hasMore false, tek istek', () async {
      final repo = repoReturning((req) async => _respond(req, const <Object>[]));
      final page = await repo.loadMore('u1', 't1', '2026-08-15T10:00:00Z');
      expect(page.messages, isEmpty);
      expect(page.hasMore, isFalse);
      expect(uris, hasLength(1), reason: 'boş sayfada kardeş taraması yapılmaz');
    });
  });

  group('archiveThread — kapsam filtresi', () {
    test('userId filtresi gider (RLS savunma-derinliği)', () async {
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        return _respond(req, const <Object>[]);
      });
      await ChatRepository(client).archiveThread('u1', 't1');

      final req = requests.single;
      expect(req.method, 'PATCH');
      expect(req.url.queryParameters['id'], 'eq.t1');
      expect(req.url.queryParameters['user_id'], 'eq.u1');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body.keys, contains('archived_at'));
      expect(DateTime.parse(body['archived_at'] as String).isUtc, isTrue);
    });
  });
}

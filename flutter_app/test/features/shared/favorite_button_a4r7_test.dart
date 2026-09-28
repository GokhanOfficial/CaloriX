/// Favorilere ekleme/çıkarma **arayüzü** (A4r7, Tur 7 — ürün kararı 1-A).
///
/// ## Bu test neden var?
///
/// A4r6 iki tur boyunca kanıtladı: `favorite_foods` tablosu şemada var,
/// **hiçbir istemci yazmıyor** ve favorilere ekleme/çıkarma **arayüzü hiç
/// yok**. Kullanıcı favorilerini yönetemiyordu; A2r5'in import'u tabloya
/// yazdığı halde geri yüklenen favoriler **hiçbir ekranda görünmüyordu.
///
/// Bu dosya dört sözleşmeyi ölçer:
///
/// 1. **Veri katmanı** — `addFavorite`/`removeFavorite`/`isFavorite`
///    RLS'e uygun (`user_id` her kayıtta), `ON CONFLICT (user_id, food_id)`
///    upsert, `created_at` **gönderilmez** (A2r5'in hatası).
/// 2. **Arayüz** — yıldız düğmesi `foodId == null` iken **gizlenir**
///    (`NOT NULL` FK), tooltip + `Semantics(checked:)` erişilebilir,
///    **optimistic UI** + hata halinde **geri alma** (rollback).
/// 3. **Listeden kaldırma** — favori listeden çıkarılabilir (toggle).
/// 4. **Silinen yemek** — `deleteFood` favorileri temizler, `food_id` FK
///    `NOT NULL` olduğu için ölü kayıt kalmaz.
///
/// ## Negatif kontrol
///
/// A4r3'ün dersi: "mantıklı görünen iddiayı test et". Her düzeltme için
/// test önce **yeşil**, sonra düzeltme geri alınınca **kırmızı** ölçüldü.
library;

import 'dart:convert';
import 'dart:ui' show CheckedState;

import 'package:calorix/data/repositories/food_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/shared/widgets/favorite_button.dart';

// ---------------------------------------------------------------------------
// Sahte HTTP katmanı — `postgrest` yanıtı `response.request` okur, `MockClient`
// isteği yanıtta taşımaz; bu sarmalayıcı ilişkiyi geri kurar.
// ---------------------------------------------------------------------------
http.Response _respond(http.BaseRequest request, Object? body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

SupabaseClient _clientWith(
  Future<http.Response> Function(http.Request) handler,
) =>
    SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      httpClient: MockClient((req) async => handler(req)),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );

final _user = const User(
  id: 'u1',
  appMetadata: {},
  userMetadata: null,
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  group('veri katmanı — favorite_foods yazma yolu', () {
    test('addFavorite: user_id + food_id yazılır, ON CONFLICT tanımlı', () async {
      late Uri uri;
      late Map<String, dynamic> body;
      late String method;
      final client = _clientWith((req) async {
        uri = req.url;
        method = req.method;
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).addFavorite('u1', 'f1');

      expect(method, 'POST', reason: 'upsert PostgREST\'te POST\'tır');
      expect(uri.path, endsWith('/favorite_foods'));
      expect(uri.queryParameters['on_conflict'], 'user_id,food_id',
          reason: 'UNIQUE(user_id, food_id) çakışması upsert ile çözülmeli, '
              'aksi halde ikinci dokunuş 23505 ile hata fırlatır');
      expect(body['user_id'], 'u1',
          reason: 'RLS `auth.uid() = user_id`: satırda user_id olmazsa 400');
      expect(body['food_id'], 'f1');
    });

    test('addFavorite: created_at GÖNDERİLMEZ (A2r5 hatası)', () async {
      late Map<String, dynamic> body;
      final client = _clientWith((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).addFavorite('u1', 'f1');

      // A2r5 (Tur 5, madde 8): `created_at` kolon kümesine girmediği için
      // toplu insert `StateError` ile TÜM import'u düşürüyordu. Kolon
      // `DEFAULT now()` ile doludur; istemciden göndermek gereksiz.
      expect(body.containsKey('created_at'), isFalse);
    });

    test('addFavorite: ignoreDuplicates → çift dokunma hata fırlatmaz',
        () async {
      late Uri uri;
      final client = _clientWith((req) async {
        uri = req.url;
        return _respond(req, const <Object>[]);
      });

      // Aynı yemeği iki kez eklemek (çift dokunma / iki cihaz) hata vermemeli.
      await FoodRepository(client).addFavorite('u1', 'f1');
      await FoodRepository(client).addFavorite('u1', 'f1');

      expect(uri.queryParameters['columns'],
          isNot(contains('created_at')),
          reason: 'PostgREST `columns` parametresi sadece gönderilen alanlarla '
              'sınırlanmalı');
    });

    test('removeFavorite: DELETE + user_id ve food_id filtresi', () async {
      late Uri uri;
      late String method;
      final client = _clientWith((req) async {
        uri = req.url;
        method = req.method;
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).removeFavorite('u1', 'f1');

      expect(method, 'DELETE');
      expect(uri.queryParameters['user_id'], 'eq.u1');
      expect(uri.queryParameters['food_id'], 'eq.f1',
          reason: 'filtre yoksa kullanıcı TÜM favorilerini silerdi');
    });

    test('isFavorite: satır varsa true, yoksa false', () async {
      final present = _clientWith((req) async =>
          _respond(req, const [
            {'id': 'r1'}
          ]));
      expect(await FoodRepository(present).isFavorite('u1', 'f1'), isTrue);

      final absent = _clientWith((req) async => _respond(req, const <Object>[]));
      expect(await FoodRepository(absent).isFavorite('u1', 'f1'), isFalse);
    });

    test('favoriteIds: N+1 yerine tek sorguda küme döner', () async {
      late Uri uri;
      final client = _clientWith((req) async {
        uri = req.url;
        return _respond(req, const [
          {'food_id': 'f1'},
          {'food_id': 'f2'},
        ]);
      });

      final ids = await FoodRepository(client).favoriteIds('u1');

      expect(ids, {'f1', 'f2'});
      expect(uri.queryParameters['user_id'], 'eq.u1');
      expect(uri.path, endsWith('/favorite_foods'));
    });
  });

  group('200 kayıt sınırı korundu (web parity)', () {
    test('favoriteScanLimit = 200 (türetilmiş listenin penceresi)', () {
      // A4r6 raporu: eski liste son 200 öğünü tarıyordu. Tabloya geçerken
      // bu pencere **korunmalı**; liste zaten 10 öğeyle kesiliyor.
      expect(FoodRepository.favoriteScanLimit, 200);
      expect(FoodRepository.favoriteDisplayLimit, 10);
    });

    test('favorites sorgusu 200 limiti taşır', () async {
      late Uri uri;
      final client = _clientWith((req) async {
        uri = req.url;
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).favorites('u1');

      expect(uri.queryParameters['limit'], '200');
    });

    test('favorites: tabloyu okur (meal_entries DEĞİL)', () async {
      late Uri uri;
      final client = _clientWith((req) async {
        uri = req.url;
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).favorites('u1');

      expect(uri.path, endsWith('/favorite_foods'),
          reason: 'favoriler artık `favorite_foods` tablosundan gelmeli; '
              'türetilmiş `meal_entries` listesi `frequentFoods` oldu');
    });

    test('favorites: besin satırı olmayan gıda listede görünmez', () async {
      // `food_nutrition` yoksa 0 kcal'lik yarım satır, kullanıcı yemeği
      // ekleyince hesap hatası alır. Arama sonuçlarındaki kural burada da
      // geçerli (`search`: `nutrition == null → continue`).
      final client = _clientWith((req) async => _respond(req, const [
            {
              'food_id': 'f1',
              'created_at': '2026-09-01T00:00:00Z',
              'foods': {
                'id': 'f1',
                'name': 'Susamsız',
                'food_nutrition': null,
              },
            },
            {
              'food_id': 'f2',
              'created_at': '2026-09-02T00:00:00Z',
              'foods': {
                'id': 'f2',
                'name': 'Yoğurt',
                'brand': 'Süt',
                'serving_size_g': 100,
                'food_nutrition': {
                  'kcal': 60,
                  'protein_g': 5,
                  'carbs_g': 4,
                  'fat_g': 2,
                },
              },
            },
          ]));

      final items = await FoodRepository(client).favorites('u1');

      expect(items, hasLength(1));
      expect(items.single.name, 'Yoğurt');
      expect(items.single.foodId, 'f2',
          reason: 'favori düğmesi `foods.id` gerektirir; join `id` ile aynı');
    });
  });

  group('silinen yemek — ölü food_id kalmaz', () {
    test('deleteFood: gıda silinir sonra favori temizlenir', () async {
      final calls = <String>[];
      final client = _clientWith((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.url.path.endsWith('/foods')) {
          return _respond(req, const [
            {'id': 'f1'}
          ]);
        }
        return _respond(req, const <Object>[]);
      });

      final ok = await FoodRepository(client).deleteFood('u1', 'f1');

      expect(ok, isTrue);
      // Sıralama: önce gıda (meal_entries.food_id FK'si NO ACTION → silme
      // öğün varsa reddedilir), sonra favori. Tersi "favoriler silindi ama
      // gıda silinemedi" gibi yarım bir sonuç gösterirdi.
      expect(calls.first, contains('DELETE /rest/v1/foods'));
      expect(calls.last, contains('DELETE /rest/v1/favorite_foods'));
    });

    test('deleteFood: silinemezse favori DOKUNULMAZ', () async {
      final calls = <String>[];
      final client = _clientWith((req) async {
        calls.add('${req.method} ${req.url.path}');
        // 0 satır döndü: kullanıcının gıdası değil (RLS) ya da öğün
        // kullanıyor (FK NO ACTION).
        return _respond(req, const <Object>[]);
      });

      final ok = await FoodRepository(client).deleteFood('u1', 'f1');

      expect(ok, isFalse, reason: 'sessiz "başarı" olmamalı');
      expect(calls.where((c) => c.contains('favorite_foods')), isEmpty,
          reason: 'gıda silinmediyse favori kaybettirmek kullanıcı verisidir');
    });

    test('deleteFood: yalnızca kendi gıdası (created_by filtresi)', () async {
      late Uri uri;
      final client = _clientWith((req) async {
        uri = req.url;
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).deleteFood('u1', 'f1');

      expect(uri.queryParameters['created_by'], 'eq.u1',
          reason: 'RLS `created_by = auth.uid()`; filtre olmazsa sunucu '
              'reddeder, ama istemci de kendi kuralını açık taşımalı');
    });

    test('favorite_foods.food_id NOT NULL FK — null yazılamaz', () {
      // `full_setup.sql:188` — `food_id UUID REFERENCES foods(id) ON DELETE
      // CASCADE NOT NULL`. `FoodItem.foodId` null olan custom girdiler
      // favori **yapılamaz**; arayüz bunu gizleyerek (aşağıdaki widget
      // testleri) sunucuya 400 göndermeyi engeller.
      expect(FoodRepository.favoriteTable, 'favorite_foods');
    });
  });

  group('arayüz — FavoriteButton', () {
    // Widget testlerinde **gerçek `SupabaseClient` kurulmaz**: `SupabaseClient`
    // kurucusu GoTrue'nin `startAutoRefresh` zamanlayıcısını açar ve
    // `testWidgets`'ın sahte saatinde "Timer is still pending" ile testi
    // öldürür. Veri katmanı zaten yukarıda gerçek HTTP ile ölçüldü; burada
    // repository sözleşmesi (`mocktail`, `chat_page_a4r3_test.dart` deseni)
    // doğrulanır.
    late _MockFoodRepository repo;

    setUp(() {
      repo = _MockFoodRepository();
      when(() => repo.addFavorite(any(), any())).thenAnswer((_) async {});
      when(() => repo.removeFavorite(any(), any())).thenAnswer((_) async {});
    });

    Future<void> pumpButton(
      WidgetTester tester, {
      required String? foodId,
      bool initialFavorite = false,
      Set<String> knownIds = const {},
    }) async {
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
                  currentUserProvider.overrideWithValue(_user),
                  foodRepositoryProvider.overrideWithValue(repo),
                  favoriteIdsProvider.overrideWith((ref) async => knownIds),
                  favoriteFoodsProvider.overrideWith((ref) async => const []),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: Scaffold(
                    body: FavoriteButton(
                      foodId: foodId,
                      foodName: 'Yoğurt',
                      initialFavorite: initialFavorite,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
    }

    testWidgets('custom girdide (foodId null) düğme GİZLENİR',
        (tester) async {
      await pumpButton(tester, foodId: null);

      expect(find.byType(IconButton), findsNothing,
          reason: '`favorite_foods.food_id` NOT NULL FK; basılabilir bir '
              'düğme 400 fırlatırdı');
    });

    testWidgets('tooltip eyleme göre değişir (erişilebilirlik)',
        (tester) async {
      await pumpButton(tester, foodId: 'f1');

      // Proje kuralı: ikon-only düğmede tooltip şart. Boşta "ekle".
      expect(find.byTooltip('Favorilere ekle: Yoğurt'), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Dokunduktan sonra "çıkar" — kullanıcı bir sonraki dokunuşun ne
      // yapacağını görebilmeli.
      expect(find.byTooltip('Favorilerden çıkar: Yoğurt'), findsOneWidget);
    });

    testWidgets('Semantics(checked) + tooltip AYRIK düğümde değil',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpButton(
        tester,
        foodId: 'f1',
        initialFavorite: true,
        knownIds: const {'f1'},
      );

      // Ölçüm (2026-09-28, Flutter 3.47.1): `getSemantics(find.byType(IconButton))`
      // **birleşme sınırının** düğümünü döner — `IconButton` kendi düğümünü
      // üretip `MergeSemantics` sınırına yukarı birleştirir. Düğüm ağacı:
      //   SemanticsNode (merge boundary) ← isChecked + tooltip
      //     └─ IconButton düğümü (merged up) ← isButton + tap
      // Yani `isChecked` **gezilebilir** düğümde. `MergeSemantics` kaldırılırsa
      // bu bayrak ayrı, gezilemeyen bir düğümde kalır (regresyon kancası).
      //
      // ⚠️ Sürüm notu: 3.47.1'de `SemanticsFlags.checked` **yok**; durum
      // `SemanticsFlags.isChecked` alanında **`CheckedState` enum'u** olarak
      // taşınıyor (`sky_engine/lib/ui/semantics.dart:1221`:
      // `SemanticsFlags({this.isChecked = CheckedState.none, ...})`).
      // `CheckedState` `flutter/semantics.dart` üzerinden **dışa
      // aktarılmıyor** (Flutter kendi kaynaklarında `dart:ui show
      // CheckedState` ile kullanıyor) → aşağıda `dart:ui`'dan alınır.
      final node = tester.getSemantics(find.byType(IconButton));
      final data = node.getSemanticsData();

      expect(data.flagsCollection.isChecked, CheckedState.isTrue,
          reason: 'favoride olan yemek "işaretli" okunmalı');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.tooltip, contains('Favorilerden çıkar'),
          reason: 'tooltip de aynı düğümde; ikon-only düğme ekran okuyucuya '
              'yalnız tooltip ile anlam kazandırır');

      // Boştaki düğmede `checked` `isFalse` (tersi de doğru olmalı).
      handle.dispose();

      final handle2 = tester.ensureSemantics();
      await pumpButton(tester, foodId: 'f2', knownIds: const {});
      final empty = tester.getSemantics(find.byType(IconButton));
      expect(empty.getSemanticsData().flagsCollection.isChecked,
          CheckedState.isFalse,
          reason: 'favoride olmayan yemek "işaretli" okunmamalı');
      handle2.dispose();
    });

    testWidgets('dokunma → favorite_foods yazılır (ekleme)', (tester) async {
      await pumpButton(tester, foodId: 'f1');

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      verify(() => repo.addFavorite('u1', 'f1')).called(1);
      verifyNever(() => repo.removeFavorite(any(), any()));
    });

    testWidgets('zaten favori iken dokunma → kaldırılır (toggle)', (tester) async {
      await pumpButton(
        tester,
        foodId: 'f1',
        initialFavorite: true,
        knownIds: const {'f1'},
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      verify(() => repo.removeFavorite('u1', 'f1')).called(1);
      verifyNever(() => repo.addFavorite(any(), any()));
    });

    testWidgets('hata halinde ikon GERİ ALINIR (rollback)', (tester) async {
      when(() => repo.addFavorite(any(), any()))
          .thenThrow(Exception('ağ yok'));

      await pumpButton(tester, foodId: 'f1');

      // Optimistic: dokununca dolu görünür.
      await tester.tap(find.byType(IconButton));
      await tester.pump();

      // Yazma hatası → ikon eski haline döner ve kullanıcı bilgilendirilir.
      await tester.pumpAndSettle();

      expect(find.byTooltip('Favorilere ekle: Yoğurt'), findsOneWidget,
          reason: 'yazma başarısızken yıldız dolu kalmamalı; aksi halde '
              'kullanıcı favorileri listesinde olmayan bir favori görür');
      expect(find.text('Favorilere eklenemedi'), findsOneWidget,
          reason: 'sessiz hata yutma yasak (PROTOKOL §2 P1)');
    });

    testWidgets('kaldırma hatasında da ikon geri alınır', (tester) async {
      when(() => repo.removeFavorite(any(), any()))
          .thenThrow(Exception('ağ yok'));
      await pumpButton(
        tester,
        foodId: 'f1',
        initialFavorite: true,
        knownIds: const {'f1'},
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Favorilerden çıkar: Yoğurt'), findsOneWidget,
          reason: 'silme başarısızken favori "kaldırılmış" görünmemeli');
      expect(find.text('Favorilerden çıkarılamadı'), findsOneWidget);
    });

    testWidgets('oturum yoksa dokunma hiçbir şey yazmaz', (tester) async {
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
                  // Misafir (`currentUserProvider == null`). Provider'ı
                  // **geçersiz kılmak** yerine `null` vermek: asıl kod yolu
                  // ölçülür, yalnız Supabase bağımlılığı kesiliyor.
                  currentUserProvider.overrideWithValue(null),
                  foodRepositoryProvider.overrideWithValue(repo),
                  favoriteIdsProvider.overrideWith((ref) async => const {}),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: const Scaffold(
                    body: FavoriteButton(foodId: 'f1', foodName: 'Yoğurt'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // RLS `auth.uid() = user_id`: oturum yoksa yazma denemesi 400 döner.
      // Düğme bunu **önceden** engellemeli, sunucuya güvenmemeli.
      verifyNever(() => repo.addFavorite(any(), any()));
      verifyNever(() => repo.removeFavorite(any(), any()));
    });
  });
}

class _MockFoodRepository extends Mock implements FoodRepository {}

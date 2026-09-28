/// Favorilere ekleme/çıkarma düğmesi — `favorite_foods` tablosuna yazar
/// (A4r7, ürün kararı 1-A).
///
/// ## Neden `shared/` altında?
///
/// Düğme hem **arama sonuçlarında** (`features/add`) hem **favori
/// listesinde** (`features/add`) hem de **öğün detay dialogunda**
/// (`features/add`) görünür. `features/**` altında bir `widgets/` kopyası
/// her ekranda farklı bir kopya üretirdi; bu yüzden tek doğruluk kaynağı
/// burada tutulur ve testler de tek yerden sürer.
///
/// ## Erişilebilirlik
///
/// İkon-only düğme olduğu için **her zaman** `tooltip` taşır (proje kuralı)
/// ve `tooltip` metni **eyleme göre** değişir ("Favorilere ekle" ⇄
/// "Favorilerden çıkar"). Ekran okuyucu `tooltip`'ı düğme adı olarak
/// okur, böylece ekran görüntüsü/rozet simgesi tek başına anlamsız
/// kalmaz. Ek olarak `Semantics(checked:)` verilir: yıldızın dolu/boş
/// olması bir **durum**dur, ekran okuyucuya "işaretli" olarak iletilir
/// (WCAG 1.3.1).
///
/// ## Optimistic UI
///
/// Tıklama anında ikon **hemen** değişir; DB yazımı arka planda yürür. Hata
/// olursa ikon **geri alınır** ve `SnackBar` ile kullanıcıya "favori
/// eklenemedi" bildirilir. Tersi (önce bekle, sonra güncelle) 300 ms'lik
/// sorgu gecikmesi sırasında düğmeye ikinci kez basılabilir ve iki yazma
/// isteği yarışır.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/food_repository.dart';

/// Favori düğmesi — yalnız ikon, `tooltip` zorunlu.
///
/// [foodId] `null` ise düğme **gizlenmez**: `favorite_foods.food_id`
/// `NOT NULL` FK'dir, custom/manuel girdi (`FoodItem.foodId == null`)
/// favorileyemez. Yanlış bir şekilde basılabilir bir düğmeden
/// `ArgumentError` yutturmak yerine düğmeyi göstermemek doğrudur.
class FavoriteButton extends ConsumerStatefulWidget {
  const FavoriteButton({
    super.key,
    required this.foodId,
    required this.foodName,
    this.initialFavorite = false,
    this.size = 20,
  });

  /// `foods.id` — `null` ise düğme hiç kurulmaz.
  final String? foodId;

  /// Erişilebilir etikette okunacak yemek adı.
  final String foodName;

  /// İlk karede bilinen durum. `favoriteIdsProvider` henüz yüklenmemişse
  /// listedeki öğe için doğru bir başlangıç sağlar (aksi halde her
  /// favori dolu görünürdü — `ListView` her satırda istek atmadığı için).
  final bool initialFavorite;

  final double size;

  @override
  ConsumerState<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<FavoriteButton> {
  /// Optimistic durum: `null` = henüz bilinmiyor (provider yükleniyor).
  late bool? _optimistic;

  @override
  void initState() {
    super.initState();
    _optimistic = widget.foodId == null ? null : widget.initialFavorite;
  }

  @override
  void didUpdateWidget(FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Düğme başka bir satıra taşınırsa (liste yeniden kuruldu) optimistic
    // durum **taşınmaz**; aksi halde 2. satır 1. satırın durumunu gösterir.
    if (oldWidget.foodId != widget.foodId) {
      _optimistic = widget.foodId == null ? null : widget.initialFavorite;
    }
  }

  /// Provider'dan (veya başlangıçtan) gelen gerçek durum.
  ///
  /// `initialFavorite` **daima kazanır**: liste kendi favorilerini
  /// `favoriteFoodsProvider`'dan çekiyor, yani listede görünen her öğe
  /// favoridir. `favoriteIdsProvider` yalnız **arama sonuçlarındaki** satır
  /// için anlamlıdır ve orada da liste kısa ömürlüdür.
  bool _resolve(bool? known) => _optimistic ?? known ?? widget.initialFavorite;

  Future<void> _toggle() async {
    final foodId = widget.foodId;
    if (foodId == null) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final wasFavorite = _resolve(null);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(foodRepositoryProvider);

    // 1) Optimistic: ikon anında değişir.
    setState(() => _optimistic = !wasFavorite);

    try {
      if (wasFavorite) {
        await repo.removeFavorite(user.id, foodId);
      } else {
        await repo.addFavorite(user.id, foodId);
      }
      // 2) Liste + id kümesi bayatladı. `favoriteIdsProvider` **atlanmaz**:
      // arama sonuçlarındaki yıldızlar aksi hâlde DB'ye yazılmış favori
      // için boş kalır.
      ref.invalidate(favoriteFoodsProvider);
      ref.invalidate(favoriteIdsProvider);
    } catch (_) {
      // 3) Hata → **geri al** + kullanıcıya bildir. Sessizce yutulursa
      //    kullanıcı yıldızı dolu görür ama favorileri listesinde yoktur.
      if (mounted) setState(() => _optimistic = wasFavorite);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            wasFavorite
                ? 'favorites.toasts.removeFailed'.tr()
                : 'favorites.toasts.addFailed'.tr(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final foodId = widget.foodId;
    if (foodId == null) return const SizedBox.shrink();

    // Arama sonuçlarında gerçek durumu tek sorgudan al; favoriler/son
    // yenilenler bölümlerinde `null` gelir (o öğeler zaten favoridir ya da
    // favori olamaz) ve `initialFavorite` kullanılır.
    final known = ref.watch(
      favoriteIdsProvider.select((async) {
        final ids = async.valueOrNull;
        return ids?.contains(foodId);
      }),
    );
    final favorite = _resolve(known);

    // `MergeSemantics` **zorunlu**: `IconButton` kendi ayrı semantik
    // düğümünü üretir (`isButton`, `tap`). `Semantics(checked:)` ise
    // **üstte** ayrı bir düğüm oluşturur; birleştirilmezse ekran okuyucu
    // iki ayrı düğüm gezer ve "işaretli" durumu butona **bağlı** görünmez
    // (ölçüldü: `isChecked` yalnız sarmalayıcı düğümdeydi, düğme düğümünde
    // `isButton` vardı). `MergeSemantics` ikisini **tek** düğümde birleştirir
    // → "Favorilerden çıkar: Yoğurt, işaretli düğme".
    return MergeSemantics(
      child: Semantics(
        // Yıldızın dolu/boş olması **yalnız görsel** bir ayrımdır; ekran
        // okuyucu bunu göremez. `checked` bayrağı "favoride" **durumunu**
        // ayrıca iletir (WCAG 1.3.1 "Anlam ve İşlev").
        button: true,
        checked: favorite,
        child: Tooltip(
          // Proje kuralı: ikon-only düğmede `tooltip` **şart** (erişilebilirlik
          // + test kancası). Metin **eyleme göre** değişir ve yemek adını
          // içerir — liste 10 satır olduğunda ekran okuyucu hangi yemeğin
          // favori olduğunu duyabilmeli.
          message: (favorite ? 'favorites.remove'.tr() : 'favorites.add'.tr())
              .replaceAll('{food}', widget.foodName),
          child: IconButton(
            onPressed: _toggle,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              favorite ? Icons.star : Icons.star_border,
              size: widget.size,
              color: favorite
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Kullanıcının **kendi eklediği** gıdayı silme akışı (A4r10, Tur 11).
///
/// ## Bu neden var?
///
/// `FoodRepository.deleteFood` (`food_repository.dart:189`) veri katmanında
/// **tam** sözleşmeyi uyguluyor: önce `foods` satırını (RLS
/// `created_by = auth.uid()`), sonra favori satırını temizliyor; silinemezse
/// `false` dönüyor. A2r9 ve A4r7b bunu **yalnız testlerde** ölçtü —
///
/// ```text
/// A4r7b'in notu: "deleteFood'ın hiç UI çağıranı yok."
/// ```
///
/// Yani kullanıcı eklediği yiyeceği **silemiyordu**; `foods` tablosu
/// (ve `food_nutrition`) yalnız büyüyordu. Bu dosya o eksik arayüzü kapatır.
///
/// ## Neden `shared/` altında?
///
/// Silme girişi hem **arama sonuçlarında** hem **"son eklenenler" /
/// "sık kullanılanlar" / "favoriler"** bölümlerinde görünecek; hepsi
/// `features/add` altında ama widget'ın tek doğruluk kaynağı olması için
/// `shared/widgets/` altında tutulur (aynı gerekçe `favorite_button.dart`).
///
/// ## Onay diyaloğu **zorunlu**
///
/// Yanlışlıkla silme (kayıp veri) P1 sınıfıdır; diyalog üç bilgiyi birlikte
/// gösterir:
///
/// 1. **Yemeğin adı** — hangi kaydın silineceği belli olsun.
/// 2. **Kaç öğünde kullanıldığı** — 0 ise "hiç kullanılmadı", >0 ise bu
///    sayı. Bu bilgi yemeğin "kıymetini" gösterir ve kullanıcıyı iki kez
///    düşünmeye iter.
/// 3. **Favorileri de silinecek** — `favorite_foods.food_id` FK'si
///    `ON DELETE CASCADE`; favori ayrı bir kayıt olduğu için kullanıcıya
///    söylenmelidir.
///
/// ## Erişilebilirlik
///
/// - Silme düğmesi **ikon-only** → `tooltip` **şart** (proje kuralı) ve
///   metin **eyleme göre** değişmez (her zaman "sil"), yemeğin adını içerir.
/// - `Semantics(button: true, label: …)` verilir; yalnız ikon bir ekran
///   okuyucuya anlamsızdır.
/// - Düğme yalnızca **silinebilir** gıdalarda çizilir:
///   - `foodId == null` → custom/manuel girdi; `foods` tablosunda satır yok.
///   - `canDelete == false` → `foods.created_by != auth.uid()`; RLS DELETE
///     reddeder (A4r11). Düğme görünür ama hiç çalışmazsa kullanıcı
///     "bozuk özellik" sanır; hiç görünmezse soru sormaya gerek kalmaz.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/observability/app_logger.dart';
import '../../data/models/food_item.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/food_repository.dart';

/// Silme düğmesi + onay diyaloğu — [onDeleted] başarıyla silinince çağrılır.
///
/// [food] `foodId == null` ise (custom/manuel girdi) **hiçbir şey
/// çizilmez** (`SizedBox.shrink`), çünkü `foods` tablosunda silinecek satır
/// yoktur.
class DeleteFoodButton extends ConsumerStatefulWidget {
  const DeleteFoodButton({
    super.key,
    required this.food,
    this.onDeleted,
  });

  final FoodItem food;

  /// Gıda silindikten sonra çağrılır (listeyi tazelemek için).
  final VoidCallback? onDeleted;

  @override
  ConsumerState<DeleteFoodButton> createState() => _DeleteFoodButtonState();
}

class _DeleteFoodButtonState extends ConsumerState<DeleteFoodButton> {
  bool _deleting = false;

  Future<void> _confirmAndDelete() async {
    final food = widget.food;
    final foodId = food.foodId;
    if (foodId == null) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final messenger = ScaffoldMessenger.of(context);

    // ⭐ Onay diyaloğu: kullanıcı **adı + kullanım sayısı + favori bilgisi**
    // görmeden silme yoluna giremez.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('foodDelete.title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(food.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            // "Kaç öğünde kullanıldı" — `useCount` yalnız favoriler/
            // sık kullanılanlar bölümlerinde doludur (arama sonuçlarında ve
            // "son eklenenler"de `null` gelir). `null` iken mesaj
            // gösterilmez — yanlış "0 öğünde kullanıldı" iddiası üretmemek
            // için bilgi **uydurulmaz**.
            if (food.useCount != null)
              Text(
                'foodDelete.usageCount'.tr(
                  namedArgs: {'count': '${food.useCount}'},
                ),
              ),
            const SizedBox(height: 8),
            Text('foodDelete.favoriteWarning'.tr()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('foodDelete.confirm'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      // ⭐ Sıra veri katmanında **belirlidir** (gıda önce, favori sonra);
      // gıda silinemezse favorilere dokunulmaz. Burada yalnız sonucu
      // yorumluyoruz.
      final ok = await ref.read(foodRepositoryProvider).deleteFood(user.id, foodId);

      // Liste + favori id kümesi bayatladı (favori satırı CASCADE ile silindi).
      ref.invalidate(favoriteFoodsProvider);
      ref.invalidate(favoriteIdsProvider);
      ref.invalidate(recentFoodsProvider);
      ref.invalidate(frequentFoodsProvider);

      if (!mounted) return;
      if (ok) {
        widget.onDeleted?.call();
        messenger.showSnackBar(
          SnackBar(content: Text('foodDelete.deleted'.tr())),
        );
      } else {
        // Sessiz "başarı" olmaz: kullanıcı ya RLS'yi (başkasının gıdası)
        // ya da `meal_entries.food_id` FK'sini (`NO ACTION` → öğün varsa
        // 23503) tetikledi. İkisi de kullanıcıya **açıklanır**.
        messenger.showSnackBar(
          SnackBar(content: Text('foodDelete.deleteFailed'.tr())),
        );
      }
    } catch (e, s) {
      AppLog.w('Gıda silinemedi (${food.name})', e, s);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('foodDelete.deleteFailed'.tr())),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final foodId = widget.food.foodId;
    // ⭐ A4r11: `foodId == null` → custom/manuel girdi, `foods` tablosunda
    // silinecek satır yok.
    //
    // `canDelete == false` → `foods.created_by != auth.uid()`: RLS DELETE
    // politikası (`full_setup.sql:424`) reddedeceği için düğme **işe yaramaz**.
    // A4r10 bu yüzden **tohumluk/topluluk** gıdalarında da düğmeyi
    // gösteriyordu; kullanıcı "neden silemiyorum" diye boşuna dener.
    // `canDelete` = `created_by == userId` (`food_repository.dart:24-63`), yani
    // `deleteFood`'in süzgeciyle **birebir** aynı koşul → düğme yalnız işe
    // yarayacağı yerde görünür.
    if (foodId == null || !widget.food.canDelete) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tooltip = 'foodDelete.tooltip'.tr(
      namedArgs: {'food': widget.food.name},
    );

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: tooltip,
        child: Tooltip(
          // İkon-only düğmede tooltip şart (proje kuralı). Yemeğin adını
          // içerir: listede 10 satır varken ekran okuyucu hangi yemeği
          // sileceğini duyabilmeli.
          message: tooltip,
          child: IconButton(
            onPressed: _deleting ? null : _confirmAndDelete,
            visualDensity: VisualDensity.compact,
            icon: _deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );
  }
}

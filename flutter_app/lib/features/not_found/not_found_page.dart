import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_page.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) => PlaceholderPage(
        // `errors.notFound` / `common.comingSoon` çeviri anahtarları JSON'da
        // yok (bkz. RAPOR-A4 AKTARIM) — `tr()` anahtarın kendisini döndürür.
        title: 'errors.notFound'.tr(),
        icon: Icons.error_outline,
      );
}

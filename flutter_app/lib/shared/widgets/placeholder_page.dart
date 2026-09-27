import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Faz 0 iskeleti için geçici sayfa gövdesi.
/// Her fazda gerçek implementasyonla değiştirilecek.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
            ],
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              // Sabit Türkçe metin diğer 11 dilde çeviriye rağmen Türkçe
              // kalıyordu; anahtar eksikse `.tr()` anahtarı döndürür (test
              // `widget_test.dart` bu davranışı doğruluyor).
              'common.comingSoon'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

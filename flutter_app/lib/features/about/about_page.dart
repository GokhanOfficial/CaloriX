import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Hakkında — web `AboutPage.tsx` parity.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('about.title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Uygulama bilgisi ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.info_outline, size: 32, color: scheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Text('CaloriX',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('about.subtitle'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.outline,
                          )),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'about.version'
                          .tr(namedArgs: {'version': AppConstants.appVersion}),
                      style: TextStyle(color: scheme.primary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- Özellikler ----
          _Card(
            title: 'about.features.title'.tr(),
            children: [
              _bullet(context, 'about.features.ai'.tr()),
              _bullet(context, 'about.features.tracker'.tr()),
              _bullet(context, 'about.features.analytics'.tr()),
              _bullet(context, 'about.features.notifications'.tr()),
            ],
          ),
          const SizedBox(height: 16),

          // ---- Geliştirici ----
          _Card(
            title: 'about.developer.title'.tr(),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.code, color: scheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Gökhan Tekyıldırım',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('about.developer.role'.tr(),
                          style: TextStyle(
                              color: scheme.outline, fontSize: 13)),
                    ],
                  ),
                ],
              ),
              const Divider(height: 24),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    _mailto('gokhantekyildirim@outlook.com'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.mail_outline, color: scheme.outline, size: 20),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('about.email'.tr(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500, fontSize: 13)),
                          Text('gokhantekyildirim@outlook.com',
                              style: TextStyle(
                                  color: scheme.outline, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- Destekleyenler ----
          _Card(
            title: 'about.poweredBy'.tr(),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, color: scheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text('Pollinations AI',
                      style: TextStyle(
                          color: scheme.outline,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- Alt bilgi ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('about.footer.madeWith'.tr(),
                          style: TextStyle(color: scheme.outline, fontSize: 13)),
                      const SizedBox(width: 6),
                      Icon(Icons.favorite,
                          color: AppColors.destructive, size: 16),
                      const SizedBox(width: 6),
                      Text('about.footer.inTurkey'.tr(),
                          style: TextStyle(color: scheme.outline, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('about.footer.copyright'.tr(),
                      style: TextStyle(color: scheme.outline, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7),
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Future<void> _mailto(String address) async {
    final uri = Uri.parse('mailto:$address');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: scheme.outline,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

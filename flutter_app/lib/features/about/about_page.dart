import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderPage(title: 'AboutPage', icon: Icons.info);
}

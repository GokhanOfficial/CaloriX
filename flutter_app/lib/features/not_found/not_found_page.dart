import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_page.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderPage(title: 'NotFoundPage', icon: Icons.error_outline);
}

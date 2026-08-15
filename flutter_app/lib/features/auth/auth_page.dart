import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_page.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderPage(title: 'AuthPage', icon: Icons.login);
}

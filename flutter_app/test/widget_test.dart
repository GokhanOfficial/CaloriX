import 'package:calorix/shared/widgets/placeholder_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PlaceholderPage başlık ve ikonu gösterir', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlaceholderPage(title: 'DashboardPage', icon: Icons.dashboard),
      ),
    );

    expect(find.text('DashboardPage'), findsNWidgets(2)); // appBar + body
    expect(find.byIcon(Icons.dashboard), findsOneWidget);
    expect(find.text('Yakında (iskelet)'), findsOneWidget);
  });
}

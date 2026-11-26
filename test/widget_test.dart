import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ganaderov/app.dart';

void main() {
  testWidgets('shows the Ganaderov dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: GanaderovApp()));

    expect(find.text('Ganaderov'), findsOneWidget);
    expect(find.text('Todo tu ganado,\nen un solo lugar.'), findsOneWidget);
    expect(find.text('Actividad reciente'), findsOneWidget);
    expect(find.text('Animales'), findsOneWidget);
  });
}

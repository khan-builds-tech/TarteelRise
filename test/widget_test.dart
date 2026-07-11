import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tarteel_rise/main.dart';

void main() {
  testWidgets(
    'shows the debug preview reciting session on startup',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: TarteelRiseApp()),
      );
      await tester.pump();

      expect(find.textContaining('إِيَّاكَ نَعْبُدُ'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    },
  );
}

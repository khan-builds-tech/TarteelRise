import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tarteel_rise/main.dart';

void main() {
  testWidgets('shows the idle placeholder when no alarm is active', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: TarteelRiseApp()),
    );

    expect(find.text('No active alarm.'), findsOneWidget);
  });
}

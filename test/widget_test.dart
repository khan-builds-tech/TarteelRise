import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tarteel_rise/main.dart';
import 'package:tarteel_rise/providers/alarm_state_provider.dart';
import 'package:tarteel_rise/services/alarm_hardware_service.dart';

void main() {
  late Directory tempHiveDir;
  late ProviderContainer container;

  setUp(() async {
    tempHiveDir = Directory.systemTemp.createTempSync('tarteel_rise_test_hive');
    container = ProviderContainer(
      overrides: [
        // The real 10s production timeout exists for a native channel
        // that will never respond in a widget test — no plugin handler is
        // registered, so the call hangs rather than throwing until that
        // timeout fires. Shortened here so tests don't have to actually
        // wait out the production duration in real wall-clock time
        // (`tester.pump` advances the animation clock, not real `Timer`s).
        alarmHardwareServiceProvider.overrideWithValue(
          AlarmHardwareService(nativeCallTimeout: const Duration(milliseconds: 50)),
        ),
      ],
    );
    await container
        .read(databaseServiceProvider)
        .init(testHiveDirectoryPath: tempHiveDir.path);
  });

  tearDown(() {
    container.dispose();
    tempHiveDir.deleteSync(recursive: true);
  });

  testWidgets('boots to the dashboard on cold launch', (WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const TarteelRiseApp()),
    );
    await tester.pump();

    expect(find.text('Tarteel Rise'), findsOneWidget);
    expect(find.text('Test Active Alarm UI'), findsOneWidget);
  });

  testWidgets(
    'Test Active Alarm UI button reaches the debug preview reciting session',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const TarteelRiseApp()),
      );
      await tester.pump();

      await tester.tap(find.text('Test Active Alarm UI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('إِيَّاكَ نَعْبُدُ'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    },
  );

  testWidgets(
    'creating an alarm persists it and shows it back on the dashboard',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const TarteelRiseApp()),
      );
      await tester.pump();

      expect(find.text('No alarms yet.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('New Alarm'), findsOneWidget);

      // The form is long enough to overflow the test viewport, and
      // ListView only builds visible children, so the Save button isn't
      // in the tree until scrolled into view.
      await tester.dragUntilVisible(
        find.text('Save Alarm'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      // Saving does a real Hive disk write, which needs the real event
      // loop to complete — `testWidgets` runs in a fake-async zone that
      // doesn't service real I/O callbacks on its own, so without
      // `runAsync` this hangs forever (not a timeout — no timer is
      // involved in Hive's write completion). `runAsync` is the
      // documented escape hatch for exactly this.
      await tester.runAsync(() async {
        await tester.tap(find.text('Save Alarm'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      // Two pumps: the first flushes the pop() call itself, the second
      // (timed) lets the route transition animation finish — otherwise
      // the exiting "New Alarm" route is still mid-transition and present
      // in the tree, same as the pop-back handling in the test above.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('New Alarm'), findsNothing);
      expect(find.text('No alarms yet.'), findsNothing);
      expect(find.textContaining('Every day'), findsOneWidget);
      expect(find.textContaining('3 Ayahs'), findsOneWidget);
    },
  );
}

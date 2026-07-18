import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tarteel_rise/main.dart';
import 'package:tarteel_rise/models/alarm_model.dart';
import 'package:tarteel_rise/providers/alarm_state_provider.dart';
import 'package:tarteel_rise/providers/dashboard_providers.dart';
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
    // AlarmCreateScreen's Surah dropdown needs this loaded — without it,
    // `allSurahs` is empty and the screen shows its "dataset failed to
    // load" fallback instead of the form.
    await container.read(quranRepositoryProvider).loadFromAssets();
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
    'Test Active Alarm UI button reaches the debug preview paused session',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const TarteelRiseApp()),
      );
      await tester.pump();

      await tester.tap(find.text('Test Active Alarm UI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('إِيَّاكَ نَعْبُدُ'), findsOneWidget);
      expect(find.text('Start Reciting'), findsOneWidget);
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

  testWidgets(
    'tapping an existing alarm opens edit mode and updates it in place',
    (WidgetTester tester) async {
      await container.read(databaseServiceProvider).saveAlarm(
            AlarmModel(
              id: 'edit-test-alarm',
              hour: 5,
              minute: 30,
              daysOfWeek: const [],
              isEnabled: true,
              selectedSurahIndex: 1,
              numberOfAyahs: 3,
              difficultyLevel: 'medium',
            ),
          );
      container.read(alarmListProvider.notifier).refresh();

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const TarteelRiseApp()),
      );
      await tester.pump();

      expect(find.text('05:30'), findsOneWidget);

      // Tapping the card (not the trailing delete icon) opens it for editing.
      await tester.tap(find.text('05:30'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Edit Alarm'), findsOneWidget);

      await tester.dragUntilVisible(
        find.byIcon(Icons.add_circle_outline),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();

      await tester.dragUntilVisible(
        find.text('Save Changes'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save Changes'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Edit Alarm'), findsNothing);
      // Same alarm updated in place, not a second one created alongside it.
      expect(container.read(alarmListProvider).length, 1);
      expect(find.text('05:30'), findsOneWidget);
      expect(find.textContaining('4 Ayahs'), findsOneWidget);
    },
  );

  testWidgets(
    'deleting an alarm removes it after confirmation',
    (WidgetTester tester) async {
      await container.read(databaseServiceProvider).saveAlarm(
            AlarmModel(
              id: 'delete-test-alarm',
              hour: 6,
              minute: 0,
              daysOfWeek: const [],
              isEnabled: true,
              selectedSurahIndex: 1,
            ),
          );
      container.read(alarmListProvider.notifier).refresh();

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const TarteelRiseApp()),
      );
      await tester.pump();

      expect(find.text('06:00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      expect(find.text('Delete Alarm?'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('Delete Alarm?'), findsNothing);
      expect(find.text('06:00'), findsNothing);
      expect(find.text('No alarms yet.'), findsOneWidget);
    },
  );
}

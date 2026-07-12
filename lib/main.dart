import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/alarm_model.dart';
import 'providers/alarm_state_provider.dart';
import 'services/alarm_hardware_service.dart';
import 'services/alarm_ringing_listener.dart';
import 'services/database_service.dart';
import 'services/quran_repository.dart';
import 'theme/app_theme.dart';
import 'ui/screens/alarm_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A ProviderContainer built ahead of runApp() so the services it creates
  // (Hive boxes, native alarm ports) can finish async initialization before
  // any widget reads them, while still being the exact same instances the
  // widget tree gets via UncontrolledProviderScope below.
  final ProviderContainer container = ProviderContainer();

  final DatabaseService databaseService = container.read(databaseServiceProvider);
  await databaseService.init();

  final AlarmHardwareService alarmHardwareService =
      container.read(alarmHardwareServiceProvider);
  await alarmHardwareService.initializeHardware();

  final AlarmRingingListener ringingListener = AlarmRingingListener(
    databaseService: databaseService,
    alarmStateNotifier: container.read(alarmStateProvider.notifier),
    resolveAyahContent: _resolveAyahContent,
  );
  ringingListener.start();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TarteelRiseApp(),
    ),
  );
}

/// Looks up this session's Ayah content from [QuranRepository] — Surah +
/// bookmark from [alarm]. Deliberately does NOT advance the bookmark here:
/// that only happens once [AlarmStateNotifier] confirms a validated
/// recitation, so a missed or failed morning re-reads the same ayahs
/// tomorrow instead of silently skipping ahead.
Future<AyahContent> _resolveAyahContent(AlarmModel alarm) async {
  const QuranRepository quranRepository = QuranRepository();
  final QuranSession session = quranRepository.buildSession(
    surahIndex: alarm.selectedSurahIndex,
    startAyah: alarm.currentBookmarkAyah,
    requestedAyahCount: alarm.numberOfAyahs,
  );

  return AyahContent(arabicText: session.arabicText, translation: session.translation);
}

class TarteelRiseApp extends StatelessWidget {
  const TarteelRiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tarteel Rise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AlarmDashboardScreen(),
    );
  }
}

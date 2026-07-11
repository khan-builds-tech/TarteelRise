import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/alarm_model.dart';
import 'providers/alarm_state_provider.dart';
import 'services/alarm_hardware_service.dart';
import 'services/alarm_ringing_listener.dart';
import 'services/database_service.dart';
import 'theme/app_theme.dart';
import 'ui/screens/alarm_active_screen.dart';

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
    resolveAyahContent: _resolvePlaceholderAyahContent,
  );
  ringingListener.start();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TarteelRiseApp(),
    ),
  );
}

/// Stands in for the Quran verse database (Section 4 of the product spec)
/// until that content layer — Surah lookup, bookmarking, per-alarm Ayah
/// selection — is built. Returns a real Ayah (Al-Fatiha, verse 1) rather
/// than dummy text, so the ringing -> reciting -> completed flow is fully
/// exercisable end to end in the meantime.
Future<AyahContent> _resolvePlaceholderAyahContent(AlarmModel alarm) async {
  return const AyahContent(
    arabicText: 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
    translation: 'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
  );
}

class TarteelRiseApp extends StatelessWidget {
  const TarteelRiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tarteel Rise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AlarmActiveScreen(),
    );
  }
}

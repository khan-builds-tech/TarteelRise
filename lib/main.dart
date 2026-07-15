import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/alarm_model.dart';
import 'models/alarm_state_enum.dart';
import 'providers/alarm_state_provider.dart';
import 'providers/dashboard_providers.dart';
import 'services/alarm_hardware_service.dart';
import 'services/alarm_ringing_listener.dart';
import 'services/database_service.dart';
import 'services/quran_repository.dart';
import 'theme/app_theme.dart';
import 'ui/screens/alarm_active_screen.dart';
import 'ui/screens/alarm_dashboard_screen.dart';

/// App-wide navigator access so a real alarm ringing (which can happen
/// while any screen is on top, or while the app is merely backgrounded)
/// can push [AlarmActiveScreen] itself, rather than relying on the state
/// machine's `ringing` transition to somehow be visible on its own.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// True while [AlarmActiveScreen] is the pushed, on-screen route — guards
/// against pushing a second copy if `ringing` fires again (or the ringing
/// stream re-emits) while it's already showing.
bool _isActiveAlarmScreenShowing = false;

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
  await alarmHardwareService.rescheduleAllEnabledAlarms(databaseService.getAllAlarms());
  await alarmHardwareService.requestBatteryOptimizationExemption();

  // Pre-warm the on-device speech engine so the first "Tap to Recite" during
  // a wake-up doesn't stall on a cold permission/init handshake.
  await container.read(speechServiceProvider).initializeSpeech();

  final AlarmRingingListener ringingListener = AlarmRingingListener(
    databaseService: databaseService,
    alarmStateNotifier: container.read(alarmStateProvider.notifier),
    resolveAyahContent: _resolveAyahContent,
  );
  ringingListener.start();

  // The one and only place that reacts to the state machine entering
  // `ringing` by actually SHOWING the wake-up screen. Without this, a real
  // alarm firing only ever changes background Riverpod state — the Adhan
  // plays natively regardless, but there is no way to reach the mic
  // button or stop it.
  container.listen<AlarmSessionState>(
    alarmStateProvider,
    (previous, next) {
      final bool enteringRinging = next.state == AlarmStateEnum.ringing &&
          previous?.state != AlarmStateEnum.ringing;
      if (enteringRinging && !_isActiveAlarmScreenShowing) {
        _isActiveAlarmScreenShowing = true;
        navigatorKey.currentState
            ?.push(MaterialPageRoute<void>(builder: (_) => const AlarmActiveScreen()))
            .then((_) {
          _isActiveAlarmScreenShowing = false;
          container.read(userStatsProvider.notifier).refresh();
          container.read(alarmListProvider.notifier).refresh();
        });
      }
    },
  );

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
      navigatorKey: navigatorKey,
      title: 'Tarteel Rise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AlarmDashboardScreen(),
    );
  }
}

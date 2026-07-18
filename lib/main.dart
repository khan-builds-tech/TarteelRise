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

  // Parses the ~2.3MB bundled Quran dataset off the synchronous call
  // stack (see QuranRepository.loadFromAssets) before any widget or the
  // ringing listener can ask for Surah/Ayah data — everything downstream
  // reads it synchronously thereafter.
  final QuranRepository quranRepository = container.read(quranRepositoryProvider);
  await quranRepository.loadFromAssets();

  // Pre-warm the on-device speech engine so the first "Tap to Recite" during
  // a wake-up doesn't stall on a cold permission/init handshake.
  await container.read(speechServiceProvider).initializeSpeech();

  final AlarmRingingListener ringingListener = AlarmRingingListener(
    databaseService: databaseService,
    alarmStateNotifier: container.read(alarmStateProvider.notifier),
    resolveAyahContent: (AlarmModel alarm) => _resolveAyahContent(alarm, quranRepository),
  );
  ringingListener.start();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TarteelRiseApp(),
    ),
  );
}

/// Looks up this session's Ayah content from [quranRepository] — Surah +
/// bookmark from [alarm]. Deliberately does NOT advance the bookmark here:
/// that only happens once [AlarmStateNotifier] confirms a validated
/// recitation, so a missed or failed morning re-reads the same ayahs
/// tomorrow instead of silently skipping ahead.
Future<AyahContent> _resolveAyahContent(
  AlarmModel alarm,
  QuranRepository quranRepository,
) async {
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
      home: const AppNavigationWrapper(),
    );
  }
}

/// Single source of truth for whole-app routing driven by
/// [alarmStateProvider]. `ref.listen` here — rather than a global
/// `NavigatorState` key — means routing reacts through the widget actually
/// mounted in the tree, so there's no window where a state transition
/// fires before the app's `Navigator` exists to receive it.
///
/// Whenever the state machine leaves `idle` (a real alarm ringing while the
/// app sits on the Dashboard, inside a pushed screen, or newly resumed from
/// the background — all indistinguishable to this listener, since it only
/// watches the state, never how the app got there) this hard-replaces the
/// *entire* navigation stack with [AlarmActiveScreen] via
/// `pushAndRemoveUntil`. That's deliberate, not just a stronger `push`:
/// leaving a stale Dashboard/Create-alarm screen underneath would let the
/// system back button pop straight past the recitation requirement. The
/// reverse transition (session finishes or resets) hard-replaces back to a
/// fresh [AlarmDashboardScreen] the same way, so the stack never
/// accumulates alarm-session routes across repeated wake-ups.
class AppNavigationWrapper extends ConsumerWidget {
  const AppNavigationWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AlarmStateEnum>(
      alarmStateProvider.select((AlarmSessionState s) => s.state),
      (AlarmStateEnum? previous, AlarmStateEnum next) {
        final bool wasIdle = previous == null || previous == AlarmStateEnum.idle;
        final bool isIdle = next == AlarmStateEnum.idle;
        if (wasIdle == isIdle) return;

        if (isIdle) {
          ref.read(userStatsProvider.notifier).refresh();
          ref.read(alarmListProvider.notifier).refresh();
        }

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) =>
                isIdle ? const AlarmDashboardScreen() : const AlarmActiveScreen(),
          ),
          (Route<void> route) => false,
        );
      },
    );
    return const AlarmDashboardScreen();
  }
}

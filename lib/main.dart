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
import 'ui/screens/streak_success_screen.dart';

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

/// Looks up this session's Ayah content from [quranRepository]: a fresh
/// random, short (see `QuranRepository.maxChallengeAyahWords`) verse from
/// [alarm]'s chosen Surah, picked anew every time the alarm rings.
Future<AyahContent> _resolveAyahContent(
  AlarmModel alarm,
  QuranRepository quranRepository,
) async {
  final QuranSession session =
      quranRepository.buildRandomChallenge(surahIndex: alarm.selectedSurahIndex);

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
/// Three routing rules, in priority order:
///  1. Entering `completed` (from any other non-idle state) hard-replaces
///     the stack with [StreakSuccessScreen] — a dedicated screen, not just
///     another case inside [AlarmActiveScreen]'s own `switch`, so there is
///     no route left underneath to accidentally navigate back into once
///     the recitation flow is actually finished.
///  2. Leaving `idle` (a real alarm ringing while the app sits on the
///     Dashboard, inside a pushed screen, or newly resumed from the
///     background — all indistinguishable to this listener, since it only
///     watches the state, never how the app got there) hard-replaces the
///     stack with [AlarmActiveScreen].
///  3. Returning to `idle` (finished, or reset) hard-replaces the stack
///     back to a fresh [AlarmDashboardScreen].
/// All three use `pushAndRemoveUntil`, deliberately, not just a stronger
/// `push`: leaving a stale Dashboard/Create-alarm/recitation screen
/// underneath would let the system back button pop straight past the
/// recitation requirement, and the stack must never accumulate
/// alarm-session routes across repeated wake-ups.
class AppNavigationWrapper extends ConsumerWidget {
  const AppNavigationWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AlarmStateEnum>(
      alarmStateProvider.select((AlarmSessionState s) => s.state),
      (AlarmStateEnum? previous, AlarmStateEnum next) {
        if (previous == next) return;

        if (next == AlarmStateEnum.completed && previous != AlarmStateEnum.completed) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const StreakSuccessScreen()),
            (Route<void> route) => false,
          );
          return;
        }

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

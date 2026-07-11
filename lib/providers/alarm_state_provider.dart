import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/active_alarm_session.dart';
import '../models/alarm_model.dart';
import '../models/alarm_state_enum.dart';
import '../services/alarm_hardware_service.dart';
import '../services/speech_service.dart';
import '../utils/arabic_utils.dart';

/// Provides the hardware-facing services the state machine drives as a
/// side effect of its own transitions (starting/stopping the mic, killing
/// the ringing Adhan once a recitation is validated).
final Provider<SpeechService> speechServiceProvider =
    Provider<SpeechService>((ref) => SpeechService());

final Provider<AlarmHardwareService> alarmHardwareServiceProvider =
    Provider<AlarmHardwareService>((ref) => AlarmHardwareService());

/// Match-percentage threshold required to clear each configured difficulty.
/// Mirrors the Difficulty Matrix in the product spec; unrecognized levels
/// fall back to Medium so a bad/missing config never blocks completion.
double _thresholdForDifficulty(String difficultyLevel) {
  switch (difficultyLevel) {
    case 'easy':
      return 65.0;
    case 'hard':
      return 95.0;
    case 'medium':
    default:
      return 80.0;
  }
}

/// Wraps the atomic [AlarmStateEnum] alongside the (optional) workspace for
/// whichever alarm session is currently active.
class AlarmSessionState {
  final AlarmStateEnum state;
  final ActiveAlarmSession? session;

  const AlarmSessionState({
    this.state = AlarmStateEnum.idle,
    this.session,
  });

  AlarmSessionState copyWith({
    AlarmStateEnum? state,
    ActiveAlarmSession? session,
  }) {
    return AlarmSessionState(
      state: state ?? this.state,
      session: session ?? this.session,
    );
  }
}

/// Drives the `idle -> ringing -> reciting -> completed` state machine.
/// Every transition is guarded by the state it must originate from, so a
/// stray or duplicate call (e.g. a double-tap on the mic button) can never
/// leave the session in an inconsistent state.
class AlarmStateNotifier extends StateNotifier<AlarmSessionState> {
  final SpeechService speechService;
  final AlarmHardwareService alarmHardwareService;

  AlarmStateNotifier({
    required this.speechService,
    required this.alarmHardwareService,
  }) : super(const AlarmSessionState());

  void triggerAlarmSession(
    AlarmModel alarm,
    String arabicText,
    String translation,
  ) {
    if (state.state != AlarmStateEnum.idle) return;

    state = AlarmSessionState(
      state: AlarmStateEnum.ringing,
      session: ActiveAlarmSession(
        activeAlarm: alarm,
        currentAyahArabic: arabicText,
        currentAyahTranslation: translation,
      ),
    );
  }

  Future<void> startVoiceCapture() async {
    if (state.state != AlarmStateEnum.ringing) return;

    final ActiveAlarmSession? session = state.session;
    state = state.copyWith(state: AlarmStateEnum.reciting);

    if (session != null) {
      await alarmHardwareService.duckAlarmForRecitation(
        AlarmHardwareService.nativeAlarmIdFor(session.activeAlarm.id),
      );
    }

    await speechService.startListeningToRecitation(processSpeechInput);
  }

  Future<void> processSpeechInput(String recognizedText) async {
    final ActiveAlarmSession? session = state.session;
    if (state.state != AlarmStateEnum.reciting || session == null) return;

    final double matchPercentage = calculateMatchPercentage(
      session.currentAyahArabic,
      recognizedText,
    );
    final ActiveAlarmSession updatedSession = session.copyWith(
      currentProgress: matchPercentage,
    );
    final double threshold = _thresholdForDifficulty(
      session.activeAlarm.difficultyLevel,
    );
    final bool cleared = matchPercentage >= threshold;

    state = AlarmSessionState(
      state: cleared ? AlarmStateEnum.completed : AlarmStateEnum.reciting,
      session: updatedSession,
    );

    if (cleared) {
      await _silenceAlarmOnCompletion(updatedSession.activeAlarm);
    }
  }

  /// Once a recitation clears the threshold, the mic is no longer needed
  /// and the ringing Adhan must be killed immediately — both wrapped so a
  /// hardware failure here can't strand the app on a silenced-looking but
  /// still-ringing alarm.
  Future<void> _silenceAlarmOnCompletion(AlarmModel alarm) async {
    await speechService.stopListening();
    await alarmHardwareService.stopActiveAlarmSound(
      AlarmHardwareService.nativeAlarmIdFor(alarm.id),
    );
  }

  void resetToIdle() {
    state = const AlarmSessionState();
  }
}

final StateNotifierProvider<AlarmStateNotifier, AlarmSessionState>
    alarmStateProvider =
    StateNotifierProvider<AlarmStateNotifier, AlarmSessionState>(
  (ref) => AlarmStateNotifier(
    speechService: ref.watch(speechServiceProvider),
    alarmHardwareService: ref.watch(alarmHardwareServiceProvider),
  ),
);

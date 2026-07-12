import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/surah_catalog.dart';
import '../models/active_alarm_session.dart';
import '../models/alarm_model.dart';
import '../models/alarm_state_enum.dart';
import '../services/alarm_hardware_service.dart';
import '../services/database_service.dart';
import '../services/speech_service.dart';
import '../utils/arabic_utils.dart';
import '../utils/bookmark_utils.dart';

/// Provides the hardware-facing services the state machine drives as a
/// side effect of its own transitions (starting/stopping the mic, killing
/// the ringing Adhan once a recitation is validated).
final Provider<SpeechService> speechServiceProvider =
    Provider<SpeechService>((ref) => SpeechService());

final Provider<AlarmHardwareService> alarmHardwareServiceProvider =
    Provider<AlarmHardwareService>((ref) => AlarmHardwareService());

/// `main()` reads this via a [ProviderContainer] to open the Hive boxes
/// before `runApp()`, and it stays the same instance for the rest of the
/// app's lifetime (e.g. the ringing -> state-machine bridge).
final Provider<DatabaseService> databaseServiceProvider =
    Provider<DatabaseService>((ref) => DatabaseService());

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
  final DatabaseService databaseService;

  AlarmStateNotifier({
    required this.speechService,
    required this.alarmHardwareService,
    required this.databaseService,
  }) : super(const AlarmSessionState()) {
    if (kDebugMode) {
      _seedMockRecitingSessionForPreview();
    }
  }

  // TEMPORARY — UI PREVIEW ONLY. Seeds a fake `reciting` session at
  // startup so the active-alarm layout (pulsing mic, Arabic text, live
  // match tracker) is visible without a real scheduled alarm or Quran
  // verse database driving it. Gated on `kDebugMode` so the Dart compiler
  // strips this out of release builds entirely. Remove once real alarm
  // scheduling + Ayah lookup call `triggerAlarmSession` for real.
  void _seedMockRecitingSessionForPreview() {
    final AlarmModel mockAlarm = AlarmModel(
      id: 'preview-mock-alarm',
      hour: 5,
      minute: 30,
      daysOfWeek: const [],
      isEnabled: true,
      selectedSurahIndex: 0,
      difficultyLevel: 'medium',
    );

    state = AlarmSessionState(
      state: AlarmStateEnum.reciting,
      session: ActiveAlarmSession(
        activeAlarm: mockAlarm,
        currentAyahArabic: 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
        currentAyahTranslation: 'It is You we worship and You we ask for help.',
        currentProgress: 0.0,
      ),
    );
  }

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

    final List<bool> wordFlags = matchedWordFlags(
      session.currentAyahArabic,
      recognizedText,
    );
    final double matchPercentage = calculateMatchPercentage(
      session.currentAyahArabic,
      recognizedText,
    );
    final ActiveAlarmSession updatedSession = session.copyWith(
      currentProgress: matchPercentage,
      matchedWordFlags: wordFlags,
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
      await databaseService.recordSuccessfulRecitation();
      await _advanceBookmark(updatedSession.activeAlarm);
    }
  }

  /// Advances the Surah bookmark only once a recitation is actually
  /// validated — a missed or failed morning re-reads the same ayahs
  /// tomorrow rather than silently skipping ahead. Recomputes the range
  /// from [alarm]'s still-unadvanced [AlarmModel.currentBookmarkAyah]
  /// (unchanged since [triggerAlarmSession], since bookmark advancement
  /// was deliberately removed from the ring-time content resolver).
  ///
  /// Deliberately uses the Surah's real ayah count from the catalog
  /// directly, rather than going through [QuranRepository.buildSession] —
  /// that silently substitutes Al-Fatiha for a Surah with no verse text
  /// seeded yet, which would advance the bookmark relative to Al-Fatiha's
  /// length instead of the Surah actually selected.
  Future<void> _advanceBookmark(AlarmModel alarm) async {
    final Surah surah = starterSurahCatalog.firstWhere(
      (candidate) => candidate.index == alarm.selectedSurahIndex,
      orElse: () => starterSurahCatalog.first,
    );

    final List<int> ayahNumbers = ayahNumbersForSession(
      startAyah: alarm.currentBookmarkAyah.clamp(1, surah.ayahCount),
      requestedCount: alarm.numberOfAyahs,
      totalAyahsInSurah: surah.ayahCount,
    );

    alarm.currentBookmarkAyah = computeNextBookmark(
      lastAyahRead: ayahNumbers.last,
      totalAyahsInSurah: surah.ayahCount,
    );
    await databaseService.saveAlarm(alarm);
  }

  /// The Emergency Snooze fallback: typing the English translation instead
  /// of reciting, for when the user genuinely cannot speak. Valid from
  /// `ringing` or `reciting` — wherever the alarm is still demanding
  /// interaction. Returns `false` (state untouched) if the typed text
  /// doesn't match, so the caller can show a retry prompt instead of
  /// silently doing nothing.
  ///
  /// Unlike a validated recitation, this breaks the streak rather than
  /// extending it — per the spec, this exists to preserve the app's
  /// integrity, not to be a free pass.
  Future<bool> submitEmergencyTranslationFallback(String typedTranslation) async {
    final ActiveAlarmSession? session = state.session;
    final bool validState =
        state.state == AlarmStateEnum.ringing || state.state == AlarmStateEnum.reciting;
    if (!validState || session == null) return false;

    final bool matches = _normalizeForComparison(typedTranslation) ==
        _normalizeForComparison(session.currentAyahTranslation);
    if (!matches) return false;

    final ActiveAlarmSession updatedSession = session.copyWith(
      completedViaEmergencyFallback: true,
    );

    state = AlarmSessionState(state: AlarmStateEnum.completed, session: updatedSession);

    await _silenceAlarmOnCompletion(updatedSession.activeAlarm);
    await databaseService.recordEmergencySnooze();

    return true;
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

  /// Lenient equality for the typed-translation fallback: case, leading/
  /// trailing whitespace, internal whitespace runs, and common trailing
  /// punctuation shouldn't fail a sleepy, correctly-typed answer.
  static String _normalizeForComparison(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.,!?;:]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

final StateNotifierProvider<AlarmStateNotifier, AlarmSessionState>
    alarmStateProvider =
    StateNotifierProvider<AlarmStateNotifier, AlarmSessionState>(
  (ref) => AlarmStateNotifier(
    speechService: ref.watch(speechServiceProvider),
    alarmHardwareService: ref.watch(alarmHardwareServiceProvider),
    databaseService: ref.watch(databaseServiceProvider),
  ),
);

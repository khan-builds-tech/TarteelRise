import 'dart:async';

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
import '../utils/translation_match_utils.dart';

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
/// Applies to both the Arabic Ayah and its English translation.
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

/// Drives the `idle -> ringing -> reciting -> recitingTranslation ->
/// completed` state machine. Every transition is guarded by the state it
/// must originate from, so a stray or duplicate call (e.g. a double-tap on
/// the mic button) can never leave the session in an inconsistent state.
class AlarmStateNotifier extends StateNotifier<AlarmSessionState> {
  final SpeechService speechService;
  final AlarmHardwareService alarmHardwareService;
  final DatabaseService databaseService;

  /// If the user doesn't reach `completed` within this long after starting
  /// to recite, the Adhan resumes and the session drops back to `ringing`.
  /// Overridable so tests don't have to wait out the real duration.
  final Duration resumeGracePeriod;

  Timer? _resumeTimer;

  AlarmStateNotifier({
    required this.speechService,
    required this.alarmHardwareService,
    required this.databaseService,
    this.resumeGracePeriod = const Duration(minutes: 4),
  }) : super(const AlarmSessionState());

  // TEMPORARY — DEBUG ONLY. Seeds a fake `reciting` session so the
  // active-alarm layout (pulsing mic, Arabic text, live match tracker) is
  // visible without a real scheduled alarm. Invoked explicitly from the
  // Dashboard debug button — not at startup — so debug builds can still
  // exercise the real `idle -> ringing` path when a native alarm fires.
  void seedPreviewSessionForDebug() {
    if (!kDebugMode) return;
    _seedMockRecitingSessionForPreview();
  }

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

    if (session != null) {
      await alarmHardwareService.duckAlarmForRecitation(
        AlarmHardwareService.nativeAlarmIdFor(session.activeAlarm.id),
      );
    }

    if (!speechService.isInitialized) {
      final bool speechReady = await speechService.initializeSpeech();
      if (!speechReady) {
        await alarmHardwareService.resumeAdhanPlayback();
        return;
      }
    }

    state = state.copyWith(state: AlarmStateEnum.reciting);
    _scheduleResumeIfIncomplete();
    await speechService.startListening(
      localePreferenceOrder: arabicLocalePreferenceOrder,
      onRecognized: processSpeechInput,
    );
  }

  /// Matches recognized speech against the Arabic Ayah. Once it clears the
  /// threshold, moves on to the translation-recitation gate rather than
  /// completing outright — the spec now requires the English translation
  /// to be recited too, not just displayed.
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

    if (matchPercentage < threshold) {
      state = AlarmSessionState(state: AlarmStateEnum.reciting, session: updatedSession);
      return;
    }

    state = AlarmSessionState(
      state: AlarmStateEnum.recitingTranslation,
      session: updatedSession,
    );

    // Switch the mic to English for the translation gate. Stopped first
    // rather than just calling `startListening` again, since starting a
    // fresh locale mid-stream on top of an active session isn't a
    // documented, reliable pattern for the underlying engine.
    await speechService.stopListening();
    await speechService.startListening(
      localePreferenceOrder: englishLocalePreferenceOrder,
      onRecognized: processTranslationSpeechInput,
    );
  }

  /// Matches recognized speech against the English translation — the
  /// second recitation gate, after the Arabic Ayah clears. Only once this
  /// also clears does the session actually reach `completed`: silence the
  /// alarm, record the streak, and advance the Surah bookmark.
  Future<void> processTranslationSpeechInput(String recognizedText) async {
    final ActiveAlarmSession? session = state.session;
    if (state.state != AlarmStateEnum.recitingTranslation || session == null) return;

    final List<bool> wordFlags = matchedTranslationWordFlags(
      session.currentAyahTranslation,
      recognizedText,
    );
    final double matchPercentage = calculateTranslationMatchPercentage(
      session.currentAyahTranslation,
      recognizedText,
    );
    final ActiveAlarmSession updatedSession = session.copyWith(
      translationProgress: matchPercentage,
      translationMatchedWordFlags: wordFlags,
    );
    final double threshold = _thresholdForDifficulty(
      session.activeAlarm.difficultyLevel,
    );
    final bool cleared = matchPercentage >= threshold;

    state = AlarmSessionState(
      state: cleared ? AlarmStateEnum.completed : AlarmStateEnum.recitingTranslation,
      session: updatedSession,
    );

    if (cleared) {
      _cancelResumeTimer();
      await _silenceAlarmOnCompletion(updatedSession.activeAlarm);
      await databaseService.recordSuccessfulRecitation();
      await _advanceBookmark(updatedSession.activeAlarm);
    }
  }

  /// If the user hasn't reached `completed` within [resumeGracePeriod] of
  /// starting to recite, abandon the current listen session and resume
  /// the Adhan — dropping back to `ringing` so they can tap to try again
  /// rather than the alarm silently staying dismissed forever.
  void _scheduleResumeIfIncomplete() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(resumeGracePeriod, _handleIncompleteTimeout);
  }

  void _cancelResumeTimer() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  Future<void> _handleIncompleteTimeout() async {
    if (state.state == AlarmStateEnum.completed || state.state == AlarmStateEnum.idle) {
      return;
    }

    await speechService.stopListening();
    await alarmHardwareService.resumeAdhanPlayback();
    state = state.copyWith(state: AlarmStateEnum.ringing);
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
  /// `ringing`, `reciting`, or `recitingTranslation` — wherever the alarm
  /// is still demanding interaction. Returns `false` (state untouched) if
  /// the typed text doesn't match, so the caller can show a retry prompt
  /// instead of silently doing nothing.
  ///
  /// Unlike a validated recitation, this breaks the streak rather than
  /// extending it — per the spec, this exists to preserve the app's
  /// integrity, not to be a free pass.
  Future<bool> submitEmergencyTranslationFallback(String typedTranslation) async {
    final ActiveAlarmSession? session = state.session;
    final bool validState = state.state == AlarmStateEnum.ringing ||
        state.state == AlarmStateEnum.reciting ||
        state.state == AlarmStateEnum.recitingTranslation;
    if (!validState || session == null) return false;

    final bool matches = _normalizeForComparison(typedTranslation) ==
        _normalizeForComparison(session.currentAyahTranslation);
    if (!matches) return false;

    final ActiveAlarmSession updatedSession = session.copyWith(
      completedViaEmergencyFallback: true,
    );

    _cancelResumeTimer();
    state = AlarmSessionState(state: AlarmStateEnum.completed, session: updatedSession);

    await _silenceAlarmOnCompletion(updatedSession.activeAlarm);
    await databaseService.recordEmergencySnooze();

    return true;
  }

  /// Once the flow is fully complete, the mic is no longer needed and the
  /// ringing (or resumed) Adhan must be killed immediately — both wrapped
  /// so a hardware failure here can't strand the app on a silenced-looking
  /// but still-ringing alarm.
  Future<void> _silenceAlarmOnCompletion(AlarmModel alarm) async {
    await speechService.stopListening();
    await alarmHardwareService.stopActiveAlarmSound(
      AlarmHardwareService.nativeAlarmIdFor(alarm.id),
    );
  }

  void resetToIdle() {
    _cancelResumeTimer();
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

  @override
  void dispose() {
    _resumeTimer?.cancel();
    super.dispose();
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

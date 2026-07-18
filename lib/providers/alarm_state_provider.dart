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
import '../utils/word_match_utils.dart';

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

  /// Shown on the wake-up screen when mic permission or speech init fails.
  final String? speechErrorMessage;

  /// True once the on-device speech engine is actively listening.
  final bool isMicActive;

  const AlarmSessionState({
    this.state = AlarmStateEnum.idle,
    this.session,
    this.speechErrorMessage,
    this.isMicActive = false,
  });

  AlarmSessionState copyWith({
    AlarmStateEnum? state,
    ActiveAlarmSession? session,
    String? speechErrorMessage,
    bool? isMicActive,
    bool clearSpeechError = false,
  }) {
    return AlarmSessionState(
      state: state ?? this.state,
      session: session ?? this.session,
      speechErrorMessage:
          clearSpeechError ? null : (speechErrorMessage ?? this.speechErrorMessage),
      isMicActive: isMicActive ?? this.isMicActive,
    );
  }
}

/// Drives the `idle -> ringing -> paused -> reciting -> recitingTranslation
/// -> completed` state machine. Every transition is guarded by the state it
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

  /// Accumulated, OR-merged word-match flags for the Arabic Ayah — the
  /// single source of truth both `session.currentProgress` (the progress
  /// bar) and `session.matchedWordFlags` (the per-word highlighting) are
  /// derived from on every `onResult` chunk, via [mergeWordMatchFlags] and
  /// [percentageFromFlags] respectively. Deliberately a field on the
  /// notifier itself, outside `ActiveAlarmSession` and the per-chunk
  /// `onResult` text buffer, so a transient empty-string or lower-scoring
  /// partial result between spoken words (the speech engine revising its
  /// whole-utterance hypothesis mid-stream is normal, expected behavior,
  /// not an error) can never un-highlight an already-recognized word or
  /// pull the progress bar back down — and deriving *both* from this one
  /// list, rather than ratcheting a percentage separately from whatever
  /// the latest raw chunk's flags happen to be, is what keeps the
  /// highlighted word count and the displayed percentage always in
  /// agreement instead of drifting apart.
  ///
  /// The only two places allowed to reset this back to empty are
  /// [triggerAlarmSession] (a brand new alarm ring, a different Ayah) and
  /// clearing into the translation gate in [processSpeechInput] (a
  /// different match target). A mic restart ([retryVoiceCapture]) or a
  /// grace-period timeout ([_handleIncompleteTimeout]) must never touch it.
  List<bool> _accumulatedArabicWordFlags = const <bool>[];

  /// Same ratchet as [_accumulatedArabicWordFlags], for the English
  /// translation gate (`session.translationProgress` /
  /// `session.translationMatchedWordFlags`). Reset only in
  /// [processSpeechInput] the moment the translation gate is freshly
  /// entered.
  List<bool> _accumulatedTranslationWordFlags = const <bool>[];

  AlarmStateNotifier({
    required this.speechService,
    required this.alarmHardwareService,
    required this.databaseService,
    this.resumeGracePeriod = const Duration(minutes: 4),
  }) : super(const AlarmSessionState());

  // TEMPORARY — DEBUG ONLY. Seeds a fake `paused` session so the two-step
  // wake-up layout can be exercised without a real scheduled alarm.
  void seedPreviewSessionForDebug() {
    if (!kDebugMode) return;

    _accumulatedArabicWordFlags = const <bool>[];
    _accumulatedTranslationWordFlags = const <bool>[];

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
      state: AlarmStateEnum.paused,
      session: ActiveAlarmSession(
        activeAlarm: mockAlarm,
        currentAyahArabic: 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
        currentAyahTranslation: 'It is You we worship and You we ask for help.',
      ),
    );
  }

  static const String _micPermissionError =
      'Microphone access is required. Allow it in Settings, then tap Start Reciting again.';

  /// Includes the native engine's own error code (e.g.
  /// `error_language_not_supported` — no on-device model for this locale
  /// on this device) when available, since "could not open the mic" alone
  /// isn't actionable — this is what tells us (or the user, reporting
  /// back) *why*.
  String _micStartErrorMessage() {
    const String base =
        'Could not open the microphone. Tap the mic button to try again, or use Emergency Snooze.';
    final String? nativeError = speechService.lastErrorMessage;
    return nativeError == null ? base : '$base\n(engine: $nativeError)';
  }

  void triggerAlarmSession(
    AlarmModel alarm,
    String arabicText,
    String translation,
  ) {
    if (state.state != AlarmStateEnum.idle) return;

    // A brand new alarm ring for a brand new Ayah — the only legitimate
    // reset point for both ratchets. Everything else in this class (mic
    // restarts, grace-period timeouts) must leave them untouched.
    _accumulatedArabicWordFlags = const <bool>[];
    _accumulatedTranslationWordFlags = const <bool>[];

    state = AlarmSessionState(
      state: AlarmStateEnum.ringing,
      session: ActiveAlarmSession(
        activeAlarm: alarm,
        currentAyahArabic: arabicText,
        currentAyahTranslation: translation,
      ),
    );
  }

  /// Step one of the wake-up flow: silence the Adhan and reveal the Ayah
  /// so the user can read it before opening the microphone.
  Future<void> pauseAdhanForReview() async {
    if (state.state != AlarmStateEnum.ringing) return;

    final ActiveAlarmSession? session = state.session;
    if (session != null) {
      await alarmHardwareService.duckAlarmForRecitation(
        AlarmHardwareService.nativeAlarmIdFor(session.activeAlarm.id),
      );
      // `ringing` isn't only reached via a fresh alarm (the id stopped
      // above) — it's also reached when the Dead Man's Switch itself
      // fires and resumes the Adhan under its own, *different* native
      // alarm id. Without also stopping that one, tapping "Pause Adhan"
      // after a switch-triggered resume silences nothing audible and
      // looks like the button doesn't work. Unconditional and harmless —
      // a no-op if nothing is scheduled under this id.
      await alarmHardwareService.cancelDeadMansSwitchAlarm(session.activeAlarm.id);
    }

    state = state.copyWith(state: AlarmStateEnum.paused);
  }

  /// How much later than [resumeGracePeriod] the native Dead Man's Switch
  /// is allowed to fire — enough slack that, under normal conditions (the
  /// Dart isolate alive and responsive), `_handleIncompleteTimeout`'s own
  /// cancel call reliably lands before the native alarm's delivery, so the
  /// switch is only ever the actual backup, never a second, competing
  /// deadline.
  static const Duration _deadMansSwitchBuffer = Duration(seconds: 15);

  /// Step two: open the microphone once the user is ready to recite. Only
  /// valid from [AlarmStateEnum.paused] — the Adhan must already be silent.
  Future<void> startVoiceCapture() async {
    if (state.state != AlarmStateEnum.paused) return;

    if (!await _ensureSpeechReady()) {
      state = state.copyWith(speechErrorMessage: _micPermissionError);
      return;
    }

    state = state.copyWith(
      state: AlarmStateEnum.reciting,
      clearSpeechError: true,
      isMicActive: false,
    );
    _scheduleResumeIfIncomplete();

    // Belt-and-suspenders with `_scheduleResumeIfIncomplete`: that Dart
    // `Timer` only fires if this isolate is still alive and scheduled in
    // time when the grace period lapses — not guaranteed if the app is
    // killed, or merely throttled by the OS while backgrounded. This native
    // alarm is the Dead Man's Switch that fires regardless. Best-effort and
    // unawaited — starting the mic can't stall on a native scheduling call.
    //
    // `fallbackDelay` deliberately matches `resumeGracePeriod` (plus a
    // small buffer) rather than some shorter, independent duration — a
    // fallback that fires *before* the actual grace period lapses would
    // resume the Adhan mid-recitation while the user is still legitimately
    // reciting successfully.
    final ActiveAlarmSession? armingSession = state.session;
    if (armingSession != null) {
      unawaited(alarmHardwareService.scheduleDeadMansSwitchAlarm(
        armingSession.activeAlarm,
        fallbackDelay: resumeGracePeriod + _deadMansSwitchBuffer,
      ));
    }

    final bool listening = await speechService.startListening(
      localePreferenceOrder: arabicLocalePreferenceOrder,
      onRecognized: processSpeechInput,
    );

    if (!listening) {
      _cancelResumeTimer();
      state = state.copyWith(
        state: AlarmStateEnum.paused,
        speechErrorMessage: _micStartErrorMessage(),
        isMicActive: false,
      );
      // The mic never actually opened, so there's no recitation grace
      // period running — disarm the switch armed above, or it would fire
      // a minute later against a session that's just sitting in `paused`.
      if (armingSession != null) {
        unawaited(alarmHardwareService.cancelDeadMansSwitchAlarm(armingSession.activeAlarm.id));
      }
      return;
    }

    state = state.copyWith(isMicActive: true);
  }

  /// Re-opens the microphone if recognition stalled, or the user tapped the
  /// pulsing mic while already in a recitation phase.
  Future<void> retryVoiceCapture() async {
    if (state.state != AlarmStateEnum.reciting &&
        state.state != AlarmStateEnum.recitingTranslation) {
      return;
    }

    if (!await _ensureSpeechReady()) {
      state = state.copyWith(speechErrorMessage: _micPermissionError);
      return;
    }

    state = state.copyWith(clearSpeechError: true, isMicActive: false);

    final bool listening = state.state == AlarmStateEnum.recitingTranslation
        ? await speechService.startListening(
            localePreferenceOrder: englishLocalePreferenceOrder,
            onRecognized: processTranslationSpeechInput,
          )
        : await speechService.startListening(
            localePreferenceOrder: arabicLocalePreferenceOrder,
            onRecognized: processSpeechInput,
          );

    state = state.copyWith(
      isMicActive: listening,
      clearSpeechError: listening,
      speechErrorMessage: listening ? null : _micStartErrorMessage(),
    );
  }

  Future<bool> _ensureSpeechReady() async {
    if (speechService.isInitialized) {
      return true;
    }
    return speechService.initializeSpeech();
  }

  /// Returns to [AlarmStateEnum.ringing] and resumes the Adhan loop if the
  /// user isn't ready to recite yet after pausing.
  Future<void> resumeAdhanFromReview() async {
    if (state.state != AlarmStateEnum.paused) return;

    await alarmHardwareService.resumeAdhanPlayback();
    state = state.copyWith(state: AlarmStateEnum.ringing);
  }

  /// Matches recognized speech against the Arabic Ayah. Once it clears the
  /// threshold, moves on to the translation-recitation gate rather than
  /// completing outright — the spec now requires the English translation
  /// to be recited too, not just displayed.
  Future<void> processSpeechInput(String recognizedText) async {
    final ActiveAlarmSession? session = state.session;
    if (state.state != AlarmStateEnum.reciting || session == null) return;

    // The strict maximum-value lock: merge this chunk's flags into the
    // running total (once a word is `true` it stays `true`), then derive
    // BOTH the per-word highlighting and the percentage from that same
    // merged list — never from this chunk's raw flags alone — so the two
    // can never disagree, and neither can be pulled down by an
    // empty-string or lower-scoring partial result between spoken words.
    final List<bool> chunkFlags = matchedWordFlags(
      session.currentAyahArabic,
      recognizedText,
    );
    _accumulatedArabicWordFlags =
        mergeWordMatchFlags(_accumulatedArabicWordFlags, chunkFlags);
    final double score = percentageFromFlags(_accumulatedArabicWordFlags);

    final ActiveAlarmSession updatedSession = session.copyWith(
      currentProgress: score,
      matchedWordFlags: _accumulatedArabicWordFlags,
    );
    final double threshold = _thresholdForDifficulty(
      session.activeAlarm.difficultyLevel,
    );

    if (score < threshold) {
      state = AlarmSessionState(
        state: AlarmStateEnum.reciting,
        session: updatedSession,
        isMicActive: true,
      );
      return;
    }

    // Freshly entering the translation gate — a different match target,
    // so its own ratchet starts clean rather than inheriting whatever the
    // Arabic gate happened to reach.
    _accumulatedTranslationWordFlags = const <bool>[];

    state = AlarmSessionState(
      state: AlarmStateEnum.recitingTranslation,
      session: updatedSession,
      isMicActive: false,
    );

    // Switch the mic to English for the translation gate. Stopped first
    // rather than just calling `startListening` again, since starting a
    // fresh locale mid-stream on top of an active session isn't a
    // documented, reliable pattern for the underlying engine.
    await speechService.stopListening();
    final bool listening = await speechService.startListening(
      localePreferenceOrder: englishLocalePreferenceOrder,
      onRecognized: processTranslationSpeechInput,
    );
    state = state.copyWith(
      isMicActive: listening,
      clearSpeechError: listening,
      speechErrorMessage: listening ? null : _micStartErrorMessage(),
    );
  }

  /// Matches recognized speech against the English translation — the
  /// second recitation gate, after the Arabic Ayah clears. Only once this
  /// also clears does the session actually reach `completed`: silence the
  /// alarm, record the streak, and advance the Surah bookmark.
  Future<void> processTranslationSpeechInput(String recognizedText) async {
    final ActiveAlarmSession? session = state.session;
    if (state.state != AlarmStateEnum.recitingTranslation || session == null) return;

    // Same strict maximum-value lock as the Arabic gate: merge into the
    // running total and derive both the highlighting and the percentage
    // from that one merged list, so they can never disagree or be pulled
    // down by a lower-scoring/empty-string partial result.
    final List<bool> chunkFlags = matchedTranslationWordFlags(
      session.currentAyahTranslation,
      recognizedText,
    );
    _accumulatedTranslationWordFlags =
        mergeWordMatchFlags(_accumulatedTranslationWordFlags, chunkFlags);
    final double score = percentageFromFlags(_accumulatedTranslationWordFlags);

    final ActiveAlarmSession updatedSession = session.copyWith(
      translationProgress: score,
      translationMatchedWordFlags: _accumulatedTranslationWordFlags,
    );
    final double threshold = _thresholdForDifficulty(
      session.activeAlarm.difficultyLevel,
    );
    final bool cleared = score >= threshold;

    state = AlarmSessionState(
      state: cleared ? AlarmStateEnum.completed : AlarmStateEnum.recitingTranslation,
      session: updatedSession,
      isMicActive: !cleared,
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
  /// the Adhan — dropping back to `ringing` so they can pause and try
  /// again rather than the alarm silently staying dismissed forever.
  void _scheduleResumeIfIncomplete() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(resumeGracePeriod, _handleIncompleteTimeout);
  }

  void _cancelResumeTimer() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  Future<void> _handleIncompleteTimeout() async {
    final ActiveAlarmSession? session = state.session;
    if (state.state == AlarmStateEnum.completed || state.state == AlarmStateEnum.idle) {
      return;
    }

    await speechService.stopListening();
    await alarmHardwareService.resumeAdhanPlayback();
    state = state.copyWith(state: AlarmStateEnum.ringing);

    // This Dart timer firing on schedule means the isolate was alive and
    // responsive — the whole point of the native Dead Man's Switch armed
    // in `startVoiceCapture` is to cover the case where it *wasn't*.
    // Disarm it now so it doesn't also fire moments later and interrupt
    // this already-recovered session with a second, redundant wake-up.
    if (session != null) {
      await alarmHardwareService.cancelDeadMansSwitchAlarm(session.activeAlarm.id);
    }
  }

  /// Reacts to the native Dead Man's Switch itself firing (see
  /// `startVoiceCapture`/`AlarmHardwareService.scheduleDeadMansSwitchAlarm`)
  /// — meaning [resumeGracePeriod] (plus [_deadMansSwitchBuffer]) lapsed
  /// *without* [_handleIncompleteTimeout] catching it first, which only
  /// happens if
  /// this isolate died or was throttled sometime after the switch was
  /// armed. By the time this runs, the native alarm has already
  /// independently resumed the Adhan and, via its full-screen intent,
  /// forced the lock-screen wake-up UI back into focus — native, not
  /// something this method needs to do.
  ///
  /// Two possible situations reach here, and the existing `idle`-only
  /// guard on [triggerAlarmSession] is what tells them apart:
  ///  - The app is still alive (a slow/throttled isolate, not a kill): the
  ///    in-memory session survived, so `state.state` is whatever
  ///    mid-recitation phase it was in. This drops it back to `ringing`,
  ///    same as [_handleIncompleteTimeout] — but deliberately does NOT
  ///    call `resumeAdhanPlayback` too, since the native alarm that just
  ///    fired is already playing the Adhan; a second local player would
  ///    double the audio.
  ///  - The app was actually killed: this is a fresh [AlarmStateNotifier],
  ///    defaulting to `idle`, with no session left to reconcile — so this
  ///    is functionally a normal ring, and hands off to
  ///    [triggerAlarmSession] to show the wake-up screen from scratch for
  ///    the same alarm and Ayah.
  void handleDeadMansSwitchFired(
    AlarmModel alarm,
    String arabicText,
    String translation,
  ) {
    if (state.state == AlarmStateEnum.idle) {
      triggerAlarmSession(alarm, arabicText, translation);
      return;
    }

    if (state.state == AlarmStateEnum.completed) return;

    _cancelResumeTimer();
    speechService.stopListening();
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
        state.state == AlarmStateEnum.paused ||
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
  /// but still-ringing alarm. Also disarms the Dead Man's Switch armed in
  /// [startVoiceCapture] — a validated recitation or Emergency Snooze
  /// reaching here means the session is genuinely over, so the safety-net
  /// alarm must be cancelled "along with the parent alarm session" rather
  /// than fire a minute later against a session that no longer exists.
  Future<void> _silenceAlarmOnCompletion(AlarmModel alarm) async {
    await speechService.stopListening();
    await alarmHardwareService.stopActiveAlarmSound(
      AlarmHardwareService.nativeAlarmIdFor(alarm.id),
    );
    await alarmHardwareService.cancelDeadMansSwitchAlarm(alarm.id);
  }

  void resetToIdle() {
    final ActiveAlarmSession? session = state.session;
    _cancelResumeTimer();
    speechService.stopListening();
    state = const AlarmSessionState();
    if (session != null) {
      unawaited(alarmHardwareService.cancelDeadMansSwitchAlarm(session.activeAlarm.id));
    }
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

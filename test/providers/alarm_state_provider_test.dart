import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/models/alarm_model.dart';
import 'package:tarteel_rise/models/alarm_state_enum.dart';
import 'package:tarteel_rise/providers/alarm_state_provider.dart';
import 'package:tarteel_rise/services/alarm_hardware_service.dart';
import 'package:tarteel_rise/services/database_service.dart';
import 'package:tarteel_rise/services/speech_service.dart';

const String _alFatihaAyahsOneAndTwo =
    'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ';
const String _placeholderTranslation = 'It is You we worship and You we ask for help.';

/// [AlarmHardwareService.resumeAdhanPlayback] goes through real
/// `just_audio`, which has no plugin implementation in a plain Dart test
/// and fails in ways that escape a surrounding try/catch (its own internal
/// dispose/init sequencing runs in a separate zone). What the
/// resume-timeout test actually needs to verify is the state machine's own
/// behavior — that it calls resume and drops back to `ringing` — not
/// `just_audio`'s plugin behavior, so this fakes just that one call.
class _FakeAlarmHardwareService extends AlarmHardwareService {
  bool resumeAdhanPlaybackCalled = false;

  /// Alarm ids passed to [cancelDeadMansSwitchAlarm], in call order — lets
  /// tests confirm the fallback alarm is actually disarmed at every exit
  /// point, in particular `pauseAdhanForReview` (see the regression test
  /// for "Pause Adhan silences nothing after a Dead Man's Switch resume").
  final List<String> cancelledDeadMansSwitchAlarmIds = <String>[];

  /// The [fallbackDelay] passed to the most recent [scheduleDeadMansSwitchAlarm]
  /// call — lets tests confirm it tracks the notifier's own grace period
  /// rather than a hardcoded, independent duration.
  Duration? lastScheduledFallbackDelay;

  _FakeAlarmHardwareService() : super(nativeCallTimeout: const Duration(milliseconds: 50));

  @override
  Future<void> resumeAdhanPlayback() async {
    resumeAdhanPlaybackCalled = true;
  }

  @override
  Future<bool> cancelDeadMansSwitchAlarm(String alarmId) async {
    cancelledDeadMansSwitchAlarmIds.add(alarmId);
    return true;
  }

  @override
  Future<bool> scheduleDeadMansSwitchAlarm(
    AlarmModel alarmSettings, {
    required Duration fallbackDelay,
  }) async {
    lastScheduledFallbackDelay = fallbackDelay;
    return true;
  }
}

/// The real [SpeechService] needs a platform channel that plain Dart tests
/// don't have — without this fake, [AlarmStateNotifier.startVoiceCapture]
/// rolls back to `ringing` when init fails.
class _FakeSpeechService extends SpeechService {
  @override
  bool get isInitialized => true;

  @override
  Future<bool> initializeSpeech() async => true;

  @override
  Future<bool> startListening({
    required List<String> localePreferenceOrder,
    required void Function(String recognizedText) onRecognized,
  }) async => true;

  @override
  Future<void> stopListening() async {}
}

void main() {
  late Directory tempHiveDir;
  late DatabaseService databaseService;

  AlarmStateNotifier buildNotifier({
    Duration? resumeGracePeriod,
    AlarmHardwareService? alarmHardwareService,
    SpeechService? speechService,
  }) {
    final AlarmStateNotifier notifier = AlarmStateNotifier(
      speechService: speechService ?? _FakeSpeechService(),
      alarmHardwareService: alarmHardwareService ??
          AlarmHardwareService(nativeCallTimeout: const Duration(milliseconds: 50)),
      databaseService: databaseService,
      resumeGracePeriod: resumeGracePeriod ?? const Duration(minutes: 4),
    );
    // Reset to a clean `idle` state so each test drives the machine from
    // the top via its own `triggerAlarmSession` call.
    notifier.resetToIdle();
    return notifier;
  }

  setUp(() async {
    tempHiveDir = Directory.systemTemp.createTempSync('bookmark_timing_test_hive');
    databaseService = DatabaseService();
    await databaseService.init(testHiveDirectoryPath: tempHiveDir.path);
  });

  tearDown(() {
    tempHiveDir.deleteSync(recursive: true);
  });

  AlarmModel buildAlFatihaAlarm({int currentBookmarkAyah = 1}) {
    return AlarmModel(
      id: 'bookmark-test-alarm',
      hour: 5,
      minute: 30,
      daysOfWeek: const [],
      isEnabled: true,
      selectedSurahIndex: 1, // Al-Fatiha: 7 ayahs, real seeded verse text.
      numberOfAyahs: 2,
      difficultyLevel: 'easy',
      currentBookmarkAyah: currentBookmarkAyah,
    );
  }

  /// Mirrors the two-step wake-up flow: pause the Adhan, then open the mic.
  Future<void> beginReciting(AlarmStateNotifier notifier) async {
    await notifier.pauseAdhanForReview();
    await notifier.startVoiceCapture();
  }

  test('pauseAdhanForReview silences the Adhan and reveals the Ayah without opening the mic',
      () async {
    final AlarmStateNotifier notifier = buildNotifier();
    final AlarmModel alarm = buildAlFatihaAlarm();

    notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
    await notifier.pauseAdhanForReview();

    expect(notifier.state.state, AlarmStateEnum.paused);
    expect(notifier.state.session?.currentAyahArabic, _alFatihaAyahsOneAndTwo);
  });

  test('resumeAdhanFromReview returns to ringing and resumes playback', () async {
    final _FakeAlarmHardwareService fakeHardware = _FakeAlarmHardwareService();
    final AlarmStateNotifier notifier = buildNotifier(alarmHardwareService: fakeHardware);
    final AlarmModel alarm = buildAlFatihaAlarm();

    notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
    await notifier.pauseAdhanForReview();
    await notifier.resumeAdhanFromReview();

    expect(fakeHardware.resumeAdhanPlaybackCalled, isTrue);
    expect(notifier.state.state, AlarmStateEnum.ringing);
  });

  test('clearing the Arabic Ayah moves to recitingTranslation, not completed', () async {
    final AlarmStateNotifier notifier = buildNotifier();
    final AlarmModel alarm = buildAlFatihaAlarm();
    await databaseService.saveAlarm(alarm);

    notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
    await beginReciting(notifier);
    await notifier.processSpeechInput(_alFatihaAyahsOneAndTwo);

    expect(notifier.state.state, AlarmStateEnum.recitingTranslation);

    // Neither the streak nor the bookmark should move yet — only the
    // Arabic half of the flow has cleared.
    final AlarmModel persisted =
        databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
    expect(persisted.currentBookmarkAyah, 1);
  });

  test(
    'advances the bookmark and records the streak only after BOTH the Ayah and its translation clear',
    () async {
      final AlarmStateNotifier notifier = buildNotifier();
      final AlarmModel alarm = buildAlFatihaAlarm();
      await databaseService.saveAlarm(alarm);

      notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
      await beginReciting(notifier);
      await notifier.processSpeechInput(_alFatihaAyahsOneAndTwo);
      await notifier.processTranslationSpeechInput(_placeholderTranslation);

      expect(notifier.state.state, AlarmStateEnum.completed);

      final AlarmModel persisted =
          databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
      // Started at ayah 1, read 2 ayahs (1-2), should resume from ayah 3.
      expect(persisted.currentBookmarkAyah, 3);
    },
  );

  test('leaves the bookmark untouched when the Arabic is never recognized', () async {
    final AlarmStateNotifier notifier = buildNotifier();
    final AlarmModel alarm = buildAlFatihaAlarm();
    await databaseService.saveAlarm(alarm);

    notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
    await beginReciting(notifier);
    await notifier.processSpeechInput('completely unrelated speech');

    expect(notifier.state.state, AlarmStateEnum.reciting);
    final AlarmModel persisted =
        databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
    expect(persisted.currentBookmarkAyah, 1);
  });

  test(
    'the Arabic progress bar holds its peak instead of dropping when a later partial '
    'result (e.g. a pause between words) scores lower or comes back empty',
    () async {
      final AlarmStateNotifier notifier = buildNotifier();
      final AlarmModel alarm = buildAlFatihaAlarm(); // 'easy' difficulty -> 65% threshold.
      await databaseService.saveAlarm(alarm);

      notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
      await beginReciting(notifier);

      // 4 of the Ayah's 8 words -> 50%, below Easy's 65% threshold.
      await notifier.processSpeechInput('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ');
      expect(notifier.state.state, AlarmStateEnum.reciting);
      expect(notifier.state.session?.currentProgress, 50.0);

      // The speech engine revises its whole-utterance hypothesis down to
      // nothing between spoken words — a real, expected occurrence, not an
      // error. The ratchet must hold at the peak already reached.
      await notifier.processSpeechInput('');
      expect(notifier.state.state, AlarmStateEnum.reciting);
      expect(notifier.state.session?.currentProgress, 50.0);

      // 6 of 8 words -> 75%, clears the threshold from the ratcheted peak.
      await notifier.processSpeechInput(
        'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ',
      );
      expect(notifier.state.state, AlarmStateEnum.recitingTranslation);
      expect(notifier.state.session?.currentProgress, 75.0);
      // The translation gate's own ratchet starts clean, not inheriting
      // the Arabic gate's peak.
      expect(notifier.state.session?.translationProgress, 0.0);
    },
  );

  test(
    'word highlighting and the progress percentage always agree, and a '
    'partial result never un-highlights an already-recognized word',
    () async {
      final AlarmStateNotifier notifier = buildNotifier();
      final AlarmModel alarm = buildAlFatihaAlarm();
      await databaseService.saveAlarm(alarm);

      notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
      await beginReciting(notifier);

      // Word 1 ('بِسْمِ') and word 4 ('الرَّحِيمِ') recognized, out of order —
      // 2 of 8 words -> 25%.
      await notifier.processSpeechInput('الرَّحِيمِ بِسْمِ');
      List<bool>? flags = notifier.state.session?.matchedWordFlags;
      expect(flags, <bool>[true, false, false, true, false, false, false, false]);
      expect(
        notifier.state.session?.currentProgress,
        100.0 * flags!.where((f) => f).length / flags.length,
      );

      // The engine's whole-utterance hypothesis drops to nothing between
      // words — the already-highlighted words must stay highlighted, not
      // revert, even momentarily.
      await notifier.processSpeechInput('');
      flags = notifier.state.session?.matchedWordFlags;
      expect(flags, <bool>[true, false, false, true, false, false, false, false]);
      expect(notifier.state.session?.currentProgress, 25.0);

      // Words 2 and 3 ('اللَّهِ', 'الرَّحْمَٰنِ') now also recognized —
      // merges with the earlier peak rather than replacing it: 4 of 8 -> 50%.
      await notifier.processSpeechInput('اللَّهِ الرَّحْمَٰنِ');
      flags = notifier.state.session?.matchedWordFlags;
      expect(flags, <bool>[true, true, true, true, false, false, false, false]);
      expect(
        notifier.state.session?.currentProgress,
        100.0 * flags!.where((f) => f).length / flags.length,
      );
    },
  );

  test(
    'leaves the bookmark untouched when the Ayah clears but the translation never does',
    () async {
      final AlarmStateNotifier notifier = buildNotifier();
      final AlarmModel alarm = buildAlFatihaAlarm();
      await databaseService.saveAlarm(alarm);

      notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
      await beginReciting(notifier);
      await notifier.processSpeechInput(_alFatihaAyahsOneAndTwo);
      await notifier.processTranslationSpeechInput('completely unrelated speech');

      expect(notifier.state.state, AlarmStateEnum.recitingTranslation);
      final AlarmModel persisted =
          databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
      expect(persisted.currentBookmarkAyah, 1);
    },
  );

  test('leaves the bookmark untouched on an Emergency Snooze', () async {
    final AlarmStateNotifier notifier = buildNotifier();
    final AlarmModel alarm = buildAlFatihaAlarm();
    await databaseService.saveAlarm(alarm);

    notifier.triggerAlarmSession(alarm, 'أي آية', _placeholderTranslation);

    final bool accepted =
        await notifier.submitEmergencyTranslationFallback(_placeholderTranslation);

    expect(accepted, isTrue);
    final AlarmModel persisted =
        databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
    expect(persisted.currentBookmarkAyah, 1);
  });

  test('Emergency Snooze also works during the translation-recitation phase', () async {
    final AlarmStateNotifier notifier = buildNotifier();
    final AlarmModel alarm = buildAlFatihaAlarm();
    await databaseService.saveAlarm(alarm);

    notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
    await beginReciting(notifier);
    await notifier.processSpeechInput(_alFatihaAyahsOneAndTwo);
    expect(notifier.state.state, AlarmStateEnum.recitingTranslation);

    final bool accepted =
        await notifier.submitEmergencyTranslationFallback(_placeholderTranslation);

    expect(accepted, isTrue);
    expect(notifier.state.state, AlarmStateEnum.completed);
    expect(notifier.state.session?.completedViaEmergencyFallback, isTrue);
  });

  test('wraps the bookmark back to 1 once the Surah is exhausted', () async {
    final AlarmStateNotifier notifier = buildNotifier();
    final AlarmModel alarm = buildAlFatihaAlarm(currentBookmarkAyah: 6);
    await databaseService.saveAlarm(alarm);

    const String ayahsSixAndSeven =
        'اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ';

    notifier.triggerAlarmSession(alarm, ayahsSixAndSeven, _placeholderTranslation);
    await beginReciting(notifier);
    await notifier.processSpeechInput(ayahsSixAndSeven);
    await notifier.processTranslationSpeechInput(_placeholderTranslation);

    final AlarmModel persisted =
        databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
    // Started at ayah 6 (of 7), requested 2 -> clamped to [6, 7] -> wraps to 1.
    expect(persisted.currentBookmarkAyah, 1);
  });

  test(
    'resumes the Adhan and drops back to ringing if the flow is not completed in time',
    () async {
      final _FakeAlarmHardwareService fakeHardware = _FakeAlarmHardwareService();
      final AlarmStateNotifier notifier = buildNotifier(
        resumeGracePeriod: const Duration(milliseconds: 30),
        alarmHardwareService: fakeHardware,
      );
      final AlarmModel alarm = buildAlFatihaAlarm();
      await databaseService.saveAlarm(alarm);

      notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
      await beginReciting(notifier);
      expect(notifier.state.state, AlarmStateEnum.reciting);

      // Never recite anything — let the grace period lapse.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fakeHardware.resumeAdhanPlaybackCalled, isTrue);
      expect(notifier.state.state, AlarmStateEnum.ringing);
      // The session survives the timeout so the user can pause and try again.
      expect(notifier.state.session?.currentAyahArabic, _alFatihaAyahsOneAndTwo);
    },
  );

  test(
    "arms the native safety-net alarm for the actual grace period, not a shorter "
    "independent duration that would fire mid-recitation",
    () async {
      final _FakeAlarmHardwareService fakeHardware = _FakeAlarmHardwareService();
      const Duration gracePeriod = Duration(minutes: 4);
      final AlarmStateNotifier notifier = buildNotifier(
        resumeGracePeriod: gracePeriod,
        alarmHardwareService: fakeHardware,
      );
      final AlarmModel alarm = buildAlFatihaAlarm();

      notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
      await beginReciting(notifier);

      expect(
        fakeHardware.lastScheduledFallbackDelay,
        gracePeriod + const Duration(seconds: 15),
      );
    },
  );

  test(
    "pausing the Adhan after the safety-net alarm resumed it actually silences it, "
    "not just the primary alarm id",
    () async {
      final _FakeAlarmHardwareService fakeHardware = _FakeAlarmHardwareService();
      final AlarmStateNotifier notifier = buildNotifier(alarmHardwareService: fakeHardware);
      final AlarmModel alarm = buildAlFatihaAlarm();

      notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
      await beginReciting(notifier);

      // Simulates the native safety-net alarm firing and resuming the
      // Adhan under its own, different native id while the app is still
      // alive and mid-recitation.
      notifier.handleDeadMansSwitchFired(
        alarm,
        _alFatihaAyahsOneAndTwo,
        _placeholderTranslation,
      );
      expect(notifier.state.state, AlarmStateEnum.ringing);

      fakeHardware.cancelledDeadMansSwitchAlarmIds.clear();
      await notifier.pauseAdhanForReview();

      expect(fakeHardware.cancelledDeadMansSwitchAlarmIds, contains(alarm.id));
      expect(notifier.state.state, AlarmStateEnum.paused);
    },
  );

  test('does not resume the Adhan if the flow completed before the grace period', () async {
    final AlarmStateNotifier notifier = buildNotifier(
      resumeGracePeriod: const Duration(milliseconds: 30),
    );
    final AlarmModel alarm = buildAlFatihaAlarm();
    await databaseService.saveAlarm(alarm);

    notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
    await beginReciting(notifier);
    await notifier.processSpeechInput(_alFatihaAyahsOneAndTwo);
    await notifier.processTranslationSpeechInput(_placeholderTranslation);
    expect(notifier.state.state, AlarmStateEnum.completed);

    // Let the grace period lapse well after completion — it must not have
    // been left running and yank the state back to `ringing`.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(notifier.state.state, AlarmStateEnum.completed);
  });

  test('stays paused when speech initialization fails after the Adhan was silenced',
      () async {
    final AlarmStateNotifier notifier = buildNotifier(
      speechService: _UninitializedSpeechService(),
    );
    final AlarmModel alarm = buildAlFatihaAlarm();

    notifier.triggerAlarmSession(alarm, _alFatihaAyahsOneAndTwo, _placeholderTranslation);
    await notifier.pauseAdhanForReview();
    expect(notifier.state.state, AlarmStateEnum.paused);

    await notifier.startVoiceCapture();

    expect(notifier.state.state, AlarmStateEnum.paused);
  });
}

class _UninitializedSpeechService extends SpeechService {
  @override
  bool get isInitialized => false;

  @override
  Future<bool> initializeSpeech() async => false;
}

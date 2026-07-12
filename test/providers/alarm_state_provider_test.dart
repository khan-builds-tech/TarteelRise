import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/models/alarm_model.dart';
import 'package:tarteel_rise/providers/alarm_state_provider.dart';
import 'package:tarteel_rise/services/alarm_hardware_service.dart';
import 'package:tarteel_rise/services/database_service.dart';
import 'package:tarteel_rise/services/speech_service.dart';

void main() {
  late Directory tempHiveDir;
  late DatabaseService databaseService;
  late AlarmStateNotifier notifier;

  setUp(() async {
    tempHiveDir = Directory.systemTemp.createTempSync('bookmark_timing_test_hive');
    databaseService = DatabaseService();
    await databaseService.init(testHiveDirectoryPath: tempHiveDir.path);

    notifier = AlarmStateNotifier(
      speechService: SpeechService(),
      alarmHardwareService:
          AlarmHardwareService(nativeCallTimeout: const Duration(milliseconds: 50)),
      databaseService: databaseService,
    );
    // The kDebugMode preview seed puts the notifier straight into
    // `reciting` on construction — reset to a clean `idle` state so this
    // test's own alarm can drive the state machine from the top.
    notifier.resetToIdle();
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

  test('advances the bookmark only after a validated recitation clears the threshold', () async {
    final AlarmModel alarm = buildAlFatihaAlarm();
    await databaseService.saveAlarm(alarm);

    notifier.triggerAlarmSession(
      alarm,
      'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
      'placeholder translation',
    );
    await notifier.startVoiceCapture();

    // A recognized recitation that fully matches the displayed text clears
    // even the strictest threshold.
    await notifier.processSpeechInput(
      'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
    );

    final AlarmModel persisted =
        databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
    // Started at ayah 1, read 2 ayahs (1-2), should resume from ayah 3.
    expect(persisted.currentBookmarkAyah, 3);
  });

  test('leaves the bookmark untouched when nothing is recognized', () async {
    final AlarmModel alarm = buildAlFatihaAlarm();
    await databaseService.saveAlarm(alarm);

    notifier.triggerAlarmSession(
      alarm,
      'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
      'placeholder translation',
    );
    await notifier.startVoiceCapture();

    await notifier.processSpeechInput('completely unrelated speech');

    final AlarmModel persisted =
        databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
    expect(persisted.currentBookmarkAyah, 1);
  });

  test('leaves the bookmark untouched on an Emergency Snooze', () async {
    final AlarmModel alarm = buildAlFatihaAlarm();
    await databaseService.saveAlarm(alarm);

    notifier.triggerAlarmSession(alarm, 'أي آية', 'It is You we worship and You we ask for help.');

    final bool accepted = await notifier.submitEmergencyTranslationFallback(
      'It is You we worship and You we ask for help.',
    );

    expect(accepted, isTrue);
    final AlarmModel persisted =
        databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
    expect(persisted.currentBookmarkAyah, 1);
  });

  test('wraps the bookmark back to 1 once the Surah is exhausted', () async {
    final AlarmModel alarm = buildAlFatihaAlarm(currentBookmarkAyah: 6);
    await databaseService.saveAlarm(alarm);

    notifier.triggerAlarmSession(
      alarm,
      'اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ',
      'placeholder translation',
    );
    await notifier.startVoiceCapture();
    await notifier.processSpeechInput(
      'اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ',
    );

    final AlarmModel persisted =
        databaseService.getAllAlarms().firstWhere((a) => a.id == alarm.id);
    // Started at ayah 6 (of 7), requested 2 -> clamped to [6, 7] -> wraps to 1.
    expect(persisted.currentBookmarkAyah, 1);
  });
}

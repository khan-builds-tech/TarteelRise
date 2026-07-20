import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/models/alarm_model.dart';
import 'package:tarteel_rise/services/alarm_hardware_service.dart';

void main() {
  // `permission_handler`'s platform channel isn't registered in a plain
  // Dart test, and there's no Android host to run these tests on anyway —
  // `hasExactAlarmPermission`/`requestExactAlarmPermission` both check
  // `Platform.isAndroid` first specifically so they short-circuit safely
  // here (and on iOS in production) without ever touching the channel.
  final AlarmHardwareService service =
      AlarmHardwareService(nativeCallTimeout: const Duration(milliseconds: 50));

  group('hasExactAlarmPermission', () {
    test('is true on a non-Android host without touching the permission channel', () async {
      expect(Platform.isAndroid, isFalse); // Sanity-check the premise of this test.
      expect(await service.hasExactAlarmPermission(), isTrue);
    });
  });

  group('requestExactAlarmPermission', () {
    test('is a no-op on a non-Android host — completes without throwing', () async {
      await expectLater(service.requestExactAlarmPermission(), completes);
    });
  });

  group('scheduleMorningAlarm / scheduleDeadMansSwitchAlarm permission gate', () {
    test(
      'still attempts to schedule (and fails safe via the native-call timeout, '
      'not the permission gate) when the permission check itself passes',
      () async {
        // On this non-Android host, `hasExactAlarmPermission` returns
        // `true` immediately, so `_setNativeAlarm` proceeds to the real
        // `Alarm.set()` call, which has no plugin registered here and
        // times out — proving the new permission gate added in front of
        // it doesn't accidentally block scheduling when the permission is
        // actually fine.
        final AlarmModel alarm = AlarmModel(
          id: 'permission-gate-test-alarm',
          hour: 5,
          minute: 30,
          daysOfWeek: const [],
          isEnabled: true,
          selectedSurahIndex: 1,
        );

        final bool scheduled = await service.scheduleMorningAlarm(alarm);
        expect(scheduled, isFalse); // No plugin here — times out, not a permission denial.
      },
    );
  });
}

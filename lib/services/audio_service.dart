import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';

import 'alarm_hardware_service.dart';

/// Single choke point for "kill every audio path this app can produce."
///
/// Deliberately broader than any one alarm id: [stopAllAudio] stops the
/// locally resumed Adhan (`just_audio`, via [AlarmHardwareService]'s own
/// player) *and* every native alarm the `alarm` package currently knows
/// about (`Alarm.stopAll()`) — a catch-all for a stray id (e.g. a Dead
/// Man's Switch whose own cancel call failed) being left ringing after a
/// session is supposed to be fully over.
///
/// Only ever call this once a recitation gate (or its typed-translation
/// Emergency Fallback) has actually validated. It is not wired to any bare
/// button tap — doing that would silence the alarm unconditionally, i.e.
/// the snooze button this app is built specifically not to have. The
/// on-screen/notification "Emergency Stop" affordance instead ducks
/// (temporarily silences) and opens the fallback dialog; only a
/// successful match reaches this method. See
/// `AlarmStateNotifier.duckForEmergencyFallback` /
/// `resumeAdhanIfFallbackCancelled` for that half.
///
/// [AlarmHardwareService] itself already holds the one lazily-created,
/// reused `AudioPlayer` instance for the whole app lifetime (see its
/// `_resumePlayerInstance` doc comment) — this class deliberately does not
/// construct a second one; delegating to that existing singleton avoids two
/// classes racing for ownership of the same native audio session.
class AudioService {
  final AlarmHardwareService _alarmHardwareService;

  const AudioService(this._alarmHardwareService);

  Future<void> stopAllAudio() async {
    try {
      await _alarmHardwareService.stopResumedAdhanPlaybackIfActive();
      await Alarm.stopAll().timeout(_alarmHardwareService.nativeCallTimeout);
    } catch (error, stackTrace) {
      debugPrint('AudioService.stopAllAudio failed: $error\n$stackTrace');
    }
  }
}

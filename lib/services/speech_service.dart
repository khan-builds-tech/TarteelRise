import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Arabic locale codes to try, most specific dialect first, falling back to
/// the generic `ar` code if the device doesn't report a specific one.
const List<String> arabicLocalePreferenceOrder = <String>['ar-SA', 'ar-EG', 'ar'];

/// English locale codes to try, for the translation-recitation phase.
const List<String> englishLocalePreferenceOrder = <String>['en-US', 'en-GB', 'en'];

/// Wraps the `speech_to_text` engine (Apple `SFSpeechRecognizer` / Google
/// Speech Services) behind a minimal start/stop surface for recitation
/// capture.
///
/// Prefers on-device recognition (recitation audio never leaves the
/// device) but falls back to server-based recognition if the device has
/// no on-device model for the requested locale — on-device Arabic support
/// in particular isn't available on many Android devices unless the user
/// has manually downloaded the offline language pack, and a feature that
/// silently never works is worse than one that occasionally uses the
/// network. See [lastAttemptUsedNetwork].
class SpeechService {
  final SpeechToText _speech = SpeechToText();

  bool _isInitialized = false;

  /// Whether [initializeSpeech] has succeeded and the device has a working,
  /// permitted speech recognizer.
  bool get isInitialized => _isInitialized;

  /// Whether the native engine is actively capturing audio right now.
  bool get isListening => _speech.isListening;

  /// The native engine's own error code from the most recent failure (e.g.
  /// `error_language_not_supported`/`error_language_unavailable` when the
  /// device has no on-device model for the requested locale), regardless
  /// of whether it happened during [initializeSpeech] or [startListening].
  /// `null` until the first error. Exposed so callers can surface *why*
  /// the mic didn't open instead of a generic failure.
  String? get lastErrorMessage => _lastErrorMessage;
  String? _lastErrorMessage;

  /// True if the most recent successful [startListening] had to fall back
  /// to server-based recognition because on-device wasn't available for
  /// the resolved locale on this device.
  bool get lastAttemptUsedNetwork => _lastAttemptUsedNetwork;
  bool _lastAttemptUsedNetwork = false;

  /// Sets up the native speech engine. This also triggers the native
  /// microphone + speech-recognition permission prompts (handled internally
  /// by `speech_to_text`), so this must complete before any `listen` call.
  ///
  /// Returns `false` instead of throwing if permission is denied or the
  /// device has no speech recognizer, so callers can fall back to the
  /// Emergency Snooze text-entry path rather than crash mid wake-up.
  Future<bool> initializeSpeech() async {
    try {
      _isInitialized = await _speech.initialize(
        onError: (SpeechRecognitionError error) {
          _lastErrorMessage = error.errorMsg;
          debugPrint(
            'SpeechService recognition error: ${error.errorMsg} '
            '(permanent: ${error.permanent})',
          );
        },
        onStatus: (String status) {
          debugPrint('SpeechService status: $status');
        },
      );
      return _isInitialized;
    } catch (error, stackTrace) {
      debugPrint('SpeechService.initializeSpeech failed: $error\n$stackTrace');
      _isInitialized = false;
      return false;
    }
  }

  /// Activates the microphone and streams recognized text to [onRecognized]
  /// in real time, as both partial and final results arrive, recognizing in
  /// whichever locale from [localePreferenceOrder] the device actually
  /// supports (most specific first — e.g. [arabicLocalePreferenceOrder] for
  /// the Ayah, [englishLocalePreferenceOrder] for its translation).
  /// Returns `false` if [initializeSpeech] hasn't succeeded yet or the
  /// native engine refuses to open the microphone with both on-device and
  /// network recognition.
  Future<bool> startListening({
    required List<String> localePreferenceOrder,
    required void Function(String recognizedText) onRecognized,
  }) async {
    if (!_isInitialized) return false;

    _lastErrorMessage = null;
    _lastAttemptUsedNetwork = false;

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }

      final String localeId = await _resolveLocaleId(localePreferenceOrder);

      // Try on-device first (keeps recitation audio off the network);
      // only fall back to network recognition if the device genuinely has
      // no on-device model for this locale.
      for (final bool onDevice in <bool>[true, false]) {
        for (final ListenMode mode in <ListenMode>[
          ListenMode.dictation,
          ListenMode.search,
        ]) {
          await _speech.listen(
            onResult: (SpeechRecognitionResult result) {
              onRecognized(result.recognizedWords);
            },
            listenOptions: SpeechListenOptions(
              localeId: localeId,
              partialResults: true,
              cancelOnError: false,
              onDevice: onDevice,
              listenMode: mode,
            ),
          );

          if (_speech.isListening) {
            _lastAttemptUsedNetwork = !onDevice;
            debugPrint(
              'SpeechService listening ($localeId, $mode, onDevice: $onDevice)',
            );
            return true;
          }
        }
      }

      debugPrint(
        'SpeechService.startListening: engine never entered listening state '
        'for locale $localeId (lastErrorMessage: $_lastErrorMessage)',
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint('SpeechService.startListening failed: $error\n$stackTrace');
      return false;
    }
  }

  /// Cleanly shuts down the microphone stream to preserve battery and
  /// privacy. Safe to call even when not currently listening.
  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (error, stackTrace) {
      debugPrint('SpeechService.stopListening failed: $error\n$stackTrace');
    }
  }

  /// Picks the most specific locale the device actually supports from
  /// [preferenceOrder], falling back to the last (most generic) entry if
  /// none of the preferred codes are reported.
  Future<String> _resolveLocaleId(List<String> preferenceOrder) async {
    try {
      final List<LocaleName> availableLocales = await _speech.locales();
      final Set<String> availableIds =
          availableLocales.map((LocaleName locale) => locale.localeId).toSet();

      for (final String candidate in preferenceOrder) {
        if (availableIds.contains(candidate)) {
          return candidate;
        }
      }
    } catch (error, stackTrace) {
      debugPrint('SpeechService._resolveLocaleId failed: $error\n$stackTrace');
    }
    return preferenceOrder.last;
  }
}

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Arabic locale codes to try, most specific dialect first, falling back to
/// the generic `ar` code if the device doesn't report a specific one.
const List<String> _arabicLocalePreferenceOrder = <String>['ar-SA', 'ar-EG', 'ar'];

/// Wraps the on-device `speech_to_text` engine (Apple `SFSpeechRecognizer` /
/// Google Speech Services) behind a minimal start/stop surface for
/// recitation capture. Recognition is forced on-device only — no network
/// speech APIs are ever used.
class SpeechService {
  final SpeechToText _speech = SpeechToText();

  bool _isInitialized = false;

  /// Whether [initializeSpeech] has succeeded and the device has a working,
  /// permitted speech recognizer.
  bool get isInitialized => _isInitialized;

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
          debugPrint('SpeechService recognition error: ${error.errorMsg}');
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

  /// Activates the microphone and streams recognized Arabic text to
  /// [onRecognized] in real time, as both partial and final results arrive.
  /// No-op if [initializeSpeech] hasn't succeeded yet.
  Future<void> startListeningToRecitation(
    void Function(String recognizedText) onRecognized,
  ) async {
    if (!_isInitialized) return;

    try {
      final String localeId = await _resolveArabicLocaleId();

      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          onRecognized(result.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          partialResults: true,
          cancelOnError: true,
          onDevice: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'SpeechService.startListeningToRecitation failed: $error\n$stackTrace',
      );
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

  /// Picks the most specific Arabic locale the device actually supports,
  /// falling back to the generic `ar` code if none of the preferred
  /// dialect-specific codes are reported.
  Future<String> _resolveArabicLocaleId() async {
    try {
      final List<LocaleName> availableLocales = await _speech.locales();
      final Set<String> availableIds =
          availableLocales.map((LocaleName locale) => locale.localeId).toSet();

      for (final String candidate in _arabicLocalePreferenceOrder) {
        if (availableIds.contains(candidate)) {
          return candidate;
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'SpeechService._resolveArabicLocaleId failed: $error\n$stackTrace',
      );
    }
    return _arabicLocalePreferenceOrder.last;
  }
}

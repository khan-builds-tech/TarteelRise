import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

const List<String> arabicLocalePreferenceOrder = <String>['ar-SA', 'ar-EG', 'ar'];
const List<String> englishLocalePreferenceOrder = <String>['en-US', 'en-GB', 'en'];

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isListening => _speech.isListening;

  String? get lastErrorMessage => _lastErrorMessage;
  String? _lastErrorMessage;

  bool get lastAttemptUsedNetwork => _lastAttemptUsedNetwork;
  bool _lastAttemptUsedNetwork = false;

  // Global callbacks to bridge the async native events back to the active listener
  void Function(String)? _activeResultCallback;

  Future<bool> initializeSpeech() async {
    try {
      _isInitialized = await _speech.initialize(
        onError: (SpeechRecognitionError error) {
          _lastErrorMessage = error.errorMsg;
          debugPrint('SpeechService recognition error: ${error.errorMsg} (permanent: ${error.permanent})');
          
          // CRITICAL: If native listening fails after starting, stop state tracking
          if (error.permanent) {
            _activeResultCallback = null;
          }
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

  /// Activates microphone capture.
  /// 
  /// NOTE: Rather than guessing via a loop, we configure optimal defaults.
  /// On Android, setting `onDevice: false` will seamlessly use on-device if available,
  /// or cloud fallback automatically via Google Speech Services without crashing.
  Future<bool> startListening({
    required List<String> localePreferenceOrder,
    required void Function(String recognizedText) onRecognized,
  }) async {
    if (!_isInitialized) return false;

    _lastErrorMessage = null;
    // We cannot explicitly guarantee on-device status natively without deep OS checks,
    // so we track intent or rely on defaults.
    _lastAttemptUsedNetwork = true; 

    try {
      if (_speech.isListening) {
        await _speech.stop();
        // Give the native channel a brief moment to cycle down
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      final String localeId = await _resolveLocaleId(localePreferenceOrder);
      _activeResultCallback = onRecognized;

      // Use a single, highly compatible configuration request.
      // Trying to stack loops here forces race conditions.
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          if (_activeResultCallback != null) {
            _activeResultCallback!(result.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          partialResults: true,
          cancelOnError: false,
          // Setting onDevice to false allows Google Services to automatically
          // handle the offline-to-cloud fallback smoothly on Android.
          onDevice: false, 
          listenMode: ListenMode.dictation,
        ),
      );

      // Allow native engine a short window to flip the switch
      int retries = 0;
      while (!_speech.isListening && retries < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        retries++;
      }

      if (_speech.isListening) {
        debugPrint('SpeechService successfully listening ($localeId)');
        return true;
      }

      debugPrint('SpeechService failed to enter listening state.');
      return false;
    } catch (error, stackTrace) {
      debugPrint('SpeechService.startListening failed: $error\n$stackTrace');
      _activeResultCallback = null;
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      _activeResultCallback = null;
      await _speech.stop();
    } catch (error, stackTrace) {
      debugPrint('SpeechService.stopListening failed: $error\n$stackTrace');
    }
  }

  /// Normalizes and resolves locale format variations (e.g., ar_SA vs ar-SA)
  Future<String> _resolveLocaleId(List<String> preferenceOrder) async {
    try {
      final List<LocaleName> availableLocales = await _speech.locales();
      
      // Normalize system tags to lowercase with hyphens for bulletproof matching
      final Set<String> availableIds = availableLocales
          .map((LocaleName l) => l.localeId.toLowerCase().replaceAll('_', '-'))
          .toSet();

      for (final String candidate in preferenceOrder) {
        final String normalizedCandidate = candidate.toLowerCase().replaceAll('_', '-');
        if (availableIds.contains(normalizedCandidate)) {
          // Return the original matching string from the system, not our normalized copy
          return availableLocales
              .firstWhere((LocaleName l) => l.localeId.toLowerCase().replaceAll('_', '-') == normalizedCandidate)
              .localeId;
        }
      }
    } catch (error, stackTrace) {
      debugPrint('SpeechService._resolveLocaleId failed: $error\n$stackTrace');
    }
    return preferenceOrder.last;
  }
}

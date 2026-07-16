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

  void Function(String)? _activeResultCallback;
  
  // Exposes current speech volume changes to drive visual wave components in the UI
  void Function(double dB)? onSoundLevelChanged;

  Future<bool> initializeSpeech() async {
    try {
      _isInitialized = await _speech.initialize(
        onError: (SpeechRecognitionError error) {
          _lastErrorMessage = error.errorMsg;
          debugPrint('SpeechService recognition error: ${error.errorMsg} (permanent: ${error.permanent})');
          
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

  Future<bool> startListening({
    required List<String> localePreferenceOrder,
    required void Function(String recognizedText) onRecognized,
  }) async {
    if (!_isInitialized) return false;

    _lastErrorMessage = null;
    _lastAttemptUsedNetwork = true; 

    try {
      if (_speech.isListening) {
        await _speech.stop();
        await Future<void>.delayed(const Duration(milliseconds: 250)); // Slightly expanded cooldown
      }

      final String localeId = await _resolveLocaleId(localePreferenceOrder);
      _activeResultCallback = onRecognized;

      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          if (_activeResultCallback != null) {
            _activeResultCallback!(result.recognizedWords);
          }
        },
        // Captures sound fluctuations (dB changes) during recitation
        onSoundLevelChange: (double level) {
          if (onSoundLevelChanged != null) {
            onSoundLevelChanged!(level);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          partialResults: true,
          cancelOnError: false,
          onDevice: false,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 20),
        ),
      );

      // Expanded Retry Window: 15 retries x 100ms = 1.5 seconds maximum timeout.
      // This absorbs native scheduling latency on low-end hardware waking from Doze mode.
      int retries = 0;
      while (!_speech.isListening && retries < 15) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        retries++;
      }

      if (_speech.isListening) {
        debugPrint('SpeechService successfully listening ($localeId) after ${retries * 100}ms');
        return true;
      }

      debugPrint('SpeechService failed to enter listening state within timeout limits.');
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

  Future<String> _resolveLocaleId(List<String> preferenceOrder) async {
    try {
      final List<LocaleName> availableLocales = await _speech.locales();
      
      final Set<String> availableIds = availableLocales
          .map((LocaleName l) => l.localeId.toLowerCase().replaceAll('_', '-'))
          .toSet();

      for (final String candidate in preferenceOrder) {
        final String normalizedCandidate = candidate.toLowerCase().replaceAll('_', '-');
        if (availableIds.contains(normalizedCandidate)) {
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

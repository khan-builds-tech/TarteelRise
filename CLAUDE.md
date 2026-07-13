# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

This is a Flutter project at the very start of implementation. `lib/main.dart` is still the
default `flutter create` counter-app scaffold, and `pubspec.yaml`/`analysis_options.yaml` are
otherwise stock. The actual product is fully specified in **`tarteel_rise_spec.md`** — read it
before implementing any feature, it is the source of truth for architecture, algorithms, and UI.
**`tarteel_rise_tasks.md`** breaks that spec into a 4-phase build order (Core utilities/DB →
background hardware/speech → Material 3 UI/gamification → cloud pipeline/release); check it to
see what phase the codebase is in before adding new functionality.

## What this app does

Tarteel Rise is an Islamic alarm app: instead of a snooze button, the user must recite the
displayed Quranic Ayah aloud into the microphone. On-device speech recognition validates the
recitation (normalized to ignore diacritics) against a configurable match threshold before the
alarm audio stops and the English translation is revealed.

## Commands

```bash
flutter pub get                 # install dependencies
flutter run                     # run on a connected device/simulator
flutter analyze                 # static analysis (uses analysis_options.yaml / flutter_lints)
flutter test                    # run all tests
flutter test test/widget_test.dart          # run a single test file
flutter test --plain-name "test name"       # run a single test by name

# hive_generator / build_runner (needed once Hive TypeAdapters are added)
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch --delete-conflicting-outputs
```

There is no CI/Codemagic config yet — Phase 4 of `tarteel_rise_tasks.md` sets that up.

## Architecture (per `tarteel_rise_spec.md`)

- **State management:** `flutter_riverpod`. The whole app pivots on one atomic state machine:
  `idle -> ringing -> reciting -> completed`. Do not model alarm/recitation state any other way
  (e.g. scattered booleans) — everything should read as a transition in this machine.
- **Local persistence:** `hive` / `hive_flutter`, fully offline. Two models drive the app:
  - `AlarmModel` — hour, minute, active flag, selected Surah, difficulty level.
  - `UserStatsModel` — `streak_count`, `last_recited_date`, plus a `current_bookmark` index per
    Surah so recitation resumes where the previous morning left off.
- **Alarm scheduling:** `alarm` (v6+) for cross-platform native background scheduling, plus
  `flutter_alarmkit` for iOS AlarmKit specifically (configured via `ios/Runner/Info.plist`).
- **Audio:** `just_audio` loops the local `assets/audio/adhan.mp3` asset and must handle audio
  ducking when another app is playing media.
- **Speech pipeline:** `speech_to_text`, preferring on-device engines (Apple `SFSpeechRecognizer`
  on iOS, Google Speech Services on Android) but falling back to server-based recognition if the
  device has no on-device model for the locale — on-device Arabic isn't available on many Android
  devices by default. See `SpeechService.startListening`/`lastAttemptUsedNetwork`. This was
  originally on-device-only; relaxed by explicit product decision after on-device-only left the
  mic silently non-functional on devices without the offline Arabic language pack installed.
- **Arabic text normalization:** all recognized/reference text must be normalized before
  comparison — strip Tashkeel diacritics (`ً`–`ْ`) and fold Alef variants (`إأآ` → `ا`)
  before whitespace/case normalization. This lives in `utils/arabic_utils.dart` per the spec's
  reference implementation.
- **Difficulty / match thresholds:** Easy ≥65% (keyword/rhythm match), Medium ≥80% (default,
  full phrase structure), Hard ≥95% (Tajweed-strict). Any recitation-scoring code needs to key
  off the alarm's configured difficulty level.
- **Emergency fallback:** a secondary text-entry path (typed English translation) can silence the
  alarm without speaking, but must mark the day as an "Emergency Snooze" and break `streak_count`
  rather than incrementing it.
- **Theme:** Material 3, dark-mode-first — background `#121212`, accent `#0F9D58`, text `#F5F5F5`,
  large touch targets and AAA contrast (this is used first thing when half-asleep).

## Directory conventions

The spec mandates strict separation of concerns — do not fold storage, styling, and hardware
control into one file/class. Follow this layout as code is added:

- `services/` — hardware/system integration (alarm scheduling, audio playback, speech recognition).
- `utils/` — pure logic (e.g. `arabic_utils.dart` text normalization, match scoring).
- `ui/screens/` — screens/widgets (e.g. dashboard, active wake-up/recitation screen).

## Working conventions for this repo

- **No stub code.** Write complete, working implementations — no `// TODO: implement later`
  placeholders left in committed code.
- **Hardware calls must fail safe.** Any call into `speech_to_text` or `just_audio` needs a
  try/catch with a safe state rollback (back to a known `AlarmState`) so a hardware/permission
  failure can never leave the user stuck in a ringing alarm they can't dismiss.

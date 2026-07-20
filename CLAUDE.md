# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app does

Tarteel Rise is an Islamic alarm app: instead of a snooze button, the user must recite the
displayed Quranic Ayah aloud into the microphone, then recite its English translation, before the
alarm audio stops. On-device speech recognition validates each recitation (normalized to ignore
diacritics) against a configurable match threshold.

## Project state

`tarteel_rise_spec.md` and `tarteel_rise_tasks.md` are the *original* product spec and phased
build plan — useful for the product vision (theme, difficulty matrix, gamification loop), but the
implementation has since diverged from them in specific, deliberate ways (see "Where the code
differs from the spec docs" below). Prefer reading the actual code over those docs when they
conflict.

There is no CI/Codemagic config yet.

## Commands

```bash
flutter pub get                 # install dependencies
flutter run                     # run on a connected device/simulator
flutter analyze                 # static analysis (uses analysis_options.yaml / flutter_lints)
flutter test                    # run all tests
flutter test test/widget_test.dart          # run a single test file
flutter test --plain-name "test name"       # run a single test by name

# hive_generator / build_runner — re-run any time a @HiveField changes on
# AlarmModel/UserStatsModel
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch --delete-conflicting-outputs
```

Widget tests that drive `AlarmCreateScreen`/`AlarmActiveScreen` need `rootBundle` (for the Quran
asset) and Hive both working, so `test/widget_test.dart`'s `setUp` loads
`quranRepositoryProvider` and initializes a temp Hive dir before every test — mirror that pattern
in new widget tests rather than pumping `TarteelRiseApp` directly. Plain `test()` files (not
`testWidgets()`) that touch `rootBundle` (e.g. anything calling
`QuranRepository.loadFromAssets`) need `TestWidgetsFlutterBinding.ensureInitialized()` as the
first line of `main()`, since only `testWidgets()` sets that binding up automatically.

Two widget tests (editing and deleting an existing alarm, in `test/widget_test.dart`) are known to
hang under `flutter test` for reasons not yet root-caused — this has been repeatedly deferred by
explicit user request. Don't sink time into them unprompted; if you touch `AlarmCreateScreen`, run
the *other* widget tests individually via `--plain-name` rather than the whole file, so a hang
doesn't block you from checking the rest.

## Architecture

- **State management:** `flutter_riverpod`. The whole app pivots on one atomic state machine —
  `AlarmStateEnum`: `idle -> ringing -> paused -> reciting -> recitingTranslation -> completed`.
  Do not model alarm/recitation state any other way (e.g. scattered booleans) — everything should
  read as a transition in this machine, driven by `AlarmStateNotifier`
  (`providers/alarm_state_provider.dart`). `ringing` is the Adhan playing; `paused` is Adhan
  silenced so the user can read the Ayah before opening the mic; `reciting`/`recitingTranslation`
  are the two sequential recitation gates (Arabic, then its English translation — *both* must
  clear before `completed`).
- **Routing:** `AppNavigationWrapper` (`main.dart`) is the single source of truth for navigation,
  driven purely by `ref.listen` on `alarmStateProvider`'s state — not by individual screens
  calling `Navigator.push`. Any transition away from `idle` hard-replaces the entire nav stack
  with `AlarmActiveScreen` via `pushAndRemoveUntil`, and any transition back to `idle` does the
  same back to `AlarmDashboardScreen`. This is deliberate, not just a stronger push: leaving a
  stale Dashboard/Create-alarm screen underneath would let the system back button (or
  `AlarmActiveScreen`'s own `PopScope`, which blocks it outright while non-`idle`) skip the
  recitation requirement.
- **Local persistence:** `hive` / `hive_flutter`, fully offline. Two models:
  - `AlarmModel` — hour, minute, `daysOfWeek`, `isEnabled`, `selectedSurahIndex`,
    `difficultyLevel`. Notably *no* per-alarm Ayah/bookmark field — see below.
  - `UserStatsModel` — `streakCount`, `lastRecitedDate`, `highestStreak`.
  - Regenerate `*.g.dart` adapters (`dart run build_runner build`) after changing any
    `@HiveField`; this is a pre-launch app with no real user data, so schema changes don't need
    migration shims — just renumber/remove fields cleanly.
- **Quran content:** `services/quran_repository.dart`'s `QuranRepository` loads the full 114-Surah
  dataset (`assets/data/quran_en.json` — Arabic text *and* English translation per verse) via
  `rootBundle.loadString` + `jsonDecode`, once, during `main()`'s async bootstrap (before
  `runApp()`, same pattern as `DatabaseService.init`) — every other reader
  (`quranRepositoryProvider`) then reads it synchronously. `buildRandomChallenge(surahIndex)`
  picks a single random Ayah from that Surah, capped at `maxChallengeAyahWords` (10) via rejection
  sampling in `utils/ayah_selection_utils.dart`, called fresh every time an alarm actually rings
  (`main.dart._resolveAyahContent`) — a different short verse each morning, not a fixed one.
- **Alarm scheduling:** the `alarm` package (native `AlarmManager.setExactAndAllowWhileIdle` /
  `RTC_WAKEUP` on Android) — not `android_alarm_manager_plus`/`AndroidAlarmManager`. It handles
  exact+wakeup scheduling, its own native foreground service + audio playback, and a full-screen
  intent to relaunch the UI, entirely independent of the Dart isolate being alive. Do not add a
  second native-scheduling package alongside it; it would double-play audio and race against it.
  `flutter_alarmkit` (mentioned in the original spec) is *not* used — removed from `pubspec.yaml`.
- **Dead Man's Switch (`alarm_hardware_service.dart` / `alarm_state_provider.dart`):** the moment
  the mic opens (`startVoiceCapture`), two independent safety nets are armed: an in-process Dart
  `Timer` (`resumeGracePeriod`, default 4 min) *and* a second native `alarm` package alarm
  (`scheduleDeadMansSwitchAlarm`, under its own id via `nativeFallbackAlarmIdFor` — never the same
  id as the primary alarm) at `resumeGracePeriod + 15s`. The native one is a pure backup for when
  the Dart timer can't fire (app killed, isolate throttled) — its delay must always track
  `resumeGracePeriod`, never a shorter independent duration, or it fires mid-recitation. Both must
  be disarmed together on every exit path (completion, Emergency Snooze, reset) — grep
  `cancelDeadMansSwitchAlarm` call sites before changing any of them. `pauseAdhanForReview` stops
  *both* the primary and fallback native alarm ids, since re-entering `ringing` can come from
  either.
- **Audio:** `just_audio` (`AlarmHardwareService.resumeAdhanPlayback`) is only used to resume the
  Adhan locally when the Dart-timer safety net fires — normal ringing/silencing goes through the
  native `alarm` package directly (`Alarm.set`/`Alarm.stop`), never `just_audio`.
- **Speech pipeline:** `speech_to_text`, preferring on-device engines but falling back to
  server-based recognition if the device has no on-device model for the locale (on-device Arabic
  isn't available on many Android devices by default) — see `SpeechService.startListening`. This
  was originally on-device-only; relaxed by explicit product decision after on-device-only left
  the mic silently non-functional on devices without the offline Arabic language pack installed.
- **Arabic text normalization:** strip Tashkeel diacritics (`ً`–`ْ`) and fold Alef variants
  (`إأآ` → `ا`) before whitespace normalization — `utils/arabic_utils.dart`.
- **Word-match scoring, and why it's a ratchet:** `utils/word_match_utils.dart`'s
  `wordMatchFlags`/`percentageFromFlags` are the shared frequency-based matching primitives behind
  both Arabic (`arabic_utils.dart`) and English (`translation_match_utils.dart`) scoring. Speech
  engines revise their whole-utterance hypothesis on every partial `onResult` — a later partial
  can legitimately score *lower* than an earlier one (or come back empty) without the user having
  un-recited anything. `AlarmStateNotifier` therefore keeps its own
  `_accumulatedArabicWordFlags`/`_accumulatedTranslationWordFlags`, OR-merging each chunk's flags
  in via `mergeWordMatchFlags` and deriving *both* the displayed percentage and the per-word
  highlighting from that one accumulated list — never from a chunk's raw flags directly. This is
  what makes the progress bar monotonic and keeps it in exact agreement with which words are
  highlighted; ratcheting just a percentage while highlighting still reflected the latest raw
  chunk was a bug that shipped once already. The only two legitimate reset points are a brand new
  alarm ring (`triggerAlarmSession`) and freshly entering the translation gate.
- **Difficulty / match thresholds:** Easy ≥65%, Medium ≥80% (default), Hard ≥95% — applies to
  *both* the Arabic Ayah and its translation gate (`_thresholdForDifficulty`).
- **Emergency fallback:** typing the English translation (`submitEmergencyTranslationFallback`)
  silences the alarm without speaking, marks `completedViaEmergencyFallback`, and breaks
  `streakCount` (`DatabaseService.recordEmergencySnooze`) rather than incrementing it.
- **Theme:** Material 3, dark-mode-first — background `#121212`, accent `#0F9D58`, text `#F5F5F5`,
  large touch targets and AAA contrast (this is used first thing when half-asleep).

## Where the code differs from the spec docs

- **No Smart Bookmarking.** The spec's `current_bookmark`/sequential-Ayah-progression-through-a-
  Surah concept was removed by explicit product decision — there's no `numberOfAyahs` or
  `currentBookmarkAyah` field on `AlarmModel` anymore. Exactly one Ayah is shown per alarm, chosen
  randomly (see `buildRandomChallenge` above) each time it rings, not deterministically advanced.
- **No `flutter_alarmkit`.** Removed; the `alarm` package's own Android/iOS native scheduling is
  used directly (see above).
- **Surah selection lives only in `AlarmCreateScreen`**, via a searchable `DropdownMenu<Surah>`
  over the full 114-Surah catalog (`_SurahDropdown`) — there is no Surah picker on the Dashboard.
  There's also no Ayah-count or Ayah-number picker in the UI at all; content selection is fully
  automatic (random + word-limited) at ring time.
- **State machine has two more states than the spec's `idle/ringing/reciting/completed`**: `paused`
  (Adhan silenced, reading the Ayah before the mic opens) and `recitingTranslation` (the second,
  mandatory translation-recitation gate) — see `AlarmStateEnum` above.

## Directory conventions

Strict separation of concerns — do not fold storage, styling, and hardware control into one
file/class:

- `data/` — plain models + JSON parsing for the Quran catalog (`Surah`, `AyahRecord`).
- `services/` — hardware/system integration (alarm scheduling, audio playback, speech
  recognition, Quran asset loading) and Hive access (`DatabaseService`).
- `providers/` — Riverpod providers/notifiers wiring services together and holding UI-facing
  reactive state (`alarm_state_provider.dart` is the state machine; `dashboard_providers.dart` is
  thinner reactive views over Hive for the dashboard).
- `utils/` — pure logic (text normalization, match scoring, random-Ayah selection). No Flutter/
  platform imports.
- `ui/screens/` — screens/widgets.

## Working conventions for this repo

- **No stub code.** Write complete, working implementations — no `// TODO: implement later`
  placeholders left in committed code. If something is unused after a refactor, delete it
  completely rather than leaving it dead or behind a flag.
- **Hardware calls must fail safe.** Any call into `speech_to_text`, `just_audio`, or the `alarm`
  package needs a try/catch with a safe state rollback (back to a known `AlarmStateEnum`) so a
  hardware/permission/asset failure can never leave the user stuck in a ringing alarm they can't
  dismiss. `AlarmHardwareService` wraps every native call in `Future.timeout` for the same reason
  — a stuck platform channel doesn't throw, it just never completes.

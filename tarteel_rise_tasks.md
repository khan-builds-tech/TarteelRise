🏗️ Phase 1: Core Utilities & Local Database (Days 1–4)
Goal: Set up the foundational infrastructure, offline data access, and text processing logic.

Task 1: The Text Normalization Engine

Implement the utils/arabic_utils.dart utility based on the regex template in the specification file.

Write a suite of unit tests verifying that strings with mixed vowels (Tashkeel) and alternate Alef types normalize into clean, easily searchable strings.

Task 2: Database Layer (hive)

Design and build the storage adapters for AlarmModel (storing hour, minute, active status, selected Surah, difficulty level).

Design the tracking layer for UserStatsModel (storing streak_count and last_recited_date).

Task 3: State Pipeline Setup (flutter_riverpod)

Create the core AlarmState state machine (idle, ringing, reciting, completed).

🎙️ Phase 2: Background Hardware & Speech Engines (Days 5–12)
Goal: Get the core functionality working while the app is technically ugly. If the alarm doesn't ring while the phone is asleep, the app fails.

Task 1: Audio Playback Integration

Configure just_audio to load the local Adhan asset, loop it cleanly, and handle audio ducking policies (what happens if another media application is active).

Task 2: Background Scheduling Engine

Hook up the alarm and flutter_alarmkit configurations inside ios/Runner/Info.plist.

Build a minimal test screen to schedule an alarm 2 minutes into the future, force-close the app, lock your iPhone, and verify the background trigger fires properly.

Task 3: Native Speech-to-Text Pipeline

Configure the local microphone permissions.

Integrate speech_to_text to capture raw input strings, feed them into Phase 1's normalization utility, and verify matching accuracy percentages matching your difficulty matrix definitions.

🎨 Phase 3: Material 3 UI Layout & Gamification (Days 13–20)
Goal: Skin the working hardware layer with a beautiful, high-contrast Dark Mode design directly in code.

Task 1: Theme & Navigation Blueprint

Code your application global styling theme (ThemeData) using your slate backgrounds and emerald accents.

Task 2: Screen Construction

Dashboard Screen: Shows active alarms, a list of selectable Surahs, and the prominent daily streak component.

Active Wake-Up Screen: High-contrast layout displaying large Arabic typography, real-time color feedback tracking spoken keywords, and the translation reveal overlay.

Task 3: Gamification & Emergency Failures

Wire up the logic that automatically increments your Hive database streak counter once a recitation clears the required threshold percentage.

Build out the text input fallback interface allowing users to type the English translation to stop the audio stream, including code paths to reset active streak metrics.

🚀 Phase 4: Cloud Pipeline, Hard Testing, & App Store Submission (Days 21–28)
Goal: Connect the repository to Codemagic, stress test under real-world conditions, and pass Apple App Store review.

Task 1: Codemagic & TestFlight Setup

Establish your automated cloud pipelines so pushing code to GitHub builds a wireless installation file on your iPhone.

Task 2: Real-World Testing Loop

Test the application under edge-case hardware conditions: phone running low battery, system placed on physical mute, screen locked, and multiple hours passing since app close.

Task 3: Release Packaging & Submissions

Draft App Store submission assets: micro-narratives explaining the specific necessity of microphone capture to bypass lock-screens, clear usage guidelines for reviewers, privacy policy linkages, and graphic assets captured from TestFlight runs.

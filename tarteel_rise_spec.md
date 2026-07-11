# Product Specification: Tarteel Rise (Islamic Recitation Alarm App)

## 1. Project Overview & Core Mission

Tarteel Rise is a premium, cross-platform mobile utility built with Flutter. Its core mission is to replace traditional stressful, irritating alarm clocks with a mindful, spiritual waking habit.

Instead of hitting a standard snooze button, users are greeted by the Adhan or a beautifully recited Quranic Ayah. To turn off the audio, they must read the active Arabic verse aloud into the microphone. Once the voice engine validates their speech, the audio cuts out, and the app displays the English translation to ground their cognitive understanding and kickstart their morning with spiritual clarity.

---

## 2. Technical Stack & Architecture

### Core Frameworks

- **Frontend Framework:** Flutter (Dart) using Material 3 UI design tokens.
- **State Management:** `flutter_riverpod` (Atomic state machine tracking: `idle`, `ringing`, `reciting`, `completed`).
- **Local Cache & DB:** `hive` / `hive_flutter` (Ultra-fast, light key-value store functioning completely offline).

### System & Hardware Integrations

- **Alarm Scheduling:** `alarm` (v6+) package wrapping native OS execution frameworks.
- **iOS Platform Specifics:** `flutter_alarmkit` (Taps into iOS AlarmKit APIs for reliable background triggering).
- **Audio Infrastructure:** `just_audio` (Handles looping local assets like `assets/audio/adhan.mp3`).
- **Cognitive Pipeline:** `speech_to_text` package tapping directly into native on-device AI engines (`Apple SFSpeechRecognizer` for iOS / `Google Speech Services` for Android). No external web API calls allowed.

---

## 3. Core Logic: Arabic Text Normalization

To prevent false-negative rejections caused by slight vocal changes or morning raspy voices, text comparisons must strip vowels (_Tashkeel_) dynamically during processing.

### The Algorithm Logic (To be written in Dart)

```dart
String normalizeArabicText(String input) {
  // Use regex to strip Arabic short vowels/diacritics:
  // Fatha, Damma, Kasra, Sukun, Fathatan, Dammatan, Kasratan, Shadda
  final RegExp diacritics = RegExp(r'[\u064B-\u0652]');
  String output = input.replaceAll(diacritics, '');

  // Normalize variations of Alef (إ, أ, آ -> ا)
  output = output.replaceAll(RegExp(r'[إأآ]'), 'ا');

  // Clean whitespace and enforce lowercase/standard matching bounds
  return output.trim().replaceAll(RegExp(r'\s+'), ' ');
}
```

4. Feature Matrix Details
   A. Difficulty Matrix (Leniency Modes)
   Easy (Morning Voice): Match rate threshold >= 65%. Focuses on keyword isolation and rhythmic pace. Ideal for children, non-native speakers, or high-congestion mornings.

Medium (Flow Mode): Match rate threshold >= 80%. Checks full structural phrase components to guarantee active reading. Default mode.

Hard (Tajweed Mode): Match rate threshold >= 95%. Strict compliance with accurate text rendering.

B. Progression & Smart Bookmarking
The app links to a local SQLite or localized JSON database of the Quran.

Users configure how many Ayahs they want to recite each morning (default: 3 to 5).

For longer Surahs, the app stores a local index pointer (current_bookmark). If the user picks Surah Al-Mulk and reads Ayahs 1–5 on Monday, Tuesday morning automatically resumes from Ayah 6.

C. The Gamified Reward Loop
Streak Tracker: Successful morning recitations increment a daily streak (streak_count).

The Emergency Fallback: If a user physically cannot speak (sore throat, emergency), a secondary text bypass option requires typing out the English translation. Doing so turns off the alarm but flags the day as an "Emergency Snooze," breaking the streak to preserve the app's integrity.

5. UI Layout Blueprints (Code-First Style)
   Theme Configuration
   Dark Mode Palette: Main Background: Deep Slate (#121212), Accents/Active indicators: Soft Emerald Green (#0F9D58), Typography: Off-White (#F5F5F5).

Accessibility Constraints: Massive structural touch targets for sleepy hands. High contrast profiles matching AAA accessibility thresholds.

Screen Layout Blueprint: Active Alarm View
Top Bar: Digital System Clock alongside an inline miniature row component holding the current streak_count flame badge icon.

Center Section: An expanded, rounded Material 3 Card component with generous padding (24.0). Inside, an active Arabic font display (Font size 28+, line height 1.8) stacked above a hidden-by-default or blurred English translation section.

Bottom Section: A large, prominent, centrally placed Floating Action Button displaying a microphone glyph. The button utilizes a gentle Animation Controller loop to pulse its background surface when ready to record.

6. Development Directives for Claude Code
   When generating files for this project, adhere strictly to the following implementation rules:

Maintain Extreme Modularity: Do not combine system storage, UI styling, and audio hardware handlers into single gigantic classes. Separate them explicitly (e.g., services/alarm_service.dart, utils/arabic_utils.dart, ui/screens/alarm_screen.dart).

Handle Failure Safely: Hardware calls to the native speech recognizer (speech_to_text) or the background audio player (just_audio) must always be wrapped inside robust try-catch blocks with safe default state rollbacks so the app never locks up or crashes during a wake-up routine.

No Unfinished Drafts: Write complete, operational code blocks containing exact variable references rather than leaving broad multi-line placeholder comments like // TODO: Implement logic here.

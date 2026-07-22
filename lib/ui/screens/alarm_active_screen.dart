import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/active_alarm_session.dart';
import '../../models/alarm_state_enum.dart';
import '../../providers/alarm_state_provider.dart';
import '../../theme/app_theme.dart';

/// The full-screen wake-up flow: ringing -> paused -> reciting -> completed.
/// Layout is driven entirely by [alarmStateProvider]; this widget owns no
/// state of its own beyond the pulse/flash animation ticker.
class AlarmActiveScreen extends ConsumerStatefulWidget {
  const AlarmActiveScreen({super.key});

  @override
  ConsumerState<AlarmActiveScreen> createState() => _AlarmActiveScreenState();
}

class _AlarmActiveScreenState extends ConsumerState<AlarmActiveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AlarmSessionState sessionState = ref.watch(alarmStateProvider);
    final AlarmStateEnum state = sessionState.state;

    // `completed` and `paused` freeze the alarm flash — calmer while the
    // user reads the Ayah or reviews their finished recitation.
    if (state == AlarmStateEnum.completed || state == AlarmStateEnum.paused) {
      if (_pulseController.isAnimating) _pulseController.stop();
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }

    // Blocks the system back gesture/button for every state except `idle`
    // (this screen's own fallback placeholder — never reached in the real
    // flow, since `AppNavigationWrapper` only routes here on a non-idle
    // transition, but still safely dismissible if it ever is). Without
    // this, a back-press while `AppNavigationWrapper` has hard-replaced the
    // stack with only this route would exit the app instead of respecting
    // the recitation requirement — same escape hatch the emergency-fallback
    // dialog's typed translation is designed to close.
    return PopScope(
      canPop: state == AlarmStateEnum.idle,
      child: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _buildFab(state, sessionState),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: switch (state) {
              AlarmStateEnum.idle => const _IdlePlaceholder(),
              AlarmStateEnum.ringing => _RingingLayout(pulseController: _pulseController),
              AlarmStateEnum.paused => _PausedLayout(
                  session: sessionState.session,
                  speechErrorMessage: sessionState.speechErrorMessage,
                ),
              AlarmStateEnum.reciting => _RecitingLayout(
                  session: sessionState.session,
                  speechErrorMessage: sessionState.speechErrorMessage,
                ),
              AlarmStateEnum.recitingTranslation => _RecitingTranslationLayout(
                  session: sessionState.session,
                  speechErrorMessage: sessionState.speechErrorMessage,
                ),
              // `AppNavigationWrapper` (main.dart) hard-replaces this whole
              // route with `StreakSuccessScreen` the instant state enters
              // `completed`, in the same `ref.listen` callback that sets
              // this state — so this case is only ever transiently
              // reachable (if reachable at all) for a frame that never
              // actually gets painted, never a real fallback UI.
              AlarmStateEnum.completed => const _IdlePlaceholder(),
            },
          ),
        ),
      ),
    );
  }

  Widget? _buildFab(AlarmStateEnum state, AlarmSessionState sessionState) {
    switch (state) {
      case AlarmStateEnum.ringing:
        return FloatingActionButton.extended(
          onPressed: () => ref.read(alarmStateProvider.notifier).pauseAdhanForReview(),
          extendedPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          icon: const Icon(Icons.pause, size: 32),
          label: const Text(
            'Pause Adhan',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        );
      case AlarmStateEnum.paused:
        return FloatingActionButton.extended(
          onPressed: () => ref.read(alarmStateProvider.notifier).startVoiceCapture(),
          extendedPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          icon: const Icon(Icons.mic, size: 32),
          label: const Text(
            'Start Reciting',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        );
      case AlarmStateEnum.reciting:
      case AlarmStateEnum.recitingTranslation:
        return _MicToggleButton(isMicActive: sessionState.isMicActive);
      case AlarmStateEnum.idle:
      case AlarmStateEnum.completed:
        return null;
    }
  }
}

/// The mic control during `reciting`/`recitingTranslation`: an animated
/// waveform while listening, a static mic icon while stopped — tapping
/// either toggles to the other. [pauseVoiceCapture]/[retryVoiceCapture]
/// are the two halves of that toggle on [AlarmStateNotifier]; neither
/// races the other the way a single always-"start" action used to (see
/// [AlarmStateNotifier.pauseVoiceCapture]'s doc comment).
class _MicToggleButton extends ConsumerWidget {
  final bool isMicActive;

  const _MicToggleButton({required this.isMicActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => isMicActive
          ? ref.read(alarmStateProvider.notifier).pauseVoiceCapture()
          : ref.read(alarmStateProvider.notifier).retryVoiceCapture(),
      child: Container(
        width: 96,
        height: 96,
        decoration: const BoxDecoration(
          color: AppColors.accentEmerald,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: isMicActive
            ? const _MicWaveform()
            : const Icon(Icons.mic_none, color: Colors.white, size: 40),
      ),
    );
  }
}

/// 5 vertical bars, each oscillating on its own phase/speed so the group
/// reads as an organic audio wave rather than a mechanical, synchronized
/// pulse — driven by one [AnimationController] rather than five, since
/// the bars only need a shared clock, not independent animation state.
class _MicWaveform extends StatefulWidget {
  const _MicWaveform();

  @override
  State<_MicWaveform> createState() => _MicWaveformState();
}

class _MicWaveformState extends State<_MicWaveform> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const List<double> _speeds = <double>[1.0, 1.4, 0.8, 1.2, 0.9];
  static const List<double> _phases = <double>[0.0, 0.3, 0.6, 0.1, 0.5];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List<Widget>.generate(_speeds.length, (int i) {
            final double t = _controller.value * _speeds[i] + _phases[i];
            final double wave = (math.sin(t * 2 * math.pi) + 1) / 2;
            final double height = 10 + wave * 26;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 5,
                height: height,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _IdlePlaceholder extends StatelessWidget {
  const _IdlePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No active alarm.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _RingingLayout extends StatelessWidget {
  final AnimationController pulseController;

  const _RingingLayout({required this.pulseController});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const _DigitalClock(),
        const Spacer(),
        AnimatedBuilder(
          animation: pulseController,
          builder: (context, child) {
            final bool flashOn = pulseController.value > 0.5;
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: flashOn ? 1.0 : 0.25,
              child: child,
            );
          },
          child: const _FlashDot(),
        ),
        const Spacer(),
        const _EmergencyStopButton(),
        const SizedBox(height: 140),
      ],
    );
  }
}

/// Adhan is silenced; the Ayah is visible so the user can read it before
/// tapping "Start Reciting" to open the microphone.
class _PausedLayout extends ConsumerWidget {
  final ActiveAlarmSession? session;
  final String? speechErrorMessage;

  const _PausedLayout({required this.session, this.speechErrorMessage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ActiveAlarmSession? currentSession = session;
    if (currentSession == null) {
      return const Center(child: _MissingSessionMessage());
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        Text(
          'Read the Ayah — the microphone is opening.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (speechErrorMessage != null) ...[
          const SizedBox(height: 12),
          _SpeechErrorBanner(message: speechErrorMessage!),
        ],
        const Spacer(),
        ArabicAyahCard(arabicText: currentSession.currentAyahArabic),
        const Spacer(),
        TextButton.icon(
          onPressed: () => ref.read(alarmStateProvider.notifier).resumeAdhanFromReview(),
          icon: const Icon(Icons.volume_up),
          label: const Text('Resume Adhan'),
        ),
        const _EmergencyStopButton(),
        const SizedBox(height: 140),
      ],
    );
  }
}

class _FlashDot extends StatelessWidget {
  const _FlashDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: AppColors.accentEmerald,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _SpeechErrorBanner extends StatelessWidget {
  final String message;

  const _SpeechErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.mic_off, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecitingLayout extends StatelessWidget {
  final ActiveAlarmSession? session;
  final String? speechErrorMessage;

  const _RecitingLayout({
    required this.session,
    this.speechErrorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final ActiveAlarmSession? currentSession = session;
    if (currentSession == null) {
      return const Center(child: _MissingSessionMessage());
    }

    return Column(
      children: [
        if (speechErrorMessage != null) _SpeechErrorBanner(message: speechErrorMessage!),
        const Spacer(),
        ArabicAyahCard(
          arabicText: currentSession.currentAyahArabic,
          matchedWordFlags: currentSession.matchedWordFlags,
        ),
        const SizedBox(height: 32),
        _MatchProgressTracker(progress: currentSession.currentProgress),
        const Spacer(),
        const _EmergencyStopButton(),
        const SizedBox(height: 140),
      ],
    );
  }
}

/// The translation-recitation phase, after the Arabic Ayah clears its
/// threshold: the English translation must now be recited too, matched
/// and highlighted the same way the Ayah was.
class _RecitingTranslationLayout extends StatelessWidget {
  final ActiveAlarmSession? session;
  final String? speechErrorMessage;

  const _RecitingTranslationLayout({
    required this.session,
    this.speechErrorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final ActiveAlarmSession? currentSession = session;
    if (currentSession == null) {
      return const Center(child: _MissingSessionMessage());
    }

    return Column(
      children: [
        if (speechErrorMessage != null) _SpeechErrorBanner(message: speechErrorMessage!),
        const Spacer(),
        _TranslationCard(
          translation: currentSession.currentAyahTranslation,
          matchedWordFlags: currentSession.translationMatchedWordFlags,
        ),
        const SizedBox(height: 32),
        _MatchProgressTracker(progress: currentSession.translationProgress),
        const Spacer(),
        const _EmergencyStopButton(),
        const SizedBox(height: 140),
      ],
    );
  }
}

/// Heavily padded card holding the English translation during the
/// translation-recitation phase — same visual language as [ArabicAyahCard]
/// but left-to-right and without the Ayah above it, since by this point
/// the Ayah has already cleared and its card is off-screen.
class _TranslationCard extends StatelessWidget {
  final String translation;
  final List<bool> matchedWordFlags;

  const _TranslationCard({required this.translation, required this.matchedWordFlags});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: HighlightedWordText(
          text: translation,
          matchedWordFlags: matchedWordFlags,
          style: Theme.of(context).textTheme.headlineMedium!,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}

/// The Hybrid Escape Hatch: ducks whichever audio is currently playing and
/// opens the Emergency Fallback dialog — typing the Ayah's English
/// translation is still required to actually dismiss the alarm, so tapping
/// this alone can never silence it for free. If the dialog is cancelled
/// without a match, the Adhan resumes exactly where it left off (see
/// [AlarmStateNotifier.resumeAdhanIfFallbackCancelled]).
///
/// Deliberately more prominent than a plain text link — a user reaching
/// for a way out needs to find it immediately, not hunt for small print —
/// but still secondary to the primary voice-recitation flow (an outlined
/// button, not a FAB).
class _EmergencyStopButton extends ConsumerWidget {
  const _EmergencyStopButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => _handleTap(context, ref),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.redAccent,
        side: const BorderSide(color: Colors.redAccent, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
      icon: const Icon(Icons.stop_circle_outlined),
      label: const Text(
        'Emergency Stop / Manual Dismiss',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    final AlarmStateNotifier notifier = ref.read(alarmStateProvider.notifier);

    // The Adhan is only ever audible while `ringing` — every other active
    // state already has it silenced by design (see
    // `AlarmStateNotifier.resumeAdhanIfFallbackCancelled`'s doc comment).
    // Ducking/resuming only in that case keeps this button a no-op-safe
    // shortcut from any state, without ever *starting* playback during a
    // phase where silence is the invariant.
    final bool wasRinging = ref.read(alarmStateProvider).state == AlarmStateEnum.ringing;

    if (wasRinging) {
      await notifier.duckForEmergencyFallback();
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => const _EmergencyFallbackDialog(),
    );

    if (wasRinging) {
      await notifier.resumeAdhanIfFallbackCancelled();
    }
  }
}

class _EmergencyFallbackDialog extends ConsumerStatefulWidget {
  const _EmergencyFallbackDialog();

  @override
  ConsumerState<_EmergencyFallbackDialog> createState() =>
      _EmergencyFallbackDialogState();
}

class _EmergencyFallbackDialogState extends ConsumerState<_EmergencyFallbackDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bool accepted = await ref
        .read(alarmStateProvider.notifier)
        .submitEmergencyTranslationFallback(_controller.text);

    if (!mounted) return;

    if (accepted) {
      Navigator.of(context).pop();
    } else {
      setState(() => _errorText = "That doesn't match — check spelling and try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Emergency Snooze'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Type the English translation of the Ayah to silence the alarm. '
            'This breaks your streak.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'English translation',
              errorText: _errorText,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

/// Live speech-matching accuracy readout, updated on every recognized
/// speech chunk. Animates smoothly between values rather than jumping,
/// since [TweenAnimationBuilder] always animates from whatever value is
/// currently on screen to the new `end`, regardless of the `begin` given.
class _MatchProgressTracker extends StatelessWidget {
  final double progress;

  const _MatchProgressTracker({required this.progress});

  @override
  Widget build(BuildContext context) {
    final double clampedProgress = progress.clamp(0.0, 100.0);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: clampedProgress),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, animatedValue, child) {
        return Column(
          children: [
            Text(
              '${animatedValue.round()}%',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: animatedValue / 100,
                minHeight: 12,
                backgroundColor: AppColors.surfaceElevated,
                color: AppColors.accentEmerald,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shown on the completed screen when the alarm was silenced via the
/// Emergency Snooze fallback instead of a validated recitation, so the
/// user can see plainly that their streak was reset rather than extended.
class EmergencySnoozeBanner extends StatelessWidget {
  const EmergencySnoozeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.local_fire_department, color: Colors.redAccent),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Emergency Snooze used — your streak has been reset to 0.',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingSessionMessage extends StatelessWidget {
  const _MissingSessionMessage();

  @override
  Widget build(BuildContext context) {
    return Text(
      'No active recitation session.',
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

/// The heavily padded card holding the target Ayah, per the spec's Screen
/// Layout Blueprint. When [translation] is provided (post-completion) it is
/// revealed underneath the Arabic script.
///
/// When [matchedWordFlags] is non-empty, each word of [arabicText] is
/// colored individually — emerald once recognized, default otherwise —
/// as live real-time feedback while the user recites.
class ArabicAyahCard extends StatelessWidget {
  final String arabicText;
  final String? translation;
  final List<bool> matchedWordFlags;
  final List<bool> translationMatchedWordFlags;

  const ArabicAyahCard({
    super.key,
    required this.arabicText,
    this.translation,
    this.matchedWordFlags = const <bool>[],
    this.translationMatchedWordFlags = const <bool>[],
  });

  @override
  Widget build(BuildContext context) {
    final String? revealedTranslation = translation;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HighlightedWordText(
              text: arabicText,
              matchedWordFlags: matchedWordFlags,
              style: AppTextStyles.arabicAyah,
              textDirection: TextDirection.rtl,
            ),
            if (revealedTranslation != null) ...[
              const SizedBox(height: 24),
              HighlightedWordText(
                text: revealedTranslation,
                matchedWordFlags: translationMatchedWordFlags,
                style: Theme.of(context).textTheme.bodyLarge!,
                textDirection: TextDirection.ltr,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders [text] word by word, coloring each word emerald once
/// [matchedWordFlags] marks it recognized. Used for both the Arabic Ayah
/// (RTL) and the English translation-recitation phase (LTR) — word order
/// in [TextSpan] children always stays logical (matching [matchedWordFlags]
/// order); [textDirection] on the enclosing [Text.rich] is what lays that
/// logical sequence out left-to-right or right-to-left, so the spans
/// themselves must never be reversed.
class HighlightedWordText extends StatelessWidget {
  final String text;
  final List<bool> matchedWordFlags;
  final TextStyle style;
  final TextDirection textDirection;

  const HighlightedWordText({
    super.key,
    required this.text,
    required this.matchedWordFlags,
    required this.style,
    required this.textDirection,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> words =
        text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    if (matchedWordFlags.isEmpty || words.isEmpty) {
      return Text(
        text,
        textAlign: TextAlign.center,
        textDirection: textDirection,
        style: style,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          for (int i = 0; i < words.length; i++)
            TextSpan(
              text: i == words.length - 1 ? words[i] : '${words[i]} ',
              style: style.copyWith(
                color: (i < matchedWordFlags.length && matchedWordFlags[i])
                    ? AppColors.accentEmerald
                    : style.color,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: textDirection,
    );
  }
}

/// Live digital clock, ticking every second. Isolated into its own
/// [StatefulWidget] so only this subtree rebuilds each second rather than
/// the whole screen.
class _DigitalClock extends StatefulWidget {
  const _DigitalClock();

  @override
  State<_DigitalClock> createState() => _DigitalClockState();
}

class _DigitalClockState extends State<_DigitalClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatClock(_now),
      style: Theme.of(context).textTheme.displayLarge,
    );
  }

  static String _formatClock(DateTime time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    final String second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

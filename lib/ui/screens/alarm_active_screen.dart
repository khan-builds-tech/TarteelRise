import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/active_alarm_session.dart';
import '../../models/alarm_state_enum.dart';
import '../../providers/alarm_state_provider.dart';
import '../../providers/dashboard_providers.dart';
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

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildFab(state),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: switch (state) {
            AlarmStateEnum.idle => const _IdlePlaceholder(),
            AlarmStateEnum.ringing => _RingingLayout(pulseController: _pulseController),
            AlarmStateEnum.paused => _PausedLayout(session: sessionState.session),
            AlarmStateEnum.reciting =>
              _RecitingLayout(session: sessionState.session),
            AlarmStateEnum.recitingTranslation =>
              _RecitingTranslationLayout(session: sessionState.session),
            AlarmStateEnum.completed =>
              _CompletedLayout(session: sessionState.session),
          },
        ),
      ),
    );
  }

  Widget? _buildFab(AlarmStateEnum state) {
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
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final double scale = 1.0 + (_pulseController.value * 0.15);
            return Transform.scale(scale: scale, child: child);
          },
          child: FloatingActionButton.large(
            onPressed: () {},
            child: const Icon(Icons.mic, size: 40),
          ),
        );
      case AlarmStateEnum.idle:
      case AlarmStateEnum.completed:
        return null;
    }
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
        const _EmergencyFallbackButton(),
        const SizedBox(height: 140),
      ],
    );
  }
}

/// Adhan is silenced; the Ayah is visible so the user can read it before
/// tapping "Start Reciting" to open the microphone.
class _PausedLayout extends ConsumerWidget {
  final ActiveAlarmSession? session;

  const _PausedLayout({required this.session});

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
          'Read the Ayah, then tap Start Reciting when ready.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const Spacer(),
        _ArabicAyahCard(arabicText: currentSession.currentAyahArabic),
        const Spacer(),
        TextButton.icon(
          onPressed: () => ref.read(alarmStateProvider.notifier).resumeAdhanFromReview(),
          icon: const Icon(Icons.volume_up),
          label: const Text('Resume Adhan'),
        ),
        const _EmergencyFallbackButton(),
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

class _RecitingLayout extends StatelessWidget {
  final ActiveAlarmSession? session;

  const _RecitingLayout({required this.session});

  @override
  Widget build(BuildContext context) {
    final ActiveAlarmSession? currentSession = session;
    if (currentSession == null) {
      return const Center(child: _MissingSessionMessage());
    }

    return Column(
      children: [
        const Spacer(),
        _ArabicAyahCard(
          arabicText: currentSession.currentAyahArabic,
          matchedWordFlags: currentSession.matchedWordFlags,
        ),
        const SizedBox(height: 32),
        _MatchProgressTracker(progress: currentSession.currentProgress),
        const Spacer(),
        const _EmergencyFallbackButton(),
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

  const _RecitingTranslationLayout({required this.session});

  @override
  Widget build(BuildContext context) {
    final ActiveAlarmSession? currentSession = session;
    if (currentSession == null) {
      return const Center(child: _MissingSessionMessage());
    }

    return Column(
      children: [
        const Spacer(),
        _TranslationCard(
          translation: currentSession.currentAyahTranslation,
          matchedWordFlags: currentSession.translationMatchedWordFlags,
        ),
        const SizedBox(height: 32),
        _MatchProgressTracker(progress: currentSession.translationProgress),
        const Spacer(),
        const _EmergencyFallbackButton(),
        const SizedBox(height: 140),
      ],
    );
  }
}

/// Heavily padded card holding the English translation during the
/// translation-recitation phase — same visual language as [_ArabicAyahCard]
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
        child: _HighlightedWordText(
          text: translation,
          matchedWordFlags: matchedWordFlags,
          style: Theme.of(context).textTheme.headlineMedium!,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}

/// Entry point to the Emergency Snooze fallback — for when the user
/// genuinely cannot speak. Deliberately understated (a text button, not a
/// FAB) so it never competes with the primary voice-recitation flow.
class _EmergencyFallbackButton extends ConsumerWidget {
  const _EmergencyFallbackButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => _showEmergencyFallbackDialog(context, ref),
      icon: const Icon(Icons.keyboard),
      label: const Text("Can't speak? Type the translation instead"),
    );
  }

  Future<void> _showEmergencyFallbackDialog(BuildContext context, WidgetRef ref) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _EmergencyFallbackDialog(),
    );
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

/// Resets the state machine to `idle` and, if this screen was pushed (the
/// normal case — see `main.dart`'s ringing listener), pops back to
/// whatever was showing underneath rather than stranding the user on the
/// bare "No active alarm." placeholder.
void _finishAndReturnToDashboard(BuildContext context, WidgetRef ref) {
  ref.read(alarmStateProvider.notifier).resetToIdle();
  ref.read(userStatsProvider.notifier).refresh();
  ref.read(alarmListProvider.notifier).refresh();
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
}

class _CompletedLayout extends ConsumerWidget {
  final ActiveAlarmSession? session;

  const _CompletedLayout({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ActiveAlarmSession? currentSession = session;
    if (currentSession == null) {
      return Center(
        child: _StartYourDayButton(
          onPressed: () => ref.read(alarmStateProvider.notifier).resetToIdle(),
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        if (currentSession.completedViaEmergencyFallback) ...[
          const _EmergencySnoozeBanner(),
          const SizedBox(height: 16),
        ],
        _ArabicAyahCard(
          arabicText: currentSession.currentAyahArabic,
          translation: currentSession.currentAyahTranslation,
          matchedWordFlags: currentSession.matchedWordFlags,
          translationMatchedWordFlags: currentSession.translationMatchedWordFlags,
        ),
        const Spacer(),
        _StartYourDayButton(
          onPressed: () => _finishAndReturnToDashboard(context, ref),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Shown on the completed screen when the alarm was silenced via the
/// Emergency Snooze fallback instead of a validated recitation, so the
/// user can see plainly that their streak was reset rather than extended.
class _EmergencySnoozeBanner extends StatelessWidget {
  const _EmergencySnoozeBanner();

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
class _ArabicAyahCard extends StatelessWidget {
  final String arabicText;
  final String? translation;
  final List<bool> matchedWordFlags;
  final List<bool> translationMatchedWordFlags;

  const _ArabicAyahCard({
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
            _HighlightedWordText(
              text: arabicText,
              matchedWordFlags: matchedWordFlags,
              style: AppTextStyles.arabicAyah,
              textDirection: TextDirection.rtl,
            ),
            if (revealedTranslation != null) ...[
              const SizedBox(height: 24),
              _HighlightedWordText(
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
class _HighlightedWordText extends StatelessWidget {
  final String text;
  final List<bool> matchedWordFlags;
  final TextStyle style;
  final TextDirection textDirection;

  const _HighlightedWordText({
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

class _StartYourDayButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _StartYourDayButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: FilledButton(
        onPressed: onPressed,
        child: const Text(
          'Start Your Day',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
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

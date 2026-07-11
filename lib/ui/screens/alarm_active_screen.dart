import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/active_alarm_session.dart';
import '../../models/alarm_state_enum.dart';
import '../../providers/alarm_state_provider.dart';
import '../../theme/app_theme.dart';

/// The full-screen wake-up flow: ringing -> reciting -> completed. Layout is
/// driven entirely by [alarmStateProvider]; this widget owns no state of
/// its own beyond the pulse/flash animation ticker.
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

    // `completed` freezes the wake-up flow visually — no flashing, no
    // pulsing — everything else keeps the animation ticking.
    if (state == AlarmStateEnum.completed) {
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
            AlarmStateEnum.reciting =>
              _RecitingLayout(session: sessionState.session),
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
          onPressed: () => ref.read(alarmStateProvider.notifier).startVoiceCapture(),
          extendedPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          icon: const Icon(Icons.mic, size: 32),
          label: const Text(
            'Tap to Recite',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        );
      case AlarmStateEnum.reciting:
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
        _ArabicAyahCard(arabicText: currentSession.currentAyahArabic),
        const Spacer(),
        const SizedBox(height: 140),
      ],
    );
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
        _ArabicAyahCard(
          arabicText: currentSession.currentAyahArabic,
          translation: currentSession.currentAyahTranslation,
        ),
        const Spacer(),
        _StartYourDayButton(
          onPressed: () => ref.read(alarmStateProvider.notifier).resetToIdle(),
        ),
        const SizedBox(height: 16),
      ],
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
class _ArabicAyahCard extends StatelessWidget {
  final String arabicText;
  final String? translation;

  const _ArabicAyahCard({required this.arabicText, this.translation});

  @override
  Widget build(BuildContext context) {
    final String? revealedTranslation = translation;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              arabicText,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: AppTextStyles.arabicAyah,
            ),
            if (revealedTranslation != null) ...[
              const SizedBox(height: 24),
              Text(
                revealedTranslation,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ],
        ),
      ),
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

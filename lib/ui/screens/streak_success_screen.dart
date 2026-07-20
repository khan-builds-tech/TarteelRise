import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/active_alarm_session.dart';
import '../../providers/alarm_state_provider.dart';
import 'alarm_active_screen.dart' show ArabicAyahCard, EmergencySnoozeBanner, StartYourDayButton;

/// Shown the instant the state machine reaches `AlarmStateEnum.completed` —
/// `AppNavigationWrapper` (see `main.dart`) hard-replaces the entire
/// navigation stack with this screen as soon as that transition happens, so
/// there is no way to navigate back into the now-finished recitation flow.
///
/// Reads `alarmStateProvider` directly (no constructor params), the same
/// convention `AlarmActiveScreen` follows, since both are pushed by the same
/// state-driven router rather than given data explicitly.
class StreakSuccessScreen extends ConsumerWidget {
  const StreakSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ActiveAlarmSession? session = ref.watch(alarmStateProvider).session;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: session == null
              ? Center(
                  child: StartYourDayButton(
                    onPressed: () => ref.read(alarmStateProvider.notifier).resetToIdle(),
                  ),
                )
              : Column(
                  children: [
                    const SizedBox(height: 16),
                    if (session.completedViaEmergencyFallback) ...[
                      const EmergencySnoozeBanner(),
                      const SizedBox(height: 16),
                    ],
                    ArabicAyahCard(
                      arabicText: session.currentAyahArabic,
                      translation: session.currentAyahTranslation,
                      matchedWordFlags: session.matchedWordFlags,
                      translationMatchedWordFlags: session.translationMatchedWordFlags,
                    ),
                    const Spacer(),
                    StartYourDayButton(
                      onPressed: () => ref.read(alarmStateProvider.notifier).resetToIdle(),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
        ),
      ),
    );
  }
}

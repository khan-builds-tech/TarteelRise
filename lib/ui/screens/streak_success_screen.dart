import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/active_alarm_session.dart';
import '../../providers/alarm_state_provider.dart';
import '../../providers/dashboard_providers.dart';
import '../../theme/app_theme.dart';
import 'alarm_active_screen.dart' show EmergencySnoozeBanner;

/// Shown the instant the state machine reaches `AlarmStateEnum.completed` —
/// `AppNavigationWrapper` (see `main.dart`) hard-replaces the entire
/// navigation stack with this screen as soon as that transition happens, so
/// there is no way to navigate back into the now-finished recitation flow.
///
/// Reads `alarmStateProvider` directly (no constructor params), the same
/// convention `AlarmActiveScreen` follows, since both are pushed by the same
/// state-driven router rather than given data explicitly.
class StreakSuccessScreen extends ConsumerStatefulWidget {
  const StreakSuccessScreen({super.key});

  @override
  ConsumerState<StreakSuccessScreen> createState() => _StreakSuccessScreenState();
}

class _StreakSuccessScreenState extends ConsumerState<StreakSuccessScreen> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    // The dashboard's UserStatsNotifier only refreshes on the *next*
    // idle transition (see AppNavigationWrapper) — refresh it here too so
    // the streak count shown on this screen reflects the recitation that
    // just completed, not whatever was cached before it.
    // Deferred via microtask: this initState runs synchronously inside the
    // AppNavigationWrapper's ref.listen callback (itself triggered by the
    // alarmStateProvider transition to `completed`), so mutating another
    // provider here directly would happen mid-build and throw.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(userStatsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ActiveAlarmSession? session = ref.watch(alarmStateProvider).session;
    final int streakCount = ref.watch(userStatsProvider).streakCount;

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      const _GlowingCheckmark(),
                      const SizedBox(height: 28),
                      Text(
                        'Alhamdulillah',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Morning Recitation Completed',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 28),
                      if (session?.completedViaEmergencyFallback ?? false) ...[
                        const EmergencySnoozeBanner(),
                        const SizedBox(height: 16),
                      ],
                      _StreakCard(
                        streakCount: streakCount,
                        arabicText: session?.currentAyahArabic,
                        translation: session?.currentAyahTranslation,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ContinueToDashboardButton(
                onPressed: () => ref.read(alarmStateProvider.notifier).resetToIdle(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Emerald checkmark on a soft radial glow, scaling in on entrance.
class _GlowingCheckmark extends StatelessWidget {
  const _GlowingCheckmark();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.4, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (BuildContext context, double scale, Widget? child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: 140,
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              AppColors.accentEmerald.withValues(alpha: 0.35),
              AppColors.accentEmerald.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: const Icon(
          Icons.check_circle_rounded,
          color: AppColors.accentEmerald,
          size: 72,
        ),
      ),
    );
  }
}

/// Center card: streak count plus a compact "memory badge" of the Ayah
/// recited to complete today's alarm.
class _StreakCard extends StatelessWidget {
  final int streakCount;
  final String? arabicText;
  final String? translation;

  const _StreakCard({
    required this.streakCount,
    required this.arabicText,
    required this.translation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.local_fire_department, color: AppColors.accentEmerald),
              const SizedBox(width: 8),
              Text(
                '$streakCount Day Streak 🔥',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          if (arabicText != null && arabicText!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 20),
            Text(
              "Today's Ayah",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                arabicText!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.arabicAyah.copyWith(fontSize: 22, height: 1.6),
              ),
            ),
            if (translation != null && translation!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                translation!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ContinueToDashboardButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ContinueToDashboardButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          backgroundColor: AppColors.accentEmerald,
        ),
        child: const Text(
          'Continue to Dashboard',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

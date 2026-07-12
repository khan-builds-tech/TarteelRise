import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/surah_catalog.dart';
import '../../models/alarm_model.dart';
import '../../models/user_stats_model.dart';
import '../../providers/dashboard_providers.dart';
import '../../theme/app_theme.dart';
import 'alarm_active_screen.dart';
import 'alarm_create_screen.dart';

/// Home screen: shows the user's saved alarms, a Surah picker, and their
/// daily streak, and is the entry point to [AlarmCreateScreen].
class AlarmDashboardScreen extends ConsumerWidget {
  const AlarmDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AlarmModel> alarms = ref.watch(alarmListProvider);
    final UserStatsModel stats = ref.watch(userStatsProvider);
    final int? selectedSurahIndex = ref.watch(selectedSurahIndexProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tarteel Rise')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add Alarm',
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AlarmCreateScreen()),
          );
          ref.read(alarmListProvider.notifier).refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            _StreakBadge(streakCount: stats.streakCount),
            if (kDebugMode) ...[
              const SizedBox(height: 16),
              const _TestActiveAlarmUiButton(),
            ],
            const SizedBox(height: 32),
            Text('Your Alarms', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (alarms.isEmpty)
              const _EmptyAlarmsMessage()
            else
              ...alarms.map((alarm) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AlarmCard(alarm: alarm),
                  )),
            const SizedBox(height: 32),
            Text('Select a Surah', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...starterSurahCatalog.map((surah) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SurahTile(
                    surah: surah,
                    isSelected: surah.index == selectedSurahIndex,
                    onTap: () => ref.read(selectedSurahIndexProvider.notifier).state =
                        surah.index,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// TEMPORARY — DEBUG ONLY. Manually pushes [AlarmActiveScreen] so the
/// wake-up flow can be tested without waiting for a real scheduled alarm
/// or the Quran verse database that would normally drive it. Gated on
/// [kDebugMode] so the Dart compiler strips this out of release builds
/// entirely. Remove once real alarm scheduling triggers the screen for
/// real via [AlarmRingingListener].
class _TestActiveAlarmUiButton extends ConsumerWidget {
  const _TestActiveAlarmUiButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AlarmActiveScreen(),
            ),
          );
          // The streak may have changed while the test screen was up (a
          // completed recitation or an Emergency Snooze) — both providers
          // are long-lived singletons that only re-read Hive when
          // explicitly told to.
          ref.read(userStatsProvider.notifier).refresh();
          ref.read(alarmListProvider.notifier).refresh();
        },
        icon: const Icon(Icons.bug_report_outlined),
        label: const Text('Test Active Alarm UI'),
      ),
    );
  }
}

/// The "prominent daily streak component" from the task spec: a flame
/// badge with the current streak count.
class _StreakBadge extends StatelessWidget {
  final int streakCount;

  const _StreakBadge({required this.streakCount});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          children: [
            const Icon(
              Icons.local_fire_department,
              color: AppColors.accentEmerald,
              size: 40,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$streakCount day${streakCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    'Current streak',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAlarmsMessage extends StatelessWidget {
  const _EmptyAlarmsMessage();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(
          'No alarms yet.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  final AlarmModel alarm;

  const _AlarmCard({required this.alarm});

  @override
  Widget build(BuildContext context) {
    final String time =
        '${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatDaysOfWeek(alarm.daysOfWeek)} · '
                    '${alarm.numberOfAyahs} Ayah${alarm.numberOfAyahs == 1 ? '' : 's'} · '
                    '${_capitalize(alarm.difficultyLevel)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Icon(
              alarm.isEnabled ? Icons.alarm_on : Icons.alarm_off,
              color: alarm.isEnabled
                  ? AppColors.accentEmerald
                  : Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDaysOfWeek(List<int> daysOfWeek) {
    if (daysOfWeek.isEmpty) return 'Every day';

    const List<String> labels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final List<int> sorted = List<int>.from(daysOfWeek)..sort();
    return sorted
        .where((day) => day >= 1 && day <= 7)
        .map((day) => labels[day - 1])
        .join(', ');
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _SurahTile extends StatelessWidget {
  final Surah surah;
  final bool isSelected;
  final VoidCallback onTap;

  const _SurahTile({
    required this.surah,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isSelected ? AppColors.accentEmerald : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${surah.index}. ${surah.englishName}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${surah.ayahCount} Ayahs',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Text(
                surah.arabicName,
                textDirection: TextDirection.rtl,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              if (isSelected) ...[
                const SizedBox(width: 12),
                const Icon(Icons.check_circle, color: AppColors.accentEmerald),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

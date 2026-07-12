import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/surah_catalog.dart';
import '../../models/alarm_model.dart';
import '../../providers/alarm_state_provider.dart';
import '../../providers/dashboard_providers.dart';
import '../../theme/app_theme.dart';

/// Builds a new [AlarmModel], persists it via [DatabaseService.saveAlarm],
/// and schedules it via [AlarmHardwareService.scheduleMorningAlarm] —
/// tying together the storage and hardware layers built in earlier phases.
class AlarmCreateScreen extends ConsumerStatefulWidget {
  const AlarmCreateScreen({super.key});

  @override
  ConsumerState<AlarmCreateScreen> createState() => _AlarmCreateScreenState();
}

class _AlarmCreateScreenState extends ConsumerState<AlarmCreateScreen> {
  static const List<String> _dayLabels = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const List<String> _difficultyLevels = <String>['easy', 'medium', 'hard'];

  late TimeOfDay _selectedTime;
  final Set<int> _selectedDays = <int>{};
  late int _selectedSurahIndex;
  late int _numberOfAyahs;
  String _difficultyLevel = 'medium';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedTime = TimeOfDay.now();
    _numberOfAyahs = 3;
    // Pre-fill from whatever the Dashboard's Surah picker was last set to,
    // so tapping a Surah there then "Add Alarm" here feels connected.
    _selectedSurahIndex =
        ref.read(selectedSurahIndexProvider) ?? starterSurahCatalog.first.index;
  }

  Surah get _selectedSurah =>
      starterSurahCatalog.firstWhere((surah) => surah.index == _selectedSurahIndex);

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
  }

  void _selectSurah(Surah surah) {
    setState(() {
      _selectedSurahIndex = surah.index;
      if (_numberOfAyahs > surah.ayahCount) {
        _numberOfAyahs = surah.ayahCount;
      }
    });
  }

  void _adjustAyahCount(int delta) {
    setState(() {
      _numberOfAyahs = (_numberOfAyahs + delta).clamp(1, _selectedSurah.ayahCount);
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final AlarmModel alarm = AlarmModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      hour: _selectedTime.hour,
      minute: _selectedTime.minute,
      daysOfWeek: _selectedDays.toList()..sort(),
      isEnabled: true,
      selectedSurahIndex: _selectedSurahIndex,
      numberOfAyahs: _numberOfAyahs,
      difficultyLevel: _difficultyLevel,
    );

    await ref.read(databaseServiceProvider).saveAlarm(alarm);
    final bool scheduled =
        await ref.read(alarmHardwareServiceProvider).scheduleMorningAlarm(alarm);
    ref.read(alarmListProvider.notifier).refresh();

    if (!mounted) return;

    if (!scheduled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alarm saved, but could not be scheduled on this device.'),
        ),
      );
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Alarm')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            _TimePickerCard(time: _selectedTime, onTap: _pickTime),
            const SizedBox(height: 24),
            Text('Repeat', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _DaysOfWeekSelector(
              labels: _dayLabels,
              selectedDays: _selectedDays,
              onToggle: _toggleDay,
            ),
            const SizedBox(height: 24),
            Text('Surah', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _SurahPicker(
              selectedIndex: _selectedSurahIndex,
              onSelected: _selectSurah,
            ),
            const SizedBox(height: 24),
            Text('Ayahs to Recite', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _AyahCountStepper(
              count: _numberOfAyahs,
              maxCount: _selectedSurah.ayahCount,
              onAdjust: _adjustAyahCount,
            ),
            const SizedBox(height: 24),
            Text('Difficulty', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _DifficultySelector(
              levels: _difficultyLevels,
              selected: _difficultyLevel,
              onSelected: (level) => setState(() => _difficultyLevel = level),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Alarm',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimePickerCard({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                time.format(context),
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(width: 12),
              const Icon(Icons.edit, color: AppColors.accentEmerald),
            ],
          ),
        ),
      ),
    );
  }
}

class _DaysOfWeekSelector extends StatelessWidget {
  final List<String> labels;
  final Set<int> selectedDays;
  final void Function(int day) onToggle;

  const _DaysOfWeekSelector({
    required this.labels,
    required this.selectedDays,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List<Widget>.generate(labels.length, (i) {
        final int day = i + 1;
        final bool isSelected = selectedDays.contains(day);
        return _DayToggle(
          label: labels[i],
          isSelected: isSelected,
          onTap: () => onToggle(day),
        );
      }),
    );
  }
}

class _DayToggle extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayToggle({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? AppColors.accentEmerald : AppColors.surfaceElevated,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SurahPicker extends StatelessWidget {
  final int selectedIndex;
  final void Function(Surah surah) onSelected;

  const _SurahPicker({required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: starterSurahCatalog.map((surah) {
        final bool isSelected = surah.index == selectedIndex;
        return ChoiceChip(
          label: Text('${surah.index}. ${surah.englishName}'),
          selected: isSelected,
          onSelected: (_) => onSelected(surah),
        );
      }).toList(),
    );
  }
}

class _AyahCountStepper extends StatelessWidget {
  final int count;
  final int maxCount;
  final void Function(int delta) onAdjust;

  const _AyahCountStepper({
    required this.count,
    required this.maxCount,
    required this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: count > 1 ? () => onAdjust(-1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$count of $maxCount', style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              onPressed: count < maxCount ? () => onAdjust(1) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultySelector extends StatelessWidget {
  final List<String> levels;
  final String selected;
  final void Function(String level) onSelected;

  const _DifficultySelector({
    required this.levels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: levels
          .map((level) => ButtonSegment<String>(
                value: level,
                label: Text(level[0].toUpperCase() + level.substring(1)),
              ))
          .toList(),
      selected: <String>{selected},
      onSelectionChanged: (newSelection) => onSelected(newSelection.first),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/surah_catalog.dart';
import '../../models/alarm_model.dart';
import '../../providers/alarm_state_provider.dart';
import '../../providers/dashboard_providers.dart';
import '../../theme/app_theme.dart';

/// Builds an [AlarmModel] — a brand new one, or an edit of
/// [existingAlarm] — persists it via `DatabaseService.saveAlarm`, and
/// schedules it via `AlarmHardwareService.scheduleMorningAlarm`, tying
/// together the storage and hardware layers built in earlier phases.
///
/// The user only ever picks a Surah here — which specific Ayah gets
/// recited is decided fresh every time the alarm actually rings (see
/// `QuranRepository.buildRandomChallenge`), not at creation time. There is
/// no per-alarm difficulty level — every recitation gate uses the same
/// fixed match threshold (`AlarmStateNotifier`'s `_matchThreshold`).
class AlarmCreateScreen extends ConsumerStatefulWidget {
  /// Null for the "Add Alarm" flow. Non-null when reached by tapping an
  /// existing alarm on the dashboard to edit it — [_AlarmCreateScreenState]
  /// pre-fills every field from it and saves back under the same `id`
  /// instead of minting a new one.
  final AlarmModel? existingAlarm;

  const AlarmCreateScreen({super.key, this.existingAlarm});

  @override
  ConsumerState<AlarmCreateScreen> createState() => _AlarmCreateScreenState();
}

class _AlarmCreateScreenState extends ConsumerState<AlarmCreateScreen> {
  static const List<String> _dayLabels = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  late TimeOfDay _selectedTime;
  final Set<int> _selectedDays = <int>{};

  /// Null only if [QuranRepository.loadFromAssets] never completed (a
  /// bundled-asset failure) — [build] shows a fallback message instead of
  /// the form in that case, so nothing below this ever has to null-check
  /// it once the form is actually showing.
  Surah? _selectedSurah;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final List<Surah> allSurahs = ref.read(quranRepositoryProvider).allSurahs;
    final AlarmModel? existing = widget.existingAlarm;

    if (existing != null) {
      _selectedTime = TimeOfDay(hour: existing.hour, minute: existing.minute);
      _selectedDays.addAll(existing.daysOfWeek);
      _selectedSurah = _findSurah(allSurahs, existing.selectedSurahIndex) ?? _firstOrNull(allSurahs);
    } else {
      _selectedTime = TimeOfDay.now();
      _selectedSurah = _firstOrNull(allSurahs);
    }
  }

  static Surah? _findSurah(List<Surah> surahs, int id) {
    for (final Surah surah in surahs) {
      if (surah.id == id) return surah;
    }
    return null;
  }

  static Surah? _firstOrNull(List<Surah> surahs) => surahs.isEmpty ? null : surahs.first;

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
    setState(() => _selectedSurah = surah);
  }

  Future<void> _save() async {
    final Surah? surah = _selectedSurah;
    if (surah == null) return;

    setState(() => _isSaving = true);

    final AlarmModel? existing = widget.existingAlarm;
    final AlarmModel alarm = AlarmModel(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      hour: _selectedTime.hour,
      minute: _selectedTime.minute,
      daysOfWeek: _selectedDays.toList()..sort(),
      isEnabled: existing?.isEnabled ?? true,
      selectedSurahIndex: surah.id,
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
    final bool isEditing = widget.existingAlarm != null;
    final List<Surah> allSurahs = ref.watch(quranRepositoryProvider).allSurahs;
    final Surah? surah = _selectedSurah;

    if (allSurahs.isEmpty || surah == null) {
      return Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit Alarm' : 'New Alarm')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Text(
              'The Quran dataset failed to load, so a Surah can\'t be '
              'selected. Restart the app to try again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Alarm' : 'New Alarm')),
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
            // Extra breathing room before the Surah section, now that it's
            // the last input before the Save button rather than one of
            // several stacked sections.
            const SizedBox(height: 40),
            Text('Surah', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Each morning picks a fresh, short random Ayah from this Surah '
              'to challenge you with.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _SurahDropdown(
              allSurahs: allSurahs,
              selected: surah,
              onSelected: _selectSurah,
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
                    : Text(
                        isEditing ? 'Save Changes' : 'Save Alarm',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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

/// Searchable, scrollable Surah selector — a Material 3 [DropdownMenu]
/// covering the full 114-Surah catalog. Typing filters the list by its
/// displayed label (id, transliteration, Arabic name, or Ayah count all
/// match), and the menu itself scrolls rather than trying to lay out all
/// 114 entries at once.
class _SurahDropdown extends StatelessWidget {
  final List<Surah> allSurahs;
  final Surah selected;
  final void Function(Surah surah) onSelected;

  const _SurahDropdown({
    required this.allSurahs,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<Surah>(
      width: MediaQuery.of(context).size.width - 48,
      menuHeight: 420,
      enableFilter: true,
      enableSearch: true,
      label: const Text('Surah'),
      initialSelection: selected,
      dropdownMenuEntries: allSurahs
          .map((surah) => DropdownMenuEntry<Surah>(
                value: surah,
                label: '${surah.id}. ${surah.transliteration} (${surah.name}) - '
                    '${surah.totalVerses} Ayahs',
              ))
          .toList(),
      onSelected: (Surah? value) {
        if (value != null) onSelected(value);
      },
    );
  }
}

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
  static const List<String> _difficultyLevels = <String>['easy', 'medium', 'hard'];

  late TimeOfDay _selectedTime;
  final Set<int> _selectedDays = <int>{};

  /// Null only if [QuranRepository.loadFromAssets] never completed (a
  /// bundled-asset failure) — [build] shows a fallback message instead of
  /// the form in that case, so nothing below this ever has to null-check
  /// it once the form is actually showing.
  Surah? _selectedSurah;

  /// The specific Ayah number this alarm starts reciting from — the
  /// user's chosen "wake-up challenge verse". Persisted as
  /// [AlarmModel.currentBookmarkAyah]; Smart Bookmarking then advances it
  /// automatically after each validated recitation, same as before, just
  /// now with an explicit, user-editable starting point instead of always
  /// defaulting silently to 1.
  late int _selectedStartingAyah;

  late int _numberOfAyahs;
  String _difficultyLevel = 'medium';
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
      _numberOfAyahs = existing.numberOfAyahs;
      _difficultyLevel = existing.difficultyLevel;
      _selectedStartingAyah = existing.currentBookmarkAyah;
    } else {
      _selectedTime = TimeOfDay.now();
      _numberOfAyahs = 3;
      _selectedStartingAyah = 1;
      // Pre-fill from whatever the Dashboard's Surah picker was last set
      // to, so tapping a Surah there then "Add Alarm" here feels connected.
      final int? preselectedId = ref.read(selectedSurahIndexProvider);
      _selectedSurah = (preselectedId == null ? null : _findSurah(allSurahs, preselectedId)) ??
          _firstOrNull(allSurahs);
    }

    // Defensive clamp — guards against persisted data (or a pre-selected
    // id) referencing an Ayah number outside this Surah's real range.
    final Surah? surah = _selectedSurah;
    if (surah != null) {
      _numberOfAyahs = _numberOfAyahs.clamp(1, surah.totalVerses);
      _selectedStartingAyah = _selectedStartingAyah.clamp(1, surah.totalVerses);
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
    setState(() {
      _selectedSurah = surah;
      // A different Surah invalidates both the ayah count and the
      // starting Ayah if they overran the new Surah's shorter length.
      if (_numberOfAyahs > surah.totalVerses) {
        _numberOfAyahs = surah.totalVerses;
      }
      if (_selectedStartingAyah > surah.totalVerses) {
        _selectedStartingAyah = surah.totalVerses;
      }
    });
  }

  void _selectStartingAyah(int ayahNumber) {
    setState(() => _selectedStartingAyah = ayahNumber);
  }

  void _adjustAyahCount(int delta) {
    final Surah? surah = _selectedSurah;
    if (surah == null) return;
    setState(() {
      _numberOfAyahs = (_numberOfAyahs + delta).clamp(1, surah.totalVerses);
    });
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
      numberOfAyahs: _numberOfAyahs,
      difficultyLevel: _difficultyLevel,
      currentBookmarkAyah: _selectedStartingAyah,
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
            const SizedBox(height: 24),
            Text('Surah', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _SurahDropdown(
              allSurahs: allSurahs,
              selected: surah,
              onSelected: _selectSurah,
            ),
            const SizedBox(height: 24),
            Text('Starting Ayah', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'The specific verse this alarm challenges you to recite from.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _AyahNumberDropdown(
              key: ValueKey(surah.id),
              totalVerses: surah.totalVerses,
              selected: _selectedStartingAyah,
              onSelected: _selectStartingAyah,
            ),
            const SizedBox(height: 24),
            Text('Ayahs to Recite', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _AyahCountStepper(
              count: _numberOfAyahs,
              maxCount: surah.totalVerses,
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

/// Dependent dropdown populated from the selected Surah's [totalVerses] —
/// picks the specific starting Ayah number (the "wake-up challenge
/// verse"). Rebuilt (via the `ValueKey(surah.id)` the caller assigns) any
/// time the Surah changes, so it never shows stale entries from the
/// previous Surah's length.
class _AyahNumberDropdown extends StatelessWidget {
  final int totalVerses;
  final int selected;
  final void Function(int ayahNumber) onSelected;

  const _AyahNumberDropdown({
    super.key,
    required this.totalVerses,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<int>(
      width: MediaQuery.of(context).size.width - 48,
      menuHeight: 420,
      enableFilter: true,
      enableSearch: true,
      label: const Text('Starting Ayah'),
      initialSelection: selected,
      dropdownMenuEntries: List<DropdownMenuEntry<int>>.generate(
        totalVerses,
        (int i) => DropdownMenuEntry<int>(value: i + 1, label: 'Ayah ${i + 1}'),
      ),
      onSelected: (int? value) {
        if (value != null) onSelected(value);
      },
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

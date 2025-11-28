import 'package:flutter/material.dart';

class DateRangeFilterButton extends StatelessWidget {
  const DateRangeFilterButton({
    super.key,
    required this.label,
    this.startDate,
    this.endDate,
    required this.onRangeSelected,
    required this.onClear,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTimeRange> onRangeSelected;
  final VoidCallback onClear;
  final DateTime? firstDate;
  final DateTime? lastDate;

  bool get _hasSelection => startDate != null && endDate != null;

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    var effectiveFirstDate = firstDate ?? DateTime(now.year - 10);
    var effectiveLastDate = lastDate ?? DateTime(now.year + 10);

    if (startDate != null) {
      final startOnly = DateUtils.dateOnly(startDate!);
      if (startOnly.isBefore(effectiveFirstDate)) {
        effectiveFirstDate = startOnly;
      }
    }

    if (endDate != null) {
      final endOnly = DateUtils.dateOnly(endDate!);
      if (endOnly.isAfter(effectiveLastDate)) {
        effectiveLastDate = endOnly;
      }
    }

    if (effectiveLastDate.isBefore(effectiveFirstDate)) {
      effectiveLastDate = effectiveFirstDate;
    }

    final initialRange = _hasSelection
        ? DateTimeRange(
            start: DateUtils.dateOnly(startDate!),
            end: DateUtils.dateOnly(endDate!),
          )
        : null;

    final range = await showDateRangePicker(
      context: context,
      firstDate: effectiveFirstDate,
      lastDate: effectiveLastDate,
      initialDateRange: initialRange,
      helpText: 'Select $label range',
    );

    if (range != null) {
      onRangeSelected(
        DateTimeRange(
          start: DateUtils.dateOnly(range.start),
          end: DateUtils.dateOnly(range.end),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final hasSelection = _hasSelection;

    String buttonLabel;
    if (hasSelection) {
      final start = localizations.formatMediumDate(startDate!);
      final end = localizations.formatMediumDate(endDate!);
      buttonLabel = '$label: $start – $end';
    } else {
      buttonLabel = 'Filter by $label';
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonal(
          onPressed: () => _pickRange(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.date_range),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  buttonLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (hasSelection)
          IconButton(
            tooltip: 'Clear $label filter',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }
}

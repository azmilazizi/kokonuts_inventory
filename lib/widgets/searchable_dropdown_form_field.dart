import 'package:flutter/material.dart';

class SearchableDropdownFormField<T> extends FormField<T> {
  SearchableDropdownFormField({
    super.key,
    required List<T> items,
    required this.itemToString,
    this.onChanged,
    this.decoration = const InputDecoration(),
    this.hintText,
    this.enabled = true,
    this.dialogTitle,
    this.searchLabel = 'Search',
    this.emptyLabel = 'No options available',
    T? initialValue,
    FormFieldValidator<T>? validator,
  })  : _items = items,
        super(
          initialValue: initialValue,
          validator: validator,
          builder: (FormFieldState<T> field) {
            final state = field as _SearchableDropdownFormFieldState<T>;
            final theme = Theme.of(field.context);
            final selectedLabel = state._labelForValue(field.value);

            final placeholderStyle = theme.textTheme.bodyLarge?.copyWith(
              color: theme.hintColor,
            );

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: state._isEnabled
                  ? () async {
                      final selected = await state._showSearchDialog(field.context);
                      if (selected != null) {
                        field.didChange(selected);
                        onChanged?.call(selected);
                      }
                    }
                  : null,
              child: InputDecorator(
                decoration: decoration.copyWith(
                  errorText: field.errorText,
                  enabled: state._isEnabled,
                ),
                child: selectedLabel != null
                    ? Text(selectedLabel)
                    : Text(hintText ?? 'Select an option', style: placeholderStyle),
              ),
            );
          },
        );

  final List<T> _items;
  final String Function(T) itemToString;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final String? hintText;
  final bool enabled;
  final String? dialogTitle;
  final String searchLabel;
  final String emptyLabel;

  @override
  FormFieldState<T> createState() => _SearchableDropdownFormFieldState<T>();
}

class _SearchableDropdownFormFieldState<T> extends FormFieldState<T> {
  @override
  SearchableDropdownFormField<T> get widget => super.widget as SearchableDropdownFormField<T>;

  bool get _isEnabled => widget.enabled && widget.onChanged != null;

  String? _labelForValue(T? value) {
    if (value == null) return null;
    try {
      return widget.itemToString(value);
    } catch (_) {
      return null;
    }
  }

  Future<T?> _showSearchDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final query = controller.text.toLowerCase();
            final filteredItems = widget._items.where((item) {
              final label = widget.itemToString(item).toLowerCase();
              return label.contains(query);
            }).toList();

            return AlertDialog(
              title: Text(widget.dialogTitle ?? 'Select an option'),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: widget.searchLabel,
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                              child: Text(widget.emptyLabel),
                            )
                          : Scrollbar(
                              child: ListView.builder(
                                itemCount: filteredItems.length,
                                itemBuilder: (context, index) {
                                  final item = filteredItems[index];
                                  final label = widget.itemToString(item);
                                  return ListTile(
                                    title: Text(label),
                                    onTap: () => Navigator.of(dialogContext).pop(item),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

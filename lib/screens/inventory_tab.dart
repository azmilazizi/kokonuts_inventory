import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/inventory_manage_service.dart';

enum InventoryStockFilter { inStock, lowStock, outOfStock }

enum InventorySortOption { name, sku, unit, quantity }

class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab>
    with AutomaticKeepAliveClientMixin {
  final _service = InventoryManageService();

  List<InventoryWarehouseOption> _warehouses = const [];
  List<InventoryManageItem> _items = const [];
  List<InventoryUnitOption> _units = const [];
  List<InventoryItemGroupOption> _itemGroups = const [];
  final Set<String> _selectedWarehouseIds = {};
  final Set<InventoryStockFilter> _selectedStockFilters = {};
  final Set<String> _selectedGroupIds = {};
  InventorySortOption _selectedSortOption = InventorySortOption.name;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }

    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'You are not logged in.';
      });
      return;
    }

    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken = token
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    final normalizedAuth = sanitizedToken.isNotEmpty
        ? 'Bearer $sanitizedToken'
        : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();

    final authtokenHeader =
        autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;

    final headers = {
      'Accept': 'application/json',
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };

    try {
      final results = await Future.wait([
        _service.fetchWarehouses(headers: headers),
        _service.fetchInventoryItems(headers: headers),
        _service.fetchUnits(headers: headers),
        _service.fetchItemGroups(headers: headers),
      ]);
      if (!mounted) {
        return;
      }

      setState(() {
        _warehouses = results[0] as List<InventoryWarehouseOption>;
        _items = results[1] as List<InventoryManageItem>;
        _units = results[2] as List<InventoryUnitOption>;
        _itemGroups = results[3] as List<InventoryItemGroupOption>;
        _error = null;
      });
    } on InventoryManageException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final filteredItems = _filteredItems();
    final groupOptions = _groupOptions();
    final unitsById = {for (final unit in _units) unit.id: unit};
    final groupsById = {for (final group in _itemGroups) group.id: group};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 600;
              final searchField = TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search SKU code or name',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                ),
              );

              final filterButton = OutlinedButton.icon(
                onPressed: () => _openFilterSheet(
                  context,
                  groupOptions: groupOptions,
                ),
                icon: const Icon(Icons.filter_list),
                label: const Text('Filters'),
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 12),
                    filterButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  filterButton,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_isLoading && _items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                else if (_error != null)
                  _ErrorState(message: _error!, onRetry: _loadData)
                else if (filteredItems.isEmpty)
                  _EmptyState(
                    message: 'No inventory items match the selected filters.',
                  )
                else
                  ...filteredItems.map(
                    (item) => _InventoryItemCard(
                      item: item,
                      quantity: _calculateQuantity(item),
                      minValue: item.inventoryNumberMin ?? 0,
                      maxValue: item.inventoryNumberMax ?? 0,
                      unitLabel: unitsById[item.unitId]?.label ?? '—',
                      groupLabel: groupsById[item.groupId]?.label,
                      warehousesFilter: _selectedWarehouseIds,
                    ),
                  ),
                if (_isLoading && _items.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<InventoryManageItem> _filteredItems() {
    final filtered = _items.where((item) {
      final qty = _calculateQuantity(item);
      final minValue = item.inventoryNumberMin ?? 0;

      if (_selectedStockFilters.isNotEmpty &&
          !_selectedStockFilters.any(
            (filter) => _matchesStockFilter(filter, qty, minValue),
          )) {
        return false;
      }

      if (_selectedGroupIds.isNotEmpty &&
          !_selectedGroupIds.contains(item.groupId)) {
        return false;
      }

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery;
        final code = item.skuCode.toLowerCase();
        final name = item.skuName.toLowerCase();
        if (!code.contains(query) && !name.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();

    final unitsById = {
      for (final unit in _units) unit.id: unit.label.toLowerCase(),
    };

    switch (_selectedSortOption) {
      case InventorySortOption.name:
        filtered.sort(
          (a, b) => a.skuName.toLowerCase().compareTo(b.skuName.toLowerCase()),
        );
      case InventorySortOption.sku:
        filtered.sort(
          (a, b) => a.skuCode.toLowerCase().compareTo(b.skuCode.toLowerCase()),
        );
      case InventorySortOption.unit:
        filtered.sort((a, b) {
          final unitA = unitsById[a.unitId] ?? '';
          final unitB = unitsById[b.unitId] ?? '';
          return unitA.compareTo(unitB);
        });
      case InventorySortOption.quantity:
        filtered.sort(
          (a, b) => _calculateQuantity(a).compareTo(_calculateQuantity(b)),
        );
    }

    return filtered;
  }

  bool _matchesStockFilter(
    InventoryStockFilter filter,
    double quantity,
    double minValue,
  ) {
    switch (filter) {
      case InventoryStockFilter.inStock:
        return quantity > minValue;
      case InventoryStockFilter.lowStock:
        return quantity > 0 && quantity <= minValue;
      case InventoryStockFilter.outOfStock:
        return quantity == 0;
    }
  }

  double _calculateQuantity(InventoryManageItem item) {
    if (item.inventoryManage.isEmpty) {
      return 0;
    }

    final selectedIds = _selectedWarehouseIds;
    return item.inventoryManage
        .where((entry) =>
            selectedIds.isEmpty || selectedIds.contains(entry.warehouseId))
        .fold<double>(
          0,
          (sum, entry) => sum + entry.inventoryNumber,
        );
  }

  void _handleWarehouseSelection(Set<String> selectedIds) {
    setState(() {
      _selectedWarehouseIds
        ..clear()
        ..addAll(selectedIds);
    });
  }

  void _handleStockFilterSelection(Set<InventoryStockFilter> selectedFilters) {
    setState(() {
      _selectedStockFilters
        ..clear()
        ..addAll(selectedFilters);
    });
  }

  void _handleGroupSelection(Set<String> selectedGroupIds) {
    setState(() {
      _selectedGroupIds
        ..clear()
        ..addAll(selectedGroupIds);
    });
  }

  void _handleSortSelection(InventorySortOption selectedOption) {
    setState(() {
      _selectedSortOption = selectedOption;
    });
  }

  void _handleSearchChanged() {
    final value = _searchController.text.trim().toLowerCase();
    if (value == _searchQuery) {
      return;
    }
    setState(() {
      _searchQuery = value;
    });
  }

  List<_MultiSelectOption<String>> _groupOptions() {
    final presentGroups = _items
        .map((item) => item.groupId)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    final groupsById = {for (final group in _itemGroups) group.id: group};
    final options = presentGroups
        .map((id) => groupsById[id])
        .whereType<InventoryItemGroupOption>()
        .map(
          (group) => _MultiSelectOption(value: group.id, label: group.label),
        )
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return options;
  }

  String _sortOptionLabel(InventorySortOption option) {
    switch (option) {
      case InventorySortOption.name:
        return 'Name';
      case InventorySortOption.sku:
        return 'SKU';
      case InventorySortOption.unit:
        return 'Unit';
      case InventorySortOption.quantity:
        return 'Quantity';
    }
  }

  Future<void> _openFilterSheet(
    BuildContext context, {
    required List<_MultiSelectOption<String>> groupOptions,
  }) async {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final fieldSpacing = isCompact ? 12.0 : 16.0;

    final sortField = DropdownButtonFormField<InventorySortOption>(
      value: _selectedSortOption,
      decoration: InputDecoration(
        labelText: 'Sort by',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: InventorySortOption.values
          .map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(_sortOptionLabel(option)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          _handleSortSelection(value);
        }
      },
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (isCompact)
                  Column(
                    children: [
                      _MultiSelectField<String>(
                        label: 'Warehouses',
                        options: _warehouses
                            .map(
                              (warehouse) => _MultiSelectOption(
                                value: warehouse.id,
                                label: warehouse.label,
                              ),
                            )
                            .toList(),
                        selectedValues: _selectedWarehouseIds,
                        emptyLabel: 'All warehouses',
                        onChanged: _handleWarehouseSelection,
                      ),
                      SizedBox(height: fieldSpacing),
                      _MultiSelectField<InventoryStockFilter>(
                        label: 'Quantity status',
                        options: const [
                          _MultiSelectOption(
                            value: InventoryStockFilter.inStock,
                            label: 'In stock',
                          ),
                          _MultiSelectOption(
                            value: InventoryStockFilter.lowStock,
                            label: 'Low stock',
                          ),
                          _MultiSelectOption(
                            value: InventoryStockFilter.outOfStock,
                            label: 'Out of stock',
                          ),
                        ],
                        selectedValues: _selectedStockFilters,
                        emptyLabel: 'All statuses',
                        onChanged: _handleStockFilterSelection,
                      ),
                      SizedBox(height: fieldSpacing),
                      _MultiSelectField<String>(
                        label: 'Item groups',
                        options: groupOptions,
                        selectedValues: _selectedGroupIds,
                        emptyLabel: 'All groups',
                        onChanged: _handleGroupSelection,
                      ),
                      SizedBox(height: fieldSpacing),
                      sortField,
                    ],
                  )
                else
                  Wrap(
                    spacing: fieldSpacing,
                    runSpacing: fieldSpacing,
                    children: [
                      SizedBox(
                        width: 280,
                        child: _MultiSelectField<String>(
                          label: 'Warehouses',
                          options: _warehouses
                              .map(
                                (warehouse) => _MultiSelectOption(
                                  value: warehouse.id,
                                  label: warehouse.label,
                                ),
                              )
                              .toList(),
                          selectedValues: _selectedWarehouseIds,
                          emptyLabel: 'All warehouses',
                          onChanged: _handleWarehouseSelection,
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: _MultiSelectField<InventoryStockFilter>(
                          label: 'Quantity status',
                          options: const [
                            _MultiSelectOption(
                              value: InventoryStockFilter.inStock,
                              label: 'In stock',
                            ),
                            _MultiSelectOption(
                              value: InventoryStockFilter.lowStock,
                              label: 'Low stock',
                            ),
                            _MultiSelectOption(
                              value: InventoryStockFilter.outOfStock,
                              label: 'Out of stock',
                            ),
                          ],
                          selectedValues: _selectedStockFilters,
                          emptyLabel: 'All statuses',
                          onChanged: _handleStockFilterSelection,
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: _MultiSelectField<String>(
                          label: 'Item groups',
                          options: groupOptions,
                          selectedValues: _selectedGroupIds,
                          emptyLabel: 'All groups',
                          onChanged: _handleGroupSelection,
                        ),
                      ),
                      SizedBox(width: 200, child: sortField),
                    ],
                  ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _MultiSelectField<T> extends StatelessWidget {
  const _MultiSelectField({
    required this.label,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    required this.emptyLabel,
  });

  final String label;
  final List<_MultiSelectOption<T>> options;
  final Set<T> selectedValues;
  final ValueChanged<Set<T>> onChanged;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = selectedValues.isEmpty
        ? emptyLabel
        : options
            .where((option) => selectedValues.contains(option.value))
            .map((option) => option.label)
            .join(', ');

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openSelector(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withOpacity(0.6),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    );
  }

  Future<void> _openSelector(BuildContext context) async {
    final localSelection = Set<T>.from(selectedValues);
    final theme = Theme.of(context);

    final updated = await showModalBottomSheet<Set<T>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (options.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No options available.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: options.map((option) {
                            final isSelected =
                                localSelection.contains(option.value);
                            return CheckboxListTile(
                              value: isSelected,
                              title: Text(option.label),
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                8,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    localSelection.add(option.value);
                                  } else {
                                    localSelection.remove(option.value);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(localSelection.clear);
                          },
                          child: const Text('Clear'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: options.isEmpty
                              ? null
                              : () => Navigator.of(context).pop(localSelection),
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (updated != null) {
      onChanged(updated);
    }
  }
}

class _MultiSelectOption<T> {
  const _MultiSelectOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _InventoryItemCard extends StatelessWidget {
  const _InventoryItemCard({
    required this.item,
    required this.quantity,
    required this.minValue,
    required this.maxValue,
    required this.unitLabel,
    required this.groupLabel,
    required this.warehousesFilter,
  });

  final InventoryManageItem item;
  final double quantity;
  final double minValue;
  final double maxValue;
  final String unitLabel;
  final String? groupLabel;
  final Set<String> warehousesFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lots = item.inventoryManage
        .where((entry) =>
            warehousesFilter.isEmpty ||
            warehousesFilter.contains(entry.warehouseId))
        .toList();

    final quantityColor = _quantityColor(theme, quantity, minValue);
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.6),
      fontStyle: FontStyle.italic,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.skuCode,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (groupLabel != null && groupLabel!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _GroupChip(label: groupLabel!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.skuName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text('Min ${_formatNumber(minValue)}', style: mutedStyle),
                      Text('•', style: mutedStyle),
                      Text('Max ${_formatNumber(maxValue)}', style: mutedStyle),
                      Text('•', style: mutedStyle),
                      Text(unitLabel, style: mutedStyle),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _QuantityText(
              value: _formatNumber(quantity),
              textColor: quantityColor,
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: lots.isEmpty
                ? Text(
                    'No lot information available.',
                    style: theme.textTheme.bodyMedium,
                  )
                : Column(
                    children: [
                      const SizedBox(height: 12),
                      const _LotHeaderRow(),
                      const Divider(height: 16),
                      ...lots.map((lot) => _LotRow(lot: lot)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(double value) {
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  Color _quantityColor(ThemeData theme, double value, double minValue) {
    if (value == 0) {
      return Colors.red.shade600;
    }
    if (value <= minValue) {
      return Colors.amber.shade700;
    }
    return Colors.green.shade600;
  }

}

class _QuantityText extends StatelessWidget {
  const _QuantityText({
    required this.value,
    required this.textColor,
  });

  final String value;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }
}

class _LotHeaderRow extends StatelessWidget {
  const _LotHeaderRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            'Lot number',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Quantity',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Purchase price',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _LotRow extends StatelessWidget {
  const _LotRow({required this.lot});

  final InventoryManageLot lot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(lot.lotNumber.isEmpty ? '—' : lot.lotNumber),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatNumber(lot.inventoryNumber),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              lot.purchasePrice.isEmpty ? '—' : lot.purchasePrice,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(double value) {
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(message, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

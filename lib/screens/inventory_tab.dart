import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/inventory_manage_service.dart';

enum InventoryStockFilter { inStock, lowStock, outOfStock }

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
  final Set<String> _selectedWarehouseIds = {};
  final Set<InventoryStockFilter> _selectedStockFilters = {};

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
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
      ]);
      if (!mounted) {
        return;
      }

      setState(() {
        _warehouses = results[0] as List<InventoryWarehouseOption>;
        _items = results[1] as List<InventoryManageItem>;
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

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _FilterSection(
            warehouses: _warehouses,
            selectedWarehouseIds: _selectedWarehouseIds,
            selectedStockFilters: _selectedStockFilters,
            onWarehouseChanged: _handleWarehouseSelection,
            onStockFilterChanged: _handleStockFilterSelection,
          ),
          const SizedBox(height: 16),
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
    );
  }

  List<InventoryManageItem> _filteredItems() {
    if (_selectedStockFilters.isEmpty) {
      return _items;
    }

    return _items.where((item) {
      final qty = _calculateQuantity(item);
      final minValue = item.inventoryNumberMin ?? 0;
      return _selectedStockFilters.any(
        (filter) => _matchesStockFilter(filter, qty, minValue),
      );
    }).toList();
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

  @override
  bool get wantKeepAlive => true;
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.warehouses,
    required this.selectedWarehouseIds,
    required this.selectedStockFilters,
    required this.onWarehouseChanged,
    required this.onStockFilterChanged,
  });

  final List<InventoryWarehouseOption> warehouses;
  final Set<String> selectedWarehouseIds;
  final Set<InventoryStockFilter> selectedStockFilters;
  final ValueChanged<Set<String>> onWarehouseChanged;
  final ValueChanged<Set<InventoryStockFilter>> onStockFilterChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _MultiSelectField<String>(
              label: 'Warehouses',
              options: warehouses
                  .map(
                    (warehouse) => _MultiSelectOption(
                      value: warehouse.id,
                      label: warehouse.label,
                    ),
                  )
                  .toList(),
              selectedValues: selectedWarehouseIds,
              emptyLabel: 'All warehouses',
              onChanged: onWarehouseChanged,
            ),
            const SizedBox(height: 12),
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
              selectedValues: selectedStockFilters,
              emptyLabel: 'All statuses',
              onChanged: onStockFilterChanged,
            ),
          ],
        ),
      ),
    );
  }
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
    required this.warehousesFilter,
  });

  final InventoryManageItem item;
  final double quantity;
  final double minValue;
  final double maxValue;
  final Set<String> warehousesFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lots = item.inventoryManage
        .where((entry) =>
            warehousesFilter.isEmpty ||
            warehousesFilter.contains(entry.warehouseId))
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          'SKU Code: ${item.skuCode}',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SKU Name: ${item.skuCode}'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _MetricChip(label: 'Quantity', value: _formatNumber(quantity)),
                  _MetricChip(label: 'Minimum', value: _formatNumber(minValue)),
                  _MetricChip(label: 'Maximum', value: _formatNumber(maxValue)),
                ],
              ),
            ],
          ),
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
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../services/loss_adjustments_service.dart';
import '../services/stocktake_service.dart';

class StockAdjustmentDialog extends StatefulWidget {
  const StockAdjustmentDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.adjustmentId,
  });

  final String title;
  final String? subtitle;
  final String? adjustmentId;

  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _lossAdjustmentsService = LossAdjustmentsService();
  final _stocktakeService = StocktakeService();

  final _timeController = TextEditingController();
  final _currentQuantityController = TextEditingController();
  final _updatedQuantityController = TextEditingController();

  Timer? _timer;

  String? _selectedType;
  String? _selectedWarehouseId;

  String? _selectedItemId;
  String? _selectedLotNumber;

  List<WarehouseOption> _warehouses = const [];
  List<StocktakeItemOption> _items = const [];
  List<StocktakeLotOption> _lots = const [];

  final List<StocktakeLineItem> _lineItems = [];

  bool _isLoading = false;
  String? _loadingError;

  @override
  void initState() {
    super.initState();
    _setCurrentTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _setCurrentTime());
    _updatedQuantityController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timeController.dispose();
    _currentQuantityController.dispose();
    _updatedQuantityController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  void _setCurrentTime() {
    final formatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    if (_timeController.text != formatted) {
      _timeController.text = formatted;
    }
  }

  Future<void> _loadData() async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _loadingError = null;
      _isLoading = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _loadingError = 'You are not logged in.';
        _isLoading = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final futures = <Future<dynamic>>[
        _stocktakeService.fetchWarehouses(headers: headers),
        _stocktakeService.fetchItems(headers: headers),
      ];

      if (widget.adjustmentId != null && widget.adjustmentId!.trim().isNotEmpty) {
        futures.add(
          _lossAdjustmentsService.fetchLossAdjustmentDetail(
            id: widget.adjustmentId!.trim(),
            headers: headers,
          ),
        );
      }

      final results = await Future.wait(futures);

      if (!mounted) {
        return;
      }

      final warehouses = results[0] as List<WarehouseOption>;
      final items = results[1] as List<StocktakeItemOption>;

      setState(() {
        _warehouses = warehouses;
        _items = items;
      });

      if (results.length > 2) {
        final detail = results[2] as Map<String, dynamic>;
        _hydrateFromDetail(detail);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _hydrateFromDetail(Map<String, dynamic> detail) {
    final rawType =
        _readString(detail, const ['type', 'adjustment_type', 'loss_type']);
    final warehouseId = _readString(detail, const ['warehouse_id', 'warehouseId']);

    final nestedWarehouse = detail['warehouse'];
    final nestedWarehouseId = nestedWarehouse is Map<String, dynamic>
        ? _readString(nestedWarehouse, const ['warehouse_id', 'id'])
        : null;

    setState(() {
      final normalizedType = rawType?.toLowerCase();
      _selectedType = normalizedType == null
          ? null
          : normalizedType.contains('adjustment')
              ? 'adjustment'
              : normalizedType.contains('loss')
                  ? 'loss'
                  : normalizedType;
      _selectedWarehouseId = warehouseId ?? nestedWarehouseId;
      _lineItems
        ..clear()
        ..addAll(_extractLineItems(detail));
    });
  }

  List<StocktakeLineItem> _extractLineItems(dynamic source) {
    final items = <StocktakeLineItem>[];

    void collect(dynamic value) {
      if (value is List) {
        for (final entry in value) {
          collect(entry);
        }
        return;
      }
      if (value is Map<String, dynamic>) {
        final lotNumber = _readString(value, const ['lot_number', 'lotNumber']);
        final currentNumber =
            _readString(value, const ['current_number', 'currentNumber']);
        final updatedNumber =
            _readString(value, const ['updates_number', 'updated_number']);
        final commodityName =
            _readString(value, const ['commodity_name', 'item_name', 'name']);
        final itemId = _readString(value, const ['item_id', 'itemId']);

        if (lotNumber != null && currentNumber != null) {
          items.add(
            StocktakeLineItem(
              itemId: itemId,
              commodityName: commodityName ?? 'Unknown item',
              lotNumber: lotNumber,
              currentNumber: currentNumber,
              updatedNumber: updatedNumber ?? '',
            ),
          );
        }

        for (final nested in value.values) {
          collect(nested);
        }
      }
    }

    collect(source);
    return items;
  }

  Map<String, String> _buildAuthHeaders(AppState appState, String token) {
    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken = token
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    final normalizedAuth =
        sanitizedToken.isNotEmpty ? 'Bearer $sanitizedToken' : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    final authtokenHeader = autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;
    return {'authtoken': authtokenHeader, 'Authorization': normalizedAuth};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth = (MediaQuery.of(context).size.width * 0.95).clamp(
      520.0,
      1100.0,
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth,
        height: 640,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
            : _loadingError != null
                ? _buildErrorState(theme)
                : _buildContent(theme),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        OutlinedButton(
          onPressed: _handleSaveDraft,
          child: const Text('Save as Draft'),
        ),
        ElevatedButton(
          onPressed: _handleSave,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Text(
        _loadingError ?? 'Unable to load data.',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.error),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 200),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                if (widget.subtitle != null) const SizedBox(height: 12),
                _buildTimeField(),
                const SizedBox(height: 12),
                _buildTypeDropdown(),
                const SizedBox(height: 12),
                _buildWarehouseDropdown(),
                const SizedBox(height: 24),
                _buildItemsTable(theme),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildAddItemFooter(theme),
        ),
      ],
    );
  }

  Widget _buildTimeField() {
    return TextFormField(
      controller: _timeController,
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Time',
      ),
    );
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedType,
      items: const [
        DropdownMenuItem(value: 'loss', child: Text('Loss')),
        DropdownMenuItem(value: 'adjustment', child: Text('Adjustment Increase')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedType = value;
          _resetSelectedItem();
        });
      },
      decoration: const InputDecoration(labelText: 'Type'),
    );
  }

  Widget _buildWarehouseDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedWarehouseId,
      items: _warehouses
          .map(
            (warehouse) => DropdownMenuItem(
              value: warehouse.id,
              child: Text(warehouse.name),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedWarehouseId = value;
          _resetSelectedItem();
        });
      },
      decoration: const InputDecoration(labelText: 'Warehouse'),
    );
  }

  Widget _buildItemsTable(ThemeData theme) {
    const minTableWidth = 720.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : minTableWidth;
        final tableWidth = maxWidth < minTableWidth ? minTableWidth : maxWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Expanded(flex: 3, child: Text('Item')),
                      Expanded(flex: 2, child: Text('Lot Number')),
                      Expanded(flex: 2, child: Text('Current Quantity')),
                      Expanded(flex: 2, child: Text('Updated Quantity')),
                      Expanded(flex: 1, child: Text('Actions')),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (_lineItems.isEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: const [
                        Expanded(
                          child: Text(
                            'No Adjustment Item is added yet.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._lineItems.map(
                    (item) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(item.commodityName)),
                          Expanded(flex: 2, child: Text(item.lotNumber)),
                          Expanded(flex: 2, child: Text(item.currentNumber)),
                          Expanded(flex: 2, child: Text(item.updatedNumber)),
                          Expanded(
                            flex: 1,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remove item',
                                onPressed: () => _removeLineItem(item),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddItemFooter(ThemeData theme) {
    final canSelectItem = _selectedType != null &&
        _selectedType!.trim().isNotEmpty &&
        _selectedWarehouseId != null &&
        _selectedWarehouseId!.trim().isNotEmpty;
    final hasSelectedItem =
        _selectedItemId != null && _selectedItemId!.trim().isNotEmpty;
    final selectedLot = _lots.firstWhere(
      (lot) => lot.lotNumber == _selectedLotNumber,
      orElse: () => const StocktakeLotOption(
        lotNumber: '',
        inventoryNumber: '',
      ),
    );

    final currentQuantity = selectedLot.inventoryNumber;
    if (_currentQuantityController.text != currentQuantity) {
      _currentQuantityController.text = currentQuantity;
    }

    final adjustedItemIds = _lineItems
        .map((item) => item.itemId)
        .whereType<String>()
        .toSet();
    final availableItems = _items
        .where((item) => !adjustedItemIds.contains(item.id))
        .toList();

    final canAdd = _selectedItemId != null &&
        _selectedLotNumber != null &&
        currentQuantity.isNotEmpty &&
        _updatedQuantityController.text.trim().isNotEmpty;

    final readOnlyFillColor = theme.colorScheme.surfaceVariant.withOpacity(0.4);

    return Material(
      elevation: 6,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedItemId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Select an Item',
                filled: !canSelectItem,
                fillColor: readOnlyFillColor,
              ),
              items: availableItems
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.displayName),
                    ),
                  )
                  .toList(),
              onChanged: canSelectItem ? (value) => _handleItemSelected(value) : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: _selectedLotNumber,
                    decoration: InputDecoration(
                      labelText: 'Lot Number',
                      filled: !hasSelectedItem,
                      fillColor: readOnlyFillColor,
                    ),
                    items: _lots
                        .map(
                          (lot) => DropdownMenuItem(
                            value: lot.lotNumber,
                            child: Text(lot.lotNumber),
                          ),
                        )
                        .toList(),
                    onChanged: hasSelectedItem
                        ? (value) {
                            setState(() {
                              _selectedLotNumber = value;
                              final selected = _lots.firstWhere(
                                (lot) => lot.lotNumber == value,
                                orElse: () => const StocktakeLotOption(
                                  lotNumber: '',
                                  inventoryNumber: '',
                                ),
                              );
                              _currentQuantityController.text =
                                  selected.inventoryNumber;
                            });
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    readOnly: true,
                    enabled: hasSelectedItem,
                    controller: _currentQuantityController,
                    decoration: InputDecoration(
                      labelText: 'Current Quantity',
                      filled: true,
                      fillColor: readOnlyFillColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _updatedQuantityController,
                    enabled: hasSelectedItem,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Updated Quantity'),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: canAdd ? _handleAddLineItem : null,
                  icon: const Icon(Icons.check_circle_outline),
                  tooltip: 'Add item',
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _resetSelectedItem() {
    _selectedItemId = null;
    _selectedLotNumber = null;
    _lots = const [];
    _currentQuantityController.clear();
    _updatedQuantityController.clear();
  }

  void _handleItemSelected(String? itemId) {
    setState(() {
      _selectedItemId = itemId;
      _selectedLotNumber = null;
      _lots = const [];
      _currentQuantityController.clear();
    });

    if (itemId == null ||
        itemId.trim().isEmpty ||
        _selectedWarehouseId == null ||
        _selectedWarehouseId!.trim().isEmpty) {
      return;
    }

    _loadLots(itemId);
  }

  Future<void> _loadLots(String itemId) async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      return;
    }

    final headers = _buildAuthHeaders(appState, token);
    final warehouseId = _selectedWarehouseId;
    if (warehouseId == null || warehouseId.trim().isEmpty) {
      return;
    }

    try {
      final lots = await _stocktakeService.fetchLots(
        itemId: itemId,
        warehouseId: warehouseId,
        headers: headers,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lots = lots;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lots = const [];
      });
    }
  }

  void _handleAddLineItem() {
    final itemOption = _items.firstWhere(
      (item) => item.id == _selectedItemId,
      orElse: () => const StocktakeItemOption(
        id: '',
        skuCode: null,
        skuName: 'Unknown item',
        total: null,
      ),
    );
    final lotOption = _lots.firstWhere(
      (lot) => lot.lotNumber == _selectedLotNumber,
      orElse: () => const StocktakeLotOption(
        lotNumber: '',
        inventoryNumber: '',
      ),
    );

    final updatedQuantity = _updatedQuantityController.text.trim();

    if (itemOption.id.isEmpty ||
        lotOption.lotNumber.isEmpty ||
        updatedQuantity.isEmpty) {
      return;
    }

    setState(() {
      _lineItems.add(
        StocktakeLineItem(
          itemId: itemOption.id,
          commodityName: itemOption.skuName,
          lotNumber: lotOption.lotNumber,
          currentNumber: lotOption.inventoryNumber,
          updatedNumber: updatedQuantity,
        ),
      );
      _selectedItemId = null;
      _selectedLotNumber = null;
      _lots = const [];
      _updatedQuantityController.clear();
    });
  }

  void _removeLineItem(StocktakeLineItem item) {
    setState(() {
      _lineItems.remove(item);
    });
  }

  void _handleSaveDraft() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Save as Draft is not available yet.')),
    );
  }

  void _handleSave() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Save is not available yet.')),
    );
  }

  String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      if (value is num || value is bool) {
        return value.toString();
      }
    }
    return null;
  }
}

class StocktakeLineItem {
  StocktakeLineItem({
    required this.itemId,
    required this.commodityName,
    required this.lotNumber,
    required this.currentNumber,
    required this.updatedNumber,
  });

  final String? itemId;
  final String commodityName;
  final String lotNumber;
  final String currentNumber;
  final String updatedNumber;
}

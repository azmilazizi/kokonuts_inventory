import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state_scope.dart';
import '../services/inventory_receiving_service.dart';
import '../services/purchase_order_receiving_service.dart';
import '../services/receiving_options_service.dart';
import '../services/stocktake_service.dart';
import '../services/warehouse_unit_service.dart';

class InventoryReceivingVoucherDialog extends StatefulWidget {
  const InventoryReceivingVoucherDialog({super.key, required this.orderId});

  final String orderId;

  @override
  State<InventoryReceivingVoucherDialog> createState() =>
      _InventoryReceivingVoucherDialogState();
}

class _InventoryReceivingVoucherDialogState
    extends State<InventoryReceivingVoucherDialog> {
  final _purchaseOrderService = PurchaseOrderReceivingService();
  final _warehouseService = StocktakeService();
  final _optionsService = ReceivingOptionsService();
  final _receivingService = InventoryReceivingService();
  final _unitService = WarehouseUnitService();

  Future<_ReceivingDialogData>? _future;
  bool _initialized = false;
  bool _formsInitialized = false;
  bool _isSubmitting = false;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _dateController = TextEditingController();
  List<_ReceivingItemForm> _itemForms = [];
  List<WarehouseOption> _warehouses = [];
  Map<String, String> _unitLabels = {};
  ReceivingOptions? _options;
  PurchaseOrderReceivingDetail? _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _selectedDate = DateUtils.dateOnly(DateTime.now());
      _dateController.text = _formatDate(_selectedDate);
      _future = _loadData();
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    for (final form in _itemForms) {
      form.dispose();
    }
    super.dispose();
  }

  Future<_ReceivingDialogData> _loadData() async {
    final headers = await _buildAuthHeaders();
    if (!mounted) {
      throw const PurchaseOrderReceivingException('Dialog no longer mounted');
    }

    if (headers == null) {
      throw const PurchaseOrderReceivingException('You are not logged in.');
    }

    final resolvedHeaders = headers;
    final results = await Future.wait([
      _purchaseOrderService.fetchPurchaseOrder(
        id: widget.orderId,
        headers: resolvedHeaders,
      ),
      _warehouseService.fetchWarehouses(headers: resolvedHeaders),
      _optionsService.fetchReceivingOptions(headers: resolvedHeaders),
    ]);

    final detail = results[0] as PurchaseOrderReceivingDetail;
    final warehouses = results[1] as List<WarehouseOption>;
    final options = results[2] as ReceivingOptions;

    final unitIds = detail.items
        .map((item) => item.unitId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final unitEntries = await Future.wait(
      unitIds.map((id) async {
        try {
          final label = await _unitService.fetchUnitLabel(
            id: id,
            headers: resolvedHeaders,
          );
          return MapEntry(id, label);
        } catch (_) {
          return MapEntry(id, null);
        }
      }),
    );

    final unitLabels = <String, String>{};
    for (final entry in unitEntries) {
      final label = entry.value;
      if (label != null && label.trim().isNotEmpty) {
        unitLabels[entry.key] = label.trim();
      }
    }

    final data = _ReceivingDialogData(
      detail: detail,
      warehouses: warehouses,
      options: options,
      unitLabels: unitLabels,
    );

    if (mounted) {
      setState(() {
        _initializeForms(data);
      });
    }

    return data;
  }

  Future<Map<String, String>?> _buildAuthHeaders() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return null;
    }

    if (token == null || token.isEmpty) {
      return null;
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

    final authtokenHeader = autoTokenValue.isNotEmpty
        ? autoTokenValue
        : sanitizedToken;

    return {
      'Accept': 'application/json',
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };
  }

  void _initializeForms(_ReceivingDialogData data) {
    if (_formsInitialized) {
      return;
    }
    _warehouses = data.warehouses;
    _options = data.options;
    _unitLabels = data.unitLabels;
    _detail = data.detail;
    _itemForms = data.detail.items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final quantityLabel = _formatNumber(item.quantity);
      final unitPrice = _resolveUnitPrice(item);
      final unitPriceLabel = unitPrice != null ? _formatNumber(unitPrice) : '';
      final totalLabel = item.total != null ? _formatNumber(item.total!) : '0.00';
      final lotNumber = _buildLotNumber(index: index);
      return _ReceivingItemForm(
        item: item,
        quantityController: TextEditingController(text: quantityLabel),
        lotNumberController: TextEditingController(text: lotNumber),
        unitPriceLabel: unitPriceLabel,
        totalLabel: totalLabel,
        unitLabel: _unitLabels[item.unitId] ?? '',
        autoLotNumber: true,
      );
    }).toList(growable: false);
    _formsInitialized = true;
  }

  double? _resolveUnitPrice(PurchaseOrderReceivingItem item) {
    final total = item.total;
    if (total != null && item.quantity != 0) {
      return total / item.quantity;
    }
    return item.unitPrice;
  }

  String _buildLotNumber({required int index}) {
    final options = _options;
    final prefix = options?.lotNumberPrefix?.trim();
    final normalizedPrefix = (prefix == null || prefix.isEmpty) ? 'LOT' : prefix;
    final month = _selectedDate.month.toString().padLeft(2, '0');
    final year = (_selectedDate.year % 100).toString().padLeft(2, '0');
    final baseNumber = options?.nextLotNumber ?? 1;
    final nextNumber = (baseNumber + index).toString().padLeft(5, '0');
    return '$normalizedPrefix-$month$year-$nextNumber';
  }

  Future<void> _pickDate() async {
    final theme = Theme.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: theme,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = DateUtils.dateOnly(picked);
      _dateController.text = _formatDate(_selectedDate);
      for (var i = 0; i < _itemForms.length; i++) {
        final form = _itemForms[i];
        if (form.autoLotNumber) {
          form.lotNumberController.text = _buildLotNumber(index: i);
        }
      }
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final headers = await _buildAuthHeaders();
    if (!mounted) {
      return;
    }

    if (headers == null) {
      _showError('You are not logged in.');
      return;
    }

    final detail = _detail;
    if (detail == null) {
      _showError('Purchase order details are unavailable.');
      return;
    }

    final appState = AppStateScope.of(context);
    final totalValue = _resolveOrderTotal(detail);
    final goodsReceiptCode = _buildGoodsReceiptCode();

    final goodsReceiptItems = _itemForms.map((form) {
      final quantity =
          _parseNumber(form.quantityController.text) ?? form.item.quantity;
      final unitPrice =
          _parseNumber(form.unitPriceLabel) ?? form.item.unitPrice ?? 0;
      final amount = _parseNumber(form.totalLabel) ?? quantity * unitPrice;
      return {
        'commodity_code': form.item.code ?? '',
        'commodity_name': form.item.name,
        'warehouse_id': form.selectedWarehouseId ?? '0',
        'unit_id': form.item.unitId ?? '',
        'quantities': quantity,
        'unit_price': unitPrice,
        'tax_money': 0,
        'goods_money': amount,
        'lot_number': form.lotNumberController.text.trim(),
        'sub_total': amount,
      };
    }).toList(growable: false);

    final payload = {
      'supplier_code': detail.vendor?.code ?? '',
      'supplier_name': detail.vendor?.name ?? '',
      'buyer_id': detail.buyerId ?? '',
      'pr_order_id': detail.id,
      'date_c': _dateController.text.trim(),
      'goods_receipt_code': goodsReceiptCode,
      'warehouse_id': '0',
      'total_tax_money': 0,
      'total_goods_money': totalValue,
      'value_of_inventory': totalValue,
      'total_money': totalValue,
      'addedfrom': appState.currentUserId ?? '',
      'approval': 1,
      'items': goodsReceiptItems,
    };

    try {
      await _receivingService.createGoodsReceipt(
        headers: headers,
        payload: payload,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receiving voucher submitted.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    setState(() {
      _isSubmitting = false;
    });
  }

  String _buildGoodsReceiptCode() {
    final options = _options;
    final prefix = options?.inventoryReceivedNumberPrefix?.trim() ?? '';
    final nextNumber = options?.nextInventoryReceivedNumber;
    if (nextNumber == null) {
      return prefix;
    }
    return '$prefix$nextNumber';
  }

  double _resolveOrderTotal(PurchaseOrderReceivingDetail detail) {
    final total = detail.total;
    if (total != null) {
      return total;
    }

    var sum = 0.0;
    for (final item in detail.items) {
      if (item.total != null) {
        sum += item.total!;
      } else if (item.unitPrice != null) {
        sum += item.unitPrice! * item.quantity;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 960,
        height: 720,
        child: FutureBuilder<_ReceivingDialogData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ErrorView(
                error: snapshot.error,
                onClose: () => Navigator.of(context).pop(),
                onRetry: () {
                  setState(() {
                    _formsInitialized = false;
                    for (final form in _itemForms) {
                      form.dispose();
                    }
                    _itemForms = [];
                    _future = _loadData();
                  });
                },
              );
            }

            if (!snapshot.hasData) {
              return _ErrorView(
                error: 'Unable to load purchase order details.',
                onClose: () => Navigator.of(context).pop(),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Inventory Receiving Voucher',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _dateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Date',
                      suffixIcon: IconButton(
                        tooltip: 'Select date',
                        icon: const Icon(Icons.calendar_today),
                        onPressed: _pickDate,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: ListView.separated(
                        itemCount: _itemForms.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final form = _itemForms[index];
                          return _ReceivingItemCard(
                            form: form,
                            warehouses: _warehouses,
                            onWarehouseChanged: (value) {
                              setState(() {
                                form.selectedWarehouseId = value;
                              });
                            },
                            onLotNumberChanged: () {
                              form.autoLotNumber = false;
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReceivingItemCard extends StatelessWidget {
  const _ReceivingItemCard({
    required this.form,
    required this.warehouses,
    required this.onWarehouseChanged,
    required this.onLotNumberChanged,
  });

  final _ReceivingItemForm form;
  final List<WarehouseOption> warehouses;
  final ValueChanged<String?> onWarehouseChanged;
  final VoidCallback onLotNumberChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            form.item.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 700;
              final children = [
                TextFormField(
                  initialValue: form.item.name,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: form.selectedWarehouseId,
                  decoration: const InputDecoration(
                    labelText: 'Warehouse',
                    border: OutlineInputBorder(),
                  ),
                  items: warehouses
                      .map(
                        (warehouse) => DropdownMenuItem(
                          value: warehouse.id,
                          child: Text(warehouse.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: onWarehouseChanged,
                ),
                TextFormField(
                  controller: form.quantityController,
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    suffixText: form.unitLabel.isNotEmpty ? form.unitLabel : null,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                ),
                TextFormField(
                  initialValue: form.unitPriceLabel,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Unit Price',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextFormField(
                  controller: form.lotNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Lot Number',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => onLotNumberChanged(),
                ),
                _AmountField(value: form.totalLabel),
              ];

              if (isCompact) {
                return Column(
                  children: [
                    children[0],
                    const SizedBox(height: 12),
                    children[1],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: children[2]),
                        const SizedBox(width: 12),
                        Expanded(child: children[3]),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: children[4]),
                        const SizedBox(width: 12),
                        Expanded(child: children[5]),
                      ],
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 3, child: children[0]),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: children[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(flex: 2, child: children[2]),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: children[3]),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: children[4]),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: children[5]),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Amount',
        border: OutlineInputBorder(),
      ),
      child: Text(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ReceivingItemForm {
  _ReceivingItemForm({
    required this.item,
    required this.quantityController,
    required this.lotNumberController,
    required this.unitPriceLabel,
    required this.totalLabel,
    required this.unitLabel,
    required this.autoLotNumber,
    this.selectedWarehouseId,
  });

  final PurchaseOrderReceivingItem item;
  final TextEditingController quantityController;
  final TextEditingController lotNumberController;
  final String unitPriceLabel;
  final String totalLabel;
  final String unitLabel;
  bool autoLotNumber;
  String? selectedWarehouseId;

  void dispose() {
    quantityController.dispose();
    lotNumberController.dispose();
  }
}

class _ReceivingDialogData {
  const _ReceivingDialogData({
    required this.detail,
    required this.warehouses,
    required this.options,
    required this.unitLabels,
  });

  final PurchaseOrderReceivingDetail detail;
  final List<WarehouseOption> warehouses;
  final ReceivingOptions options;
  final Map<String, String> unitLabels;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({this.error, this.onRetry, this.onClose});

  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Close',
              onPressed: onClose ?? () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error?.toString() ?? 'Unable to load purchase order details.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatNumber(double value) {
  return value.toStringAsFixed(2);
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString().padLeft(4, '0');
  return '$day-$month-$year';
}

double? _parseNumber(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }
  return double.tryParse(normalized.replaceAll(',', ''));
}

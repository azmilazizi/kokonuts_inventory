import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../services/inventory_items_service.dart';
import '../services/payment_modes_service.dart';
import '../services/purchase_options_service.dart';
import '../services/purchase_orders_service.dart';
import '../services/purchase_order_detail_service.dart';
import '../services/vendors_service.dart';
import 'attachment_picker.dart';
import 'currency_input_formatter.dart';
import 'searchable_dropdown_form_field.dart';

enum DiscountType { percentage, amount }

class AddPurchaseOrderDialog extends StatefulWidget {
  const AddPurchaseOrderDialog({super.key, this.initialDetail, this.orderId});

  final PurchaseOrderDetail? initialDetail;
  final String? orderId;

  @override
  State<AddPurchaseOrderDialog> createState() => _AddPurchaseOrderDialogState();
}

class _AddPurchaseOrderDialogState extends State<AddPurchaseOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _orderNumberController = TextEditingController();
  final _orderNameController = TextEditingController();
  final _service = PurchaseOrdersService();
  final _vendorsService = VendorsService();
  final _purchaseOptionsService = PurchaseOptionsService();
  final _inventoryItemsService = InventoryItemsService();
  final _paymentModesService = PaymentModesService();
  final TextEditingController _itemSearchController = TextEditingController();
  final TextEditingController _orderDiscountController = TextEditingController(
    text: CurrencyInputFormatter.normalizeExistingValue('0'),
  );
  final TextEditingController _shippingFeeController = TextEditingController(
    text: CurrencyInputFormatter.normalizeExistingValue('0'),
  );

  bool get _isEditing =>
      widget.initialDetail != null &&
      (widget.orderId?.trim().isNotEmpty ?? false);

  late DateTime _orderDate;
  late _PurchaseOrderItemDraft _pendingItem;
  final List<_PurchaseOrderItemDraft> _items = [];
  DiscountType _orderDiscountType = DiscountType.amount;
  bool _isPaid = false;

  bool _isSubmitting = false;
  String? _submitError;
  bool _isLoadingReferenceData = false;
  String? _referenceDataError;
  String? _pendingItemError;
  String? _orderNumber;
  String _orderNumberStatus = '';
  String? _selectedVendorName;
  String? _selectedVendorCode;
  String? _selectedVendorId;
  String? _purchaseOrderPrefix;
  int? _nextPurchaseOrderNumber;
  String? _orderNumberSeed;
  InventoryItem? _selectedInventoryItem;
  List<VendorSummary> _vendors = const [];
  List<InventoryItem> _inventoryItems = const [];
  List<PaymentMode> _paymentModes = const [];
  final List<_PaymentEntryDraft> _payments = [];
  List<PlatformFile> _supportingAttachments = const [];
  List<PurchaseOrderAttachment> _existingAttachments = const [];
  final Set<String> _attachmentsMarkedForDeletion = {};
  final Set<String> _removedLineItemIds = {};
  final Set<String> _removedPaymentIds = {};

  String _vendorLabel(String name) => name;

  String _paymentModeLabel(String id) {
    return _paymentModes
            .firstWhere(
              (mode) => mode.id == id,
              orElse: () => PaymentMode(id: id, name: 'Unknown mode'),
            )
            .name;
  }

  @override
  void initState() {
    super.initState();
    _orderDate = widget.initialDetail?.orderDate ?? DateTime.now();
    _pendingItem = _PurchaseOrderItemDraft(onChanged: _handleItemsChanged);
    if (widget.initialDetail != null) {
      _prefillFromDetail(widget.initialDetail!);
    }
    _orderDiscountController.addListener(_handleItemsChanged);
    _shippingFeeController.addListener(_handleItemsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadReferenceData();
      }
    });
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _orderNumberController.dispose();
    _orderNameController.dispose();
    _orderDiscountController.dispose();
    _shippingFeeController.dispose();
    _pendingItem.dispose();
    _itemSearchController.dispose();
    for (final payment in _payments) {
      payment.dispose();
    }
    super.dispose();
  }

  void _prefillFromDetail(PurchaseOrderDetail detail) {
    _orderNameController.text = detail.name;
    _orderNumberController.text = detail.number;
    _selectedVendorName = detail.vendorName;
    _selectedVendorId = detail.vendorId;
    _orderDiscountController.text = CurrencyInputFormatter.normalizeExistingValue(
      _formatDouble(detail.discountValue ?? 0),
    );
    _shippingFeeController.text = CurrencyInputFormatter.normalizeExistingValue(
      _formatDouble(detail.shippingFeeValue ?? 0),
    );

    final mappedItems = detail.items
        .map(
          (item) => _PurchaseOrderItemDraft(
            onChanged: _handleItemsChanged,
            initialItemId: item.itemId,
            initialItemName: item.name,
            initialLineItemId: item.lineItemId,
            initialDescription: item.description,
            initialQuantity: _formatDouble(item.quantityValue ?? 1),
            initialSubtotal: CurrencyInputFormatter.normalizeExistingValue(
              _formatDouble(item.amountValue ?? 0),
            ),
            initialDiscount: CurrencyInputFormatter.normalizeExistingValue(
              _formatDouble(item.discountValue ?? 0),
            ),
          ),
        )
        .toList();

    for (final existing in _items) {
      existing.dispose();
    }

    _items
      ..clear()
      ..addAll(mappedItems);
    _removedLineItemIds.clear();
    _removedPaymentIds.clear();

    _existingAttachments = List.of(detail.attachments);
    _prefillPayments(detail);

    _handleItemsChanged();
  }

  void _prefillPayments(PurchaseOrderDetail detail) {
    for (final payment in _payments) {
      payment.dispose();
    }
    _payments.clear();

    _removedPaymentIds.clear();

    if (detail.payments.isEmpty) {
      _isPaid = false;
      return;
    }

    for (final payment in detail.payments) {
      final entry = _PaymentEntryDraft(
        paymentId: payment.id,
        onChanged: () => setState(() {}),
        initialAmount: _resolvePrefillPaymentAmount(payment),
        initialDate: payment.date ?? DateTime.now(),
        initialPaymentModeLabel: payment.method,
      );
      _payments.add(entry);
    }

    _isPaid = true;
  }

  String? _resolvePrefillPaymentAmount(PurchaseOrderPayment payment) {
    final amountValue = payment.amountValue;
    if (amountValue != null) {
      return _formatDouble(amountValue);
    }

    final digitsOnly =
        payment.amountLabel.replaceAll(RegExp(r'[^0-9,.-]'), '');
    if (digitsOnly.isEmpty) {
      return null;
    }

    if (digitsOnly.contains(',') && digitsOnly.contains('.')) {
      final lastComma = digitsOnly.lastIndexOf(',');
      final lastDot = digitsOnly.lastIndexOf('.');
      if (lastComma > lastDot) {
        final withoutDots = digitsOnly.replaceAll('.', '');
        return withoutDots.replaceAll(',', '.');
      }
      return digitsOnly.replaceAll(',', '');
    }

    if (digitsOnly.contains(',')) {
      return digitsOnly.replaceAll(',', '.');
    }

    return digitsOnly;
  }

  void _removeItem(int index) {
    setState(() {
      final removed = _items.removeAt(index);
      final removedLineItemId = removed.lineItemId?.trim();
      if (_isEditing && removedLineItemId != null && removedLineItemId.isNotEmpty) {
        _removedLineItemIds.add(removedLineItemId);
      }
      removed.dispose();
    });
  }

  Future<void> _loadReferenceData() async {
    setState(() {
      _isLoadingReferenceData = true;
      _referenceDataError = null;
      _orderNumberStatus = _isEditing ? '' : 'Generating...';
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }
    if (token == null || token.trim().isEmpty) {
      setState(() {
        _referenceDataError = 'You are not logged in.';
        _isLoadingReferenceData = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final results = await Future.wait([
        _vendorsService.fetchVendors(headers: headers),
        _inventoryItemsService.fetchItems(headers: headers),
        _purchaseOptionsService.fetchPurchaseOptions(headers: headers),
        _paymentModesService.fetchPaymentModes(headers: headers),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _vendors = results[0] as List<VendorSummary>;
        _inventoryItems = results[1] as List<InventoryItem>;
        final options = results[2] as PurchaseOptions;
        _paymentModes = results[3] as List<PaymentMode>;
        _purchaseOrderPrefix = '#PO-';
        _nextPurchaseOrderNumber = options.nextPurchaseOrderNumber;
        _orderNumberSeed = _buildOrderNumberSeed(
          _purchaseOrderPrefix,
          _nextPurchaseOrderNumber,
        );
        final selectedVendor = _findVendorByName(_selectedVendorName);
        _selectedVendorCode = selectedVendor?.code;
        _selectedVendorId = selectedVendor?.id;
        if (_paymentModes.isNotEmpty) {
          for (final payment in _payments) {
            final matchedId = payment.paymentModeId ??
                _matchPaymentModeId(payment.initialPaymentModeLabel);
            payment.setPaymentModeId(
              matchedId ?? _paymentModes.first.id,
            );
          }
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _referenceDataError = 'Failed to load reference data: $error';
        _orderNumberStatus = 'Unable to generate order number';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReferenceData = false;
          _updateOrderNumber();
        });
      }
    }
  }

  void _updateSelectedItem(InventoryItem? item) {
    setState(() {
      _selectedInventoryItem = item;
      final formattedName = item == null
          ? null
          : _formatInventoryItemName(item);
      _pendingItem.setItem(itemName: formattedName, itemId: item?.id);
      _pendingItemError = null;
    });
  }

  void _resetPendingItem() {
    setState(() {
      _selectedInventoryItem = null;
      _itemSearchController.clear();
      _pendingItem.clear();
      _pendingItemError = null;
    });
  }

  void _commitPendingItem() {
    final error = _validatePendingItem();
    if (error != null) {
      setState(() {
        _pendingItemError = error;
      });
      return;
    }

    final newItem = _PurchaseOrderItemDraft(
      onChanged: _handleItemsChanged,
      initialItemId: _pendingItem.itemId,
      initialItemName: _pendingItem.itemName,
      initialDescription: _pendingItem.descriptionController.text,
      initialQuantity: _pendingItem.quantityController.text,
      initialSubtotal: _pendingItem.subtotalController.text,
      initialDiscount: _pendingItem.discountController.text,
    );

    setState(() {
      _items.add(newItem);
      _pendingItemError = null;
    });
    _resetPendingItem();
  }

  String? _validatePendingItem() {
    if ((_pendingItem.itemName ?? '').isEmpty) {
      return 'Select an item before adding it to the order.';
    }
    if (_pendingItem.quantity <= 0) {
      return 'Enter a quantity greater than zero.';
    }
    if (_pendingItem.subtotal < 0) {
      return 'Subtotal cannot be negative.';
    }
    if (_pendingItem.discount < 0) {
      return 'Discount cannot be negative.';
    }
    return null;
  }

  void _handleItemsChanged() {
    setState(() {});
  }

  double get _itemsSubtotal => _items.fold(
    0.0,
    (total, item) => total + item.subtotal.clamp(0, double.infinity),
  );

  double get _itemsDiscount => _items.fold(
    0.0,
    (total, item) => total + item.discount.clamp(0, double.infinity),
  );

  double get _itemsNetSubtotal =>
      (_itemsSubtotal - _itemsDiscount).clamp(0, double.infinity);

  double get _orderDiscountValue =>
      double.tryParse(_orderDiscountController.text) ?? 0;

  double get _orderDiscountAmount {
    final value = _orderDiscountValue;
    if (value <= 0) {
      return 0;
    }
    final baseAmount = _itemsNetSubtotal;
    final rawDiscount = _orderDiscountType == DiscountType.percentage
        ? baseAmount * (value / 100)
        : value;
    return rawDiscount.clamp(0, baseAmount);
  }

  double get _totalDiscount =>
      (_itemsDiscount + _orderDiscountAmount).clamp(0, _itemsSubtotal);

  double get _shippingFee =>
      double.tryParse(_shippingFeeController.text) ?? 0;

  double get _grandTotal => (_itemsSubtotal - _totalDiscount + _shippingFee)
      .clamp(0, double.infinity);

  void _addPaymentEntry() {
    setState(() {
      final entry = _PaymentEntryDraft(onChanged: () => setState(() {}));
      if (_paymentModes.isNotEmpty) {
        entry.setPaymentModeId(_paymentModes.first.id);
      }
      _payments.add(entry);
    });
  }

  String? _matchPaymentModeId(String? label) {
    if (label == null || label.trim().isEmpty) {
      return null;
    }

    final normalized = label.trim().toLowerCase();
    for (final mode in _paymentModes) {
      if (mode.name.toLowerCase() == normalized) {
        return mode.id;
      }
    }
    return null;
  }

  void _removePaymentEntry(int index) {
    setState(() {
      final removed = _payments.removeAt(index);
      if (_isEditing) {
        final removedPaymentId = removed.paymentId?.trim();
        if (removedPaymentId != null && removedPaymentId.isNotEmpty) {
          _removedPaymentIds.add(removedPaymentId);
        }
      }
      removed.dispose();
    });
  }

  Future<void> _pickPaymentDate(_PaymentEntryDraft entry) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 10),
      lastDate: DateTime(DateTime.now().year + 10),
      initialDate: entry.date,
    );

    if (selected != null) {
      setState(() {
        entry.setDate(selected);
      });
    }
  }

  Map<String, String> _buildAuthHeaders(AppState appState, String token) {
    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken = token
        .replaceFirst(RegExp('^Bearer\s+', caseSensitive: false), '')
        .trim();
    final normalizedAuth = sanitizedToken.isNotEmpty
        ? 'Bearer $sanitizedToken'
        : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\s+', caseSensitive: false), '')
        .trim();
    final authtokenHeader = autoTokenValue.isNotEmpty
        ? autoTokenValue
        : sanitizedToken;
    return {'authtoken': authtokenHeader, 'Authorization': normalizedAuth};
  }

  Future<void> _pickOrderDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
      initialDate: _orderDate,
    );

    if (selected != null) {
      setState(() {
        _orderDate = selected;
        _updateOrderNumber();
      });
    }
  }

  void _updateOrderNumber() {
    if (_isEditing) {
      _orderNumberStatus = '';
      _orderNumber = _orderNumberController.text.trim();
      return;
    }

    final generated = _buildOrderNumber();
    if (generated.isEmpty) {
      _orderNumberStatus = _isLoadingReferenceData
          ? 'Generating...'
          : 'Unable to generate order number';
      _orderNumber = null;
      _orderNumberController.text = '';
    } else {
      _orderNumberStatus = '';
      _orderNumber = generated;
      _orderNumberController.text = generated;
    }
  }

  String _buildOrderNumber() {
    if (_nextPurchaseOrderNumber == null) return '';
    final datePart = _formatDate(_orderDate);
    // Format: #PO-{next_po_number}-{DDMMYYYY}
    return '#PO-$_nextPurchaseOrderNumber-$datePart';
  }

  String _buildBaseOrderNumber() {
    // Legacy method, kept for compatibility if called elsewhere (it isn't)
    // but replaced implementation in _buildOrderNumber
    final seed = _orderNumberSeed;
    if (seed == null || seed.isEmpty) {
      return '';
    }
    final datePart = _formatDate(_orderDate);
    return '$seed-$datePart';
  }

  String? _buildOrderNumberSeed(String? prefix, int? nextNumber) {
    final sanitizedPrefix = (prefix ?? '').trim();
    if (nextNumber == null || sanitizedPrefix.isEmpty) {
      return null;
    }
    // Note: This seed might not be used anymore for the final string construction
    // but we keep it for now or we can update it to match new format
    return '$sanitizedPrefix$nextNumber';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$day$month$year';
  }

  String _formatDouble(double value) {
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_items.isEmpty) {
      setState(() {
        _submitError =
            'Add at least one item to ${_isEditing ? 'update' : 'create'} a purchase order.';
      });
      return;
    }

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _submitError = 'You are not logged in.';
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    final items = _items
        .where((item) => (item.itemName ?? '').isNotEmpty)
        .map(
          (item) => CreatePurchaseOrderItem(
            itemId: item.itemId ?? '',
            itemName: item.itemName ?? 'Item',
            lineItemId: item.lineItemId,
            description: item.descriptionController.text.trim().isEmpty
                ? null
                : item.descriptionController.text.trim(),
            quantity: item.quantity,
            subtotal: item.subtotal,
            discount: item.discount,
            unitPrice: item.unitPrice,
            total: item.total,
            unitId: item.itemId,
          ),
        )
        .toList(growable: false);

    List<CreatePurchaseOrderPayment>? payments;
    if (_isPaid) {
      if (_payments.isEmpty) {
        setState(() {
          _submitError = 'Add at least one payment entry when marking as paid.';
        });
        return;
      }

      final parsedPayments = <CreatePurchaseOrderPayment>[];
      for (final payment in _payments) {
        final isExistingPayment =
            _isEditing && (payment.paymentId?.trim().isNotEmpty ?? false);
        if (isExistingPayment) {
          continue;
        }

        final amount = double.tryParse(payment.amountController.text) ?? 0;
        final paymentMode = payment.paymentModeId?.trim() ?? '';

        if (amount <= 0 || paymentMode.isEmpty) {
          setState(() {
            _submitError =
                'Enter a payment mode and amount greater than zero for all payments.';
          });
          return;
        }

        parsedPayments.add(
          CreatePurchaseOrderPayment(
            purchaseOrderNumber: _nextPurchaseOrderNumber,
            amount: amount,
            paymentMode: paymentMode,
            date: payment.date,
            requester: appState.currentUserId,
          ),
        );
      }

      payments = parsedPayments;
    }

    final removedPaymentIds = _isEditing
        ? _removedPaymentIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    final request = CreatePurchaseOrderRequest(
      vendorId: _selectedVendorId,
      orderName: _orderNameController.text.trim(),
      orderNumber: _orderNumberController.text.trim(),
      orderDate: _orderDate,
      items: items,
      subtotal: _itemsSubtotal,
      total: _grandTotal,
      totalDiscount: _totalDiscount,
      shippingFee: _shippingFee,
      discountValue: _orderDiscountValue,
      isDiscountPercentage: _orderDiscountType == DiscountType.percentage,
      payments: payments,
      userId: appState.currentUserId,
      nextPurchaseOrderNumber: _nextPurchaseOrderNumber,
      isUpdate: _isEditing,
      removedLineItemIds: _isEditing
          ? _removedLineItemIds
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toList(growable: false)
          : null,
      removedPaymentIds:
          removedPaymentIds.isEmpty ? null : removedPaymentIds,
    );

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final created = _isEditing
          ? await _service.updatePurchaseOrder(
              id: widget.orderId!,
              headers: headers,
              request: request,
            )
          : await _service.createPurchaseOrder(
              headers: headers,
              request: request,
            );

      if (!mounted) {
        return;
      }

      if (_isEditing && removedPaymentIds.isNotEmpty) {
        try {
          await _service.deletePayments(
            id: created.id,
            headers: headers,
            paymentIds: removedPaymentIds,
          );
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to delete some payments: $error'),
              ),
            );
          }
        }
      }

      if (_isEditing && _attachmentsMarkedForDeletion.isNotEmpty) {
        try {
          await _service.deleteAttachments(
            id: created.id,
            headers: headers,
            attachmentIds: _attachmentsMarkedForDeletion.toList(growable: false),
          );
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to delete some attachments: $error'),
              ),
            );
          }
        }
      }

      if (_supportingAttachments.isNotEmpty) {
        try {
          await _service.uploadAttachments(
            id: created.id,
            headers: headers,
            attachments: _supportingAttachments,
          );
        } catch (error) {
          if (mounted) {
            final actionWord = _isEditing ? 'updated' : 'created';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Purchase order $actionWord but failed to upload attachments: $error',
                ),
              ),
            );
          }
        }
      }

      Navigator.of(context).pop(created);
    } on PurchaseOrdersException catch (error) {
      setState(() {
        _submitError = error.message;
      });
    } catch (error) {
      setState(() {
        _submitError =
            'Failed to ${_isEditing ? 'update' : 'create'} purchase order: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final dialogWidth = (MediaQuery.of(context).size.width * 0.92).clamp(
      420.0,
      1200.0,
    );

    return AlertDialog(
      title: Text(_isEditing ? 'Edit Purchase Order' : 'Add Purchase Order'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Attachments', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                AttachmentPicker(
                  description:
                      'Drag and drop files or tap to browse for invoice or payment receipt documents.',
                  files: _supportingAttachments,
                  onPick: _pickAttachment,
                  onFilesSelected: (files) =>
                      setState(() => _supportingAttachments = files),
                  onFileRemoved: (file) => setState(() {
                    _supportingAttachments = List.of(_supportingAttachments)
                      ..remove(file);
                  }),
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 12),
                  _ExistingAttachmentsList(
                    attachments: _existingAttachments,
                    onRemove: _scheduleExistingAttachmentRemoval,
                    pendingDeletionCount: _attachmentsMarkedForDeletion.length,
                  ),
                ],
                if (_supportingAttachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _NewAttachmentsList(
                    attachments: _supportingAttachments,
                    onRemove: (file) => setState(() {
                      _supportingAttachments = List.of(_supportingAttachments)
                        ..remove(file);
                    }),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _isPaid,
                      onChanged: (value) {
                        setState(() {
                          _isPaid = value ?? false;
                          if (!_isPaid) {
                            if (_isEditing) {
                              for (final payment in _payments) {
                                final removedPaymentId =
                                    payment.paymentId?.trim();
                                if (removedPaymentId != null &&
                                    removedPaymentId.isNotEmpty) {
                                  _removedPaymentIds.add(removedPaymentId);
                                }
                              }
                            }
                            for (final payment in _payments) {
                              payment.dispose();
                            }
                            _payments.clear();
                          } else if (_payments.isEmpty) {
                            _addPaymentEntry();
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text('Paid'),
                  ],
                ),
                if (_isPaid) ...[
                  const SizedBox(height: 12),
                  _PaymentEntriesTable(
                    entries: _payments,
                    isLoadingPaymentModes: _isLoadingReferenceData,
                    paymentModes: _paymentModes,
                    onAdd: _addPaymentEntry,
                    onRemove: _removePaymentEntry,
                    onPickDate: _pickPaymentDate,
                    onPaymentModeChanged: (entry, modeId) =>
                        setState(() => entry.setPaymentModeId(modeId)),
                  ),
                  const SizedBox(height: 24),
                ],
                const SizedBox(height: 12),
                _buildVendorField(theme),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _orderNameController,
                  decoration: const InputDecoration(
                    labelText: 'Order name',
                    hintText: 'Describe the purchase order',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Order name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _orderNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Order number',
                    filled: true,
                  ),
                  readOnly: true,
                ),
                const SizedBox(height: 12),
                _OrderDateField(date: _orderDate, onTap: _pickOrderDate),
                const SizedBox(height: 24),
                Text('Items', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _buildItemsDropdown(theme),
                const SizedBox(height: 12),
                _buildItemCard(theme, item: _pendingItem, isPlaceholder: true),
                if (_pendingItemError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _pendingItemError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                for (var i = 0; i < _items.length; i++) ...[
                  _buildItemCard(theme, item: _items[i], index: i),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 16),
                _TotalsSummary(
                  subtotal: _itemsSubtotal,
                  orderDiscountAmount: _orderDiscountAmount,
                  totalDiscount: _totalDiscount,
                  shippingFee: _shippingFee,
                  grandTotal: _grandTotal,
                  discountController: _orderDiscountController,
                  discountType: _orderDiscountType,
                  onDiscountTypeChanged: (type) {
                    setState(() {
                      _orderDiscountType = type;
                      if (type == DiscountType.amount) {
                        _orderDiscountController.text =
                            CurrencyInputFormatter.normalizeExistingValue(
                          _orderDiscountController.text,
                        );
                      }
                    });
                  },
                  shippingFeeController: _shippingFeeController,
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _submitError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Save Changes' : 'Create'),
        ),
      ],
    );
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      withReadStream: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(growable: false),
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final newFiles = result.files
        .where(
          (file) => isAllowedAttachmentExtension(
            file.extension ?? attachmentExtension(file.name),
          ),
        )
        .toList(growable: false);

    if (newFiles.isEmpty) {
      return;
    }

    setState(() {
      _supportingAttachments = [..._supportingAttachments, ...newFiles];
    });
  }

  void _scheduleExistingAttachmentRemoval(int index) {
    setState(() {
      final removed = _existingAttachments.removeAt(index);
      if (removed.id != null && removed.id!.isNotEmpty) {
        _attachmentsMarkedForDeletion.add(removed.id!);
      } else {
        _attachmentsMarkedForDeletion.add(removed.fileName);
      }
    });
  }

  Widget _buildVendorField(ThemeData theme) {
    if (_isLoadingReferenceData && _vendors.isEmpty) {
      return _ReferenceStatusField(
        label: 'Vendor name',
        child: Row(
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Loading vendor list...')),
          ],
        ),
      );
    }

    if (_referenceDataError != null && _vendors.isEmpty) {
      return _ReferenceErrorField(
        label: 'Vendor name',
        error: _referenceDataError!,
        onRetry: _isLoadingReferenceData ? null : _loadReferenceData,
      );
    }

    if (_vendors.isEmpty) {
      return _ReferenceStatusField(
        label: 'Vendor name',
        child: Row(
          children: const [
            Icon(Icons.info_outline),
            SizedBox(width: 12),
            Expanded(child: Text('No vendors found. Refresh to try again.')),
          ],
        ),
        onRetry: _isLoadingReferenceData ? null : _loadReferenceData,
      );
    }

    return SearchableDropdownFormField<String>(
      initialValue: _selectedVendorName,
      items: _vendors.map((vendor) => vendor.name).toList(growable: false),
      itemToString: _vendorLabel,
      decoration: const InputDecoration(
        labelText: 'Vendor name',
        hintText: 'Select a vendor',
      ),
      dialogTitle: 'Select vendor',
      onChanged: (value) {
        setState(() {
          _selectedVendorName = value;
          final selectedVendor = _findVendorByName(value);
          _selectedVendorCode = selectedVendor?.code;
          _selectedVendorId = selectedVendor?.id;
          _updateOrderNumber();
        });
      },
      validator: (value) {
        if ((value ?? '').trim().isEmpty) {
          return 'Vendor name is required.';
        }
        return null;
      },
    );
  }

  VendorSummary? _findVendorByName(String? name) {
    if (name == null) {
      return null;
    }
    for (final vendor in _vendors) {
      if (vendor.name == name) {
        return vendor;
      }
    }
    return null;
  }

  String _formatInventoryItemName(InventoryItem item) {
    final code = item.skuCode?.trim();
    final skuName = item.skuName?.trim();
    if ((code ?? '').isEmpty && (skuName ?? '').isEmpty) {
      return item.name;
    }
    if (code != null &&
        code.isNotEmpty &&
        skuName != null &&
        skuName.isNotEmpty) {
      return '${code}_$skuName ';
    }
    return code?.isNotEmpty == true ? code! : skuName ?? item.name;
  }

  Widget _buildItemsDropdown(ThemeData theme) {
    if (_isLoadingReferenceData && _inventoryItems.isEmpty) {
      return _ReferenceStatusField(
        label: 'Items',
        child: Row(
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Loading inventory items...')),
          ],
        ),
      );
    }

    if (_referenceDataError != null && _inventoryItems.isEmpty) {
      return _ReferenceErrorField(
        label: 'Items',
        error: _referenceDataError!,
        onRetry: _isLoadingReferenceData ? null : _loadReferenceData,
      );
    }

    if (_inventoryItems.isEmpty) {
      return _ReferenceStatusField(
        label: 'Items',
        child: Row(
          children: const [
            Icon(Icons.info_outline),
            SizedBox(width: 12),
            Expanded(
              child: Text('No inventory items found. Refresh to try again.'),
            ),
          ],
        ),
        onRetry: _isLoadingReferenceData ? null : _loadReferenceData,
      );
    }

    final entries = _inventoryItems
        .map(
          (item) => DropdownMenuEntry<InventoryItem>(
            value: item,
            label: _formatInventoryItemName(item),
          ),
        )
        .toList(growable: false);

    return DropdownMenu<InventoryItem>(
      controller: _itemSearchController,
      requestFocusOnTap: true,
      enableFilter: true,
      leadingIcon: const Icon(Icons.search),
      label: const Text('Select item'),
      dropdownMenuEntries: entries,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      onSelected: _updateSelectedItem,
    );
  }

  Widget _buildItemCard(
    ThemeData theme, {
    required _PurchaseOrderItemDraft item,
    bool isPlaceholder = false,
    int? index,
  }) {
    final title = isPlaceholder ? 'Add item details' : 'Item ${index! + 1}';
    final canRemove = !isPlaceholder;
    final canCommit = isPlaceholder;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                if (canRemove)
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: _isSubmitting || index == null
                        ? null
                        : () => _removeItem(index),
                    icon: const Icon(Icons.delete_outline),
                  )
                else if (canCommit)
                  IconButton.filled(
                    tooltip: 'Add to order',
                    onPressed: _isSubmitting ? null : _commitPendingItem,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ResponsiveFieldsRow(
              children: [
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    item.itemName ??
                        (isPlaceholder
                            ? 'Select an item from the dropdown above'
                            : 'Item unavailable'),
                    style: (item.itemName == null)
                        ? theme.textTheme.bodyMedium?.copyWith(
                            color: theme.hintColor,
                          )
                        : theme.textTheme.bodyMedium,
                  ),
                ),
                TextFormField(
                  controller: item.descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.multiline,
                  minLines: 2,
                  maxLines: null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ResponsiveFieldsRow(
              children: [
                TextFormField(
                  controller: item.quantityController,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (value) => _validateQuantityField(
                    item,
                    isPlaceholder: isPlaceholder,
                  ),
                ),
                TextFormField(
                  controller: item.subtotalController,
                  decoration: const InputDecoration(labelText: 'Subtotal (RM)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  inputFormatters: const [CurrencyInputFormatter()],
                  validator: (value) => _validateSubtotalField(
                    item,
                    isPlaceholder: isPlaceholder,
                  ),
                ),
                TextFormField(
                  controller: item.discountController,
                  decoration: const InputDecoration(labelText: 'Discount (RM)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  inputFormatters: const [CurrencyInputFormatter()],
                  validator: (value) => _validateDiscountField(
                    item,
                    isPlaceholder: isPlaceholder,
                  ),
                ),
                _SystemValueField(
                  label: 'Unit price (RM)',
                  value: item.unitPrice,
                ),
                _SystemValueField(label: 'Total (RM)', value: item.total),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String? _validateQuantityField(
    _PurchaseOrderItemDraft item, {
    required bool isPlaceholder,
  }) {
    if (isPlaceholder) {
      return null;
    }
    if (item.quantity <= 0) {
      return 'Enter a quantity greater than zero.';
    }
    return null;
  }

  String? _validateSubtotalField(
    _PurchaseOrderItemDraft item, {
    required bool isPlaceholder,
  }) {
    if (isPlaceholder) {
      return null;
    }
    if (item.subtotal < 0) {
      return 'Subtotal cannot be negative.';
    }
    return null;
  }

  String? _validateDiscountField(
    _PurchaseOrderItemDraft item, {
    required bool isPlaceholder,
  }) {
    if (isPlaceholder) {
      return null;
    }
    if (item.discount < 0) {
      return 'Discount cannot be negative.';
    }
    if (item.discount > item.subtotal) {
      return 'Discount cannot exceed subtotal.';
    }
    return null;
  }
}

class _PaymentEntriesTable extends StatelessWidget {
  const _PaymentEntriesTable({
    required this.entries,
    required this.paymentModes,
    required this.isLoadingPaymentModes,
    required this.onAdd,
    required this.onRemove,
    required this.onPickDate,
    required this.onPaymentModeChanged,
  });

  final List<_PaymentEntryDraft> entries;
  final List<PaymentMode> paymentModes;
  final bool isLoadingPaymentModes;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final void Function(_PaymentEntryDraft entry) onPickDate;
  final void Function(_PaymentEntryDraft entry, String? modeId)
  onPaymentModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No payments added yet.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add payment'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Payment ${i + 1}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove payment',
                        icon: const Icon(Icons.delete_outline),
                        color: theme.colorScheme.error,
                        onPressed: () => onRemove(i),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ResponsiveFieldsRow(
                    children: [
                      TextFormField(
                        controller: entries[i].amountController,
                        decoration: const InputDecoration(
                          labelText: 'Amount (RM)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [CurrencyInputFormatter()],
                      ),
                      SearchableDropdownFormField<String>(
                        initialValue: entries[i].paymentModeId,
                        items: paymentModes.map((mode) => mode.id).toList(),
                        itemToString: (id) => paymentModes
                            .firstWhere(
                              (mode) => mode.id == id,
                              orElse: () => PaymentMode(id: id, name: 'Unknown mode'),
                            )
                            .name,
                        decoration: const InputDecoration(
                          labelText: 'Payment mode',
                          border: OutlineInputBorder(),
                        ),
                        hintText: isLoadingPaymentModes
                            ? 'Loading payment modes...'
                            : 'Select payment mode',
                        enabled: !isLoadingPaymentModes,
                        dialogTitle: 'Select payment mode',
                        onChanged: paymentModes.isEmpty || isLoadingPaymentModes
                            ? null
                            : (value) =>
                                  onPaymentModeChanged(entries[i], value),
                      ),
                      _PaymentDateField(
                        label: 'Payment date',
                        dateLabel: entries[i].dateLabel,
                        onTap: () => onPickDate(entries[i]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add payment'),
        ),
      ],
    );
  }
}

class _PaymentDateField extends StatelessWidget {
  const _PaymentDateField({
    required this.label,
    required this.dateLabel,
    required this.onTap,
  });

  final String label;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Icon(Icons.event, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(dateLabel)),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

class _OrderDateField extends StatelessWidget {
  const _OrderDateField({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Order date',
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Icon(Icons.event, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text(formatted),
          ],
        ),
      ),
    );
  }
}

class _TotalsSummary extends StatelessWidget {
  const _TotalsSummary({
    required this.subtotal,
    required this.orderDiscountAmount,
    required this.totalDiscount,
    required this.shippingFee,
    required this.grandTotal,
    required this.discountController,
    required this.discountType,
    required this.onDiscountTypeChanged,
    required this.shippingFeeController,
  });

  final double subtotal;
  final double orderDiscountAmount;
  final double totalDiscount;
  final double shippingFee;
  final double grandTotal;
  final TextEditingController discountController;
  final DiscountType discountType;
  final ValueChanged<DiscountType> onDiscountTypeChanged;
  final TextEditingController shippingFeeController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TotalsRow(label: 'Subtotal', amount: subtotal),
        const SizedBox(height: 12),
        _DiscountRow(
          controller: discountController,
          discountType: discountType,
          onDiscountTypeChanged: onDiscountTypeChanged,
          computedDiscount: orderDiscountAmount,
        ),
        const SizedBox(height: 8),
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 8),
        _TotalsRow(
          label: 'Total Discount',
          amount: -totalDiscount,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        _ShippingRow(
          controller: shippingFeeController,
          computedShipping: shippingFee,
        ),
        const SizedBox(height: 12),
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 8),
        _TotalsRow(
          label: 'Grand Total',
          amount: grandTotal,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ResponsiveFieldsRow extends StatelessWidget {
  const _ResponsiveFieldsRow({
    required this.children,
    this.breakpoint = 640,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < breakpoint;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i < children.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.label, required this.amount, this.style});

  final String label;
  final double amount;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveStyle = style ?? theme.textTheme.bodyMedium;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: effectiveStyle),
        Text(_formatCurrency(amount), style: effectiveStyle),
      ],
    );
  }

  String _formatCurrency(double value) {
    final sign = value < 0 ? '-' : '';
    return '${sign}RM${value.abs().toStringAsFixed(2)}';
  }
}

class _DiscountRow extends StatelessWidget {
  const _DiscountRow({
    required this.controller,
    required this.discountType,
    required this.onDiscountTypeChanged,
    required this.computedDiscount,
  });

  final TextEditingController controller;
  final DiscountType discountType;
  final ValueChanged<DiscountType> onDiscountTypeChanged;
  final double computedDiscount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(child: Text('Discount', style: theme.textTheme.bodyMedium)),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                inputFormatters: discountType == DiscountType.amount
                    ? const [CurrencyInputFormatter()]
                    : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<DiscountType>(
              value: discountType,
              items: const [
                DropdownMenuItem(
                  value: DiscountType.percentage,
                  child: Text('%'),
                ),
                DropdownMenuItem(
                  value: DiscountType.amount,
                  child: Text('Amount'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onDiscountTypeChanged(value);
                }
              },
            ),
            const SizedBox(width: 12),
            Text('RM${computedDiscount.toStringAsFixed(2)}'),
          ],
        ),
      ],
    );
  }
}

class _ShippingRow extends StatelessWidget {
  const _ShippingRow({
    required this.controller,
    required this.computedShipping,
  });

  final TextEditingController controller;
  final double computedShipping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text('Shipping Fee', style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                inputFormatters: const [CurrencyInputFormatter()],
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 12),
            Text('RM${computedShipping.toStringAsFixed(2)}'),
          ],
        ),
      ],
    );
  }
}

class _SystemValueField extends StatelessWidget {
  const _SystemValueField({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(value.toStringAsFixed(2)),
    );
  }
}

class _ExistingAttachmentsList extends StatelessWidget {
  const _ExistingAttachmentsList({
    required this.attachments,
    required this.onRemove,
    required this.pendingDeletionCount,
  });

  final List<PurchaseOrderAttachment> attachments;
  final ValueChanged<int> onRemove;
  final int pendingDeletionCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Existing attachments', style: theme.textTheme.titleSmall),
            if (pendingDeletionCount > 0) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text('Deleting on save: $pendingDeletionCount'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (attachments.isEmpty)
          Text(
            'No attachments uploaded for this purchase order.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: attachments.length,
            itemBuilder: (context, index) {
              final attachment = attachments[index];
              final subtitleParts = <String>[];
              final sizeLabel = attachment.sizeLabel?.trim();
              if (sizeLabel != null && sizeLabel.isNotEmpty) {
                subtitleParts.add(sizeLabel);
              }
              final uploadedBy = attachment.uploadedBy?.trim();
              if (uploadedBy != null && uploadedBy.isNotEmpty) {
                subtitleParts.add('Uploaded by $uploadedBy');
              }
              final subtitle = subtitleParts.isEmpty
                  ? null
                  : subtitleParts.join(' • ');

              return Card(
                key: ValueKey(
                  'existing-attachment-$index-${attachment.fileName}',
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(attachment.fileName),
                  subtitle: subtitle == null ? null : Text(subtitle),
                  trailing: IconButton(
                    tooltip: 'Remove attachment',
                    icon: const Icon(Icons.close),
                    onPressed: () => onRemove(index),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _NewAttachmentsList extends StatelessWidget {
  const _NewAttachmentsList({
    required this.attachments,
    required this.onRemove,
  });

  final List<PlatformFile> attachments;
  final ValueChanged<PlatformFile> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'New attachments (uploaded on save)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: attachments.length,
          itemBuilder: (context, index) {
            final file = attachments[index];
            return Card(
              key: ValueKey(
                'new-attachment-$index-${file.name}-${file.identifier ?? ''}',
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(file.name),
                subtitle: Text(_formatSize(file.size)),
                trailing: IconButton(
                  tooltip: 'Remove attachment',
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemove(file),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatSize(int size) {
    const kb = 1024;
    const mb = kb * 1024;
    if (size >= mb) {
      return '${(size / mb).toStringAsFixed(1)} MB';
    }
    if (size >= kb) {
      return '${(size / kb).toStringAsFixed(1)} KB';
    }
    return '$size B';
  }
}

class _ReferenceStatusField extends StatelessWidget {
  const _ReferenceStatusField({
    required this.label,
    required this.child,
    this.onRetry,
  });

  final String label;
  final Widget child;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: child,
      ),
    ];

    if (onRetry != null) {
      children.addAll([
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _ReferenceErrorField extends StatelessWidget {
  const _ReferenceErrorField({
    required this.label,
    required this.error,
    this.onRetry,
  });

  final String label;
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: const Text('Unable to load data.'),
        ),
        const SizedBox(height: 8),
        Text(
          error,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _PaymentEntryDraft {
  _PaymentEntryDraft({
    this.paymentId,
    VoidCallback? onChanged,
    String? initialAmount,
    DateTime? initialDate,
    String? initialPaymentModeId,
    this.initialPaymentModeLabel,
  })  : amountController = TextEditingController(
          text: CurrencyInputFormatter.normalizeExistingValue(initialAmount),
        ),
        _onChanged = onChanged,
        date = initialDate ?? DateTime.now(),
        paymentModeId = initialPaymentModeId {
    amountController.addListener(_notifyChange);
  }

  final String? paymentId;
  final TextEditingController amountController;
  final VoidCallback? _onChanged;
  DateTime date;
  String? paymentModeId;
  final String? initialPaymentModeLabel;

  String get dateLabel => DateFormat.yMMMd().format(date);

  void setDate(DateTime newDate) {
    date = newDate;
    _notifyChange();
  }

  void setPaymentModeId(String? value) {
    if (paymentModeId == value) {
      return;
    }
    paymentModeId = value;
    _notifyChange();
  }

  void _notifyChange() {
    _onChanged?.call();
  }

  void dispose() {
    amountController.dispose();
  }
}

class _PurchaseOrderItemDraft {
  _PurchaseOrderItemDraft({
    required VoidCallback onChanged,
    String? initialItemId,
    String? initialItemName,
    String? initialLineItemId,
    String initialDescription = '',
    String initialQuantity = '1',
    String initialSubtotal = '0',
    String initialDiscount = '0',
  }) : descriptionController = TextEditingController(text: initialDescription),
       quantityController = TextEditingController(text: initialQuantity),
       subtotalController = TextEditingController(
         text: CurrencyInputFormatter.normalizeExistingValue(initialSubtotal),
       ),
       discountController = TextEditingController(
         text: CurrencyInputFormatter.normalizeExistingValue(initialDiscount),
       ),
       itemId = initialItemId,
       itemName = initialItemName,
       lineItemId = initialLineItemId,
       _onChanged = onChanged {
    descriptionController.addListener(onChanged);
    quantityController.addListener(onChanged);
    subtotalController.addListener(onChanged);
    discountController.addListener(onChanged);
  }

  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController subtotalController;
  final TextEditingController discountController;
  final VoidCallback _onChanged;

  String? itemId;
  String? itemName;
  String? lineItemId;

  double get quantity =>
      double.tryParse(quantityController.text.replaceAll(',', '.')) ?? 0;

  double get subtotal =>
      double.tryParse(subtotalController.text.replaceAll(',', '.')) ?? 0;

  double get discount =>
      double.tryParse(discountController.text.replaceAll(',', '.')) ?? 0;

  double get total {
    final value = subtotal - discount;
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value <= 0 ? 0 : value;
  }

  double get unitPrice => quantity <= 0 ? 0 : total / quantity;

  bool get hasContent {
    return (itemName?.trim().isNotEmpty ?? false) ||
        descriptionController.text.trim().isNotEmpty ||
        quantityController.text.trim().isNotEmpty ||
        subtotalController.text.trim().isNotEmpty ||
        discountController.text.trim().isNotEmpty;
  }

  void setItem({String? itemId, String? itemName}) {
    this.itemId = itemId;
    this.itemName = itemName;
    _onChanged();
  }

  void clear() {
    itemId = null;
    itemName = null;
    lineItemId = null;
    descriptionController.clear();
    quantityController.text = '1';
    subtotalController.text = CurrencyInputFormatter.normalizeExistingValue('0');
    discountController.text = CurrencyInputFormatter.normalizeExistingValue('0');
    _onChanged();
  }

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    subtotalController.dispose();
    discountController.dispose();
  }
}

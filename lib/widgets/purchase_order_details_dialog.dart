import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/app/app_state.dart';

import '../app/app_state_scope.dart';
import '../services/payment_modes_service.dart';
import '../services/purchase_order_detail_service.dart';
import '../services/purchase_orders_service.dart';
import 'attachment_picker.dart';
import 'attachment_pdf_preview.dart';
import 'currency_input_formatter.dart';
import 'searchable_dropdown_form_field.dart';

class PurchaseOrderDetailsDialog extends StatefulWidget {
  const PurchaseOrderDetailsDialog({super.key, required this.orderId});

  final String orderId;

  @override
  State<PurchaseOrderDetailsDialog> createState() =>
      _PurchaseOrderDetailsDialogState();
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

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
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
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

class _PurchaseOrderDetailsDialogState
    extends State<PurchaseOrderDetailsDialog> {
  late Future<PurchaseOrderDetail> _future;
  final _service = PurchaseOrderDetailService();
  final _itemsScrollController = ScrollController();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _loadDetails();
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _itemsScrollController.dispose();
    super.dispose();
  }

  Future<PurchaseOrderDetail> _loadDetails() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      throw const PurchaseOrderDetailException('Dialog no longer mounted');
    }

    if (token == null || token.trim().isEmpty) {
      throw const PurchaseOrderDetailException('You are not logged in.');
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

    return _service.fetchPurchaseOrder(
      id: widget.orderId,
      headers: {
        'Accept': 'application/json',
        'authtoken': authtokenHeader,
        'Authorization': normalizedAuth,
      },
    );
  }

  void _retry() {
    setState(() {
      _future = _loadDetails();
    });
  }

  Future<void> _openAddAttachmentDialog(PurchaseOrderDetail detail) async {
    final added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _AddAttachmentsDialog(orderId: detail.id, orderNumber: detail.number),
    );

    if (added == true) {
      _retry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 840,
        height: 620,
        child: FutureBuilder<PurchaseOrderDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ErrorView(error: snapshot.error, onRetry: _retry);
            }

            if (!snapshot.hasData) {
              return const _ErrorView(
                error: 'Unable to load purchase order details.',
              );
            }

            final detail = snapshot.data!;

            return DefaultTabController(
              length: 3,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DialogHeader(
                      orderNumber: detail.number,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 12),
                    _DialogTabs(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _DetailsTab(
                            detail: detail,
                            itemsController: _itemsScrollController,
                          ),
                          _PaymentsTab(
                            detail: detail,
                            onPaymentsUpdated: _retry,
                          ),
                          _AttachmentsTab(
                            detail: detail,
                            onAddAttachment: () =>
                                _openAddAttachmentDialog(detail),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.orderNumber, required this.onClose});

  final String orderNumber;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Purchase Order $orderNumber',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _DialogTabs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return TabBar(
      labelStyle: labelStyle,
      labelColor: theme.colorScheme.primary,
      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
      indicatorColor: theme.colorScheme.primary,
      tabs: const [
        Tab(text: 'Details'),
        Tab(text: 'Payments'),
        Tab(text: 'Attachments'),
      ],
    );
  }
}

class _PillStyle {
  const _PillStyle({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
}

class _SummaryField {
  const _SummaryField._(this.label, this.value, this.pillStyle);

  const _SummaryField.text(String label, String value)
    : this._(label, value, null);

  _SummaryField.pill({required String label, required _PillStyle pillStyle})
    : this._(label, pillStyle.label, pillStyle);

  final String label;
  final String value;
  final _PillStyle? pillStyle;
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.field});

  final _SummaryField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = field.pillStyle;
    final value = field.value.trim().isEmpty ? '—' : field.value.trim();

    if (pill == null || value == '—') {
      return Text(value, style: theme.textTheme.bodyMedium);
    }

    final textStyle =
        theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: pill.foregroundColor,
        ) ??
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: pill.foregroundColor,
        );

    return Container(
      decoration: BoxDecoration(
        color: pill.backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(pill.label, style: textStyle),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.field});

  final _SummaryField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          _SummaryValue(field: field),
        ],
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.detail});

  final PurchaseOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approvalStatusField = _SummaryField.pill(
      label: 'Approval status',
      pillStyle: _buildApprovalPillStyle(theme, detail),
    );
    final deliveryStatusField = _SummaryField.pill(
      label: 'Delivery status',
      pillStyle: _buildDeliveryStatusPillStyle(theme, detail),
    );
    final vendorField = _SummaryField.text('Vendor', detail.vendorName);
    final orderNameField = _SummaryField.text('Order name', detail.name);
    final orderDateField = _SummaryField.text(
      'Order date',
      detail.orderDateLabel,
    );
    final deliveryDateField = _SummaryField.text(
      'Delivery date',
      detail.deliveryDateLabel,
    );
    final referenceField = detail.referenceLabel != null
        ? _SummaryField.text('Reference', detail.referenceLabel!)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        if (!isWide) {
          final fields = <_SummaryField?>[
            approvalStatusField,
            deliveryStatusField,
            vendorField,
            orderNameField,
            orderDateField,
            deliveryDateField,
            referenceField,
          ].whereType<_SummaryField>().toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < fields.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == fields.length - 1 ? 0 : 16,
                  ),
                  child: _SummaryTile(field: fields[i]),
                ),
            ],
          );
        }

        final rows = <Widget>[
          Row(
            children: [
              Expanded(child: _SummaryTile(field: approvalStatusField)),
              const SizedBox(width: 16),
              Expanded(child: _SummaryTile(field: deliveryStatusField)),
            ],
          ),
          const SizedBox(height: 16),
          _SummaryTile(field: vendorField),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _SummaryTile(field: orderNameField)),
              const SizedBox(width: 16),
              Expanded(child: _SummaryTile(field: orderDateField)),
            ],
          ),
          const SizedBox(height: 16),
          _SummaryTile(field: deliveryDateField),
        ];

        if (referenceField != null) {
          rows
            ..add(const SizedBox(height: 16))
            ..add(_SummaryTile(field: referenceField));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}

_PillStyle _buildDeliveryStatusPillStyle(
  ThemeData theme,
  PurchaseOrderDetail detail,
) {
  final label = _resolvePillLabel(
    explicit: detail.deliveryStatusLabel,
    id: detail.deliveryStatusId,
    lookup: purchaseOrderDeliveryStatusLabels,
  );

  final id =
      detail.deliveryStatusId ??
      _findIdForLabel(label, purchaseOrderDeliveryStatusLabels);
  final colorScheme = theme.colorScheme;

  Color background;
  Color foreground;

  switch (id) {
    case 1:
      background = Colors.green.shade100;
      foreground = Colors.green.shade900;
      break;
    case 0:
      background = colorScheme.errorContainer;
      foreground = colorScheme.onErrorContainer;
      break;
    default:
      background = colorScheme.surfaceVariant;
      foreground = colorScheme.onSurfaceVariant;
      break;
  }

  return _PillStyle(
    label: label,
    backgroundColor: background,
    foregroundColor: foreground,
  );
}

_PillStyle _buildApprovalPillStyle(
  ThemeData theme,
  PurchaseOrderDetail detail,
) {
  final label = _resolvePillLabel(
    explicit: detail.approvalStatus,
    id: detail.approvalStatusId,
    lookup: purchaseOrderApprovalStatusLabels,
  );

  final id =
      detail.approvalStatusId ??
      _findIdForLabel(label, purchaseOrderApprovalStatusLabels);
  final colorScheme = theme.colorScheme;

  Color background;
  Color foreground;

  switch (id) {
    case 2:
      background = colorScheme.primaryContainer;
      foreground = colorScheme.onPrimaryContainer;
      break;
    case 3:
      background = colorScheme.errorContainer;
      foreground = colorScheme.onErrorContainer;
      break;
    case 4:
      background = colorScheme.tertiaryContainer;
      foreground = colorScheme.onTertiaryContainer;
      break;
    case 1:
    default:
      background = colorScheme.surfaceVariant;
      foreground = colorScheme.onSurfaceVariant;
      break;
  }

  return _PillStyle(
    label: label,
    backgroundColor: background,
    foregroundColor: foreground,
  );
}

String _resolvePillLabel({
  required String explicit,
  required int? id,
  required Map<int, String> lookup,
}) {
  final trimmed = explicit.trim();
  if (trimmed.isNotEmpty && trimmed != '—') {
    final numericLabel = int.tryParse(trimmed);
    if (numericLabel != null) {
      final mapped = lookup[numericLabel];
      if (mapped != null) {
        return mapped;
      }
    }
    return trimmed;
  }
  if (id != null) {
    final mapped = lookup[id];
    if (mapped != null) {
      return mapped;
    }
  }
  return '—';
}

int? _findIdForLabel(String label, Map<int, String> lookup) {
  final normalized = label.trim().toLowerCase();
  for (final entry in lookup.entries) {
    if (entry.value.toLowerCase() == normalized) {
      return entry.key;
    }
  }
  return null;
}

class _ItemsSection extends StatelessWidget {
  const _ItemsSection({required this.detail, required this.controller});

  final PurchaseOrderDetail detail;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (detail.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'No items were returned for this purchase order.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    const tablePadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final headerTextStyle = theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle(fontWeight: FontWeight.w700);
    final cellStyle = theme.textTheme.bodyMedium;
    final dividerColor = theme.dividerColor;

    final hasDiscountColumn = detail.items.any((item) => item.hasDiscount);

    TableRow buildHeaderRow() {
      final headers = [
        'Item',
        'Description',
        'Quantity',
        'Rate',
        if (hasDiscountColumn) 'Discount (RM)',
        'Total',
      ];

      return TableRow(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        children: headers
            .map(
              (label) => Padding(
                padding: tablePadding,
                child: Text(label, style: headerTextStyle),
              ),
            )
            .toList(),
      );
    }

    TableRow buildDataRow(PurchaseOrderItem item) {
      final values = [
        item.name,
        item.description,
        item.quantityLabel,
        item.rateLabel,
        if (hasDiscountColumn) item.discountLabel ?? '—',
        item.amountLabel,
      ];

      return TableRow(
        children: values
            .map(
              (value) => Padding(
                padding: tablePadding,
                child: Text(value, style: cellStyle, softWrap: true),
              ),
            )
            .toList(),
      );
    }

    Table buildTable() {
      final columnWidths = <int, TableColumnWidth>{
        0: const FlexColumnWidth(2),
        1: const FlexColumnWidth(3),
        2: const FlexColumnWidth(1.4),
        3: const FlexColumnWidth(1.4),
      };

      var columnIndex = 4;
      if (hasDiscountColumn) {
        columnWidths[columnIndex] = const FlexColumnWidth(1.4);
        columnIndex++;
      }

      columnWidths[columnIndex] = const FlexColumnWidth(1.4);

      return Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: columnWidths,
        border: TableBorder.all(
          color: dividerColor,
          width: 1,
          borderRadius: BorderRadius.circular(8),
        ),
        children: [buildHeaderRow(), ...detail.items.map(buildDataRow)],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const minTableWidth = 900.0;
            return Scrollbar(
              controller: controller,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: math.max(constraints.maxWidth, minTableWidth),
                  ),
                  child: buildTable(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TotalsSection extends StatelessWidget {
  const _TotalsSection({required this.detail, required this.theme});

  final PurchaseOrderDetail detail;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [..._buildTotalRows()],
      ),
    );
  }

  List<Widget> _buildTotalRows() {
    final rows = <Widget>[];

    void addRow(String label, String value, {bool emphasize = false}) {
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: 8));
      }
      rows.add(
        _TotalRow(
          label: label,
          value: value,
          theme: theme,
          emphasize: emphasize,
        ),
      );
    }

    addRow('Subtotal', detail.subtotalLabel);

    if (detail.hasDiscount && detail.discountLabel != null) {
      addRow('Discount', detail.discountLabel!);
    }

    if (detail.hasShippingFee && detail.shippingFeeLabel != null) {
      addRow('Shipping Fee', detail.shippingFeeLabel!);
    }

    addRow('Total', detail.totalLabel, emphasize: true);

    return rows;
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    required this.theme,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final ThemeData theme;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final labelStyle = theme.textTheme.bodyMedium;
    final valueStyle = emphasize
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);

    return Align(
      alignment: Alignment.centerRight,
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: labelStyle,
          children: [TextSpan(text: value, style: valueStyle)],
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}

class _RichTextSection extends StatelessWidget {
  const _RichTextSection({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.detail, required this.itemsController});

  final PurchaseOrderDetail detail;
  final ScrollController itemsController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummarySection(detail: detail),
          const SizedBox(height: 24),
          _ItemsSection(detail: detail, controller: itemsController),
          const SizedBox(height: 24),
          _TotalsSection(detail: detail, theme: theme),
          if (detail.hasNotes) ...[
            const SizedBox(height: 24),
            _RichTextSection(title: 'Notes', value: detail.notes!),
          ],
          if (detail.hasTerms) ...[
            const SizedBox(height: 24),
            _RichTextSection(title: 'Terms & Conditions', value: detail.terms!),
          ],
        ],
      ),
    );
  }
}

class _EmptyTabMessage extends StatelessWidget {
  const _EmptyTabMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: color),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class _PaymentsTab extends StatefulWidget {
  const _PaymentsTab({required this.detail, this.onPaymentsUpdated});

  final PurchaseOrderDetail detail;
  final VoidCallback? onPaymentsUpdated;

  @override
  State<_PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<_PaymentsTab> {
  final _paymentModesService = PaymentModesService();
  final _paymentDrafts = <_PaymentEntryDraft>[];
  List<PaymentMode> _paymentModes = const [];
  bool _isLoadingPaymentModes = false;
  String? _paymentModesError;
  bool _hasInitializedPaymentModes = false;

  @override
  void initState() {
    super.initState();
    _initializeDrafts();
  }

  @override
  void didUpdateWidget(covariant _PaymentsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.payments != widget.detail.payments) {
      _resetDrafts();
      _initializeDrafts();
      _applyPaymentModeMatches();
    }
  }

  @override
  void dispose() {
    _resetDrafts();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitializedPaymentModes) {
      _hasInitializedPaymentModes = true;
      _loadPaymentModes();
    }
  }

  void _initializeDrafts() {
    for (final payment in widget.detail.payments) {
      _paymentDrafts.add(
        _PaymentEntryDraft(
          amountText: payment.amountLabel,
          initialDate: payment.date,
          paymentModeLabel: payment.method,
        ),
      );
    }
  }

  void _resetDrafts() {
    for (final draft in _paymentDrafts) {
      draft.dispose();
    }
    _paymentDrafts.clear();
  }

  Future<void> _loadPaymentModes() async {
    setState(() {
      _paymentModesError = null;
      _isLoadingPaymentModes = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _paymentModesError = 'You are not logged in.';
        _isLoadingPaymentModes = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final modes = await _paymentModesService.fetchPaymentModes(
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _paymentModes = modes;
        _applyPaymentModeMatches();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _paymentModesError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingPaymentModes = false);
      }
    }
  }

  Map<String, String> _buildAuthHeaders(AppState appState, String token) {
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
    return {'authtoken': authtokenHeader, 'Authorization': normalizedAuth};
  }

  void _applyPaymentModeMatches() {
    if (_paymentModes.isEmpty) {
      return;
    }

    for (final draft in _paymentDrafts) {
      final matchedId = _matchPaymentModeId(draft.paymentModeLabel);
      final resolvedId = matchedId ?? draft.paymentModeId;
      if (resolvedId != null) {
        draft.setPaymentModeId(
          resolvedId,
          name: _resolvePaymentModeName(resolvedId) ?? draft.paymentModeLabel,
        );
      } else if (draft.paymentModeLabel == null && _paymentModes.isNotEmpty) {
        final defaultMode = _paymentModes.first;
        draft.setPaymentModeId(defaultMode.id, name: defaultMode.name);
      }
    }
  }

  String? _matchPaymentModeId(String? labelOrId) {
    if (labelOrId == null) {
      return null;
    }
    final trimmed = labelOrId.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    for (final mode in _paymentModes) {
      if (mode.id == trimmed) {
        return mode.id;
      }
    }

    final normalized = trimmed.toLowerCase();
    for (final mode in _paymentModes) {
      if (mode.name.toLowerCase() == normalized) {
        return mode.id;
      }
    }
    return null;
  }

  String? _resolvePaymentModeName(String? id) {
    if (id == null) {
      return null;
    }
    for (final mode in _paymentModes) {
      if (mode.id == id) {
        return mode.name;
      }
    }
    return null;
  }

  Future<void> _openAddPaymentDialog() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CreatePaymentsDialog(detail: widget.detail),
    );

    if (created == true) {
      widget.onPaymentsUpdated?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final payments = widget.detail.payments;

    if (payments.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: _EmptyTabMessage(
              icon: Icons.receipt_long,
              message: 'No payments recorded for this purchase order.',
              action: ElevatedButton.icon(
                onPressed: _openAddPaymentDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add payment'),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: _PaymentEntriesTable(
                entries: _paymentDrafts,
                paymentModes: _paymentModes,
                isLoadingPaymentModes: _isLoadingPaymentModes,
                paymentModesError: _paymentModesError,
                readOnly: true,
                showAddButton: false,
                showRemoveButton: false,
                onAdd: () {},
                onRemove: (_) {},
                onPickDate: (_) {},
                onPaymentModeChanged: (entry, modeId) {
                  final name = _resolvePaymentModeName(modeId);
                  setState(() => entry.setPaymentModeId(modeId, name: name));
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: _openAddPaymentDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add payment'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CreatePaymentsDialog extends StatefulWidget {
  const _CreatePaymentsDialog({required this.detail});

  final PurchaseOrderDetail detail;

  @override
  State<_CreatePaymentsDialog> createState() => _CreatePaymentsDialogState();
}

class _CreatePaymentsDialogState extends State<_CreatePaymentsDialog> {
  final _payments = <_PaymentEntryDraft>[];
  final _service = PurchaseOrdersService();
  final _paymentModesService = PaymentModesService();
  bool _isSubmitting = false;
  bool _isLoadingPaymentModes = false;
  bool _hasLoadedPaymentModes = false;
  String? _paymentModesError;
  List<PaymentMode> _paymentModes = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _payments.add(_PaymentEntryDraft(initialDate: DateTime.now()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoadedPaymentModes) {
      _hasLoadedPaymentModes = true;
      _loadPaymentModes();
    }
  }

  @override
  void dispose() {
    for (final payment in _payments) {
      payment.dispose();
    }
    super.dispose();
  }

  void _addPayment() {
    setState(() {
      final entry = _PaymentEntryDraft(initialDate: DateTime.now());
      if (_paymentModes.isNotEmpty) {
        entry.setPaymentModeId(_paymentModes.first.id);
      }
      _payments.add(entry);
    });
  }

  void _removePayment(int index) {
    setState(() {
      final removed = _payments.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _loadPaymentModes() async {
    setState(() {
      _paymentModesError = null;
      _isLoadingPaymentModes = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _paymentModesError = 'You are not logged in.';
        _isLoadingPaymentModes = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final modes = await _paymentModesService.fetchPaymentModes(
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _paymentModes = modes;
        final defaultModeId = _paymentModes.isNotEmpty
            ? _paymentModes.first.id
            : null;
        for (final entry in _payments) {
          entry.setPaymentModeId(
            entry.paymentModeId ?? defaultModeId,
            name:
                entry.paymentModeLabel ??
                (defaultModeId == null
                    ? null
                    : _paymentModes
                          .firstWhere((mode) => mode.id == defaultModeId)
                          .name),
          );
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _paymentModesError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingPaymentModes = false);
      }
    }
  }

  Map<String, String> _buildAuthHeaders(AppState appState, String token) {
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
    return {'authtoken': authtokenHeader, 'Authorization': normalizedAuth};
  }

  Future<void> _pickDate(_PaymentEntryDraft entry) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: entry.date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (picked != null) {
      setState(() {
        entry.setDate(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (_payments.isEmpty) {
      setState(() {
        _error = 'Add at least one payment entry.';
      });
      return;
    }

    setState(() {
      _error = null;
      _isSubmitting = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _error = 'You are not logged in.';
        _isSubmitting = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    final purchaseOrderNumber = int.tryParse(widget.detail.number);
    final payments = <CreatePurchaseOrderPayment>[];

    for (final entry in _payments) {
      final amount =
          double.tryParse(entry.amountController.text.replaceAll(',', '.')) ??
          0;
      final method = entry.paymentModeId?.trim() ?? '';

      if (amount <= 0 || method.isEmpty) {
        setState(() {
          _error =
              'Enter a payment mode and amount greater than zero for all payments.';
          _isSubmitting = false;
        });
        return;
      }

      payments.add(
        CreatePurchaseOrderPayment(
          purchaseOrderNumber: purchaseOrderNumber,
          amount: amount,
          paymentMode: method,
          date: entry.date ?? DateTime.now(),
          requester: appState.currentUserId,
        ),
      );
    }

    try {
      await _service.createPayments(
        id: widget.detail.id,
        headers: headers,
        payments: payments,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Add Payment',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _PaymentEntriesTable(
                entries: _payments,
                isLoadingPaymentModes: _isLoadingPaymentModes,
                paymentModes: _paymentModes,
                paymentModesError: _paymentModesError,
                onAdd: _addPayment,
                onRemove: _removePayment,
                onPickDate: _pickDate,
                onPaymentModeChanged: (entry, modeId) =>
                    setState(() => entry.setPaymentModeId(modeId)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSubmitting ? 'Saving...' : 'Save payments'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
    this.paymentModesError,
    this.readOnly = false,
    this.showAddButton = true,
    this.showRemoveButton = true,
  });

  final List<_PaymentEntryDraft> entries;
  final List<PaymentMode> paymentModes;
  final bool isLoadingPaymentModes;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final void Function(_PaymentEntryDraft entry) onPickDate;
  final void Function(_PaymentEntryDraft entry, String? modeId)
  onPaymentModeChanged;
  final String? paymentModesError;
  final bool readOnly;
  final bool showAddButton;
  final bool showRemoveButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No payments added yet.', style: theme.textTheme.bodyMedium),
          if (showAddButton) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add payment'),
            ),
          ],
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
                      if (showRemoveButton)
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
                      if (readOnly)
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Amount (RM)',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _resolveAmountLabel(entries[i]),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.disabledColor,
                            ),
                          ),
                        )
                      else
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
                          enabled: !readOnly,
                        ),
                      if (readOnly)
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Payment mode',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            entries[i].paymentModeLabel ?? '—',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.disabledColor,
                            ),
                          ),
                        )
                      else
                        SearchableDropdownFormField<String>(
                          initialValue: entries[i].paymentModeId,
                          items: paymentModes.map((mode) => mode.id).toList(),
                          itemToString: (id) =>
                              _findPaymentModeName(paymentModes, id) ?? 'Unknown mode',
                          decoration: InputDecoration(
                            labelText: 'Payment mode',
                            border: const OutlineInputBorder(),
                            helperText:
                                paymentModesError ??
                                (paymentModes.isEmpty
                                    ? 'Unable to load payment modes'
                                    : null),
                          ),
                          hintText: isLoadingPaymentModes
                              ? 'Loading payment modes...'
                              : 'Select payment mode',
                          enabled: !isLoadingPaymentModes && !readOnly,
                          dialogTitle: 'Select payment mode',
                          onChanged:
                              paymentModes.isEmpty ||
                                      isLoadingPaymentModes ||
                                      readOnly
                                  ? null
                                  : (value) {
                                      final selectedName = _findPaymentModeName(
                                        paymentModes,
                                        value,
                                      );
                                      onPaymentModeChanged(entries[i], value);
                                      entries[i].setPaymentModeId(
                                        value,
                                        name: selectedName,
                                      );
                                    },
                        ),
                      _PaymentDateField(
                        label: 'Payment date',
                        dateLabel: entries[i].dateLabel,
                        onTap: () => onPickDate(entries[i]),
                        enabled: !readOnly,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showAddButton)
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add payment'),
          ),
      ],
    );
  }

  String? _findPaymentModeName(List<PaymentMode> modes, String? id) {
    if (id == null) {
      return null;
    }
    for (final mode in modes) {
      if (mode.id == id) {
        return mode.name;
      }
    }
    return null;
  }

  String _resolveAmountLabel(_PaymentEntryDraft entry) {
    final text = entry.amountController.text.trim();
    return text.isEmpty ? '—' : text;
  }
}

class _PaymentDateField extends StatelessWidget {
  const _PaymentDateField({
    required this.label,
    required this.dateLabel,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String dateLabel;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today, color: theme.primaryColor),
        ),
        child: Text(
          dateLabel,
          style: !enabled
              ? theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor)
              : theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _PaymentEntryDraft {
  _PaymentEntryDraft({
    String? amountText,
    DateTime? initialDate,
    this.paymentModeLabel,
  }) : amountController = TextEditingController(
         text: CurrencyInputFormatter.normalizeExistingValue(amountText),
       ),
       date = initialDate;

  final TextEditingController amountController;
  DateTime? date;
  String? paymentModeId;
  String? paymentModeLabel;

  String get dateLabel => date == null ? '—' : DateFormat.yMMMd().format(date!);

  void setDate(DateTime newDate) {
    date = newDate;
  }

  void setPaymentModeId(String? value, {String? name}) {
    paymentModeId = value;
    if (name != null || value == null) {
      paymentModeLabel = name;
    }
  }

  void dispose() {
    amountController.dispose();
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

class _AttachmentsTab extends StatelessWidget {
  const _AttachmentsTab({
    super.key,
    this.detail,
    this.onAddAttachment,
  });

  final PurchaseOrderDetail? detail;
  final VoidCallback? onAddAttachment;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;

    if (detail == null) {
      return const _ErrorView(
        error: 'Purchase order details are unavailable.',
      );
    }

    if (!detail.hasAttachments) {
      return Column(
        children: [
          Expanded(
            child: _EmptyTabMessage(
              icon: Icons.attach_file,
              message: 'No attachments were uploaded for this purchase order.',
              action: onAddAttachment == null
                  ? null
                  : ElevatedButton.icon(
                      onPressed: onAddAttachment,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Add attachment'),
                    ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: detail.attachments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final attachment = detail.attachments[index];
              return _AttachmentCard(attachment: attachment);
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (onAddAttachment != null)
              ElevatedButton.icon(
                onPressed: onAddAttachment,
                icon: const Icon(Icons.attach_file),
                label: const Text('Add attachment'),
              ),
          ],
        ),
      ],
    );
  }
}

class _AddAttachmentsDialog extends StatefulWidget {
  const _AddAttachmentsDialog({
    required this.orderId,
    required this.orderNumber,
  });

  final String orderId;
  final String orderNumber;

  @override
  State<_AddAttachmentsDialog> createState() => _AddAttachmentsDialogState();
}

class _AddAttachmentsDialogState extends State<_AddAttachmentsDialog> {
  final _service = PurchaseOrdersService();
  List<PlatformFile> _attachments = [];
  bool _isSubmitting = false;
  String? _error;

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      withReadStream: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(),
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final validFiles = result.files
        .where(
          (file) =>
              isAllowedAttachmentExtension(attachmentExtension(file.name)),
        )
        .toList();

    if (validFiles.isEmpty) {
      return;
    }

    setState(() {
      _attachments = [..._attachments, ...validFiles];
    });
  }

  void _onFilesSelected(List<PlatformFile> files) {
    setState(() => _attachments = files);
  }

  void _removeAttachment(PlatformFile file) {
    setState(() {
      _attachments = List.of(_attachments)..remove(file);
    });
  }

  Future<void> _submit() async {
    if (_attachments.isEmpty) {
      setState(() {
        _error = 'Select at least one attachment to upload.';
      });
      return;
    }

    setState(() {
      _error = null;
      _isSubmitting = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _error = 'You are not logged in.';
        _isSubmitting = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      await _service.uploadAttachments(
        id: widget.orderId,
        headers: headers,
        attachments: _attachments,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } on PurchaseOrdersException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Failed to upload attachments: ${error.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Map<String, String> _buildAuthHeaders(AppState appState, String token) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        'Add attachment${widget.orderNumber.isNotEmpty ? ' — ${widget.orderNumber}' : ''}',
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Upload supporting files for this purchase order.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            AttachmentPicker(
              description:
                  'Drag and drop files or tap to browse for purchase order attachments.',
              files: _attachments,
              onPick: _pickAttachments,
              onFilesSelected: _onFilesSelected,
              onFileRemoved: _removeAttachment,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload),
          label: Text(_isSubmitting ? 'Uploading...' : 'Upload attachments'),
        ),
      ],
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: labelColor,
    );

    final displayValue = value.trim().isEmpty ? '—' : value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: labelStyle)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayValue,
              style: theme.textTheme.bodyMedium,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeAttachmentDownloadUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }

  if (trimmed.startsWith('//')) {
    return 'https:$trimmed';
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return trimmed;
  }

  if (uri.hasScheme) {
    return uri.toString();
  }

  final base = Uri.base;
  final canUseBase =
      base.hasScheme && (base.scheme == 'http' || base.scheme == 'https');
  if (canUseBase) {
    return base.resolveUri(uri).toString();
  }

  return uri.toString();
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment});

  final PurchaseOrderAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final normalizedDownloadUrl = attachment.hasDownloadUrl
        ? _normalizeAttachmentDownloadUrl(attachment.downloadUrl!)
        : null;
    final previewType = normalizedDownloadUrl != null
        ? _resolvePreviewType(attachment)
        : null;

    final children = <Widget>[
      Row(
        children: [
          Icon(Icons.attach_file, color: labelColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.fileName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _LabelValueRow(label: 'Uploaded on', value: attachment.uploadedAtLabel),
    ];

    if (attachment.uploadedBy != null &&
        attachment.uploadedBy!.trim().isNotEmpty) {
      children.add(
        _LabelValueRow(
          label: 'Uploaded by',
          value: attachment.uploadedBy!.trim(),
        ),
      );
    }

    if (attachment.sizeLabel != null &&
        attachment.sizeLabel!.trim().isNotEmpty) {
      children.add(
        _LabelValueRow(label: 'Size', value: attachment.sizeLabel!.trim()),
      );
    }

    if (attachment.hasDescription) {
      children.addAll([
        const SizedBox(height: 12),
        Text(
          'Description',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(attachment.description!.trim(), style: theme.textTheme.bodyMedium),
      ]);
    }

    if (attachment.hasDownloadUrl && normalizedDownloadUrl != null) {
      children.addAll([
        const SizedBox(height: 12),
        Text(
          'Download URL',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          normalizedDownloadUrl,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ]);
    }

    if (previewType != null && normalizedDownloadUrl != null) {
      children.addAll([
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            icon: const Icon(Icons.visibility),
            label: const Text('Preview'),
            onPressed: () {
              _showAttachmentPreview(
                context: context,
                attachment: attachment,
                downloadUrl: normalizedDownloadUrl,
                previewType: previewType,
              );
            },
          ),
        ),
      ]);
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

enum _AttachmentPreviewType { image, pdf }

_AttachmentPreviewType? _resolvePreviewType(
  PurchaseOrderAttachment attachment,
) {
  if (!attachment.hasDownloadUrl) {
    return null;
  }

  if (_matchesExtension(attachment.fileName, _imageExtensions) ||
      _matchesExtension(attachment.downloadUrl, _imageExtensions)) {
    return _AttachmentPreviewType.image;
  }

  if (_matchesExtension(attachment.fileName, _pdfExtensions) ||
      _matchesExtension(attachment.downloadUrl, _pdfExtensions)) {
    return _AttachmentPreviewType.pdf;
  }

  return null;
}

const _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.bmp',
  '.webp',
  '.heic',
};

const _pdfExtensions = <String>{'.pdf'};

bool _matchesExtension(String? value, Set<String> extensions) {
  if (value == null || value.trim().isEmpty) {
    return false;
  }

  bool match(String candidate) {
    final lower = candidate.toLowerCase();
    for (final ext in extensions) {
      final normalizedExt = ext.startsWith('.') ? ext : '.$ext';
      if (lower.endsWith(normalizedExt)) {
        return true;
      }
    }
    return false;
  }

  final trimmed = value.trim();
  if (match(trimmed)) {
    return true;
  }

  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && match(parsed.path)) {
    return true;
  }

  return false;
}

void _showAttachmentPreview({
  required BuildContext context,
  required PurchaseOrderAttachment attachment,
  required String downloadUrl,
  required _AttachmentPreviewType previewType,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => _AttachmentPreviewDialog(
      attachment: attachment,
      downloadUrl: downloadUrl,
      previewType: previewType,
    ),
  );
}

class _AttachmentPreviewDialog extends StatelessWidget {
  const _AttachmentPreviewDialog({
    required this.attachment,
    required this.downloadUrl,
    required this.previewType,
  });

  final PurchaseOrderAttachment attachment;
  final String downloadUrl;
  final _AttachmentPreviewType previewType;

  @override
  Widget build(BuildContext context) {
    final title = '${attachment.fileName} preview';
    final theme = Theme.of(context);
    Widget content;

    switch (previewType) {
      case _AttachmentPreviewType.image:
        content = _ImagePreview(downloadUrl: downloadUrl);
        break;
      case _AttachmentPreviewType.pdf:
        content = _PdfPreview(downloadUrl: downloadUrl);
        break;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.downloadUrl});

  final String downloadUrl;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      child: Center(
        child: Image.network(
          downloadUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Unable to load image preview.'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PdfPreview extends StatelessWidget {
  const _PdfPreview({required this.downloadUrl});

  final String downloadUrl;

  @override
  Widget build(BuildContext context) {
    return buildAttachmentPdfPreview(downloadUrl);
  }
}

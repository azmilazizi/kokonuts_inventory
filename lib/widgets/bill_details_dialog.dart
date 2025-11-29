import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/app/app_state.dart';
import 'package:kokonuts_bookkeeping/app/app_state_scope.dart';
import 'package:kokonuts_bookkeeping/widgets/authenticated_image.dart';
import 'attachment_pdf_preview.dart';
import 'attachment_picker.dart';
import 'currency_input_formatter.dart';
import 'searchable_dropdown_form_field.dart';

import '../services/accounts_service.dart';
import '../services/bills_service.dart';

class BillDetailsDialog extends StatefulWidget {
  const BillDetailsDialog({
    super.key,
    required this.bill,
    required this.vendorName,
    this.onBillUpdated,
  });

  final Bill bill;
  final String vendorName;
  final void Function(Bill bill)? onBillUpdated;

  @override
  State<BillDetailsDialog> createState() => _BillDetailsDialogState();
}

class _BillDetailsDialogState extends State<BillDetailsDialog> {
  late Future<Bill> _future;
  final _billsService = BillsService();
  final _accountsService = AccountsService();
  bool _initialized = false;
  bool _isLoadingAccounts = false;
  bool _isLoadingAccountNames = false;
  bool _isLoadingPayments = false;
  String? _accountsError;
  String? _paymentsError;
  List<Account> _accounts = const [];
  Map<String, String> _accountNamesById = {};
  List<BillPayment> _payments = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _loadDetails();
      _initialized = true;
    }
  }

  Future<Bill> _loadDetails({bool notifyParent = false}) async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      throw BillsException('Dialog no longer mounted');
    }

    if (token == null || token.trim().isEmpty) {
      throw BillsException('You are not logged in.');
    }

    final headers = _buildAuthHeaders(appState, token);

    setState(() {
      _isLoadingAccounts = true;
      _isLoadingAccountNames = false;
      _isLoadingPayments = true;
      _accountsError = null;
      _paymentsError = null;
      _accountNamesById = {};
      _paymentsLoaded = false;
      _payments = const [];
    });

    try {
      final bill = await _billsService.getBill(
        id: widget.bill.id,
        headers: headers,
      );

      if (!mounted) {
        return bill;
      }

      await Future.wait([
        _loadAccounts(headers),
        _loadAccountNames(bill, headers),
        _loadPayments(bill.id, headers),
      ]);

      if (notifyParent && widget.onBillUpdated != null) {
        widget.onBillUpdated!(bill);
      }

      return bill;
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoadingAccounts = false;
          _isLoadingAccountNames = false;
          _isLoadingPayments = false;
        });
      }
      rethrow;
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

  final _pendingPayments = <BillPayment>[];
  bool _paymentsLoaded = false;

  List<BillPayment> _buildPaymentEntries(Bill bill) {
    final entries = <BillPayment>[];

    if (_paymentsLoaded) {
      entries.addAll(_payments);
    } else if (_payments.isNotEmpty) {
      entries.addAll(_payments);
    } else if (bill.payments.isNotEmpty) {
      entries.addAll(bill.payments);
    } else if (bill.attachments.isNotEmpty) {
      entries.addAll(
        bill.attachments.map(
          (attachment) => BillPayment(
            id: attachment.paymentId ?? attachment.id ?? attachment.fileName,
            date: attachment.paymentDate ?? attachment.uploadedAt,
            paymentAccount: attachment.description,
            amount: attachment.amount,
            attachment: attachment,
          ),
        ),
      );
    }

    entries.addAll(_pendingPayments);
    return entries;
  }

  List<BillAttachment> _collectAttachments(
    Bill bill,
    List<BillPayment> payments,
  ) {
    final seen = <String>{};
    final attachments = <BillAttachment>[];

    void addAttachment(BillAttachment attachment) {
      final key =
          attachment.id ?? attachment.downloadUrl ?? attachment.fileName;
      if (seen.add(key)) {
        attachments.add(attachment);
      }
    }

    for (final payment in payments) {
      final attachment = payment.attachment;
      if (attachment != null) {
        addAttachment(attachment);
      }
    }

    for (final attachment in bill.attachments) {
      addAttachment(attachment);
    }

    return attachments;
  }

  Future<void> _loadAccounts(Map<String, String> headers) async {
    try {
      final accounts = await _accountsService.fetchAccounts(
        page: 1,
        perPage: 200,
        headers: headers,
      );

      if (mounted) {
        setState(() {
          _accounts = accounts.accounts;
          _accountNamesById = {..._accountNamesById, ...accounts.namesById};
          _isLoadingAccounts = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _accountsError = error.toString();
          _isLoadingAccounts = false;
        });
      }
    }
  }

  Future<void> _loadPayments(String billId, Map<String, String> headers) async {
    try {
      final payments = await _billsService.fetchBillPayments(
        billId: billId,
        headers: headers,
      );

      await _populatePaymentAccountNames(payments, headers);

      if (mounted) {
        setState(() {
          _payments = payments;
          _isLoadingPayments = false;
          _paymentsLoaded = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _paymentsError = error.toString();
          _isLoadingPayments = false;
        });
      }
    }
  }

  Future<void> _populatePaymentAccountNames(
    List<BillPayment> payments,
    Map<String, String> headers,
  ) async {
    final creditIds = payments
        .map((payment) => payment.paymentAccountId?.trim())
        .where((id) => id != null && id!.isNotEmpty)
        .where((id) => !_accountNamesById.containsKey(id))
        .toSet();

    if (creditIds.isEmpty) {
      return;
    }

    try {
      final results = await Future.wait(
        creditIds.map((id) async {
          final account = await _accountsService.fetchAccountById(
            id: id!,
            headers: headers,
          );
          return MapEntry(id, account.name);
        }),
      );

      if (mounted) {
        setState(() {
          for (final entry in results) {
            _accountNamesById[entry.key] = entry.value;
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _paymentsError ??=
              'Unable to resolve payment accounts: ${error.toString()}';
        });
      }
    }
  }

  Future<void> _loadAccountNames(Bill bill, Map<String, String> headers) async {
    final creditId = bill.creditAccountId;
    final debitId = bill.debitAccountId;

    if ((creditId == null || creditId.trim().isEmpty) &&
        (debitId == null || debitId.trim().isEmpty)) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingAccountNames = true;
        _accountsError = null;
      });
    }

    String? errorMessage;

    Future<void> fetchName(String? id) async {
      final trimmedId = id?.trim();
      if (trimmedId == null || trimmedId.isEmpty) {
        return;
      }

      try {
        final account = await _accountsService.fetchAccountById(
          id: trimmedId,
          headers: headers,
        );

        if (mounted) {
          setState(() {
            _accountNamesById[trimmedId] = account.name;
          });
        }
      } catch (error) {
        errorMessage ??= error.toString();
      }
    }

    await Future.wait([fetchName(creditId), fetchName(debitId)]);

    if (mounted) {
      setState(() {
        _isLoadingAccountNames = false;
        if (errorMessage != null) {
          _accountsError = errorMessage;
        }
      });
    }
  }

  Future<void> _openAddPaymentDialog(Bill bill) async {
    final result = await showDialog<BillPayment>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddPaymentDialog(
        currencySymbol: bill.currencySymbol,
        billId: bill.id,
        vendor: bill.vendorId,
        debitAccounts: bill.debitAccounts,
      ),
    );

    if (result != null) {
      setState(() {
        _payments = List.of(_payments)..add(result);

        final accountId = result.paymentAccountId?.trim();
        if (accountId != null && accountId.isNotEmpty) {
          final accountName = result.paymentAccount?.trim();
          if (accountName != null && accountName.isNotEmpty) {
            _accountNamesById[accountId] = accountName;
          }
        }
      });

      _refreshBillDetails();
    }
  }

  Future<void> _openEditPaymentDialog(BillPayment payment, Bill bill) async {
    final result = await showDialog<BillPayment>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditPaymentDialog(
        payment: payment,
        currencySymbol: bill.currencySymbol,
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      var replaced = false;
      for (var i = 0; i < _payments.length; i++) {
        if (_payments[i].id == result.id) {
          _payments[i] = result;
          replaced = true;
        }
      }

      if (!replaced) {
        for (var i = 0; i < _pendingPayments.length; i++) {
          if (_pendingPayments[i].id == result.id) {
            _pendingPayments[i] = result;
            replaced = true;
          }
        }
      }

      if (!replaced) {
        _pendingPayments.add(result);
      }

      final accountId = result.paymentAccountId?.trim();
      if (accountId != null && accountId.isNotEmpty) {
        final accountName = result.paymentAccount?.trim();
        if (accountName != null && accountName.isNotEmpty) {
          _accountNamesById[accountId] = accountName;
        }
      }
    });
  }

  Future<void> _confirmAndDeletePayment(BillPayment payment, Bill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete payment?'),
        content: const Text(
          'Are you sure you want to delete this payment? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You are not logged in.')));
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    setState(() {
      _isLoadingPayments = true;
      _paymentsError = null;
    });

    try {
      await _billsService.deleteBillPayment(
        billId: bill.id,
        paymentId: payment.id,
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _payments = _payments.where((entry) => entry.id != payment.id).toList();
        _pendingPayments.removeWhere((entry) => entry.id == payment.id);
        _isLoadingPayments = false;
      });

      _refreshBillDetails();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment deleted.')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingPayments = false;
        _paymentsError = error.toString();
      });

      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete payment: $error'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  void _refreshBillDetails() {
    setState(() {
      _future = _loadDetails(notifyParent: true);
    });
  }

  Future<void> _openAddAttachmentDialog(Bill bill) async {
    final uploaded = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddAttachmentDialog(billId: bill.id),
    );

    if (uploaded == true) {
      setState(() {
        _future = _loadDetails();
      });
    }
  }

  Future<void> _handlePreviewAttachment(
    BillAttachment attachment, {
    String? previewUrlOverride,
    Map<String, String>? headersOverride,
  }) async {
    final normalizedDownloadUrl = _normalizeAttachmentDownloadUrl(
      previewUrlOverride ?? _buildBillAttachmentPreviewUrl(widget.bill.id),
    );
    final previewType = _resolvePreviewType(
      attachment.fileName,
      normalizedDownloadUrl,
    );

    if (previewType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No preview available for this attachment.'),
        ),
      );
      return;
    }

    Map<String, String>? headers = headersOverride;

    if (headers == null) {
      final appState = AppStateScope.of(context);
      final token = await appState.getValidAuthToken();

      if (!mounted) {
        return;
      }

      if (token != null && token.isNotEmpty) {
        headers = _buildAuthHeaders(appState, token);
      }
    }

    _showAttachmentPreview(
      context: context,
      fileName: attachment.fileName,
      downloadUrl: normalizedDownloadUrl,
      previewType: previewType,
      apiHeaders: headers,
    );
  }

  Future<void> _handlePreviewPaymentAttachment(BillPayment payment) async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You are not logged in.')));
      return;
    }

    final attachmentName =
        payment.attachment?.fileName ?? payment.attachmentFileName;
    if (attachmentName == null || attachmentName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment is missing an attachment name.')),
      );
      return;
    }

    final payBillItemPaidId = payment.payBillItemPaidId?.trim();
    final payBillId = payBillItemPaidId?.isNotEmpty == true
        ? payBillItemPaidId!
        : payment.payBillId?.trim();
    final resolvedBillId = payBillId?.isNotEmpty == true
        ? payBillId!
        : payment.id.trim();

    if (resolvedBillId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment is missing an attachment id.')),
      );
      return;
    }

    final headers = _buildAuthHeaders(appState, token);
    final previewUrl = _buildPaymentAttachmentPreviewUrl(
      payBillItemPaidId: resolvedBillId,
      attachmentName: attachmentName.trim(),
    );

    final attachment =
        payment.attachment ??
        BillAttachment(
          fileName: attachmentName.trim(),
          paymentId: resolvedBillId,
        );

    try {
      await _handlePreviewAttachment(
        attachment,
        previewUrlOverride: previewUrl,
        headersOverride: headers,
      );
    } catch (error) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load attachment: $error'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  String _resolveAccountName({String? accountId, String? fallbackLabel}) {
    final trimmedId = accountId?.trim();
    final trimmedFallback = fallbackLabel?.trim();

    if ((trimmedId == null || trimmedId.isEmpty) &&
        (trimmedFallback == null || trimmedFallback.isEmpty)) {
      return '—';
    }

    if (trimmedId != null && trimmedId.isNotEmpty) {
      final mappedName = _accountNamesById[trimmedId];
      if (mappedName != null && mappedName.isNotEmpty) {
        return mappedName;
      }
    }

    if (_isLoadingAccounts || _isLoadingAccountNames) {
      return 'Loading accounts...';
    }

    if (trimmedId != null && trimmedId.isNotEmpty) {
      for (final account in _accounts) {
        if (account.id == trimmedId) {
          return account.name.isNotEmpty ? account.name : trimmedId;
        }
      }
    }

    if (trimmedFallback != null &&
        trimmedFallback.isNotEmpty &&
        trimmedFallback.toLowerCase() != 'account') {
      return trimmedFallback;
    }

    return trimmedId ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final maxDialogHeight = MediaQuery.sizeOf(context).height - 48;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: maxDialogHeight),
        child: DefaultTabController(
          length: 2,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FutureBuilder<Bill>(
              future: _future,
              initialData: widget.bill,
              builder: (context, snapshot) {
                final bill = snapshot.data ?? widget.bill;
                final payments = _buildPaymentEntries(bill);
                final attachments = _collectAttachments(bill, payments);
                final isLoading =
                    snapshot.connectionState == ConnectionState.waiting;
                final hasError = snapshot.hasError;
                double? totalPaidOverride;
                double? totalDueOverride;

                if (bill.datePaid != null) {
                  totalPaidOverride = payments.fold<double>(
                    0,
                    (total, payment) => total + (payment.amount ?? 0),
                  );

                  final amount = bill.totalAmount;
                  if (amount != null) {
                    totalDueOverride = amount - totalPaidOverride;
                  }
                }

                final totalAmountLabel = bill.totalLabel;
                final totalPaidLabel = bill.formatCurrency(
                  totalPaidOverride ?? bill.resolvedTotalPaid,
                );
                final totalDueLabel = bill.formatCurrency(
                  totalDueOverride ?? bill.resolvedTotalDue,
                );

                return Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DialogHeader(onClose: () => Navigator.of(context).pop()),
                    const SizedBox(height: 12),
                    TabBar(
                      labelColor: Theme.of(context).colorScheme.primary,
                      tabs: const [
                        Tab(text: 'Details'),
                        Tab(text: 'Payments'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Failed to load details: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (isLoading && snapshot.data == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!isLoading || snapshot.data != null)
                      Expanded(
                        child: Column(
                          children: [
                            if (isLoading)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _DetailsTab(
                                    bill: bill,
                                    vendorName: widget.vendorName,
                                    creditAccountLabel: _resolveAccountName(
                                      accountId: bill.creditAccountId,
                                      fallbackLabel: bill.creditAccount,
                                    ),
                                    debitAccountLabel: _resolveAccountName(
                                      accountId: bill.debitAccountId,
                                      fallbackLabel: bill.debitAccount,
                                    ),
                                    isLoadingAccounts:
                                        _isLoadingAccounts ||
                                        _isLoadingAccountNames,
                                    onAddAttachment: () =>
                                        _openAddAttachmentDialog(bill),
                                    onPreviewAttachment:
                                        _handlePreviewAttachment,
                                    accountsError: _accountsError,
                                    totalAmountLabel: totalAmountLabel,
                                    totalPaidLabel: totalPaidLabel,
                                    totalDueLabel: totalDueLabel,
                                  ),
                                  _PaymentsTab(
                                    bill: bill,
                                    payments: payments,
                                    attachments: attachments,
                                    isLoading: _isLoadingPayments,
                                    error: _paymentsError,
                                    onAddPayment: () =>
                                        _openAddPaymentDialog(bill),
                                    onDeletePayment: (payment) =>
                                        _confirmAndDeletePayment(payment, bill),
                                    onPreviewPaymentAttachment:
                                        _handlePreviewPaymentAttachment,
                                    resolveAccountName: _resolveAccountName,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Bill Details',
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

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.bill,
    required this.vendorName,
    required this.creditAccountLabel,
    required this.debitAccountLabel,
    required this.isLoadingAccounts,
    required this.onAddAttachment,
    required this.onPreviewAttachment,
    required this.totalAmountLabel,
    required this.totalPaidLabel,
    required this.totalDueLabel,
    this.accountsError,
  });

  final Bill bill;
  final String vendorName;
  final String creditAccountLabel;
  final String debitAccountLabel;
  final bool isLoadingAccounts;
  final VoidCallback onAddAttachment;
  final void Function(BillAttachment attachment) onPreviewAttachment;
  final String totalAmountLabel;
  final String totalPaidLabel;
  final String totalDueLabel;
  final String? accountsError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scrollbar(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment Status',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _StatusPill(status: bill.status, theme: theme),
            const SizedBox(height: 16),
            _DetailField(
              label: 'Vendor',
              value: vendorName.isEmpty ? '—' : vendorName,
            ),
            const SizedBox(height: 16),
            _DateRow(bill: bill),
            const SizedBox(height: 16),
            _AttachmentSection(
              bill: bill,
              onAddAttachment: onAddAttachment,
              onPreviewAttachment: onPreviewAttachment,
            ),
            const SizedBox(height: 16),
            _AccountRow(
              creditAccount: creditAccountLabel,
              debitAccount: debitAccountLabel,
              isLoading: isLoadingAccounts,
            ),
            if (accountsError != null) ...[
              const SizedBox(height: 8),
              Text(
                accountsError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            _BillTotalsSection(
              totalAmount: totalAmountLabel,
              totalPaid: totalPaidLabel,
              totalDue: totalDueLabel,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 520;
        final billDateField = _DetailField(
          label: 'Bill date',
          value: bill.formattedDate,
        );
        final dueDateField = _DetailField(
          label: 'Due date',
          value: bill.formattedDueDate,
        );

        if (isWide) {
          return Row(
            children: [
              Expanded(child: billDateField),
              const SizedBox(width: 12),
              Expanded(child: dueDateField),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [billDateField, const SizedBox(height: 12), dueDateField],
        );
      },
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.creditAccount,
    required this.debitAccount,
    this.isLoading = false,
  });

  final String creditAccount;
  final String debitAccount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildCell(String text, {TextStyle? style}) {
      final resolvedText = text.trim().isEmpty ? '—' : text.trim();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Text(resolvedText, style: style ?? theme.textTheme.bodyMedium),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
          border: TableBorder.all(
            color: theme.dividerColor,
            width: 1,
            borderRadius: BorderRadius.circular(8),
          ),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              children: [
                buildCell(
                  'Type',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                buildCell(
                  'Account',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            TableRow(
              children: [buildCell('Debit Account'), buildCell(debitAccount)],
            ),
            TableRow(
              children: [buildCell('Credit Account'), buildCell(creditAccount)],
            ),
          ],
        ),
        if (isLoading) ...[
          const SizedBox(height: 8),
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      ],
    );
  }
}

class _BillTotalsSection extends StatelessWidget {
  const _BillTotalsSection({
    required this.totalAmount,
    required this.totalPaid,
    required this.totalDue,
    required this.theme,
  });

  final String totalAmount;
  final String totalPaid;
  final String totalDue;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _BillTotalRow(
            label: 'Total Amount',
            value: totalAmount,
            theme: theme,
            emphasize: true,
          ),
          const SizedBox(height: 8),
          _BillTotalRow(label: 'Total Paid', value: totalPaid, theme: theme),
          const SizedBox(height: 8),
          _BillTotalRow(
            label: 'Total Due',
            value: totalDue,
            theme: theme,
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

class _BillTotalRow extends StatelessWidget {
  const _BillTotalRow({
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.theme});

  final BillStatus status;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    Color background;
    Color foreground;
    switch (status.code) {
      case 2:
        background = Colors.green.shade100;
        foreground = Colors.green.shade800;
        break;
      case 1:
        background = Colors.yellow.shade100;
        foreground = Colors.yellow.shade900;
        break;
      default:
        background = Colors.red.shade100;
        foreground = Colors.red.shade800;
        break;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          status.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedValue = value.trim().isEmpty ? '—' : value.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(resolvedValue, style: valueStyle ?? theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({
    required this.bill,
    required this.payments,
    required this.attachments,
    required this.isLoading,
    this.error,
    required this.onAddPayment,
    required this.onDeletePayment,
    required this.onPreviewPaymentAttachment,
    required this.resolveAccountName,
  });

  final Bill bill;
  final List<BillPayment> payments;
  final List<BillAttachment> attachments;
  final bool isLoading;
  final String? error;
  final VoidCallback onAddPayment;
  final void Function(BillPayment payment) onDeletePayment;
  final void Function(BillPayment payment) onPreviewPaymentAttachment;
  final String Function({String? accountId, String? fallbackLabel})
  resolveAccountName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (payments.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.payments_outlined, size: 40),
                  const SizedBox(height: 12),
                  if (error != null)
                    Text(
                      'Failed to load payments: $error',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    )
                  else
                    Text(
                      isLoading
                          ? 'Loading payments...'
                          : 'No payments recorded yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: onAddPayment,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Payment'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Failed to load payments: $error',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                  _PaymentsTable(
                    bill: bill,
                    payments: payments,
                    attachments: attachments,
                    resolveAccountName: resolveAccountName,
                    onDeletePayment: onDeletePayment,
                    onPreviewPaymentAttachment: onPreviewPaymentAttachment,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: onAddPayment,
            icon: const Icon(Icons.add),
            label: const Text('Add Payment'),
          ),
        ),
      ],
    );
  }
}

class _PaymentsTable extends StatelessWidget {
  const _PaymentsTable({
    required this.bill,
    required this.payments,
    required this.attachments,
    required this.resolveAccountName,
    required this.onDeletePayment,
    required this.onPreviewPaymentAttachment,
  });

  final Bill bill;
  final List<BillPayment> payments;
  final List<BillAttachment> attachments;
  final String Function({String? accountId, String? fallbackLabel})
  resolveAccountName;
  final void Function(BillPayment payment) onDeletePayment;
  final void Function(BillPayment payment) onPreviewPaymentAttachment;

  BillAttachment? _findAttachment(BillPayment payment) {
    if (payment.attachment != null) {
      return payment.attachment;
    }
    for (final attachment in attachments) {
      final payBillId = payment.payBillId?.trim();
      final payBillItemPaidId = payment.payBillItemPaidId?.trim();
      if (attachment.paymentId == payment.id || attachment.id == payment.id) {
        return attachment;
      }
      if (payBillId != null &&
          payBillId.isNotEmpty &&
          (attachment.paymentId == payBillId || attachment.id == payBillId)) {
        return attachment;
      }
      if (payBillItemPaidId != null &&
          payBillItemPaidId.isNotEmpty &&
          (attachment.paymentId == payBillItemPaidId ||
              attachment.id == payBillItemPaidId)) {
        return attachment;
      }
    }
    return null;
  }

  String _formatAmount(double? amount) {
    if (amount == null) {
      return '-';
    }
    final symbol = bill.currencySymbol;
    final formatted = amount.toStringAsFixed(2);
    if (symbol.isNotEmpty && symbol.toLowerCase() != '0') {
      return '$symbol $formatted';
    }
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 720),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(3),
              2: FlexColumnWidth(2),
              3: IntrinsicColumnWidth(),
            },
            border: TableBorder.all(
              color: theme.dividerColor,
              width: 1,
              borderRadius: BorderRadius.circular(8),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    child: Text('Date', style: headerStyle),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    child: Text('Payment Account', style: headerStyle),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    child: Text('Amount', style: headerStyle),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    child: Text(
                      'Options',
                      style: headerStyle,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              ...payments.map((payment) {
                final attachment = _findAttachment(payment);
                final dateLabel = payment.date != null
                    ? DateFormat.yMMMd().format(payment.date!)
                    : '—';
                final paymentAccountLabel = resolveAccountName(
                  accountId: payment.paymentAccountId,
                  fallbackLabel: payment.paymentAccount,
                );
                final canPreviewAttachment = payment.hasEmptyAttachment
                    ? false
                    : payment.hasAttachmentString || attachment != null;
                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      child: Text(dateLabel),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      child: Text(
                        paymentAccountLabel.trim().isNotEmpty
                            ? paymentAccountLabel
                            : '—',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      child: Text(
                        _formatAmount(payment.amount),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View attachment',
                              icon: const Icon(Icons.visibility_outlined),
                              onPressed: canPreviewAttachment
                                  ? () => onPreviewPaymentAttachment(payment)
                                  : null,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Delete payment',
                              icon: const Icon(Icons.delete_outline),
                              color: theme.colorScheme.error,
                              onPressed: () => onDeletePayment(payment),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.bill,
    required this.onAddAttachment,
    required this.onPreviewAttachment,
  });

  final Bill bill;
  final VoidCallback onAddAttachment;
  final void Function(BillAttachment attachment) onPreviewAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (bill.attachments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachment',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onAddAttachment,
            icon: const Icon(Icons.attach_file),
            label: const Text('Add Attachment'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Attachment',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: bill.attachments
              .map(
                (attachment) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _BillAttachmentCard(
                    attachment: attachment,
                    billId: bill.id,
                    onPreviewAttachment: onPreviewAttachment,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _BillAttachmentCard extends StatelessWidget {
  const _BillAttachmentCard({
    required this.attachment,
    required this.billId,
    required this.onPreviewAttachment,
  });

  final BillAttachment attachment;
  final String billId;
  final void Function(BillAttachment attachment) onPreviewAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;

    final normalizedDownloadUrl = _normalizeAttachmentDownloadUrl(
      _buildBillAttachmentPreviewUrl(billId),
    );

    final previewType = _resolvePreviewType(
      attachment.fileName,
      normalizedDownloadUrl,
    );

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
    ];

    if (attachment.uploadedAt != null) {
      children.add(
        _LabelValueRow(
          label: 'Uploaded on',
          value: DateFormat.yMMMd().format(attachment.uploadedAt!),
        ),
      );
    }

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

    if (attachment.description != null &&
        attachment.description!.trim().isNotEmpty) {
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

    if (normalizedDownloadUrl != null) {
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

    if (previewType != null) {
      children.addAll([
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            icon: const Icon(Icons.visibility),
            label: const Text('Preview'),
            onPressed: () => onPreviewAttachment(attachment),
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

String _buildBillAttachmentPreviewUrl(String billId) {
  // Align preview URL with bill attachment preview structure
  // Example: https://crm.kokonuts.my/accounting/api/v1/bill/{billId}/attachment
  const baseUrl = 'https://crm.kokonuts.my/accounting/api/v1/bill';
  return '$baseUrl/$billId/attachment';
}

String _buildPaymentAttachmentPreviewUrl({
  required String payBillItemPaidId,
  required String attachmentName,
}) {
  final trimmedBillId = payBillItemPaidId.trim();
  final trimmedAttachment = attachmentName.trim();

  return 'https://crm.kokonuts.my/modules/accounting/uploads/pay_bills/$trimmedBillId/$trimmedAttachment';
}

class _AddAttachmentDialog extends StatefulWidget {
  const _AddAttachmentDialog({required this.billId});

  final String billId;

  @override
  State<_AddAttachmentDialog> createState() => _AddAttachmentDialogState();
}

class _AddAttachmentDialogState extends State<_AddAttachmentDialog> {
  final _billsService = BillsService();
  PlatformFile? _selectedFile;
  bool _isSubmitting = false;
  String? _submitError;

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      withReadStream: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(),
    );

    if (result != null && result.files.isNotEmpty) {
      _handleFilesSelected(result.files);
    }
  }

  void _handleFilesSelected(List<PlatformFile> files) {
    if (files.isEmpty) {
      setState(() {
        _selectedFile = null;
      });
      return;
    }

    final latest = files.last;
    if (!isAllowedAttachmentExtension(attachmentExtension(latest.name))) {
      setState(() {
        _submitError = 'Unsupported file type. Please select a PDF or image.';
        _selectedFile = null;
      });
      return;
    }

    setState(() {
      _submitError = null;
      _selectedFile = latest;
    });
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

  Future<void> _handleSubmit() async {
    if (_selectedFile == null) {
      setState(() {
        _submitError = 'Please select a file to upload.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.isEmpty) {
      setState(() {
        _submitError = 'You are not logged in.';
        _isSubmitting = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      await _billsService.uploadAttachments(
        id: widget.billId,
        headers: headers,
        attachments: [_selectedFile!],
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
        _submitError = error.toString();
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
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add Attachment',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_submitError != null) ...[
                Text(_submitError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              AttachmentPicker(
                label: 'Attachment',
                description: 'Choose a file to attach to this bill.',
                files: _selectedFile == null
                    ? const []
                    : <PlatformFile>[_selectedFile!],
                onPick: _isSubmitting ? () {} : _pickAttachment,
                onFilesSelected: _isSubmitting
                    ? (_) {}
                    : (files) => _handleFilesSelected(files),
                onFileRemoved: _isSubmitting
                    ? (_) {}
                    : (_) => _handleFilesSelected(const <PlatformFile>[]),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Upload'),
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

class _EditPaymentDialog extends StatefulWidget {
  const _EditPaymentDialog({
    required this.payment,
    required this.currencySymbol,
  });

  final BillPayment payment;
  final String currencySymbol;

  @override
  State<_EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends State<_EditPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _accountsService = AccountsService();

  DateTime _selectedDate = DateTime.now();
  PlatformFile? _selectedFile;
  bool _removeExistingAttachment = false;
  bool _isLoadingAccounts = false;
  String? _loadError;
  List<Account> _accounts = const [];
  Account? _selectedPaymentAccount;
  Account? _selectedDepositAccount;

  String _accountLabel(String id) {
    return _accounts
        .firstWhere(
          (account) => account.id == id,
          orElse: () => Account(
            id: id,
            name: 'Unknown account',
            parentAccountId: '',
            typeName: '',
            detailTypeName: '',
            balance: '',
            primaryBalance: '',
            isActive: false,
          ),
        )
        .name;
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.payment.date ?? DateTime.now();
    _amountController.text = widget.payment.amount != null
        ? widget.payment.amount!.toStringAsFixed(2)
        : '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccounts());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _isLoadingAccounts = true;
      _loadError = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }

    if (token == null || token.isEmpty) {
      setState(() {
        _isLoadingAccounts = false;
        _loadError = 'You are not logged in.';
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final accounts = await _accountsService.fetchAccounts(
        page: 1,
        perPage: 200,
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _accounts = accounts.accounts;
        _loadError = null;
      });

      _syncSelectedAccounts(accounts.accounts);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingAccounts = false);
      }
    }
  }

  void _syncSelectedAccounts(List<Account> accounts) {
    Account? match(String? idOrName) {
      if (idOrName == null || idOrName.trim().isEmpty) {
        return null;
      }
      final trimmed = idOrName.trim();
      try {
        return accounts.firstWhere(
          (account) =>
              account.id == trimmed ||
              account.name.toLowerCase() == trimmed.toLowerCase(),
        );
      } catch (_) {
        return null;
      }
    }

    final paymentAccount = match(
      widget.payment.paymentAccountId ?? widget.payment.paymentAccount,
    );
    final depositAccount = match(widget.payment.depositAccountId);

    setState(() {
      _selectedPaymentAccount =
          paymentAccount != null && paymentAccount.id.isNotEmpty
          ? paymentAccount
          : null;
      _selectedDepositAccount =
          depositAccount != null && depositAccount.id.isNotEmpty
          ? depositAccount
          : null;
    });
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

  void _setSelectedFile(PlatformFile? file) {
    setState(() {
      _selectedFile = file;
      _removeExistingAttachment = false;
    });
  }

  void _onFilesSelected(List<PlatformFile> files) {
    if (files.isEmpty) {
      return;
    }

    final validFile = files.lastWhere(
      (file) => isAllowedAttachmentExtension(attachmentExtension(file.name)),
      orElse: () => files.last,
    );

    _setSelectedFile(validFile);
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      withReadStream: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(),
    );

    if (result != null && result.files.isNotEmpty) {
      _onFilesSelected(result.files);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (selected != null) {
      setState(() => _selectedDate = selected);
    }
  }

  void _clearSelectedFile() {
    setState(() {
      _selectedFile = null;
      _removeExistingAttachment = false;
    });
  }

  void _handleRemoveAttachment() {
    setState(() {
      _selectedFile = null;
      _removeExistingAttachment = true;
    });
  }

  String _formatFileSize(int sizeInBytes) {
    const kilo = 1024;
    const mega = kilo * 1024;
    if (sizeInBytes >= mega) {
      return '${(sizeInBytes / mega).toStringAsFixed(2)} MB';
    }
    if (sizeInBytes >= kilo) {
      return '${(sizeInBytes / kilo).toStringAsFixed(2)} KB';
    }
    return '$sizeInBytes B';
  }

  BillAttachment? _buildAttachment() {
    if (_selectedFile != null) {
      return BillAttachment(
        fileName: _selectedFile!.name,
        description: _selectedFile!.name,
        downloadUrl: _selectedFile!.path,
        uploadedAt: _selectedDate,
        sizeLabel: _formatFileSize(_selectedFile!.size),
        id: null,
        paymentId: widget.payment.id,
        paymentDate: _selectedDate,
        amount:
            double.tryParse(_amountController.text.trim()) ??
            widget.payment.amount,
      );
    }

    if (_removeExistingAttachment) {
      return null;
    }

    return widget.payment.attachment;
  }

  void _handleSubmit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final amountText = _amountController.text.trim();
    final parsedAmount = amountText.isEmpty
        ? widget.payment.amount
        : double.tryParse(amountText);

    final updatedPayment = widget.payment.copyWith(
      date: _selectedDate,
      amount: parsedAmount,
      paymentAccount:
          _selectedPaymentAccount?.name ?? widget.payment.paymentAccount,
      paymentAccountId:
          _selectedPaymentAccount?.id ?? widget.payment.paymentAccountId,
      depositAccountId:
          _selectedDepositAccount?.id ?? widget.payment.depositAccountId,
      attachment: _buildAttachment(),
    );

    Navigator.of(context).pop(updatedPayment);
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit Payment',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_isLoadingAccounts)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              else
                const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AttachmentPicker(
                      label: 'Attachment',
                      description:
                          'Drag and drop files or tap to browse for payment attachments.',
                      files: _selectedFile != null
                          ? [_selectedFile!]
                          : const [],
                      onPick: _pickAttachment,
                      onFilesSelected: _onFilesSelected,
                      onFileRemoved: (_) => _clearSelectedFile(),
                    ),
                    if (_selectedFile == null &&
                        !_removeExistingAttachment &&
                        widget.payment.attachment != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Current: ${widget.payment.attachment!.fileName}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: _handleRemoveAttachment,
                              child: const Text('Remove current attachment'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date Paid',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat.yMMMd().format(_selectedDate),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: _pickDate,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SearchableDropdownFormField<String>(
                            initialValue: _selectedPaymentAccount?.id,
                            items: _accounts
                                .map((account) => account.id)
                                .toList(),
                            itemToString: _accountLabel,
                            decoration: const InputDecoration(
                              labelText: 'Payment Account',
                              border: OutlineInputBorder(),
                            ),
                            hintText: _accounts.isEmpty
                                ? 'No accounts available'
                                : 'Select payment account',
                            dialogTitle: 'Select payment account',
                            onChanged: (value) {
                              setState(() {
                                _selectedPaymentAccount = value == null
                                    ? null
                                    : _accounts.firstWhere(
                                        (account) => account.id == value,
                                        orElse: () => Account(
                                          id: value,
                                          name: _accountLabel(value),
                                          parentAccountId: '',
                                          typeName: '',
                                          detailTypeName: '',
                                          balance: '',
                                          primaryBalance: '',
                                          isActive: false,
                                        ),
                                      );
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SearchableDropdownFormField<String>(
                            initialValue: _selectedDepositAccount?.id,
                            items: _accounts
                                .map((account) => account.id)
                                .toList(),
                            itemToString: _accountLabel,
                            decoration: const InputDecoration(
                              labelText: 'Deposit Account',
                              border: OutlineInputBorder(),
                            ),
                            hintText: _accounts.isEmpty
                                ? 'No accounts available'
                                : 'Select deposit account',
                            dialogTitle: 'Select deposit account',
                            onChanged: (value) {
                              setState(() {
                                _selectedDepositAccount = value == null
                                    ? null
                                    : _accounts.firstWhere(
                                        (account) => account.id == value,
                                        orElse: () => Account(
                                          id: value,
                                          name: _accountLabel(value),
                                          parentAccountId: '',
                                          typeName: '',
                                          detailTypeName: '',
                                          balance: '',
                                          primaryBalance: '',
                                          isActive: false,
                                        ),
                                      );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            'Amount (${widget.currencySymbol.isEmpty ? 'value' : widget.currencySymbol})',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return null;
                        }
                        if (double.tryParse(value.trim()) == null) {
                          return 'Enter a valid number';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _handleSubmit,
                    child: const Text('Save Changes'),
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

class _AddPaymentDialog extends StatefulWidget {
  const _AddPaymentDialog({
    required this.currencySymbol,
    required this.billId,
    required this.vendor,
    required this.debitAccounts,
  });

  final String currencySymbol;
  final String billId;
  final String vendor;
  final List<BillAccountLine> debitAccounts;

  @override
  State<_AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends State<_AddPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(
    text: CurrencyInputFormatter.normalizeExistingValue(null),
  );
  final _accountsService = AccountsService();
  final _billsService = BillsService();

  DateTime _selectedDate = DateTime.now();
  Account? _selectedPaymentAccount;
  Account? _selectedDepositAccount;
  PlatformFile? _selectedFile;
  bool _isSubmitting = false;
  bool _isLoadingOptions = false;
  String? _loadError;
  List<Account> _accounts = const [];

  String _accountLabel(String id) {
    return _accounts
        .firstWhere(
          (account) => account.id == id,
          orElse: () => Account(
            id: id,
            name: 'Unknown account',
            parentAccountId: '',
            typeName: '',
            detailTypeName: '',
            balance: '',
            primaryBalance: '',
            isActive: false,
          ),
        )
        .name;
  }

  String? _submitError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOptions());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _isLoadingOptions = true;
      _loadError = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }

    if (token == null || token.isEmpty) {
      setState(() {
        _isLoadingOptions = false;
        _loadError = 'You are not logged in.';
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final accounts = await _accountsService.fetchAccounts(
        page: 1,
        perPage: 200,
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _accounts = accounts.accounts;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingOptions = false);
      }
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
    return {
      'Accept': 'application/json',
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      withReadStream: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(),
    );
    if (result != null && result.files.isNotEmpty) {
      _handleFilesSelected(result.files);
    }
  }

  void _handleFilesSelected(List<PlatformFile> files) {
    if (files.isEmpty) {
      setState(() => _selectedFile = null);
      return;
    }

    final validFile = files.lastWhere(
      (file) => isAllowedAttachmentExtension(attachmentExtension(file.name)),
      orElse: () => files.last,
    );

    setState(() => _selectedFile = validFile);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (selected != null) {
      setState(() => _selectedDate = selected);
    }
  }

  String _attachmentDescription() {
    final paymentAccount = _selectedPaymentAccount?.name ?? '-';
    final depositTo = _selectedDepositAccount?.name ?? '-';
    return 'Payment account: $paymentAccount\nDeposit to: $depositTo';
  }

  double? _parseAmountInput() {
    final sanitized = _amountController.text
        .replaceAll(RegExp(r'[^0-9.,-]'), '')
        .replaceAll(',', '')
        .trim();

    return double.tryParse(sanitized);
  }

  Future<void> _handleSubmit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final parsedAmount = _parseAmountInput();
    if (parsedAmount == null || parsedAmount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }

    if (token == null || token.isEmpty) {
      setState(() {
        _submitError = 'You are not logged in.';
        _isSubmitting = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    final paymentLines = <Map<String, dynamic>>[];

    for (final debitAccount in widget.debitAccounts) {
      final accountId = debitAccount.account?.trim();

      String? accountName;

      if (accountId != null && accountId.isNotEmpty) {
        try {
          final account = await _accountsService.fetchAccountById(
            id: accountId,
            headers: headers,
          );
          accountName = account.name;
        } catch (error) {
          if (!mounted) {
            return;
          }

          setState(() {
            _submitError = 'Unable to load debit account name: $error';
            _isSubmitting = false;
          });
          return;
        }
      }

      paymentLines.add({
        'item_id': debitAccount.id,
        'item_name': accountName ?? '',
        'item_amount': debitAccount.amount ?? parsedAmount,
        'amount_paid': parsedAmount,
      });
    }

    try {
      final payment = await _billsService.createBillPayment(
        billId: widget.billId,
        headers: headers,
        vendor: widget.vendor,
        paymentDate: _selectedDate,
        paymentLines: paymentLines,
        paymentAccountId: _selectedPaymentAccount?.id,
        depositAccountId: _selectedDepositAccount?.id,
        attachment: _selectedFile,
        attachmentDescription: _attachmentDescription(),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(payment);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitError = error.toString();
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save payment: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add Payment',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_isLoadingOptions)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              else
                const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_submitError != null) ...[
                      Text(
                        _submitError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 12),
                    ],
                    AttachmentPicker(
                      label: 'Attachment',
                      description:
                          'Drag and drop payment receipts or tap to browse.',
                      files: _selectedFile == null
                          ? const []
                          : [_selectedFile!],
                      onPick: _pickAttachment,
                      onFilesSelected: _handleFilesSelected,
                      onFileRemoved: (_) =>
                          _handleFilesSelected(<PlatformFile>[]),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 520;

                        final amountField = Expanded(
                          child: TextFormField(
                            controller: _amountController,
                            enabled: !_isSubmitting,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              hintText: '0.00',
                              border: OutlineInputBorder(),
                            ),
                            inputFormatters: const [CurrencyInputFormatter()],
                            validator: (value) {
                              final sanitized = value
                                  ?.replaceAll(RegExp(r'[^0-9.,-]'), '')
                                  .replaceAll(',', '')
                                  .trim();
                              final parsed = double.tryParse(sanitized ?? '');
                              if (parsed == null || parsed <= 0) {
                                return 'Enter a valid amount';
                              }
                              return null;
                            },
                          ),
                        );

                        final dateField = Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Payment Date',
                              border: OutlineInputBorder(),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    DateFormat.yMMMd().format(_selectedDate),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                  ),
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => _pickDate(),
                                ),
                              ],
                            ),
                          ),
                        );

                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              amountField,
                              const SizedBox(width: 12),
                              dateField,
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            amountField,
                            const SizedBox(height: 12),
                            dateField,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SearchableDropdownFormField<String>(
                            initialValue: _selectedPaymentAccount?.id,
                            items: _accounts
                                .map((account) => account.id)
                                .toList(),
                            itemToString: _accountLabel,
                            decoration: const InputDecoration(
                              labelText: 'Payment Account',
                              border: OutlineInputBorder(),
                            ),
                            hintText: _accounts.isEmpty
                                ? 'No accounts available'
                                : 'Select payment account',
                            dialogTitle: 'Select payment account',
                            enabled: !_isSubmitting,
                            onChanged: _isSubmitting
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedPaymentAccount = value == null
                                          ? null
                                          : _accounts.firstWhere(
                                              (account) => account.id == value,
                                              orElse: () => Account(
                                                id: value,
                                                name: _accountLabel(value),
                                                parentAccountId: '',
                                                typeName: '',
                                                detailTypeName: '',
                                                balance: '',
                                                primaryBalance: '',
                                                isActive: false,
                                              ),
                                            );
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SearchableDropdownFormField<String>(
                            initialValue: _selectedDepositAccount?.id,
                            items: _accounts
                                .map((account) => account.id)
                                .toList(),
                            itemToString: _accountLabel,
                            decoration: const InputDecoration(
                              labelText: 'Deposit To',
                              border: OutlineInputBorder(),
                            ),
                            hintText: _accounts.isEmpty
                                ? 'No accounts available'
                                : 'Select deposit account',
                            dialogTitle: 'Select deposit account',
                            enabled: !_isSubmitting,
                            onChanged: _isSubmitting
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedDepositAccount = value == null
                                          ? null
                                          : _accounts.firstWhere(
                                              (account) => account.id == value,
                                              orElse: () => Account(
                                                id: value,
                                                name: _accountLabel(value),
                                                parentAccountId: '',
                                                typeName: '',
                                                detailTypeName: '',
                                                balance: '',
                                                primaryBalance: '',
                                                isActive: false,
                                              ),
                                            );
                                    });
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    child: const Text('Save Payment'),
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

enum _AttachmentPreviewType { image, pdf }

_AttachmentPreviewType? _resolvePreviewType(
  String fileName,
  String? downloadUrl,
) {
  if (_matchesExtension(fileName, _imageExtensions) ||
      _matchesExtension(downloadUrl, _imageExtensions)) {
    return _AttachmentPreviewType.image;
  }

  if (_matchesExtension(fileName, _pdfExtensions) ||
      _matchesExtension(downloadUrl, _pdfExtensions)) {
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
  required String fileName,
  required String downloadUrl,
  required _AttachmentPreviewType previewType,
  Map<String, String>? apiHeaders,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => _AttachmentPreviewDialog(
      fileName: fileName,
      downloadUrl: downloadUrl,
      previewType: previewType,
      apiHeaders: apiHeaders,
    ),
  );
}

class _AttachmentPreviewDialog extends StatelessWidget {
  const _AttachmentPreviewDialog({
    required this.fileName,
    required this.downloadUrl,
    required this.previewType,
    this.apiHeaders,
  });

  final String fileName;
  final String downloadUrl;
  final _AttachmentPreviewType previewType;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    final title = '$fileName preview';
    final theme = Theme.of(context);
    Widget content;

    switch (previewType) {
      case _AttachmentPreviewType.image:
        content = _ImagePreview(
          downloadUrl: downloadUrl,
          apiHeaders: apiHeaders,
        );
        break;
      case _AttachmentPreviewType.pdf:
        content = _PdfPreview(downloadUrl: downloadUrl, apiHeaders: apiHeaders);
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
  const _ImagePreview({required this.downloadUrl, this.apiHeaders});

  final String downloadUrl;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      child: Center(
        child: AuthenticatedImage(
          imageUrl: downloadUrl,
          headers: apiHeaders,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
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
  const _PdfPreview({required this.downloadUrl, this.apiHeaders});

  final String downloadUrl;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    return buildAttachmentPdfPreview(downloadUrl, headers: apiHeaders);
  }
}

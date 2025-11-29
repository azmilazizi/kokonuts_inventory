import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/app/app_state.dart';

import '../app/app_state_scope.dart';
import '../services/accounts_service.dart';
import '../services/bills_service.dart';
import '../services/vendors_service.dart';
import 'attachment_picker.dart';
import 'currency_input_formatter.dart';
import 'searchable_dropdown_form_field.dart';

class CreateBillDialog extends StatefulWidget {
  const CreateBillDialog({super.key});

  @override
  State<CreateBillDialog> createState() => _CreateBillDialogState();
}

class _CreateBillDialogState extends State<CreateBillDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _debitAmountController = TextEditingController();
  final _creditAmountController = TextEditingController();
  final _accountsService = AccountsService();
  final _billsService = BillsService();
  final _vendorsService = VendorsService();

  DateTime _billDate = DateTime.now();
  DateTime _dueDate = DateTime.now();
  String? _selectedVendorId;
  String? _selectedDebitAccount;
  String? _selectedCreditAccount;
  List<PlatformFile> _attachments = [];

  List<Account> _accounts = const <Account>[];
  List<VendorSummary> _vendors = const <VendorSummary>[];
  bool _hasInitializedVendors = false;
  bool _hasInitializedAccounts = false;
  bool _isLoadingVendors = false;
  bool _isLoadingAccounts = false;
  String? _vendorsError;
  String? _accountsError;
  bool _isSubmitting = false;
  String? _submitError;

  String _vendorLabel(String id) {
    return _vendors
        .firstWhere(
          (vendor) => vendor.id == id,
          orElse: () => VendorSummary(id: id, name: 'Unknown vendor'),
        )
        .name;
  }

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

  static const _accountsPerPage = 50;

  @override
  void dispose() {
    _nameController.dispose();
    _debitAmountController.dispose();
    _creditAmountController.dispose();
    super.dispose();
  }

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

  void _showSubmitSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _debitAmountController.text = CurrencyInputFormatter.normalizeExistingValue(
      _debitAmountController.text,
    );
    _creditAmountController.text =
        CurrencyInputFormatter.normalizeExistingValue(
          _creditAmountController.text,
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitializedVendors || !_hasInitializedAccounts) {
      _hasInitializedVendors = true;
      _hasInitializedAccounts = true;
      _loadVendors();
      _loadAccounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth = (MediaQuery.of(context).size.width * 0.95).clamp(
      420.0,
      1040.0,
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Add New Bill',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 12, bottom: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 680;
                    final fieldSpacing = isNarrow ? 12.0 : 16.0;

                    final vendorAndName = isNarrow
                        ? Column(
                            children: [
                              _buildVendorDropdown(theme),
                              SizedBox(height: fieldSpacing),
                              _buildNameField(),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: _buildVendorDropdown(theme)),
                              SizedBox(width: fieldSpacing),
                              Expanded(child: _buildNameField()),
                            ],
                          );

                    final dateFields = isNarrow
                        ? Column(
                            children: [
                              _buildDateField(
                                label: 'Bill date',
                                value: _billDate,
                                onTap: () => _pickDate(isBillDate: true),
                              ),
                              SizedBox(height: fieldSpacing),
                              _buildDateField(
                                label: 'Due date',
                                value: _dueDate,
                                onTap: () => _pickDate(isBillDate: false),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _buildDateField(
                                  label: 'Bill date',
                                  value: _billDate,
                                  onTap: () => _pickDate(isBillDate: true),
                                ),
                              ),
                              SizedBox(width: fieldSpacing),
                              Expanded(
                                child: _buildDateField(
                                  label: 'Due date',
                                  value: _dueDate,
                                  onTap: () => _pickDate(isBillDate: false),
                                ),
                              ),
                            ],
                          );

                    return Column(
                      children: [
                        vendorAndName,
                        SizedBox(height: fieldSpacing),
                        dateFields,
                        if (_vendorsError != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _vendorsError!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text('Attachment', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                AttachmentPicker(
                  description:
                      'Drag and drop supporting files here, or click to browse for uploads.',
                  files: _attachments,
                  onPick: _pickAttachments,
                  onFilesSelected: _onFilesSelected,
                  onFileRemoved: _removeAttachment,
                ),
                const SizedBox(height: 20),
                Text('Expenses', style: theme.textTheme.titleMedium),
                _buildExpensesTab(),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
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
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildVendorDropdown(ThemeData theme) {
    return SearchableDropdownFormField<String>(
      decoration: InputDecoration(
        labelText: 'Vendor',
        suffixIcon: _isLoadingVendors
            ? Padding(
                padding: const EdgeInsets.all(12.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              )
            : null,
      ),
      initialValue: _selectedVendorId,
      items: _vendors.map((vendor) => vendor.id).toList(),
      itemToString: _vendorLabel,
      hintText: _isLoadingVendors ? 'Loading vendors...' : 'Select a vendor',
      enabled: !_isLoadingVendors,
      dialogTitle: 'Select vendor',
      onChanged: (value) => setState(() => _selectedVendorId = value),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please select a vendor';
        }
        return null;
      },
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(labelText: 'Expense Name'),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Expense name is required';
        }
        return null;
      },
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    final formatted = DateFormat('dd-MM-yyyy').format(value);
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(formatted),
      ),
    );
  }

  Widget _buildExpensesTab() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAccountRow(
            label: 'Debit account',
            selected: _selectedDebitAccount,
            onChanged: (value) => setState(() => _selectedDebitAccount = value),
            amountController: _debitAmountController,
          ),
          const SizedBox(height: 14),
          _buildAccountRow(
            label: 'Credit account',
            selected: _selectedCreditAccount,
            onChanged: (value) =>
                setState(() => _selectedCreditAccount = value),
            amountController: _creditAmountController,
          ),
          if (_accountsError != null) ...[
            const SizedBox(height: 8),
            Text(
              _accountsError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountRow({
    required String label,
    required String? selected,
    required ValueChanged<String?> onChanged,
    required TextEditingController amountController,
  }) {
    return Row(
      children: [
        Expanded(
          child: SearchableDropdownFormField<String>(
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: _isLoadingAccounts
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            initialValue: selected,
            items: _accounts.map((account) => account.id).toList(),
            itemToString: _accountLabel,
            hintText: _isLoadingAccounts
                ? 'Loading accounts...'
                : 'Select an account',
            enabled: !_isLoadingAccounts,
            dialogTitle: 'Select $label',
            onChanged: _isLoadingAccounts || _accounts.isEmpty
                ? null
                : onChanged,
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 120,
          child: TextFormField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [CurrencyInputFormatter()],
            decoration: const InputDecoration(labelText: 'Amount'),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isBillDate}) async {
    final initialDate = isBillDate ? _billDate : _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        if (isBillDate) {
          _billDate = picked;
        } else {
          _dueDate = picked;
        }
      });
    }
  }

  double? _parseAmount(TextEditingController controller) {
    return double.tryParse(
      controller.text.replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', ''),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitError = null;
      _isSubmitting = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _submitError = 'You are not logged in.';
        _isSubmitting = false;
      });
      _showSubmitSnackBar('Failed to create bill: $_submitError');
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    final debitAmount = _parseAmount(_debitAmountController) ?? 0;
    final creditAmount = _parseAmount(_creditAmountController) ?? 0;
    const tolerance = 0.01;

    if ((debitAmount - creditAmount).abs() > tolerance) {
      setState(() {
        _submitError =
            'Debit and credit amounts must be balanced before saving.';
        _isSubmitting = false;
      });
      _showSubmitSnackBar(_submitError!);
      return;
    }

    final requestData = <String, dynamic>{
      'date': DateFormat('yyyy-MM-dd').format(_billDate),
      'due_date': DateFormat('yyyy-MM-dd').format(_dueDate),
      'vendor': _selectedVendorId,
      'expense_name': _nameController.text.trim(),
      'amount': debitAmount,
      'debit_lines': [
        {'account': _selectedDebitAccount, 'amount': debitAmount},
      ],
      'credit_lines': [
        {'account': _selectedCreditAccount, 'amount': debitAmount},
      ],
      'approved': 1,
      if (_attachments.isNotEmpty)
        'attachments': _attachments.map((file) => file.name).toList(),
    };

    try {
      final created = await _billsService.createBill(
        headers: headers,
        data: requestData,
      );

      if (_attachments.isNotEmpty) {
        try {
          await _billsService.uploadAttachments(
            id: created.id,
            headers: headers,
            attachments: _attachments,
          );
        } catch (error) {
          if (mounted) {
            _showSubmitSnackBar(
              'Bill created but failed to upload attachments: $error',
            );
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() => _isSubmitting = false);
      Navigator.of(context).pop(created);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = error.toString();
        _isSubmitting = false;
      });
      _showSubmitSnackBar('Failed to create bill: $_submitError');
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
    final authtokenHeader = rawToken
        .replaceFirst(RegExp('^Bearer\s+', caseSensitive: false), '')
        .trim();
    final autoTokenValue = authtokenHeader.isNotEmpty
        ? authtokenHeader
        : sanitizedToken;
    return {'authtoken': autoTokenValue, 'Authorization': normalizedAuth};
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _accountsError = null;
      _isLoadingAccounts = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _accountsError = 'You are not logged in.';
        _isLoadingAccounts = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);
    try {
      final result = await _accountsService.fetchAccounts(
        page: 1,
        perPage: _accountsPerPage,
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _accounts = result.accounts;

        if (_selectedDebitAccount != null &&
            !_accounts.any((account) => account.id == _selectedDebitAccount)) {
          _selectedDebitAccount = null;
        }

        if (_selectedCreditAccount != null &&
            !_accounts.any((account) => account.id == _selectedCreditAccount)) {
          _selectedCreditAccount = null;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _accountsError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingAccounts = false);
      }
    }
  }

  Future<void> _loadVendors() async {
    setState(() {
      _vendorsError = null;
      _isLoadingVendors = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _vendorsError = 'You are not logged in.';
        _isLoadingVendors = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final vendors = await _vendorsService.fetchVendors(headers: headers);

      if (!mounted) {
        return;
      }

      setState(() {
        _vendors = vendors;

        if (_selectedVendorId != null &&
            !_vendors.any((vendor) => vendor.id == _selectedVendorId)) {
          _selectedVendorId = null;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _vendorsError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingVendors = false);
      }
    }
  }
}

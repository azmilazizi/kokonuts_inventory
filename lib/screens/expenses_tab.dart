import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/expenses_service.dart';
import '../widgets/date_range_filter_button.dart';
import '../widgets/expense_details_dialog.dart';
import '../widgets/edit_expense_dialog.dart';
import '../widgets/sortable_header_cell.dart';
import '../widgets/table_filter_bar.dart';

enum ExpensesSortColumn { vendor, name, category, amount, date, paymentMode }

class ExpensesTab extends StatefulWidget {
  const ExpensesTab({super.key});

  @override
  ExpensesTabState createState() => ExpensesTabState();
}

class ExpensesTabState extends State<ExpensesTab> {
  final _service = ExpensesService();
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  final _expenses = <Expense>[];
  final _allExpenses = <Expense>[];
  final _filterController = TextEditingController();
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  ExpensesSortColumn _sortColumn = ExpensesSortColumn.date;
  bool _sortAscending = false;
  String _filterQuery = '';

  static const _perPage = 20;
  // Provides generous breathing room for the seven expense columns so they do
  // not crowd each other on smaller screens.
  static const double _minTableWidth = 1080;

  bool _isLoading = false;
  bool _hasMore = true;
  int _nextPage = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchPage(reset: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _horizontalController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _fetchPage();
    }
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      if (reset) {
        _error = null;
        _hasMore = true;
      }
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

    final authtokenHeader = autoTokenValue.isNotEmpty
        ? autoTokenValue
        : sanitizedToken;

    final pageToLoad = reset ? 1 : _nextPage;

    try {
      final result = await _service.fetchExpenses(
        page: pageToLoad,
        perPage: _perPage,
        headers: {
          'Accept': 'application/json',
          'authtoken': authtokenHeader,
          'Authorization': normalizedAuth,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _mergeExpenses(result.expenses, reset: reset);
        _error = null;
        _hasMore = result.hasMore;
        _nextPage = result.hasMore ? pageToLoad + 1 : pageToLoad;
      });
    } on ExpensesException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
        _hasMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _hasMore = false;
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
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => _fetchPage(reset: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _minTableWidth;
          final tableWidth = maxWidth < _minTableWidth
              ? _minTableWidth
              : maxWidth;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: CustomScrollView(
                        shrinkWrap: true,
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: TableFilterBar(
                              controller: _filterController,
                              onChanged: _handleFilterChanged,
                              hintText: 'Search by vendor, name, or category',
                              isFiltering: _filterController.text.isNotEmpty,
                              horizontalController: _horizontalController,
                              trailing: DateRangeFilterButton(
                                label: 'Expense date',
                                startDate: _filterStartDate,
                                endDate: _filterEndDate,
                                onRangeSelected: _handleDateRangeSelected,
                                onClear: _clearDateRange,
                              ),
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _ExpensesHeaderDelegate(
                              theme: theme,
                              sortColumn: _sortColumn,
                              sortAscending: _sortAscending,
                              onSort: _handleSort,
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final expense = _expenses[index];
                              return _ExpenseRow(
                                expense: expense,
                                theme: theme,
                                showTopBorder: index == 0,
                                onUpdated: _handleExpenseUpdated,
                                onDeleted: _handleExpenseDeleted,
                              );
                            }, childCount: _expenses.length),
                          ),
                          SliverToBoxAdapter(child: _buildFooter(theme)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleSort(ExpensesSortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _applySorting();
      _applyFilters();
    });
  }

  void _mergeExpenses(List<Expense> newExpenses, {required bool reset}) {
    if (reset) {
      _allExpenses.clear();
    }

    final seenKeys = <String>{
      for (final expense in _allExpenses) _expenseKey(expense),
    };

    for (final expense in newExpenses) {
      final key = _expenseKey(expense);
      if (seenKeys.add(key)) {
        _allExpenses.add(expense);
      }
    }

    _applySorting();
    _applyFilters();
  }

  String _expenseKey(Expense expense) {
    final normalizedId = expense.id.trim().toLowerCase();
    if (normalizedId.isNotEmpty) {
      return normalizedId;
    }

    final vendor = expense.vendor.trim().toLowerCase();
    final name = expense.name.trim().toLowerCase();
    final amount = expense.amountLabel.trim().toLowerCase();
    final date = expense.date?.millisecondsSinceEpoch ?? 0;
    final paymentMode = expense.paymentMode.trim().toLowerCase();

    return '$vendor|$name|$amount|$date|$paymentMode';
  }

  void _applySorting() {
    _allExpenses.sort(_compareExpenses);
  }

  void _applyFilters() {
    if (_filterQuery.isEmpty && !_hasDateRangeFilter) {
      _expenses
        ..clear()
        ..addAll(_allExpenses);
      return;
    }

    _expenses
      ..clear()
      ..addAll(_allExpenses.where(_matchesAllFilters));
  }

  bool get _hasDateRangeFilter =>
      _filterStartDate != null && _filterEndDate != null;

  bool _matchesAllFilters(Expense expense) {
    final query = _filterQuery;
    if (query.isNotEmpty && !_matchesQuery(expense, query)) {
      return false;
    }
    if (!_isWithinDateRange(expense.date)) {
      return false;
    }
    return true;
  }

  bool _matchesQuery(Expense expense, String query) {
    if (expense.vendor.toLowerCase().contains(query)) {
      return true;
    }
    if (expense.name.toLowerCase().contains(query)) {
      return true;
    }
    if (expense.categoryName.toLowerCase().contains(query)) {
      return true;
    }
    final paymentMode = expense.paymentMode.toLowerCase();
    if (paymentMode.contains(query)) {
      return true;
    }
    final amountLabel = expense.amountLabel.toLowerCase();
    if (amountLabel.contains(query)) {
      return true;
    }
    final date = expense.date?.toIso8601String().toLowerCase() ?? '';
    return date.contains(query);
  }

  bool _isWithinDateRange(DateTime? value) {
    if (!_hasDateRangeFilter) {
      return true;
    }
    if (value == null) {
      return false;
    }
    final start = DateUtils.dateOnly(_filterStartDate!);
    final end = DateUtils.dateOnly(_filterEndDate!);
    final date = DateUtils.dateOnly(value);
    if (date.isBefore(start)) {
      return false;
    }
    if (date.isAfter(end)) {
      return false;
    }
    return true;
  }

  void _handleFilterChanged(String value) {
    setState(() {
      _filterQuery = value.trim().toLowerCase();
      _applyFilters();
    });
  }

  void _handleDateRangeSelected(DateTimeRange range) {
    setState(() {
      _filterStartDate = DateUtils.dateOnly(range.start);
      _filterEndDate = DateUtils.dateOnly(range.end);
      _applyFilters();
    });
  }

  void _clearDateRange() {
    setState(() {
      _filterStartDate = null;
      _filterEndDate = null;
      _applyFilters();
    });
  }

  void insertCreatedExpense(Expense expense) {
    setState(() {
      final existingIndex = _allExpenses.indexWhere(
        (item) => _isSameExpense(item, expense),
      );

      if (existingIndex != -1) {
        _allExpenses[existingIndex] = expense;
      } else {
        _allExpenses.add(expense);
      }

      _applySorting();
      _applyFilters();
    });
  }

  void _handleExpenseUpdated(Expense updatedExpense) {
    setState(() {
      final existingIndex = _allExpenses.indexWhere(
        (expense) => _isSameExpense(expense, updatedExpense),
      );

      if (existingIndex != -1) {
        _allExpenses[existingIndex] = updatedExpense;
      } else {
        _allExpenses.add(updatedExpense);
      }

      _applySorting();
      _applyFilters();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Expense updated successfully.')),
    );
  }

  Future<void> _handleExpenseDeleted(Expense expense) async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }

    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You are not logged in.')));
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

    final authtokenHeader = autoTokenValue.isNotEmpty
        ? autoTokenValue
        : sanitizedToken;

    try {
      await _service.deleteExpense(
        id: expense.id,
        headers: {
          'Accept': 'application/json',
          'authtoken': authtokenHeader,
          'Authorization': normalizedAuth,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _allExpenses.removeWhere((item) => _isSameExpense(item, expense));
        _applyFilters();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${expense.name} deleted.')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete expense: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  bool _isSameExpense(Expense a, Expense b) {
    if (a.id.trim().isNotEmpty && b.id.trim().isNotEmpty) {
      return a.id.trim().toLowerCase() == b.id.trim().toLowerCase();
    }
    return _expenseKey(a) == _expenseKey(b);
  }

  int _compareExpenses(Expense a, Expense b) {
    final primary = _rawCompareExpenses(a, b);
    if (primary != 0) {
      return _sortAscending ? primary : -primary;
    }
    final idCompare = a.id.toLowerCase().compareTo(b.id.toLowerCase());
    return _sortAscending ? idCompare : -idCompare;
  }

  int _rawCompareExpenses(Expense a, Expense b) {
    switch (_sortColumn) {
      case ExpensesSortColumn.vendor:
        return a.vendor.toLowerCase().compareTo(b.vendor.toLowerCase());
      case ExpensesSortColumn.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case ExpensesSortColumn.category:
        return a.categoryName.toLowerCase().compareTo(
          b.categoryName.toLowerCase(),
        );
      case ExpensesSortColumn.amount:
        final left = a.amount ?? _parseFallbackAmount(a.amountLabel);
        final right = b.amount ?? _parseFallbackAmount(b.amountLabel);
        return left.compareTo(right);
      case ExpensesSortColumn.date:
        final leftDate = a.date;
        final rightDate = b.date;
        if (leftDate == null && rightDate == null) {
          return 0;
        }
        if (leftDate == null) {
          return -1;
        }
        if (rightDate == null) {
          return 1;
        }
        return leftDate.compareTo(rightDate);
      case ExpensesSortColumn.paymentMode:
        return a.paymentMode.toLowerCase().compareTo(
          b.paymentMode.toLowerCase(),
        );
    }
  }

  double _parseFallbackAmount(String label) {
    final sanitized = label.replaceAll(RegExp(r'[^0-9.,-]'), '');
    final normalized = sanitized.replaceAll(',', '');
    return double.tryParse(normalized) ?? 0;
  }

  Widget _buildFooter(ThemeData theme) {
    if (_isLoading && _expenses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _fetchPage(reset: _expenses.isEmpty),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_expenses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(
              Icons.payments_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No expenses available.', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Pull to refresh to check for updates.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Scroll to load more expenses…',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return const SizedBox(height: 24);
  }
}

class _ExpensesHeaderDelegate extends SliverPersistentHeaderDelegate {
  _ExpensesHeaderDelegate({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final ExpensesSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<ExpensesSortColumn> onSort;

  static const double _height = 52;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final background = theme.colorScheme.surfaceVariant.withOpacity(0.6);
    return SizedBox.expand(
      child: Material(
        color: background,
        elevation: overlapsContent ? 2 : 0,
        shadowColor: theme.shadowColor.withOpacity(0.2),
        child: _ExpensesHeader(
          theme: theme,
          sortColumn: sortColumn,
          sortAscending: sortAscending,
          onSort: onSort,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ExpensesHeaderDelegate oldDelegate) {
    return sortColumn != oldDelegate.sortColumn ||
        sortAscending != oldDelegate.sortAscending ||
        theme != oldDelegate.theme;
  }
}

class _ExpensesHeader extends StatelessWidget {
  const _ExpensesHeader({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final ExpensesSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<ExpensesSortColumn> onSort;

  static const _columnFlex = [4, 4, 3, 2, 3, 3, 3];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Vendor',
            flex: _columnFlex[0],
            theme: theme,
            isActive: sortColumn == ExpensesSortColumn.vendor,
            ascending: sortAscending,
            onTap: () => onSort(ExpensesSortColumn.vendor),
          ),
          SortableHeaderCell(
            label: 'Name',
            flex: _columnFlex[1],
            theme: theme,
            isActive: sortColumn == ExpensesSortColumn.name,
            ascending: sortAscending,
            onTap: () => onSort(ExpensesSortColumn.name),
          ),
          SortableHeaderCell(
            label: 'Category',
            flex: _columnFlex[2],
            theme: theme,
            isActive: sortColumn == ExpensesSortColumn.category,
            ascending: sortAscending,
            onTap: () => onSort(ExpensesSortColumn.category),
          ),
          SortableHeaderCell(
            label: 'Amount',
            flex: _columnFlex[3],
            theme: theme,
            textAlign: TextAlign.end,
            isActive: sortColumn == ExpensesSortColumn.amount,
            ascending: sortAscending,
            onTap: () => onSort(ExpensesSortColumn.amount),
          ),
          SortableHeaderCell(
            label: 'Date',
            flex: _columnFlex[4],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == ExpensesSortColumn.date,
            ascending: sortAscending,
            onTap: () => onSort(ExpensesSortColumn.date),
          ),
          SortableHeaderCell(
            label: 'Payment mode',
            flex: _columnFlex[5],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == ExpensesSortColumn.paymentMode,
            ascending: sortAscending,
            onTap: () => onSort(ExpensesSortColumn.paymentMode),
          ),
          Expanded(
            flex: _columnFlex[6],
            child: Align(
              alignment: Alignment.center,
              child: Text(
                'Actions',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatefulWidget {
  const _ExpenseRow({
    required this.expense,
    required this.theme,
    required this.showTopBorder,
    required this.onUpdated,
    required this.onDeleted,
  });

  final Expense expense;
  final ThemeData theme;
  final bool showTopBorder;
  final ValueChanged<Expense> onUpdated;
  final Future<void> Function(Expense) onDeleted;

  @override
  State<_ExpenseRow> createState() => _ExpenseRowState();
}

class _ExpenseRowState extends State<_ExpenseRow> {
  bool _hovering = false;

  static const _columnFlex = [4, 4, 3, 2, 3, 3, 3];

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.theme.dividerColor.withOpacity(0.6);
    final baseBackground = widget.theme.colorScheme.surfaceVariant.withOpacity(
      0.25,
    );
    final hoverBackground = widget.theme.colorScheme.surfaceVariant.withOpacity(
      0.45,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleView,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovering ? hoverBackground : baseBackground,
            border: Border(
              top: widget.showTopBorder
                  ? BorderSide(color: borderColor)
                  : BorderSide.none,
              bottom: BorderSide(color: borderColor),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: Row(
            children: [
              _DataCell(widget.expense.vendor, flex: _columnFlex[0]),
              _DataCell(widget.expense.name, flex: _columnFlex[1]),
              _DataCell(widget.expense.categoryName, flex: _columnFlex[2]),
              _DataCell(
                widget.expense.formattedAmountWithoutCurrency,
                flex: _columnFlex[3],
                textAlign: TextAlign.end,
                style: widget.theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: widget.theme.colorScheme.error,
                ),
              ),
              _DataCell(
                widget.expense.formattedDate,
                flex: _columnFlex[4],
                textAlign: TextAlign.center,
              ),
              _DataCell(
                widget.expense.paymentMode,
                flex: _columnFlex[5],
                textAlign: TextAlign.center,
              ),
              Expanded(
                flex: _columnFlex[6],
                child: Align(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        onPressed: _handleEdit,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        color: widget.theme.colorScheme.error,
                        onPressed: _handleDelete,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleEdit() async {
    final updated = await showDialog<Expense>(
      context: context,
      builder: (context) => EditExpenseDialog(expense: widget.expense),
    );

    if (updated != null) {
      widget.onUpdated(updated);
    }
  }

  void _handleView() {
    showDialog(
      context: context,
      builder: (context) => ExpenseDetailsDialog(expense: widget.expense),
    );
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense'),
        content: Text(
          'Are you sure you want to delete "${widget.expense.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.theme.colorScheme.error,
              foregroundColor: widget.theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.onDeleted(widget.expense);
    }
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell(this.value, {required this.flex, this.textAlign, this.style});

  final String value;
  final int flex;
  final TextAlign? textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        textAlign: textAlign ?? TextAlign.start,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: style,
      ),
    );
  }
}

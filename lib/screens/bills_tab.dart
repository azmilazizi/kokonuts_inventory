import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../services/bills_service.dart';
import '../widgets/bill_details_dialog.dart';
import '../widgets/date_range_filter_button.dart';
import '../widgets/sortable_header_cell.dart';
import '../widgets/table_filter_bar.dart';

enum BillsSortColumn { vendor, billDate, dueDate, status, total }

class BillsTab extends StatefulWidget {
  const BillsTab({super.key});

  @override
  BillsTabState createState() => BillsTabState();
}

class BillsTabState extends State<BillsTab> {
  final _service = BillsService();
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  final _bills = <Bill>[];
  final _allBills = <Bill>[];
  final _vendorNames = <String, String?>{};
  final _filterController = TextEditingController();
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  BillsSortColumn _sortColumn = BillsSortColumn.billDate;
  bool _sortAscending = false;
  String _filterQuery = '';

  static const _perPage = 20;
  // The bills table includes action buttons which require extra width; raising
  // the minimum ensures the columns stay separated on compact layouts.
  static const double _minTableWidth = 1000;

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

    final pageToLoad = reset ? 1 : _nextPage;
    final headers = _buildAuthHeaders(appState, token);

    try {
      final result = await _service.fetchBills(
        page: pageToLoad,
        perPage: _perPage,
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _seedVendorNames(result.bills);
        _mergeBills(result.bills, reset: reset);
        _error = null;
        _hasMore = result.hasMore;
        _nextPage = result.hasMore ? pageToLoad + 1 : pageToLoad;
      });

      final vendorIds = result.bills
          .map((bill) => bill.vendorId)
          .where((id) => id.isNotEmpty && !_vendorNames.containsKey(id))
          .toSet();

      for (final vendorId in vendorIds) {
        unawaited(_loadVendorName(vendorId, headers));
      }
    } on BillsException catch (error) {
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

  Future<void> _loadVendorName(
    String vendorId,
    Map<String, String> headers,
  ) async {
    try {
      final name = await _service.resolveVendorName(
        vendorId: vendorId,
        headers: headers,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _vendorNames[vendorId] = name ?? 'Unknown vendor';
        final shouldResort = _sortColumn == BillsSortColumn.vendor;
        if (shouldResort) {
          _applySorting();
        }
        if (shouldResort || _filterQuery.isNotEmpty) {
          _applyFilters();
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _vendorNames[vendorId] = 'Unknown vendor';
        final shouldResort = _sortColumn == BillsSortColumn.vendor;
        if (shouldResort) {
          _applySorting();
        }
        if (shouldResort || _filterQuery.isNotEmpty) {
          _applyFilters();
        }
      });
    }
  }

  Future<void> _deleteBill(Bill bill) async {
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

    try {
      await _service.deleteBill(id: bill.id, headers: headers);
      if (!mounted) {
        return;
      }
      setState(() {
        _allBills.removeWhere((item) => _billKey(item) == _billKey(bill));
        _bills.removeWhere((item) => _billKey(item) == _billKey(bill));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill deleted successfully.')),
      );
    } on BillsException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete bill: ${error.message}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete bill: $error')));
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
                              hintText: 'Search by vendor, status, or amount',
                              isFiltering: _filterController.text.isNotEmpty,
                              horizontalController: _horizontalController,
                              trailing: DateRangeFilterButton(
                                label: 'Bill or due date',
                                startDate: _filterStartDate,
                                endDate: _filterEndDate,
                                onRangeSelected: _handleDateRangeSelected,
                                onClear: _clearDateRange,
                              ),
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _BillsHeaderDelegate(
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
                              final bill = _bills[index];
                              return _BillRow(
                                bill: bill,
                                vendorName: _vendorLabel(bill),
                                theme: theme,
                                showTopBorder: index == 0,
                                onDelete: () => _deleteBill(bill),
                                onBillUpdated: _handleBillUpdated,
                              );
                            }, childCount: _bills.length),
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

  void _handleSort(BillsSortColumn column) {
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

  void insertCreatedBill(Bill bill) {
    setState(() {
      _vendorNames.putIfAbsent(bill.vendorId, () => bill.vendorName);

      final existingIndex = _allBills.indexWhere(
        (item) => _billKey(item) == _billKey(bill),
      );

      if (existingIndex != -1) {
        _allBills[existingIndex] = bill;
      } else {
        _allBills.add(bill);
      }

      _applySorting();
      _applyFilters();
    });
  }

  void _handleBillUpdated(Bill bill) {
    setState(() {
      final vendorId = bill.vendorId;
      final vendorName = bill.vendorName?.trim();
      if (vendorName != null && vendorName.isNotEmpty) {
        _vendorNames[vendorId] = vendorName;
      }

      final key = _billKey(bill);
      final existingIndex = _allBills.indexWhere(
        (item) => _billKey(item) == key,
      );

      if (existingIndex != -1) {
        _allBills[existingIndex] = bill;
      } else {
        _allBills.add(bill);
      }

      _applySorting();
      _applyFilters();
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

  void _mergeBills(List<Bill> newBills, {required bool reset}) {
    if (reset) {
      _allBills.clear();
    }

    final seenKeys = <String>{for (final bill in _allBills) _billKey(bill)};

    for (final bill in newBills) {
      final key = _billKey(bill);
      if (seenKeys.add(key)) {
        _allBills.add(bill);
      }
    }

    _applySorting();
    _applyFilters();
  }

  void _seedVendorNames(List<Bill> bills) {
    for (final bill in bills) {
      final vendorId = bill.vendorId;
      final vendorName = bill.vendorName?.trim();
      if (vendorId.isEmpty || vendorName == null || vendorName.isEmpty) {
        continue;
      }
      _vendorNames.putIfAbsent(vendorId, () => vendorName);
    }
  }

  String _billKey(Bill bill) {
    final normalizedId = bill.id.trim().toLowerCase();
    if (normalizedId.isNotEmpty) {
      return normalizedId;
    }

    final vendorId = bill.vendorId.trim().toLowerCase();
    final billDate = bill.billDate?.millisecondsSinceEpoch ?? 0;
    final dueDate = bill.dueDate?.millisecondsSinceEpoch ?? 0;
    final status = bill.status.code;
    final amount = bill.totalAmount?.toStringAsFixed(2) ?? 'null';

    return '$vendorId|$billDate|$dueDate|$status|$amount';
  }

  void _applySorting() {
    _allBills.sort(_compareBills);
  }

  void _applyFilters() {
    if (_filterQuery.isEmpty && !_hasDateRangeFilter) {
      _bills
        ..clear()
        ..addAll(_allBills);
      return;
    }

    _bills
      ..clear()
      ..addAll(_allBills.where(_matchesAllFilters));
  }

  bool get _hasDateRangeFilter =>
      _filterStartDate != null && _filterEndDate != null;

  bool _matchesAllFilters(Bill bill) {
    final query = _filterQuery;
    if (query.isNotEmpty && !_matchesQuery(bill, query)) {
      return false;
    }
    if (!_matchesDateRange(bill)) {
      return false;
    }
    return true;
  }

  bool _matchesQuery(Bill bill, String query) {
    if (_vendorLabel(bill).toLowerCase().contains(query)) {
      return true;
    }
    final status = bill.status.label.toLowerCase();
    final statusCode = bill.status.code.toString().toLowerCase();
    if (status.contains(query) || statusCode.contains(query)) {
      return true;
    }
    final total = bill.totalAmount?.toStringAsFixed(2) ?? bill.totalLabel;
    if (total.toLowerCase().contains(query)) {
      return true;
    }
    final billDate = bill.billDate?.toIso8601String().toLowerCase() ?? '';
    if (billDate.contains(query)) {
      return true;
    }
    final dueDate = bill.dueDate?.toIso8601String().toLowerCase() ?? '';
    return dueDate.contains(query);
  }

  bool _matchesDateRange(Bill bill) {
    if (!_hasDateRangeFilter) {
      return true;
    }
    return _isWithinDateRange(bill.billDate) ||
        _isWithinDateRange(bill.dueDate);
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

  int _compareBills(Bill a, Bill b) {
    final primary = _rawCompareBills(a, b);
    if (primary != 0) {
      return _sortAscending ? primary : -primary;
    }

    final idCompare = a.id.toLowerCase().compareTo(b.id.toLowerCase());
    return _sortAscending ? idCompare : -idCompare;
  }

  int _rawCompareBills(Bill a, Bill b) {
    switch (_sortColumn) {
      case BillsSortColumn.vendor:
        return _vendorLabel(
          a,
        ).toLowerCase().compareTo(_vendorLabel(b).toLowerCase());
      case BillsSortColumn.billDate:
        final leftDate = a.billDate;
        final rightDate = b.billDate;
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
      case BillsSortColumn.dueDate:
        final left = a.dueDate;
        final right = b.dueDate;
        if (left == null && right == null) {
          return 0;
        }
        if (left == null) {
          return -1;
        }
        if (right == null) {
          return 1;
        }
        return left.compareTo(right);
      case BillsSortColumn.status:
        return a.status.code.compareTo(b.status.code);
      case BillsSortColumn.total:
        final left = a.totalAmount ?? 0;
        final right = b.totalAmount ?? 0;
        return left.compareTo(right);
    }
  }

  String _vendorLabel(Bill bill) {
    final name = bill.vendorName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return _vendorNames[bill.vendorId] ?? 'Loading vendor…';
  }

  Widget _buildFooter(ThemeData theme) {
    if (_isLoading && _bills.isEmpty) {
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
              onPressed: () => _fetchPage(reset: _bills.isEmpty),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_bills.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No bills available.', style: theme.textTheme.titleMedium),
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
            'Scroll to load more bills…',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _BillsHeader extends StatelessWidget {
  const _BillsHeader({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final BillsSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<BillsSortColumn> onSort;

  static const _columnFlex = [4, 3, 3, 3, 2, 3];

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
            isActive: sortColumn == BillsSortColumn.vendor,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.vendor),
          ),
          SortableHeaderCell(
            label: 'Date',
            flex: _columnFlex[1],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == BillsSortColumn.billDate,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.billDate),
          ),
          SortableHeaderCell(
            label: 'Due Date',
            flex: _columnFlex[2],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == BillsSortColumn.dueDate,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.dueDate),
          ),
          SortableHeaderCell(
            label: 'Status',
            flex: _columnFlex[3],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == BillsSortColumn.status,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.status),
          ),
          SortableHeaderCell(
            label: 'Total',
            flex: _columnFlex[4],
            theme: theme,
            textAlign: TextAlign.end,
            isActive: sortColumn == BillsSortColumn.total,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.total),
          ),
          const SizedBox(width: 12),
          SortableHeaderCell(
            label: 'Actions',
            flex: _columnFlex[5],
            theme: theme,
            textAlign: TextAlign.center,
            ascending: sortAscending,
          ),
        ],
      ),
    );
  }
}

class _BillsHeaderDelegate extends SliverPersistentHeaderDelegate {
  _BillsHeaderDelegate({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final BillsSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<BillsSortColumn> onSort;

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
        child: _BillsHeader(
          theme: theme,
          sortColumn: sortColumn,
          sortAscending: sortAscending,
          onSort: onSort,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _BillsHeaderDelegate oldDelegate) {
    return sortColumn != oldDelegate.sortColumn ||
        sortAscending != oldDelegate.sortAscending ||
        theme != oldDelegate.theme;
  }
}

class _BillRow extends StatefulWidget {
  const _BillRow({
    required this.bill,
    required this.vendorName,
    required this.theme,
    required this.showTopBorder,
    required this.onDelete,
    this.onBillUpdated,
  });

  final Bill bill;
  final String vendorName;
  final ThemeData theme;
  final bool showTopBorder;
  final Future<void> Function() onDelete;
  final void Function(Bill bill)? onBillUpdated;

  @override
  State<_BillRow> createState() => _BillRowState();
}

class _BillRowState extends State<_BillRow> {
  bool _hovering = false;
  bool _isDeleting = false;

  static const _columnFlex = [4, 3, 3, 3, 2, 3];

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
              _DataCell(widget.vendorName, flex: _columnFlex[0]),
              _DataCell(
                widget.bill.formattedDate,
                flex: _columnFlex[1],
                textAlign: TextAlign.center,
              ),
              _DataCell(
                widget.bill.formattedDueDate,
                flex: _columnFlex[2],
                textAlign: TextAlign.center,
              ),
              Expanded(
                flex: _columnFlex[3],
                child: Align(
                  alignment: Alignment.center,
                  child: _StatusPill(
                    status: widget.bill.status,
                    theme: widget.theme,
                  ),
                ),
              ),
              _DataCell(
                widget.bill.totalLabel,
                flex: _columnFlex[4],
                textAlign: TextAlign.end,
                style: widget.theme.textTheme.bodyMedium?.copyWith(
                  color: widget.theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: _columnFlex[5],
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete bill',
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        color: widget.theme.colorScheme.error,
                        onPressed: _isDeleting ? null : _handleDelete,
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

  void _handleView() {
    showDialog(
      context: context,
      builder: (context) => BillDetailsDialog(
        bill: widget.bill,
        vendorName: widget.vendorName,
        onBillUpdated: widget.onBillUpdated,
      ),
    );
  }

  Future<void> _handleDelete() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete bill?'),
            content: Text(
              'Are you sure you want to delete the bill for ${widget.vendorName}? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await widget.onDelete();
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
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

    return Container(
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
    );
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

import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/purchase_orders_service.dart';
import '../widgets/alert_banner.dart';
import '../widgets/date_range_filter_button.dart';
import '../widgets/purchase_order_details_dialog.dart';
import '../widgets/sortable_header_cell.dart';
import '../widgets/table_filter_bar.dart';

enum PurchaseOrderSortColumn {
  number,
  name,
  vendor,
  orderDate,
  deliveryDate,
}

class PurchaseOrdersTab extends StatefulWidget {
  const PurchaseOrdersTab({super.key});

  @override
  PurchaseOrdersTabState createState() => PurchaseOrdersTabState();
}

class PurchaseOrdersTabState extends State<PurchaseOrdersTab> {
  final _service = PurchaseOrdersService();
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  final _orders = <PurchaseOrder>[];
  final _allOrders = <PurchaseOrder>[];
  final _filterController = TextEditingController();
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  PurchaseOrderSortColumn _sortColumn = PurchaseOrderSortColumn.orderDate;
  bool _sortAscending = false;
  String _filterQuery = '';

  static const _perPage = 20;
  // A wider minimum width keeps the eight data columns readable on compact
  // layouts and prevents them from collapsing into each other on small
  // screens. The wider width ensures horizontal scrolling kicks in before the
  // table gets cramped.
  static const double _minTableWidth = 1100;

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

    final headers = await _buildAuthHeaders();
    if (!mounted) {
      return;
    }

    if (headers == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final pageToLoad = reset ? 1 : _nextPage;

    try {
      final result = await _service.fetchPurchaseOrders(
        page: pageToLoad,
        perPage: _perPage,
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (reset) {
          _allOrders
            ..clear()
            ..addAll(result.orders);
        } else {
          _allOrders.addAll(result.orders);
        }
        _applySorting();
        _applyFilters();
        _error = null;
        _hasMore = result.hasMore;
        _nextPage = result.hasMore ? pageToLoad + 1 : pageToLoad;
      });
    } on PurchaseOrdersException catch (error) {
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
        _error =
            'Something went wrong while loading purchase orders. Please try again later.';
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

  Future<Map<String, String>?> _buildAuthHeaders() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return null;
    }

    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'You are not logged in.';
      });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return RefreshIndicator(
      onRefresh: () => _fetchPage(reset: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _minTableWidth;
          final isCompactLayout = maxWidth < _minTableWidth;
          final tableWidth = isCompactLayout ? _minTableWidth : maxWidth;

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
                              hintText: 'Search by number, vendor, or total',
                              isFiltering: _filterController.text.isNotEmpty,
                              horizontalController: _horizontalController,
                              trailing: DateRangeFilterButton(
                                label: 'Order date',
                                startDate: _filterStartDate,
                                endDate: _filterEndDate,
                                onRangeSelected: _handleDateRangeSelected,
                                onClear: _clearDateRange,
                              ),
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _PurchaseOrdersHeaderDelegate(
                              theme: theme,
                              isCompactLayout: isCompactLayout,
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
                              final order = _orders[index];
                              return _PurchaseOrderRow(
                                order: order,
                                theme: theme,
                                showTopBorder: index == 0,
                                isCompactLayout: isCompactLayout,
                              );
                            }, childCount: _orders.length),
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

  void _handleSort(PurchaseOrderSortColumn column) {
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

  void insertCreatedPurchaseOrder(
    PurchaseOrder order, {
    String? successMessage,
  }) {
    setState(() {
      final existingIndex = _allOrders.indexWhere(
        (element) => element.id == order.id,
      );
      if (existingIndex >= 0) {
        _allOrders[existingIndex] = order;
      } else {
        _allOrders.add(order);
      }
      _applySorting();
      _applyFilters();
      _error = null;
    });

    if (successMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    }
  }

  void _applySorting() {
    _allOrders.sort(_compareOrders);
  }

  void _applyFilters() {
    if (_filterQuery.isEmpty && !_hasDateRangeFilter) {
      _orders
        ..clear()
        ..addAll(_allOrders);
      return;
    }

    _orders
      ..clear()
      ..addAll(_allOrders.where(_matchesAllFilters));
  }

  bool get _hasDateRangeFilter =>
      _filterStartDate != null && _filterEndDate != null;

  bool _matchesAllFilters(PurchaseOrder order) {
    final query = _filterQuery;
    if (query.isNotEmpty && !_matchesQuery(order, query)) {
      return false;
    }
    if (!_isWithinDateRange(order.orderDate)) {
      return false;
    }
    return true;
  }

  bool _matchesQuery(PurchaseOrder order, String query) {
    if (order.number.toLowerCase().contains(query)) {
      return true;
    }
    if (order.name.toLowerCase().contains(query)) {
      return true;
    }
    if (order.vendorName.toLowerCase().contains(query)) {
      return true;
    }
    final date = order.orderDate?.toIso8601String().toLowerCase() ?? '';
    if (date.contains(query)) {
      return true;
    }
    return false;
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

  int _compareOrders(PurchaseOrder a, PurchaseOrder b) {
    final primary = _rawCompareOrders(a, b);
    if (primary != 0) {
      return _sortAscending ? primary : -primary;
    }

    final numberCompare = a.number.toLowerCase().compareTo(
      b.number.toLowerCase(),
    );
    if (numberCompare != 0) {
      return _sortAscending ? numberCompare : -numberCompare;
    }

    final idCompare = a.id.toLowerCase().compareTo(b.id.toLowerCase());
    return _sortAscending ? idCompare : -idCompare;
  }

  int _rawCompareOrders(PurchaseOrder a, PurchaseOrder b) {
    switch (_sortColumn) {
      case PurchaseOrderSortColumn.number:
        return a.number.toLowerCase().compareTo(b.number.toLowerCase());
      case PurchaseOrderSortColumn.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case PurchaseOrderSortColumn.vendor:
        return a.vendorName.toLowerCase().compareTo(b.vendorName.toLowerCase());
      case PurchaseOrderSortColumn.orderDate:
        final left = a.orderDate;
        final right = b.orderDate;
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
      case PurchaseOrderSortColumn.deliveryDate:
        final left = a.deliveryDate;
        final right = b.deliveryDate;
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
    }
  }

  Widget _buildFooter(ThemeData theme) {
    if (_isLoading && _orders.isEmpty) {
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
              onPressed: () => _fetchPage(reset: _orders.isEmpty),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_orders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No purchase orders available.',
              style: theme.textTheme.titleMedium,
            ),
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
            'Scroll to load more purchase orders…',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _PurchaseOrdersHeader extends StatelessWidget {
  const _PurchaseOrdersHeader({
    required this.theme,
    required this.isCompactLayout,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final bool isCompactLayout;
  final PurchaseOrderSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<PurchaseOrderSortColumn> onSort;

  static const _columnFlex = [3, 4, 3, 3, 3, 3];

  @override
  Widget build(BuildContext context) {
    final gap = isCompactLayout ? 8.0 : 12.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompactLayout ? 16 : 24,
        vertical: 8,
      ),
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Order Number',
            flex: _columnFlex[0],
            theme: theme,
            isActive: sortColumn == PurchaseOrderSortColumn.number,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.number),
          ),
          SizedBox(width: gap),
          SortableHeaderCell(
            label: 'Order Name',
            flex: _columnFlex[1],
            theme: theme,
            isActive: sortColumn == PurchaseOrderSortColumn.name,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.name),
          ),
          SortableHeaderCell(
            label: 'Vendor',
            flex: _columnFlex[2],
            theme: theme,
            isActive: sortColumn == PurchaseOrderSortColumn.vendor,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.vendor),
          ),
          SortableHeaderCell(
            label: 'Order Date',
            flex: _columnFlex[3],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == PurchaseOrderSortColumn.orderDate,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.orderDate),
          ),
          SortableHeaderCell(
            label: 'Delivery Date',
            flex: _columnFlex[4],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == PurchaseOrderSortColumn.deliveryDate,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.deliveryDate),
          ),
          SortableHeaderCell(
            label: 'Delivery Status',
            flex: _columnFlex[5],
            theme: theme,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PurchaseOrdersHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PurchaseOrdersHeaderDelegate({
    required this.theme,
    required this.isCompactLayout,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final bool isCompactLayout;
  final PurchaseOrderSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<PurchaseOrderSortColumn> onSort;

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
        child: _PurchaseOrdersHeader(
          theme: theme,
          isCompactLayout: isCompactLayout,
          sortColumn: sortColumn,
          sortAscending: sortAscending,
          onSort: onSort,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PurchaseOrdersHeaderDelegate oldDelegate) {
    return sortColumn != oldDelegate.sortColumn ||
        sortAscending != oldDelegate.sortAscending ||
        theme != oldDelegate.theme ||
        isCompactLayout != oldDelegate.isCompactLayout;
  }
}

class _PurchaseOrderRow extends StatefulWidget {
  const _PurchaseOrderRow({
    required this.order,
    required this.theme,
    required this.showTopBorder,
    required this.isCompactLayout,
  });

  final PurchaseOrder order;
  final ThemeData theme;
  final bool showTopBorder;
  final bool isCompactLayout;

  @override
  State<_PurchaseOrderRow> createState() => _PurchaseOrderRowState();
}

class _PurchaseOrderRowState extends State<_PurchaseOrderRow> {
  bool _hovering = false;

  static const _columnFlex = [3, 4, 3, 3, 3, 3];

  void _showDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) =>
          PurchaseOrderDetailsDialog(orderId: widget.order.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.theme.dividerColor.withOpacity(0.6);
    final baseBackground = widget.theme.colorScheme.surfaceVariant.withOpacity(
      0.25,
    );
    final hoverBackground = widget.theme.colorScheme.surfaceVariant.withOpacity(
      0.45,
    );

    final double horizontalPadding = widget.isCompactLayout ? 16.0 : 24.0;
    final double columnGap = widget.isCompactLayout ? 8.0 : 12.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () => _showDetails(context),
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
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 6,
          ),
          child: Row(
            children: [
              _DataCell(widget.order.number, flex: _columnFlex[0]),
              SizedBox(width: columnGap),
              _DataCell(widget.order.name, flex: _columnFlex[1]),
              _DataCell(widget.order.vendorName, flex: _columnFlex[2]),
              _DataCell(
                widget.order.formattedDate,
                flex: _columnFlex[3],
                textAlign: TextAlign.center,
              ),
              _DataCell(
                widget.order.formattedDeliveryDate,
                flex: _columnFlex[4],
                textAlign: TextAlign.center,
              ),
              _DeliveryStatusCell(
                status: widget.order.deliveryStatus,
                flex: _columnFlex[5],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryStatusCell extends StatelessWidget {
  const _DeliveryStatusCell({required this.status, required this.flex});

  final int status;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final isDelivered = status == 1;
    final color = isDelivered ? Colors.green : Colors.red;
    final label = isDelivered ? 'Delivered' : 'Undelivered';

    return Expanded(
      flex: flex,
      child: Center(
        child: Semantics(
          label: label,
          child: Icon(Icons.circle, size: 12, color: color),
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

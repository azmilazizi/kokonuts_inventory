import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/warehouse_history_service.dart';
import '../widgets/sortable_header_cell.dart';
import '../widgets/table_filter_bar.dart';

enum InventoryHistorySortColumn {
  code,
  type,
  commodityName,
  warehouseCode,
  warehouseName,
  voucherDate,
  openingStock,
  closingStock,
  lotNumber,
}

class InventoryHistoryTab extends StatefulWidget {
  const InventoryHistoryTab({super.key});

  @override
  State<InventoryHistoryTab> createState() => _InventoryHistoryTabState();
}

class _InventoryHistoryTabState extends State<InventoryHistoryTab> {
  final _service = WarehouseHistoryService();
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  final _entriesByKey = <String, WarehouseHistoryEntry>{};
  final _displayEntries = <WarehouseHistoryEntry>[];
  final _filterController = TextEditingController();

  InventoryHistorySortColumn _sortColumn = InventoryHistorySortColumn.voucherDate;
  bool _sortAscending = false;
  String _filterQuery = '';

  static const _perPage = 20;
  // Ensures the inventory history columns retain enough space before
  // horizontal scrolling is required, avoiding overlap on narrow screens.
  static const double _minTableWidth = 1500;

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
    final sanitizedToken =
        token.replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '').trim();
    final normalizedAuth =
        sanitizedToken.isNotEmpty ? 'Bearer $sanitizedToken' : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();

    final authtokenHeader = autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;

    final pageToLoad = reset ? 1 : _nextPage;

    try {
      final result = await _service.fetchHistory(
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
        if (reset) {
          _entriesByKey
            ..clear()
            ..addEntries(
              result.entries.map(
                (entry) => MapEntry(_entryStorageKey(entry), entry),
              ),
            );
        } else {
          for (final entry in result.entries) {
            _entriesByKey[_entryStorageKey(entry)] = entry;
          }
        }

        _rebuildDisplayEntries();
        _error = null;
        _hasMore = result.hasMore;
        _nextPage = result.hasMore ? pageToLoad + 1 : pageToLoad;
      });
    } on WarehouseHistoryException catch (error) {
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
          final maxWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : _minTableWidth;
          final tableWidth = maxWidth < _minTableWidth ? _minTableWidth : maxWidth;

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
                              hintText:
                                  'Search by code, type, commodity, or warehouse',
                              isFiltering: _filterController.text.isNotEmpty,
                              horizontalController: _horizontalController,
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _InventoryHistoryHeaderDelegate(
                              theme: theme,
                              sortColumn: _sortColumn,
                              sortAscending: _sortAscending,
                              onSort: _handleSort,
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final entry = _displayEntries[index];
                                return _InventoryHistoryRow(
                                  entry: entry,
                                  theme: theme,
                                  showTopBorder: index == 0,
                                );
                              },
                              childCount: _displayEntries.length,
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: _buildFooter(theme),
                          ),
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

  void _handleSort(InventoryHistorySortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _rebuildDisplayEntries();
    });
  }

  void _handleFilterChanged(String value) {
    setState(() {
      _filterQuery = value.trim().toLowerCase();
      _rebuildDisplayEntries();
    });
  }

  String _entryStorageKey(WarehouseHistoryEntry entry) {
    if (entry.id.isNotEmpty) {
      return entry.id;
    }
    return '${entry.code}::${entry.type}::${entry.voucherDate}::${entry.warehouseCode}';
  }

  void _rebuildDisplayEntries() {
    final ordered = _entriesByKey.values.toList()..sort(_compareEntries);
    if (_filterQuery.isEmpty) {
      _displayEntries
        ..clear()
        ..addAll(ordered);
      return;
    }

    _displayEntries
      ..clear()
      ..addAll(
        ordered.where(_matchesFilter),
      );
  }

  bool _matchesFilter(WarehouseHistoryEntry entry) {
    if (_filterQuery.isEmpty) {
      return true;
    }
    final query = _filterQuery;
    return entry.code.toLowerCase().contains(query) ||
        entry.type.toLowerCase().contains(query) ||
        entry.commodityName.toLowerCase().contains(query) ||
        entry.warehouseCode.toLowerCase().contains(query) ||
        entry.warehouseName.toLowerCase().contains(query) ||
        entry.voucherDate.toLowerCase().contains(query) ||
        entry.openingStock.toLowerCase().contains(query) ||
        entry.closingStock.toLowerCase().contains(query) ||
        entry.lotNumber.toLowerCase().contains(query);
  }

  int _compareEntries(WarehouseHistoryEntry a, WarehouseHistoryEntry b) {
    final result = _rawCompareEntries(a, b);
    if (result != 0) {
      return _sortAscending ? result : -result;
    }

    final idCompare = a.id.toLowerCase().compareTo(b.id.toLowerCase());
    return _sortAscending ? idCompare : -idCompare;
  }

  int _rawCompareEntries(WarehouseHistoryEntry a, WarehouseHistoryEntry b) {
    switch (_sortColumn) {
      case InventoryHistorySortColumn.code:
        return a.code.toLowerCase().compareTo(b.code.toLowerCase());
      case InventoryHistorySortColumn.type:
        return a.type.toLowerCase().compareTo(b.type.toLowerCase());
      case InventoryHistorySortColumn.commodityName:
        return a.commodityName.toLowerCase().compareTo(b.commodityName.toLowerCase());
      case InventoryHistorySortColumn.warehouseCode:
        return a.warehouseCode.toLowerCase().compareTo(b.warehouseCode.toLowerCase());
      case InventoryHistorySortColumn.warehouseName:
        return a.warehouseName.toLowerCase().compareTo(b.warehouseName.toLowerCase());
      case InventoryHistorySortColumn.voucherDate:
        return _compareDates(a.voucherDate, b.voucherDate);
      case InventoryHistorySortColumn.openingStock:
        return _compareNumbers(a.openingStock, b.openingStock);
      case InventoryHistorySortColumn.closingStock:
        return _compareNumbers(a.closingStock, b.closingStock);
      case InventoryHistorySortColumn.lotNumber:
        return a.lotNumber.toLowerCase().compareTo(b.lotNumber.toLowerCase());
    }
  }

  int _compareDates(String left, String right) {
    final leftDate = DateTime.tryParse(left);
    final rightDate = DateTime.tryParse(right);
    if (leftDate != null && rightDate != null) {
      return leftDate.compareTo(rightDate);
    }
    return left.toLowerCase().compareTo(right.toLowerCase());
  }

  int _compareNumbers(String left, String right) {
    final leftValue = _numericValue(left);
    final rightValue = _numericValue(right);
    if (leftValue == rightValue) {
      return 0;
    }
    return leftValue < rightValue ? -1 : 1;
  }

  double _numericValue(String value) {
    final normalized = value.replaceAll(',', '').trim();
    return double.tryParse(normalized) ?? 0;
  }

  Widget _buildFooter(ThemeData theme) {
    if (_isLoading && _displayEntries.isEmpty) {
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
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _fetchPage(reset: _displayEntries.isEmpty),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_displayEntries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.history_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'No inventory history available.',
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
            'Scroll to load more history…',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _InventoryHistoryHeader extends StatelessWidget {
  const _InventoryHistoryHeader({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final InventoryHistorySortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<InventoryHistorySortColumn> onSort;

  static const _columnFlex = [
    3,
    3,
    3,
    3,
    2,
    2,
    2,
    2,
    2,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Code',
            flex: _columnFlex[0],
            theme: theme,
            isActive: sortColumn == InventoryHistorySortColumn.code,
            ascending: sortAscending,
            onTap: () => onSort(InventoryHistorySortColumn.code),
          ),
          SortableHeaderCell(
            label: 'Type',
            flex: _columnFlex[1],
            theme: theme,
            isActive: sortColumn == InventoryHistorySortColumn.type,
            ascending: sortAscending,
            onTap: () => onSort(InventoryHistorySortColumn.type),
          ),
          SortableHeaderCell(
            label: 'Commodity Code',
            flex: _columnFlex[2],
            theme: theme,
            isActive: sortColumn == InventoryHistorySortColumn.commodityName,
            ascending: sortAscending,
            onTap: () => onSort(InventoryHistorySortColumn.commodityName),
          ),
          SortableHeaderCell(
            label: 'Warehouse Code',
            flex: _columnFlex[3],
            theme: theme,
            isActive: sortColumn == InventoryHistorySortColumn.warehouseCode,
            ascending: sortAscending,
            onTap: () => onSort(InventoryHistorySortColumn.warehouseCode),
          ),
          SortableHeaderCell(
            label: 'Warehouse Name',
            flex: _columnFlex[4],
            theme: theme,
            isActive: sortColumn == InventoryHistorySortColumn.warehouseName,
            ascending: sortAscending,
            onTap: () => onSort(InventoryHistorySortColumn.warehouseName),
          ),
          SortableHeaderCell(
            label: 'Voucher Date',
            flex: _columnFlex[5],
            theme: theme,
            isActive: sortColumn == InventoryHistorySortColumn.voucherDate,
            ascending: sortAscending,
            onTap: () => onSort(InventoryHistorySortColumn.voucherDate),
          ),
          SortableHeaderCell(
            label: 'Opening Stock',
            flex: _columnFlex[6],
            theme: theme,
            isActive: sortColumn == InventoryHistorySortColumn.openingStock,
            ascending: sortAscending,
            onTap: () => onSort(InventoryHistorySortColumn.openingStock),
          ),
          SortableHeaderCell(
            label: 'Closing Stock',
            flex: _columnFlex[7],
            theme: theme,
            isActive: sortColumn == InventoryHistorySortColumn.closingStock,
            ascending: sortAscending,
            onTap: () => onSort(InventoryHistorySortColumn.closingStock),
          ),
          SortableHeaderCell(
            label: 'Lot No Number',
            flex: _columnFlex[8],
            theme: theme,
            isActive: sortColumn == InventoryHistorySortColumn.lotNumber,
            ascending: sortAscending,
            onTap: () => onSort(InventoryHistorySortColumn.lotNumber),
          ),
        ],
      ),
    );
  }
}

class _InventoryHistoryRow extends StatelessWidget {
  const _InventoryHistoryRow({
    required this.entry,
    required this.theme,
    required this.showTopBorder,
  });

  final WarehouseHistoryEntry entry;
  final ThemeData theme;
  final bool showTopBorder;

  static const _columnFlex = [
    3,
    3,
    3,
    3,
    2,
    2,
    2,
    2,
    2,
  ];

  @override
  Widget build(BuildContext context) {
    final borderColor = theme.dividerColor.withOpacity(0.6);
    final background = theme.colorScheme.surfaceVariant.withOpacity(0.3);

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(
          top: showTopBorder ? BorderSide(color: borderColor) : BorderSide.none,
          bottom: BorderSide(color: borderColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _DataCell(_displayValue(entry.code), flex: _columnFlex[0]),
          _TypePillCell(entry.type, flex: _columnFlex[1]),
          _DataCell(_displayValue(entry.commodityName), flex: _columnFlex[2]),
          _DataCell(_displayValue(entry.warehouseCode), flex: _columnFlex[3]),
          _DataCell(_displayValue(entry.warehouseName), flex: _columnFlex[4]),
          _DataCell(_displayValue(entry.voucherDate), flex: _columnFlex[5]),
          _DataCell(_displayValue(entry.openingStock), flex: _columnFlex[6]),
          _DataCell(_displayValue(entry.closingStock), flex: _columnFlex[7]),
          _DataCell(_displayValue(entry.lotNumber), flex: _columnFlex[8]),
        ],
      ),
    );
  }

  String _displayValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '—' : trimmed;
  }
}

class _InventoryHistoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  _InventoryHistoryHeaderDelegate({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final InventoryHistorySortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<InventoryHistorySortColumn> onSort;

  static const double _height = 64;

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
        child: _InventoryHistoryHeader(
          theme: theme,
          sortColumn: sortColumn,
          sortAscending: sortAscending,
          onSort: onSort,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _InventoryHistoryHeaderDelegate oldDelegate) {
    return sortColumn != oldDelegate.sortColumn ||
        sortAscending != oldDelegate.sortAscending ||
        theme != oldDelegate.theme;
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell(
    this.value, {
    required this.flex,
    this.textAlign,
  });

  final String value;
  final int flex;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        textAlign: textAlign ?? TextAlign.start,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

class _TypePillCell extends StatelessWidget {
  const _TypePillCell(
    this.value, {
    required this.flex,
  });

  final String value;
  final int flex;

  static const Map<String, String> _labels = {
    '1': 'stock_import',
    '2': 'stock_export',
    '3': 'lost_adjustment',
    '4': 'internal_delivery_note',
    'stock_import': 'stock_import',
    'stock_export': 'stock_export',
    'lost_adjustment': 'lost_adjustment',
    'internal_delivery_note': 'internal_delivery_note',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = value.trim().toLowerCase();
    final label = _labels[normalized] ?? value.trim();
    final colors = _pillColors(theme, normalized);
    final display = label.isEmpty ? '—' : label;

    return Expanded(
      flex: flex,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            display,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  _PillColors _pillColors(ThemeData theme, String normalized) {
    switch (normalized) {
      case '1':
      case 'stock_import':
        return _PillColors(
          background: const Color(0xFFE6F6EE),
          foreground: const Color(0xFF147A42),
        );
      case '2':
      case 'stock_export':
        return _PillColors(
          background: const Color(0xFFFCEAEA),
          foreground: const Color(0xFFB42318),
        );
      case '3':
      case 'lost_adjustment':
        return _PillColors(
          background: const Color(0xFFFFF2DB),
          foreground: const Color(0xFFB54708),
        );
      case '4':
      case 'internal_delivery_note':
        return _PillColors(
          background: const Color(0xFFE8EEFF),
          foreground: const Color(0xFF3448C5),
        );
      default:
        return _PillColors(
          background: theme.colorScheme.surfaceVariant.withOpacity(0.5),
          foreground: theme.colorScheme.onSurfaceVariant,
        );
    }
  }
}

class _PillColors {
  const _PillColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/loss_adjustments_service.dart';
import '../widgets/sortable_header_cell.dart';
import '../widgets/table_filter_bar.dart';

enum StockAdjustmentSortColumn {
  type,
  dateCreated,
  lastUpdated,
  status,
  creator,
}

class StockAdjustmentTab extends StatefulWidget {
  const StockAdjustmentTab({super.key});

  @override
  State<StockAdjustmentTab> createState() => _StockAdjustmentTabState();
}

class _StockAdjustmentTabState extends State<StockAdjustmentTab> {
  final _service = LossAdjustmentsService();
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  final _entriesByKey = <String, LossAdjustmentEntry>{};
  final _displayEntries = <LossAdjustmentEntry>[];
  final _filterController = TextEditingController();

  StockAdjustmentSortColumn _sortColumn = StockAdjustmentSortColumn.dateCreated;
  bool _sortAscending = false;
  String _filterQuery = '';

  static const _perPage = 20;
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
      final result = await _service.fetchLossAdjustments(
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
    } on LossAdjustmentsException catch (error) {
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
                                  'Search by type, status, creator, or date',
                              isFiltering: _filterController.text.isNotEmpty,
                              horizontalController: _horizontalController,
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _StockAdjustmentHeaderDelegate(
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
                                return _StockAdjustmentRow(
                                  entry: entry,
                                  theme: theme,
                                  showTopBorder: index == 0,
                                  onAction: _handleAction,
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

  void _handleSort(StockAdjustmentSortColumn column) {
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

  void _handleAction(String label, LossAdjustmentEntry entry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label is not available yet.')),
    );
  }

  String _entryStorageKey(LossAdjustmentEntry entry) {
    if (entry.id.isNotEmpty) {
      return entry.id;
    }
    return '${entry.type}::${entry.dateCreated}::${entry.lastUpdated}::${entry.creator}';
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
      ..addAll(ordered.where(_matchesFilter));
  }

  bool _matchesFilter(LossAdjustmentEntry entry) {
    if (_filterQuery.isEmpty) {
      return true;
    }
    final query = _filterQuery;
    return entry.type.toLowerCase().contains(query) ||
        entry.dateCreated.toLowerCase().contains(query) ||
        entry.lastUpdated.toLowerCase().contains(query) ||
        entry.status.toLowerCase().contains(query) ||
        entry.creator.toLowerCase().contains(query);
  }

  int _compareEntries(LossAdjustmentEntry a, LossAdjustmentEntry b) {
    final result = _rawCompareEntries(a, b);
    if (result != 0) {
      return _sortAscending ? result : -result;
    }

    final keyCompare = _entryStorageKey(a).compareTo(_entryStorageKey(b));
    return _sortAscending ? keyCompare : -keyCompare;
  }

  int _rawCompareEntries(LossAdjustmentEntry a, LossAdjustmentEntry b) {
    switch (_sortColumn) {
      case StockAdjustmentSortColumn.type:
        return a.type.toLowerCase().compareTo(b.type.toLowerCase());
      case StockAdjustmentSortColumn.dateCreated:
        return _compareDates(a.dateCreated, b.dateCreated);
      case StockAdjustmentSortColumn.lastUpdated:
        return _compareDates(a.lastUpdated, b.lastUpdated);
      case StockAdjustmentSortColumn.status:
        return a.status.toLowerCase().compareTo(b.status.toLowerCase());
      case StockAdjustmentSortColumn.creator:
        return a.creator.toLowerCase().compareTo(b.creator.toLowerCase());
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
            Icon(
              Icons.tune_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No stock adjustments available.',
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
            'Scroll to load more adjustments…',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _StockAdjustmentHeader extends StatelessWidget {
  const _StockAdjustmentHeader({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final StockAdjustmentSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<StockAdjustmentSortColumn> onSort;

  static const _columnFlex = [3, 3, 3, 2, 3, 2];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Type',
            flex: _columnFlex[0],
            theme: theme,
            isActive: sortColumn == StockAdjustmentSortColumn.type,
            ascending: sortAscending,
            onTap: () => onSort(StockAdjustmentSortColumn.type),
          ),
          SortableHeaderCell(
            label: 'Date Created',
            flex: _columnFlex[1],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == StockAdjustmentSortColumn.dateCreated,
            ascending: sortAscending,
            onTap: () => onSort(StockAdjustmentSortColumn.dateCreated),
          ),
          SortableHeaderCell(
            label: 'Last Updated',
            flex: _columnFlex[2],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == StockAdjustmentSortColumn.lastUpdated,
            ascending: sortAscending,
            onTap: () => onSort(StockAdjustmentSortColumn.lastUpdated),
          ),
          SortableHeaderCell(
            label: 'Status',
            flex: _columnFlex[3],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == StockAdjustmentSortColumn.status,
            ascending: sortAscending,
            onTap: () => onSort(StockAdjustmentSortColumn.status),
          ),
          SortableHeaderCell(
            label: 'Creator',
            flex: _columnFlex[4],
            theme: theme,
            isActive: sortColumn == StockAdjustmentSortColumn.creator,
            ascending: sortAscending,
            onTap: () => onSort(StockAdjustmentSortColumn.creator),
          ),
          const SizedBox(width: 12),
          SortableHeaderCell(
            label: 'Options',
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

class _StockAdjustmentHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StockAdjustmentHeaderDelegate({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final StockAdjustmentSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<StockAdjustmentSortColumn> onSort;

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
        child: _StockAdjustmentHeader(
          theme: theme,
          sortColumn: sortColumn,
          sortAscending: sortAscending,
          onSort: onSort,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StockAdjustmentHeaderDelegate oldDelegate) {
    return sortColumn != oldDelegate.sortColumn ||
        sortAscending != oldDelegate.sortAscending ||
        theme != oldDelegate.theme;
  }
}

class _StockAdjustmentRow extends StatelessWidget {
  const _StockAdjustmentRow({
    required this.entry,
    required this.theme,
    required this.showTopBorder,
    required this.onAction,
  });

  final LossAdjustmentEntry entry;
  final ThemeData theme;
  final bool showTopBorder;
  final void Function(String label, LossAdjustmentEntry entry) onAction;

  static const _columnFlex = [3, 3, 3, 2, 3, 2];

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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          _DataCell(_displayValue(entry.type), flex: _columnFlex[0]),
          _DataCell(
            _displayValue(entry.dateCreated),
            flex: _columnFlex[1],
            textAlign: TextAlign.center,
          ),
          _DataCell(
            _displayValue(entry.lastUpdated),
            flex: _columnFlex[2],
            textAlign: TextAlign.center,
          ),
          _DataCell(
            _displayValue(entry.status),
            flex: _columnFlex[3],
            textAlign: TextAlign.center,
          ),
          _DataCell(_displayValue(entry.creator), flex: _columnFlex[4]),
          const SizedBox(width: 12),
          Expanded(
            flex: _columnFlex[5],
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility_outlined),
                    tooltip: 'View adjustment',
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    onPressed: () => onAction('View', entry),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit adjustment',
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    onPressed: () => onAction('Edit', entry),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete adjustment',
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    color: theme.colorScheme.error,
                    onPressed: () => onAction('Delete', entry),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _displayValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '—' : trimmed;
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

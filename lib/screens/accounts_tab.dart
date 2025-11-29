import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/accounts_service.dart';
import '../widgets/sortable_header_cell.dart';
import '../widgets/table_filter_bar.dart';

enum AccountsSortColumn { name, parent, type, detailType, balance }

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key});

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  final _service = AccountsService();
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  final _displayAccounts = <_AccountDisplay>[];
  final _accountsById = <String, Account>{};
  final _accountNamesById = <String, String>{};
  final _filterController = TextEditingController();

  AccountsSortColumn _sortColumn = AccountsSortColumn.name;
  bool _sortAscending = true;
  String _filterQuery = '';

  static const _perPage = 20;
  // Ensures the five account columns retain enough space before horizontal
  // scrolling is required, avoiding overlap on narrow screens.
  static const double _minTableWidth = 960;

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
      final result = await _service.fetchAccounts(
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
          _accountsById
            ..clear()
            ..addEntries(
              result.accounts.map(
                (account) => MapEntry(_accountStorageKey(account), account),
              ),
            );
          _accountNamesById.clear();
        } else {
          for (final account in result.accounts) {
            _accountsById[_accountStorageKey(account)] = account;
          }
        }

        _mergeAccountNames(result.namesById);
        _rebuildDisplayAccounts();
        _error = null;
        _hasMore = result.hasMore;
        _nextPage = result.hasMore ? pageToLoad + 1 : pageToLoad;
      });
    } on AccountsException catch (error) {
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
          final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : _minTableWidth;
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
                              hintText: 'Search by name, parent, or type',
                              isFiltering: _filterController.text.isNotEmpty,
                              horizontalController: _horizontalController,
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _AccountsHeaderDelegate(
                              theme: theme,
                              sortColumn: _sortColumn,
                              sortAscending: _sortAscending,
                              onSort: _handleSort,
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final entry = _displayAccounts[index];
                                final account = entry.account;
                                return _AccountsRow(
                                  account: account,
                                  theme: theme,
                                  showTopBorder: index == 0,
                                  parentName: _resolveParentName(account),
                                  indent: entry.depth * 24.0,
                                );
                              },
                              childCount: _displayAccounts.length,
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

  void _handleSort(AccountsSortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _rebuildDisplayAccounts();
    });
  }

  void _handleFilterChanged(String value) {
    setState(() {
      _filterQuery = value.trim().toLowerCase();
      _rebuildDisplayAccounts();
    });
  }

  String _resolveParentName(Account account) {
    final parentId = account.parentAccountId;
    if (parentId == null) {
      return '—';
    }
    final trimmed = parentId.trim();
    if (trimmed.isEmpty || trimmed == '0') {
      return '—';
    }
    return _accountNamesById[trimmed] ?? '—';
  }

  String _accountStorageKey(Account account) {
    final id = account.id.trim();
    if (id.isNotEmpty) {
      return id;
    }
    final name = account.name.trim();
    final parent = account.parentAccountId?.trim() ?? '';
    return '$name::$parent';
  }

  void _rebuildDisplayAccounts() {
    final ordered = _buildDisplayAccounts(_accountsById.values);
    if (_filterQuery.isEmpty) {
      _displayAccounts
        ..clear()
        ..addAll(ordered);
      return;
    }

    _displayAccounts
      ..clear()
      ..addAll(
        ordered.where((entry) => _matchesFilter(entry.account)),
      );
  }

  bool _matchesFilter(Account account) {
    if (_filterQuery.isEmpty) {
      return true;
    }
    final query = _filterQuery;
    if (account.name.toLowerCase().contains(query)) {
      return true;
    }
    final parent = _resolveParentName(account).toLowerCase();
    if (parent.contains(query)) {
      return true;
    }
    final type = (account.typeName ?? '').toLowerCase();
    if (type.contains(query)) {
      return true;
    }
    final detailType = (account.detailTypeName ?? '').toLowerCase();
    if (detailType.contains(query)) {
      return true;
    }
    final balance = account.primaryBalance.toLowerCase();
    return balance.contains(query);
  }

  List<_AccountDisplay> _buildDisplayAccounts(Iterable<Account> accounts) {
    final compare = (Account a, Account b) => _compareAccounts(a, b);

    final byId = <String, Account>{
      for (final account in accounts)
        if (account.id.trim().isNotEmpty) account.id.trim(): account,
    };

    final children = <String, List<Account>>{};
    final roots = <Account>[];

    for (final account in accounts) {
      final parentId = account.parentAccountId?.trim();
      final accountId = account.id.trim();

      if (parentId == null || parentId.isEmpty || parentId == '0' || !byId.containsKey(parentId)) {
        roots.add(account);
        continue;
      }

      children.putIfAbsent(parentId, () => <Account>[]).add(account);

      if (accountId.isNotEmpty && !byId.containsKey(accountId)) {
        byId[accountId] = account;
      }
    }

    roots.sort(compare);
    for (final entry in children.entries) {
      entry.value.sort(compare);
    }

    final visited = <String>{};
    final visitedNoId = <Account>{};
    final ordered = <_AccountDisplay>[];

    void visit(Account account, int depth) {
      final accountId = account.id.trim();
      if (accountId.isNotEmpty) {
        if (!visited.add(accountId)) {
          return;
        }
      } else {
        if (!visitedNoId.add(account)) {
          return;
        }
      }

      ordered.add(_AccountDisplay(account: account, depth: depth));

      final childList = children[accountId];
      if (childList == null) {
        return;
      }
      for (final child in childList) {
        visit(child, depth + 1);
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }

    // Include any unvisited accounts (e.g., missing or cyclic parents)
    final remaining = accounts.where((account) {
      final accountId = account.id.trim();
      return accountId.isNotEmpty
          ? !visited.contains(accountId)
          : !visitedNoId.contains(account);
    }).toList()
      ..sort(compare);

    for (final account in remaining) {
      visit(account, 0);
    }

    return ordered;
  }

  int _compareAccounts(Account a, Account b) {
    final result = _rawCompareAccounts(a, b);
    if (result != 0) {
      return _sortAscending ? result : -result;
    }

    final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (nameCompare != 0) {
      return _sortAscending ? nameCompare : -nameCompare;
    }

    final idCompare = a.id.toLowerCase().compareTo(b.id.toLowerCase());
    return _sortAscending ? idCompare : -idCompare;
  }

  int _rawCompareAccounts(Account a, Account b) {
    switch (_sortColumn) {
      case AccountsSortColumn.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case AccountsSortColumn.parent:
        return _resolveParentName(a)
            .toLowerCase()
            .compareTo(_resolveParentName(b).toLowerCase());
      case AccountsSortColumn.type:
        return (a.typeName ?? '—')
            .toLowerCase()
            .compareTo((b.typeName ?? '—').toLowerCase());
      case AccountsSortColumn.detailType:
        return (a.detailTypeName ?? '—')
            .toLowerCase()
            .compareTo((b.detailTypeName ?? '—').toLowerCase());
      case AccountsSortColumn.balance:
        final left = _balanceValue(a);
        final right = _balanceValue(b);
        if (left == right) {
          return 0;
        }
        return left < right ? -1 : 1;
    }
  }

  double _balanceValue(Account account) {
    final normalized = account.primaryBalance.replaceAll(',', '').trim();
    return double.tryParse(normalized) ?? 0;
  }

  void _mergeAccountNames(Map<String, String> names) {
    for (final entry in names.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      _accountNamesById[key] = entry.value;
    }
  }

  Widget _buildFooter(ThemeData theme) {
    if (_isLoading && _displayAccounts.isEmpty) {
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
              onPressed: () => _fetchPage(reset: _displayAccounts.isEmpty),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_displayAccounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.account_balance_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'No accounts available.',
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
            'Scroll to load more accounts…',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _AccountsHeader extends StatelessWidget {
  const _AccountsHeader({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final AccountsSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<AccountsSortColumn> onSort;

  static const _columnFlex = [4, 3, 3, 3, 2];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Name',
            flex: _columnFlex[0],
            theme: theme,
            isActive: sortColumn == AccountsSortColumn.name,
            ascending: sortAscending,
            onTap: () => onSort(AccountsSortColumn.name),
          ),
          SortableHeaderCell(
            label: 'Parent Account',
            flex: _columnFlex[1],
            theme: theme,
            isActive: sortColumn == AccountsSortColumn.parent,
            ascending: sortAscending,
            onTap: () => onSort(AccountsSortColumn.parent),
          ),
          SortableHeaderCell(
            label: 'Type',
            flex: _columnFlex[2],
            theme: theme,
            isActive: sortColumn == AccountsSortColumn.type,
            ascending: sortAscending,
            onTap: () => onSort(AccountsSortColumn.type),
          ),
          SortableHeaderCell(
            label: 'Detail Type',
            flex: _columnFlex[3],
            theme: theme,
            isActive: sortColumn == AccountsSortColumn.detailType,
            ascending: sortAscending,
            onTap: () => onSort(AccountsSortColumn.detailType),
          ),
          SortableHeaderCell(
            label: 'Primary Balance',
            flex: _columnFlex[4],
            theme: theme,
            textAlign: TextAlign.end,
            isActive: sortColumn == AccountsSortColumn.balance,
            ascending: sortAscending,
            onTap: () => onSort(AccountsSortColumn.balance),
          ),
        ],
      ),
    );
  }
}

class _AccountsRow extends StatelessWidget {
  const _AccountsRow({
    required this.account,
    required this.theme,
    required this.showTopBorder,
    required this.parentName,
    required this.indent,
  });

  final Account account;
  final ThemeData theme;
  final bool showTopBorder;
  final String parentName;
  final double indent;

  static const _columnFlex = [4, 3, 3, 3, 2];

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
          _DataCell(
            account.name,
            flex: _columnFlex[0],
            indent: indent,
          ),
          _DataCell(parentName, flex: _columnFlex[1]),
          _DataCell(account.typeName ?? '—', flex: _columnFlex[2]),
          _DataCell(account.detailTypeName ?? '—', flex: _columnFlex[3]),
          _DataCell(account.primaryBalance, flex: _columnFlex[4], textAlign: TextAlign.end),
        ],
      ),
    );
  }
}

class _AccountsHeaderDelegate extends SliverPersistentHeaderDelegate {
  _AccountsHeaderDelegate({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final AccountsSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<AccountsSortColumn> onSort;

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
        child: _AccountsHeader(
          theme: theme,
          sortColumn: sortColumn,
          sortAscending: sortAscending,
          onSort: onSort,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _AccountsHeaderDelegate oldDelegate) {
    return sortColumn != oldDelegate.sortColumn ||
        sortAscending != oldDelegate.sortAscending ||
        theme != oldDelegate.theme;
  }
}

class _AccountDisplay {
  const _AccountDisplay({required this.account, required this.depth});

  final Account account;
  final int depth;
}

class _DataCell extends StatelessWidget {
  const _DataCell(
    this.value, {
    required this.flex,
    this.textAlign,
    this.indent = 0.0,
  });

  final String value;
  final int flex;
  final TextAlign? textAlign;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(left: indent),
        child: Text(
          value,
          textAlign: textAlign ?? TextAlign.start,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}

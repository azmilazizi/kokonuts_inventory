import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';

import 'inventory_history_tab.dart';
import 'stock_adjustment_tab.dart';
import 'inventory_tab.dart';
import 'purchase_orders_tab.dart';

import '../services/purchase_orders_service.dart';
import '../widgets/add_purchase_order_dialog.dart';
import '../widgets/post_dialog.dart';
import '../widgets/stock_adjustment_dialog.dart';
import '../widgets/app_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _controller;
  late final List<_HomeTab> _tabs;
  final GlobalKey<PurchaseOrdersTabState> _purchaseOrdersTabKey =
      GlobalKey<PurchaseOrdersTabState>();
  final GlobalKey<StockAdjustmentTabState> _stockAdjustmentTabKey =
      GlobalKey<StockAdjustmentTabState>();

  @override
  void initState() {
    super.initState();
    _tabs = [
      _HomeTab(
        title: 'Pending Receive',
        icon: Icons.local_shipping_outlined,
        builder: (_, __) => PurchaseOrdersTab(key: _purchaseOrdersTabKey),
      ),
      _HomeTab(
        title: 'Inventory',
        icon: Icons.inventory_2_outlined,
        builder: (_, __) => const InventoryTab(),
      ),
      _HomeTab(
        title: 'Stock Adjustment',
        icon: Icons.qr_code_scanner_outlined,
        builder: (_, __) => StockAdjustmentTab(key: _stockAdjustmentTabKey),
      ),
      _HomeTab(
        title: 'Inventory History',
        icon: Icons.history_outlined,
        builder: (_, __) => const InventoryHistoryTab(),
      ),
    ];
    _controller = TabController(
        length: _tabs.length, vsync: this, initialIndex: _tabs.length - 1)
      ..addListener(_handleTabSelection);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTabSelection);
    _controller.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (!_controller.indexIsChanging) {
      setState(() {});
    }
  }

  Future<void> _openAddModal(BuildContext context, String tabTitle) async {
    if (_controller.index == 0) {
      final createdOrder = await showDialog<PurchaseOrder>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AddPurchaseOrderDialog(),
      );

      if (!mounted) {
        return;
      }

      if (createdOrder != null) {
        final normalizedNumber = createdOrder.number.trim();
        final orderLabel =
            normalizedNumber.isEmpty || normalizedNumber == '—'
                ? createdOrder.name
                : normalizedNumber;
        _purchaseOrdersTabKey.currentState?.insertCreatedPurchaseOrder(
          createdOrder,
          successMessage: orderLabel.trim().isEmpty
              ? 'Purchase order created.'
              : 'Purchase order $orderLabel created.',
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    switch (_controller.index) {
      case 2:
        final didSave = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const StockAdjustmentDialog(
            title: 'Stocktake',
          ),
        );
        if (didSave == true && mounted) {
          _stockAdjustmentTabKey.currentState?.refreshStockAdjustments();
        }
        break;
      default:
        await showDialog<void>(
          context: context,
          builder: (context) => PostDialog(
            title: 'Create $tabTitle',
            apiPath: 'https://crm.kokonuts.my',
            description:
                'Add the correct endpoint and payload for this tab when ready.',
            samplePayload: const {
              'example': 'value',
            },
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final AppState appState = AppStateScope.of(context);

    final AppState scopedAppState = AppStateScope.of(context);

    final _HomeTab currentTab = _tabs[_controller.index];
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    final overlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: theme.colorScheme.surface,
            statusBarBrightness: Brightness.dark,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: theme.colorScheme.surface,
            statusBarBrightness: Brightness.light,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 28),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  currentTab.title,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (isCompact)
               _HeaderMenuButton(appState: appState)
            else ...[
               _ThemeModeButton(appState: appState),
               IconButton(
                 tooltip: 'Log out',
                 icon: const Icon(Icons.logout),
                 onPressed: appState.logout,
               ),
            ],
            const SizedBox(width: 8),
          ],
        ),
        body: ColoredBox(
          color: theme.colorScheme.surface,
          child: SafeArea(
            top: true,
            bottom: false,
            child: TabBarView(
              controller: _controller,
              children: _tabs
                  .map(
                    (tab) => tab.builder?.call(context, scopedAppState) ??
                        _HomeTabPlaceholder(
                          title: tab.title,
                          icon: tab.icon,
                        ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
        bottomNavigationBar: Material(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _controller,
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.7),
            tabs: _tabs
                .map(
                  (tab) => Tab(
                    icon: Icon(tab.icon, size: 26),
                    iconMargin: const EdgeInsets.only(bottom: 8),
                    height: 60,
                  ),
                )
                .toList(growable: false),
          ),
        ),
        floatingActionButton: _controller.index == 1
            ? null
            : FloatingActionButton(
                tooltip: 'Add ${currentTab.title}',
                onPressed: () => _openAddModal(context, currentTab.title),
                child: const Icon(Icons.add),
              ),
      ),
    );
  }
}

class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final currentMode = appState.themeMode;
    IconData icon;
    String tooltip;

    switch (currentMode) {
      case ThemeMode.dark:
        icon = Icons.dark_mode_outlined;
        tooltip = 'Dark mode';
        break;
      case ThemeMode.light:
        icon = Icons.light_mode_outlined;
        tooltip = 'Light mode';
        break;
      case ThemeMode.system:
        icon = Icons.brightness_auto_outlined;
        tooltip = 'System theme';
        break;
    }

    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: () => _selectTheme(context, appState),
    );
  }
}

Future<void> _selectTheme(BuildContext context, AppState appState) async {
  final theme = Theme.of(context);
  final selectedMode = await showDialog<ThemeMode>(
    context: context,
    builder: (context) {
      const options = [
        MapEntry(ThemeMode.light, 'Light'),
        MapEntry(ThemeMode.dark, 'Dark'),
        MapEntry(ThemeMode.system, 'System'),
      ];

      return AlertDialog(
        title: const Text('Select theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (option) => RadioListTile<ThemeMode>(
                  value: option.key,
                  groupValue: appState.themeMode,
                  onChanged: (value) => Navigator.of(context).pop(value),
                  title: Text(option.value, style: theme.textTheme.bodyLarge),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );

  if (selectedMode != null) {
    appState.updateThemeMode(selectedMode);
  }
}

class _HeaderMenuButton extends StatelessWidget {
  const _HeaderMenuButton({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final modeLabel = _themeModeLabel(appState.themeMode);
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(modeLabel.icon),
                    title: Text('Theme: ${modeLabel.tooltip}'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _selectTheme(context, appState);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Log out'),
                    onTap: () {
                      Navigator.of(context).pop();
                      appState.logout();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ThemeModeLabel {
  const _ThemeModeLabel({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;
}

_ThemeModeLabel _themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.dark:
      return const _ThemeModeLabel(
        icon: Icons.dark_mode_outlined,
        tooltip: 'Dark mode',
      );
    case ThemeMode.light:
      return const _ThemeModeLabel(
        icon: Icons.light_mode_outlined,
        tooltip: 'Light mode',
      );
    case ThemeMode.system:
      return const _ThemeModeLabel(
        icon: Icons.brightness_auto_outlined,
        tooltip: 'System theme',
      );
  }
}


class _HomeTab {
  const _HomeTab({required this.title, required this.icon, this.builder});

  final String title;
  final IconData icon;
  final Widget Function(BuildContext context, AppState appState)? builder;
}

class _HomeTabPlaceholder extends StatelessWidget {
  const _HomeTabPlaceholder({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Content for the $title tab will appear here.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

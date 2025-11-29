import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../widgets/app_logo.dart';
import '../widgets/home_tab_placeholder.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _controller;
  late final List<_HomeTab> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      _HomeTab(
        title: 'Purchase Orders',
        icon: Icons.receipt_long_outlined,
        builder: (_, __) => const HomeTabPlaceholder(
          title: 'Purchase Orders',
          icon: Icons.receipt_long_outlined,
        ),
      ),
      _HomeTab(
        title: 'Goods Receipt',
        icon: Icons.archive_outlined,
        builder: (_, __) => const HomeTabPlaceholder(
          title: 'Goods Receipt',
          icon: Icons.archive_outlined,
        ),
      ),
      _HomeTab(
        title: 'Loss & Adjustment',
        icon: Icons.tune_outlined,
        builder: (_, __) => const HomeTabPlaceholder(
          title: 'Loss & Adjustment',
          icon: Icons.tune_outlined,
        ),
      ),
      _HomeTab(
        title: 'Items',
        icon: Icons.grid_view_outlined,
        builder: (_, __) => const HomeTabPlaceholder(
          title: 'Items',
          icon: Icons.grid_view_outlined,
        ),
      ),
      _HomeTab(
        title: 'Overview',
        icon: Icons.dashboard_outlined,
        builder: (_, __) => const HomeTabPlaceholder(
          title: 'Overview',
          icon: Icons.dashboard_outlined,
        ),
      ),
    ];
    _controller = TabController(
        length: _tabs.length, vsync: this, initialIndex: 0)
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
    // Placeholder for add modal
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create $tabTitle'),
        content: const Text('Add functionality to create items here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
                        HomeTabPlaceholder(
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
        floatingActionButton: FloatingActionButton(
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

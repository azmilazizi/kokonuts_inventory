import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import 'app_logo.dart';

/// Displays the application logo next to a page title.
class TabPageHeader extends StatelessWidget {
  const TabPageHeader({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 8),
    this.logoSize = 28,
    this.titleStyle,
  });

  final String title;
  final EdgeInsetsGeometry padding;
  final double logoSize;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = AppStateScope.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final modeLabel = _themeModeLabel(appState.themeMode);
    final themeTooltip = 'Theme: ${modeLabel.tooltip}';

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppLogo(size: logoSize),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle ??
                        theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isCompact)
            _HeaderMenuButton(
              themeLabel: themeTooltip,
              themeIcon: modeLabel.icon,
              onSelectTheme: () => _selectTheme(context, appState),
              onLogout: appState.logout,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: themeTooltip,
                  icon: Icon(modeLabel.icon),
                  onPressed: () => _selectTheme(context, appState),
                ),
                IconButton(
                  tooltip: 'Log out',
                  icon: const Icon(Icons.logout),
                  onPressed: appState.logout,
                ),
              ],
            ),
        ],
      ),
    );
  }
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

Future<void> _selectTheme(BuildContext context, AppState appState) async {
  final selectedMode = await showDialog<ThemeMode>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      const options = <_ThemeModeOption>[
        _ThemeModeOption(mode: ThemeMode.light, label: 'Light'),
        _ThemeModeOption(mode: ThemeMode.dark, label: 'Dark'),
        _ThemeModeOption(mode: ThemeMode.system, label: 'System'),
      ];

      return AlertDialog(
        title: const Text('Select theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (option) => RadioListTile<ThemeMode>(
                  value: option.mode,
                  groupValue: appState.themeMode,
                  onChanged: (value) => Navigator.of(context).pop(value),
                  title: Text(option.label, style: theme.textTheme.bodyLarge),
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
  const _HeaderMenuButton({
    required this.themeLabel,
    required this.themeIcon,
    required this.onSelectTheme,
    required this.onLogout,
  });

  final String themeLabel;
  final IconData themeIcon;
  final VoidCallback onSelectTheme;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
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
                    leading: Icon(themeIcon),
                    title: Text(themeLabel),
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelectTheme();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Log out'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onLogout();
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

class _ThemeModeOption {
  const _ThemeModeOption({required this.mode, required this.label});

  final ThemeMode mode;
  final String label;
}

class TabPageHeaderDelegate extends SliverPersistentHeaderDelegate {
  const TabPageHeaderDelegate({
    required this.title,
    this.backgroundColor,
    this.horizontalController,
  });

  final String title;
  final Color? backgroundColor;
  final ScrollController? horizontalController;

  static const double _height = 64;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final controller = horizontalController;

    if (controller == null) {
      return ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width,
            height: maxExtent,
            child: _buildHeaderContent(context, overlapsContent),
          ),
        ),
      );
    }

    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final offset = controller.hasClients ? controller.offset : 0.0;
          return Align(
            alignment: Alignment.centerLeft,
            child: Transform.translate(
              offset: Offset(offset, 0),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width,
                height: maxExtent,
                child: _buildHeaderContent(context, overlapsContent),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(covariant TabPageHeaderDelegate oldDelegate) {
    return title != oldDelegate.title ||
        backgroundColor != oldDelegate.backgroundColor ||
        horizontalController != oldDelegate.horizontalController;
  }

  Widget _buildHeaderContent(BuildContext context, bool overlapsContent) {
    final theme = Theme.of(context);
    return Material(
      color: backgroundColor ?? theme.colorScheme.surface,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: theme.shadowColor.withOpacity(0.15),
      child: TabPageHeader(
        title: title,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        logoSize: 28,
        titleStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

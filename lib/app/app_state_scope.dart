import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Provides access to [AppState] via the widget tree.
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({super.key, required AppState notifier, required Widget child})
      : super(notifier: notifier, child: child);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in context');
    return scope!.notifier!;
  }

  @override
  bool updateShouldNotify(covariant AppStateScope oldWidget) => notifier != oldWidget.notifier;
}

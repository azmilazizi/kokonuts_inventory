import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_state.dart';
import 'app/app_state_scope.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/session_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final sessionManager = SessionManager();
  final authService = AuthService(sessionManager: sessionManager);
  final appState = AppState(authService: authService, sessionManager: sessionManager);

  runApp(KokonutsInventoryApp(appState: appState));
}

class KokonutsInventoryApp extends StatefulWidget {
  const KokonutsInventoryApp({super.key, required this.appState});

  final AppState appState;

  @override
  State<KokonutsInventoryApp> createState() => _KokonutsInventoryAppState();
}

class _KokonutsInventoryAppState extends State<KokonutsInventoryApp> {
  late final AppState _appState = widget.appState;

  @override
  void initState() {
    super.initState();
    unawaited(_appState.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      notifier: _appState,
      child: AnimatedBuilder(
        animation: _appState,
        builder: (context, _) {
          return MaterialApp(
            title: 'Kokonuts Inventory',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            themeMode: _appState.themeMode,
            home: _buildHome(),
          );
        },
      ),
    );
  }

  Widget _buildHome() {
    if (!_appState.isInitialized) {
      return const SplashScreen();
    }

    if (_appState.isLoggedIn) {
      return const HomeScreen();
    }

    return const LoginScreen();
  }
}

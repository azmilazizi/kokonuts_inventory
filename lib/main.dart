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
              colorScheme: const ColorScheme.dark(
                primary: Colors.orange,
                onPrimary: Colors.black,
                primaryContainer: Color(0xFFBF5B00),
                onPrimaryContainer: Colors.white,
                secondary: Colors.orangeAccent,
                onSecondary: Colors.black,
                surface: Color(0xFF1C1C1E),
                onSurface: Color(0xFFE5E5EA),
                surfaceContainerHighest: Color(0xFF2C2C2E),
                outline: Color(0xFF636366),
              ),
              useMaterial3: true,
              snackBarTheme: const SnackBarThemeData(
                behavior: SnackBarBehavior.fixed,
              ),
            ),
            themeMode: ThemeMode.dark,
            home: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _buildHome(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHome() {
    if (!_appState.isInitialized) {
      return const SplashScreen(key: ValueKey('splash'));
    }

    if (_appState.isLoggedIn) {
      return const HomeScreen(key: ValueKey('home'));
    }

    return const LoginScreen(key: ValueKey('login'));
  }
}

import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../widgets/app_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _barOpacity;
  bool _initStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _barOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initStarted) {
      _initStarted = true;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final appState = AppStateScope.of(context);
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 1500)),
      appState.initialize(),
    ]);
    if (!mounted) return;
    appState.setInitialized();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: FadeTransition(
                opacity: _logoOpacity,
                child: const AppLogo(size: 120),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 56),
            child: FadeTransition(
              opacity: _barOpacity,
              child: const SizedBox(
                width: 120,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

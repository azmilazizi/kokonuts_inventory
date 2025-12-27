import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/auth_service.dart';
import '../widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  bool _isSubmitting = false;
  String? _error;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    _usernameFocusNode.addListener(() {
      setState(() {});
    });
    _usernameController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _fieldErrors = {};
      _error = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final appState = AppStateScope.of(context);

    try {
      final rawUsername = _usernameController.text.trim();
      final normalizedUsername =
          rawUsername.endsWith('@kokonuts.my') ? rawUsername : '${rawUsername}@kokonuts.my';
      if (normalizedUsername != _usernameController.text) {
        _usernameController.text = normalizedUsername;
        _usernameController.selection = TextSelection.collapsed(offset: normalizedUsername.length);
      }
      await appState.login(
        username: normalizedUsername,
        password: _passwordController.text,
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      final parsedFieldErrors = _mapFieldErrors(error.fieldErrors);
      final generalMessages = _extractGeneralMessages(error.fieldErrors);

      setState(() {
        _fieldErrors = parsedFieldErrors;
        final resolvedMessages = <String>[];
        if (generalMessages.isNotEmpty) {
          resolvedMessages.add(generalMessages.join('\n'));
        }
        final trimmedMessage = error.message.trim();
        final isFallback = trimmedMessage.startsWith('Login failed with status code');
        if (trimmedMessage.isNotEmpty && (!isFallback || (resolvedMessages.isEmpty && parsedFieldErrors.isEmpty))) {
          resolvedMessages.add(trimmedMessage);
        }
        _error = resolvedMessages.isEmpty ? null : resolvedMessages.toSet().join('\n');
      });
      _formKey.currentState?.validate();
    } catch (_) {
      setState(() {
        _error = 'An unexpected error occurred. Please try again later.';
        _fieldErrors = {};
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Map<String, String> _mapFieldErrors(Map<String, List<String>> source) {
    final aggregated = <String, List<String>>{};
    source.forEach((key, messages) {
      final cleanedMessages = messages
          .map((message) => message.trim())
          .where((message) => message.isNotEmpty)
          .toList();
      if (cleanedMessages.isEmpty) {
        return;
      }
      final normalizedKey = key.toLowerCase();
      if (normalizedKey.contains('user') || normalizedKey.contains('email')) {
        aggregated.update(
          'username',
          (existing) => [...existing, ...cleanedMessages],
          ifAbsent: () => List<String>.from(cleanedMessages),
        );
      } else if (normalizedKey.contains('password')) {
        aggregated.update(
          'password',
          (existing) => [...existing, ...cleanedMessages],
          ifAbsent: () => List<String>.from(cleanedMessages),
        );
      }
    });

    return aggregated.map((field, messages) {
      final uniqueMessages = <String>{};
      uniqueMessages.addAll(messages);
      return MapEntry(field, uniqueMessages.join('\n'));
    });
  }

  List<String> _extractGeneralMessages(Map<String, List<String>> source) {
    final general = <String>{};
    source.forEach((key, messages) {
      final normalizedKey = key.toLowerCase();
      if (normalizedKey.contains('user') || normalizedKey.contains('email') || normalizedKey.contains('password')) {
        return;
      }
      general.addAll(
        messages
            .map((message) => message.trim())
            .where((message) => message.isNotEmpty),
      );
    });
    return general.toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.center,
                    child: AppLogo(size: 96),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome back',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to continue to Kokonuts Inventory.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _usernameController,
                    focusNode: _usernameFocusNode,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      border: const OutlineInputBorder(),
                      suffixText: _usernameFocusNode.hasFocus || _usernameController.text.trim().isNotEmpty
                          ? '@kokonuts.my'
                          : null,
                      suffixStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_fieldErrors.containsKey('username')) {
                        setState(() {
                          _fieldErrors.remove('username');
                        });
                        _formKey.currentState?.validate();
                      }
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your username.';
                      }
                      final fieldError = _fieldErrors['username'];
                      if (fieldError != null && fieldError.isNotEmpty) {
                        return fieldError;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    onFieldSubmitted: (_) => _handleLogin(),
                    onChanged: (_) {
                      if (_fieldErrors.containsKey('password')) {
                        setState(() {
                          _fieldErrors.remove('password');
                        });
                        _formKey.currentState?.validate();
                      }
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password.';
                      }
                      final fieldError = _fieldErrors['password'];
                      if (fieldError != null && fieldError.isNotEmpty) {
                        return fieldError;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(
                    onPressed: _isSubmitting ? null : _handleLogin,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

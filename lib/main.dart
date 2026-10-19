import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_state.dart';
import 'data/database.dart';
import 'screens/home_screen.dart';
import 'services/drive_backup.dart';

const brandColor = Color(0xFFF2675A);

ThemeData appTheme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: brandColor, brightness: b, primary: brandColor),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw a screen right away and do the setup behind it, so a slow or failing
  // step shows up on screen instead of leaving the splash stuck.
  runApp(const StartupApp());
}

/// Opens settings and the database, then shows [CashbookApp]. Shows progress
/// and any error while doing so.
class StartupApp extends StatefulWidget {
  const StartupApp({super.key});

  @override
  State<StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<StartupApp> {
  AppState? _state;
  String _step = 'Starting…';
  Object? _error;
  StackTrace? _stack;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<T> _run<T>(String step, Future<T> Function() f) {
    if (mounted) setState(() => _step = step);
    return f().timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException('"$step" did not finish within 20 seconds'),
    );
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _slow = false;
    });
    final slowTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _slow = true);
    });
    try {
      final prefs = await _run('Loading settings', SharedPreferences.getInstance);
      final db = await _run('Opening database', () => AppDatabase.open());
      final state = AppState(db, prefs);
      await _run('Loading accounts', state.load);
      if (!mounted) return;
      setState(() => _state = state);
      // Daily Google Drive backup, in the background.
      unawaited(DriveBackup(prefs).autoBackupIfDue(db));
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _error = e;
          _stack = st;
        });
      }
    } finally {
      slowTimer.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state != null) return CashbookApp(state: state);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _error == null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      if (_slow) Text(_step),
                    ])
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: brandColor, size: 40),
                          const SizedBox(height: 8),
                          Text('Cashbook could not start', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text('Failed while: $_step'),
                          const SizedBox(height: 8),
                          SelectableText('$_error\n\n${_stack ?? ''}', style: const TextStyle(fontSize: 11)),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _start, child: const Text('Try again')),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class CashbookApp extends StatelessWidget {
  const CashbookApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: 'Cashbook',
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}

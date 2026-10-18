import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_state.dart';
import 'data/database.dart';
import 'screens/home_screen.dart';
import 'services/drive_backup.dart';

const brandColor = Color(0xFFF2675A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final db = await AppDatabase.open();
  final state = AppState(db, prefs);
  await state.load();
  runApp(CashbookApp(state: state));
  // Daily Google Drive backup, in the background.
  DriveBackup(prefs).autoBackupIfDue(db);
}

class CashbookApp extends StatelessWidget {
  const CashbookApp({super.key, required this.state});

  final AppState state;

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brandColor, brightness: b, primary: brandColor),
        appBarTheme: const AppBarTheme(centerTitle: false),
      );

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: 'Cashbook',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'providers/stats_provider.dart';
import 'screens/setup_screen.dart';
import 'screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsProvider();
  await settings.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => StatsProvider()),
      ],
      child: const NotifyAIApp(),
    ),
  );
}

class NotifyAIApp extends StatelessWidget {
  const NotifyAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      title: 'Notify AI',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode == 1
          ? ThemeMode.light
          : settings.themeMode == 2
              ? ThemeMode.system
              : ThemeMode.dark,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: const _AppEntry(),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF6B9E78),
        secondary: Color(0xFF6B9E78),
        surface: Color(0xFF1E1E1E),
        background: Color(0xFF121212),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF121212),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w500, color: Colors.white),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF1A1A1A),
        indicatorColor: const Color(0xFF2A3A2E),
        labelTextStyle: MaterialStateProperty.all(
          const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected)
                ? const Color(0xFF6B9E78)
                : Colors.white38),
        trackColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected)
                ? const Color(0xFF4A7A56)
                : Colors.white12),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected)
                ? const Color(0xFF6B9E78)
                : Colors.transparent),
        checkColor: MaterialStateProperty.all(Colors.white),
        side: const BorderSide(color: Colors.white38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6B9E78)),
        ),
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6B9E78),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      useMaterial3: true,
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF6B9E78),
        secondary: Color(0xFF6B9E78),
        surface: Color(0xFFFFFFFF),
        background: Color(0xFFF5F5F5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w500, color: Colors.black87),
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        indicatorColor: const Color(0xFFE8F5E9),
        labelTextStyle: MaterialStateProperty.all(
          const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected)
                ? const Color(0xFF6B9E78)
                : Colors.grey),
        trackColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected)
                ? const Color(0xFF4A7A56)
                : Colors.black12),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected)
                ? const Color(0xFF6B9E78)
                : Colors.transparent),
        checkColor: MaterialStateProperty.all(Colors.white),
        side: const BorderSide(color: Colors.black38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEEEEEE),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6B9E78)),
        ),
        labelStyle: const TextStyle(color: Colors.black54),
        hintStyle: const TextStyle(color: Colors.black26),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6B9E78),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      useMaterial3: true,
    );
  }
}

// Separate widget so context.watch works correctly after build
class _AppEntry extends StatelessWidget {
  const _AppEntry();

  @override
  Widget build(BuildContext context) {
    final setupComplete =
        context.select<SettingsProvider, bool>((s) => s.setupComplete);
    return setupComplete ? const MainShell() : const SetupScreen();
  }
}

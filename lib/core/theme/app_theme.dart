import 'package:material_ui/material_ui.dart';
abstract final class AppTheme {
  static final light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F4D37), surface: const Color(0xFFF7F8F4)),
    useMaterial3: true,
  );
}

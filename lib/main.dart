import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';
import 'ui/screens/alarm_active_screen.dart';

void main() {
  runApp(const ProviderScope(child: TarteelRiseApp()));
}

class TarteelRiseApp extends StatelessWidget {
  const TarteelRiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tarteel Rise',
      theme: AppTheme.darkTheme,
      home: const AlarmActiveScreen(),
    );
  }
}

import 'package:flutter/material.dart';

import 'features/chat/presentation/chat_screen.dart';

/// The app shell: Material 3 themes that follow the system's light or dark
/// setting, with the chat screen as home.
class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat Starter',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const ChatScreen(),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2962FF),
      brightness: brightness,
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

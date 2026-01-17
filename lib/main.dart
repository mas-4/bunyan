import 'package:flutter/material.dart';

import 'screens.dart';

void main() {
  runApp(WordLoggerApp());
}

class WordLoggerApp extends StatelessWidget {
  const WordLoggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bunyan',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      themeMode: ThemeMode.system,
      home: WordLoggerHome(),
    );
  }
}

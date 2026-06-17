import 'package:flutter/material.dart';

/// Fallback UI rendered by `main` when [AppDatabase.open] throws so the
/// user sees a clear Chinese error message instead of a blank/black
/// screen. The widget tree is intentionally minimal — no providers, no
/// router — because the database is what backs both.
class DatabaseErrorApp extends StatelessWidget {
  const DatabaseErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NousMind',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.storage, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  '数据库初始化失败',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  '请重启应用。如问题持续,请卸载后重新安装。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

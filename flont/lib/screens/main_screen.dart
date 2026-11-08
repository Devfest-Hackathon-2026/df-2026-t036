import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'timeline_screen.dart';
import 'ideas_screen.dart';
import 'inbox_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.me,
    this.googleEmail,
    this.apiBaseUrl = 'http://localhost:8080',
  });

  // 登録APIが返した本人情報をマイページへ渡す。
  final Map<String, dynamic>? me;
  final String? googleEmail;
  final String apiBaseUrl;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  List<Widget> get _pages => [
    // 一覧にもログイン済み状態と共通のAPI接続先を渡す。
    TimelineScreen(
      active: _selectedIndex == 0,
      apiBaseUrl: widget.apiBaseUrl,
      authenticated: widget.me != null,
    ),
    IdeasScreen(
      active: _selectedIndex == 1,
      apiBaseUrl: widget.apiBaseUrl,
      authenticated: widget.me != null,
    ),
    InboxScreen(
      userId: widget.me?['uid'] as String?,
      active: _selectedIndex == 2,
      authenticated: widget.me != null,
      apiBaseUrl: widget.apiBaseUrl,
    ),
    ProfileScreen(
      // IndexedStack内でも、マイページへ切り替わった時点で累計を再取得する。
      active: _selectedIndex == 3,
      me: widget.me,
      googleEmail: widget.googleEmail,
      apiBaseUrl: widget.apiBaseUrl,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EWOCURU'), centerTitle: true),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.schedule_rounded),
              selectedIcon: Icon(Icons.schedule_rounded),
              label: 'タイムライン',
            ),
            NavigationDestination(
              icon: Icon(Icons.lightbulb_outline_rounded),
              selectedIcon: Icon(Icons.lightbulb_rounded),
              label: 'アイデア',
            ),
            NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              selectedIcon: Icon(Icons.inbox_rounded),
              label: '受信箱',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'マイページ',
            ),
          ],
        ),
      ),
    );
  }
}

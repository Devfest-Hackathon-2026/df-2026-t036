import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 全画面でバーを非表示にし、タッチとマウスのドラッグを共通で扱う。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

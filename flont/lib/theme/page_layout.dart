import 'package:flutter/widgets.dart';

/// 幅の境界で三段階に切り替え、同じ区分では全画面で同じ寸法を使う。
class PageLayout {
  const PageLayout._({
    required this.maxWidth,
    required this.padding,
    this.horizontalPaddingOverride,
  });

  final double maxWidth;
  final double padding;
  final double? horizontalPaddingOverride;

  // スマホは左右にごく小さい余白を入れ、上下の余白は維持する。
  double get horizontalPadding => horizontalPaddingOverride ?? padding;
  EdgeInsets get insets =>
      EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: padding);

  // 外側に余白を置く画面でも、本文の左右位置をそろえる。
  // 本文も三段階の幅で広げ、区分内では指定寸法を維持する。
  double get contentWidth => maxWidth - horizontalPadding * 2;
  double get bodyWidth => contentWidth + horizontalPadding * 2;

  static PageLayout of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  static PageLayout forWidth(double width) {
    if (width < 600) {
      return const PageLayout._(
        maxWidth: double.infinity,
        padding: 16,
        horizontalPaddingOverride: 4,
      );
    }
    if (width < 1024) {
      return const PageLayout._(maxWidth: 768, padding: 24);
    }
    return const PageLayout._(maxWidth: 984, padding: 32);
  }
}

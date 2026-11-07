import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/theme/page_layout.dart';

void main() {
  // 境界の直前・直後で区分が切り替わり、区分内では寸法が一定になる。
  test('600未満はスマホ用', () {
    for (final width in [320.0, 599.0]) {
      final layout = PageLayout.forWidth(width);
      expect(layout.maxWidth, double.infinity);
      expect(layout.contentWidth, double.infinity);
      expect(layout.insets.left, 4);
      expect(layout.insets.right, 4);
      expect(layout.insets.top, 16);
      expect(layout.padding, 16);
    }
  });
  test('600から1024未満はタブレット用', () {
    for (final width in [600.0, 800.0, 1023.0]) {
      final layout = PageLayout.forWidth(width);
      expect(layout.maxWidth, 768);
      expect(layout.contentWidth, 720);
      expect(layout.padding, 24);
    }
  });
  test('1024以上はPC用', () {
    for (final width in [1024.0, 1440.0, 1920.0]) {
      final layout = PageLayout.forWidth(width);
      expect(layout.maxWidth, 984);
      expect(layout.contentWidth, 920);
      expect(layout.padding, 32);
    }
  });
}

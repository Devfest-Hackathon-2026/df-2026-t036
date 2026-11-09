import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Places each card below the shortest column using its actual rendered height.
class MasonryLayout extends MultiChildRenderObjectWidget {
  const MasonryLayout({
    super.key,
    required this.columns,
    this.spacing = 12,
    required super.children,
  });
  final int columns;
  final double spacing;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMasonry(columns, spacing);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderMasonry).update(columns, spacing);
  }
}

class _MasonryData extends ContainerBoxParentData<RenderBox> {}

class _RenderMasonry extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MasonryData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MasonryData> {
  _RenderMasonry(this._columns, this._spacing);
  int _columns;
  double _spacing;
  void update(int columns, double spacing) {
    if (_columns == columns && _spacing == spacing) return;
    _columns = columns;
    _spacing = spacing;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MasonryData) child.parentData = _MasonryData();
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final heights = List<double>.filled(_columns, 0);
    final width = (constraints.maxWidth - _spacing * (_columns - 1)) / _columns;
    final childConstraints = BoxConstraints.tightFor(width: width);
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _MasonryData;
      var column = 0;
      for (var index = 1; index < _columns; index++) {
        if (heights[index] < heights[column]) column = index;
      }
      final Size childSize;
      if (dry) {
        childSize = child.getDryLayout(childConstraints);
      } else {
        child.layout(childConstraints, parentUsesSize: true);
        childSize = child.size;
        data.offset = Offset(column * (width + _spacing), heights[column]);
      }
      heights[column] += childSize.height + _spacing;
      child = data.nextSibling;
    }
    final height = heights.reduce((a, b) => a > b ? a : b);
    return constraints.constrain(
      Size(constraints.maxWidth, height > 0 ? height - _spacing : 0),
    );
  }

  @override
  void performLayout() {
    size = _layout(constraints, dry: false);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);
  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

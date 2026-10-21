import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Measures cards at their natural height, then gives spare viewport space to
/// the shuttle. Unlike intrinsic sizing, this also supports cards containing
/// LayoutBuilder and expandable route details inside a scroll view.
class AdaptiveHomeColumn extends MultiChildRenderObjectWidget {
  const AdaptiveHomeColumn({
    super.key,
    required super.children,
    this.expandIndex,
    this.spacing = 12,
  });

  final int? expandIndex;
  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAdaptiveHomeColumn(expandIndex, spacing);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderAdaptiveHomeColumn)
      ..expandIndex = expandIndex
      ..spacing = spacing;
  }
}

class _HomeCardParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAdaptiveHomeColumn extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderAdaptiveHomeColumn(this._expandIndex, this._spacing);

  int? _expandIndex;
  double _spacing;

  set expandIndex(int? value) {
    if (_expandIndex == value) return;
    _expandIndex = value;
    markNeedsLayout();
  }

  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _HomeCardParentData();
    }
  }

  @override
  void performLayout() {
    final cardConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    var otherHeight = math.max(0, childCount - 1) * _spacing;
    RenderBox? expandable;
    var child = firstChild;
    var index = 0;
    while (child != null) {
      if (index == _expandIndex) {
        expandable = child;
      } else {
        child.layout(cardConstraints, parentUsesSize: true);
        otherHeight += child.size.height;
      }
      child = childAfter(child);
      index++;
    }
    expandable?.layout(
      cardConstraints.copyWith(
        minHeight: math.max(0, constraints.minHeight - otherHeight),
      ),
      parentUsesSize: true,
    );

    var top = 0.0;
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as ContainerBoxParentData<RenderBox>;
      data.offset = Offset(0, top);
      top += child.size.height;
      child = data.nextSibling;
      if (child != null) top += _spacing;
    }
    size = constraints.constrain(Size(constraints.maxWidth, top));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

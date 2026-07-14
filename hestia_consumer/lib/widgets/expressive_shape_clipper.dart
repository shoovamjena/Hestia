import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart';
import 'package:flutter/material.dart';

/// Clips a child to a Material 3 Expressive [RoundedPolygon] shape.
class ExpressiveShapeClipper extends CustomClipper<Path> {
  const ExpressiveShapeClipper({
    required this.polygon,
    this.inset = 1,
  });

  final RoundedPolygon polygon;
  final double inset;

  @override
  Path getClip(Size size) {
    final path = polygon.toPath();
    final bounds = path.getBounds();
    final canvasCenter = size.center(Offset.zero);
    final pathCenter = bounds.center;
    final matrix = Matrix4.identity()
      ..translateByDouble(canvasCenter.dx, canvasCenter.dy, 0, 1)
      ..scaleByDouble(size.width * inset, size.height * inset, 1, 1)
      ..translateByDouble(-pathCenter.dx, -pathCenter.dy, 0, 1);
    return path.transform(matrix.storage);
  }

  @override
  bool shouldReclip(ExpressiveShapeClipper oldClipper) =>
      oldClipper.polygon != polygon || oldClipper.inset != inset;
}

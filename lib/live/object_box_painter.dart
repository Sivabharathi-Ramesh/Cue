import 'package:flutter/material.dart';

import '../vision/detected_object.dart';

/// Paints live bounding boxes and confidence scores over the camera preview for
/// developers inspecting YOLO object detection in real time.
class ObjectBoundingBoxesPainter extends CustomPainter {
  const ObjectBoundingBoxesPainter(this.objects);

  final List<DetectedObject> objects;

  // Vibrant palette matching common object-detection developer visualizers.
  static const List<Color> _palette = <Color>[
    Color(0xFF00E676), // vibrant green
    Color(0xFFFFEA00), // bright yellow
    Color(0xFFFF1744), // electric pink/red
    Color(0xFF00E5FF), // bright cyan
    Color(0xFFFF9100), // bright orange
    Color(0xFFD500F9), // electric purple
    Color(0xFFAEEA00), // bright lime
    Color(0xFF2979FF), // electric blue
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) return;

    for (final object in objects) {
      final color = _palette[object.name.hashCode.abs() % _palette.length];
      final box = object.box;

      // Normalised coordinates [0.0 - 1.0] scaled to the canvas dimension.
      final left = (box.left * size.width).clamp(0.0, size.width);
      final top = (box.top * size.height).clamp(0.0, size.height);
      final right = (box.right * size.width).clamp(0.0, size.width);
      final bottom = (box.bottom * size.height).clamp(0.0, size.height);

      if (right - left <= 2 || bottom - top <= 2) continue;

      final rect = Rect.fromLTRB(left, top, right, bottom);

      // 1. Shaded box fill
      final fillPaint = Paint()
        ..color = color.withAlpha(28)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      // 2. Bounding rectangle outline
      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawRect(rect, boxPaint);

      // 3. Label text: Name + Confidence % (+ distance if known)
      final confPercent = (object.confidence * 100).round();
      final dist = object.distanceMeters;
      final label = dist != null
          ? '${object.name.toUpperCase()} $confPercent% • ${dist.toStringAsFixed(1)}m'
          : '${object.name.toUpperCase()} $confPercent%';

      final textSpan = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      const padH = 6.0;
      const padV = 3.0;
      final badgeWidth = textPainter.width + padH * 2;
      final badgeHeight = textPainter.height + padV * 2;

      // Place badge directly above top edge of box, or inside top if near top of screen
      final badgeTop = top >= badgeHeight ? top - badgeHeight : top;
      final badgeLeft = left.clamp(
        0.0,
        (size.width - badgeWidth).clamp(0.0, size.width),
      );

      final badgeRect = Rect.fromLTWH(
        badgeLeft,
        badgeTop,
        badgeWidth,
        badgeHeight,
      );

      // 4. Badge background
      final badgePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)),
        badgePaint,
      );

      // 5. Paint label text
      textPainter.paint(canvas, Offset(badgeLeft + padH, badgeTop + padV));
    }
  }

  @override
  bool shouldRepaint(covariant ObjectBoundingBoxesPainter oldDelegate) {
    if (identical(objects, oldDelegate.objects)) return false;
    if (objects.length != oldDelegate.objects.length) return true;
    for (var i = 0; i < objects.length; i++) {
      final a = objects[i];
      final b = oldDelegate.objects[i];
      if (a.name != b.name || a.confidence != b.confidence || a.box != b.box) {
        return true;
      }
    }
    return false;
  }
}

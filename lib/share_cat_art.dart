part of 'main.dart';

/// Small, code-drawn illustrations for the themed share-card corners.
enum ShareCatArtKind { flowers, forest, twilight }

class ShareCatArt extends StatelessWidget {
  const ShareCatArt({
    super.key,
    required this.kind,
    this.width = 132,
    this.height = 92,
  });

  final ShareCatArtKind kind;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _ShareCatPainter(kind),
        isComplex: false,
        willChange: false,
      ),
    ),
  );
}

class _ShareCatPainter extends CustomPainter {
  const _ShareCatPainter(this.kind);

  final ShareCatArtKind kind;

  static const Size _designSize = Size(132, 92);
  static const Color _ink = Color(0xff665b62);
  static const Color _fur = Color(0xfffff9f0);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(
      size.width / _designSize.width,
      size.height / _designSize.height,
    );
    switch (kind) {
      case ShareCatArtKind.flowers:
        _paintFlowers(canvas);
        break;
      case ShareCatArtKind.forest:
        _paintForest(canvas);
        break;
      case ShareCatArtKind.twilight:
        _paintTwilight(canvas);
        break;
    }
    canvas.restore();
  }

  void _paintFlowers(Canvas canvas) {
    // A faint ivory medallion gives the illustration a calm, printable edge.
    _oval(canvas, const Rect.fromLTWH(22, 9, 94, 76), const Color(0x66fffaf4));
    _stem(
      canvas,
      const Offset(28, 78),
      const Offset(19, 37),
      const Color(0xff93ab82),
      2.2,
    );
    _leaf(canvas, const Offset(23, 61), 1, const Color(0xffb1c59d));
    _leaf(canvas, const Offset(20, 52), -1, const Color(0xffc0cda9));
    _flower(
      canvas,
      const Offset(18, 32),
      const Color(0xffe8a9b2),
      const Color(0xffffe7ad),
      8,
    );
    _stem(
      canvas,
      const Offset(108, 80),
      const Offset(117, 44),
      const Color(0xffa5b690),
      2,
    );
    _leaf(canvas, const Offset(111, 65), -1, const Color(0xffc2d0ad));
    _flower(
      canvas,
      const Offset(119, 39),
      const Color(0xffd9b8dc),
      const Color(0xffffe8b2),
      6.3,
    );
    _paintCat(
      canvas,
      center: const Offset(67, 57),
      scale: .82,
      fur: _fur,
      shadow: const Color(0x1c8f7480),
    );
    _flower(
      canvas,
      const Offset(102, 73),
      const Color(0xffefc1c3),
      const Color(0xffffe4ad),
      5.3,
    );
  }

  void _paintForest(Canvas canvas) {
    _oval(canvas, const Rect.fromLTWH(20, 8, 96, 78), const Color(0x66f5faef));
    _leafCluster(canvas, const Offset(22, 35), const Color(0xffb6cba7), 1.0);
    _leafCluster(canvas, const Offset(109, 28), const Color(0xffced9b5), .92);
    _leafCluster(canvas, const Offset(112, 67), const Color(0xffa8c29d), .7);
    _paintCat(
      canvas,
      center: const Offset(66, 57),
      scale: .84,
      fur: const Color(0xfffff8e9),
      shadow: const Color(0x1c65816a),
    );
    _leaf(canvas, const Offset(39, 76), 1, const Color(0xffb8cda5));
    _leaf(canvas, const Offset(96, 78), -1, const Color(0xffcad7b3));
    _oval(canvas, const Rect.fromLTWH(62, 75, 8, 4), const Color(0x26788d70));
  }

  void _paintTwilight(Canvas canvas) {
    final skyRect = const Rect.fromLTWH(12, 5, 108, 78);
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xffe9def2), Color(0xffffe6ce)],
      ).createShader(skyRect);
    _roundRect(canvas, skyRect, 17, sky);
    _roundRect(
      canvas,
      const Rect.fromLTWH(18, 11, 96, 66),
      12,
      Paint()..color = const Color(0x44fff9f5),
    );
    // Window mullions stay behind the cat and never cross its face.
    _roundRect(
      canvas,
      const Rect.fromLTWH(62, 12, 3, 62),
      1.5,
      Paint()..color = const Color(0x887c6b83),
    );
    _roundRect(
      canvas,
      const Rect.fromLTWH(19, 43, 94, 3),
      1.5,
      Paint()..color = const Color(0x887c6b83),
    );
    _oval(canvas, const Rect.fromLTWH(89, 19, 11, 11), const Color(0xffffedc5));
    _oval(canvas, const Rect.fromLTWH(93, 17, 10, 10), const Color(0xffeadff1));
    _star(canvas, const Offset(36, 25), 2.1, const Color(0xfffff8e9));
    _star(canvas, const Offset(105, 34), 1.6, const Color(0xfffff8e9));
    _roundRect(
      canvas,
      const Rect.fromLTWH(6, 72, 120, 13),
      6,
      Paint()..color = const Color(0xffc7adba),
    );
    _roundRect(
      canvas,
      const Rect.fromLTWH(8, 69, 116, 7),
      3,
      Paint()..color = const Color(0xffead5d5),
    );
    _paintCat(
      canvas,
      center: const Offset(66, 60),
      scale: .73,
      fur: const Color(0xfffff7ec),
      shadow: const Color(0x33816a7c),
    );
    // A small apricot pot anchors the sill at the outer edge.
    _roundRect(
      canvas,
      const Rect.fromLTWH(99, 59, 12, 10),
      2,
      Paint()..color = const Color(0xffe4a17f),
    );
    _stem(
      canvas,
      const Offset(105, 60),
      const Offset(105, 47),
      const Color(0xff8ea17e),
      1.4,
    );
    _leaf(canvas, const Offset(102, 53), -1, const Color(0xffa6b995));
    _leaf(canvas, const Offset(108, 50), 1, const Color(0xffb7c39d));
  }

  void _paintCat(
    Canvas canvas, {
    required Offset center,
    required double scale,
    required Color fur,
    required Color shadow,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    // Tail is tucked around the body, so the silhouette reads clearly at thumbnail size.
    final tail = Path()
      ..moveTo(21, 23)
      ..cubicTo(43, 18, 44, -5, 30, -8)
      ..cubicTo(20, -10, 19, 1, 27, 3);
    canvas.drawPath(
      tail,
      Paint()
        ..color = fur
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      tail,
      Paint()
        ..color = _ink.withValues(alpha: .52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    _oval(canvas, const Rect.fromLTWH(-27, 20, 54, 12), shadow);
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-24, -5, 48, 37),
      const Radius.circular(20),
    );
    canvas.drawRRect(body, Paint()..color = fur);
    canvas.drawRRect(
      body,
      Paint()
        ..color = _ink.withValues(alpha: .58)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    final head = Path()
      ..moveTo(-22, -12)
      ..lineTo(-18, -34)
      ..quadraticBezierTo(-16, -38, -12, -34)
      ..lineTo(-4, -27)
      ..quadraticBezierTo(0, -28, 4, -27)
      ..lineTo(13, -35)
      ..quadraticBezierTo(17, -38, 19, -33)
      ..lineTo(22, -12)
      ..quadraticBezierTo(22, 10, 0, 13)
      ..quadraticBezierTo(-22, 10, -22, -12)
      ..close();
    canvas.drawPath(head, Paint()..color = fur);
    canvas.drawPath(
      head,
      Paint()
        ..color = _ink.withValues(alpha: .72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeJoin = StrokeJoin.round,
    );
    final earLeft = Path()
      ..moveTo(-16, -31)
      ..lineTo(-13, -21)
      ..lineTo(-7, -26)
      ..close();
    final earRight = Path()
      ..moveTo(13, -31)
      ..lineTo(8, -26)
      ..lineTo(16, -22)
      ..close();
    canvas.drawPath(earLeft, Paint()..color = const Color(0xffefc1c2));
    canvas.drawPath(earRight, Paint()..color = const Color(0xffefc1c2));
    _oval(canvas, const Rect.fromLTWH(-12, -10, 8, 7), const Color(0x66efb2b4));
    _oval(canvas, const Rect.fromLTWH(4, -10, 8, 7), const Color(0x66efb2b4));
    _oval(canvas, const Rect.fromLTWH(-8, -16, 3.5, 4.5), _ink);
    _oval(canvas, const Rect.fromLTWH(4.5, -16, 3.5, 4.5), _ink);
    _oval(
      canvas,
      const Rect.fromLTWH(-3, -10, 6, 4.5),
      const Color(0xffc98791),
    );
    final mouth = Path()
      ..moveTo(0, -5.5)
      ..lineTo(0, -3)
      ..quadraticBezierTo(-4, 1, -7, -2)
      ..moveTo(0, -3)
      ..quadraticBezierTo(4, 1, 7, -2);
    canvas.drawPath(
      mouth,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
    final whiskers = Path()
      ..moveTo(-9, -5)
      ..lineTo(-18, -7)
      ..moveTo(-9, -2)
      ..lineTo(-18, 0)
      ..moveTo(9, -5)
      ..lineTo(18, -7)
      ..moveTo(9, -2)
      ..lineTo(18, 0);
    canvas.drawPath(
      whiskers,
      Paint()
        ..color = _ink.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _flower(
    Canvas canvas,
    Offset center,
    Color petal,
    Color core,
    double radius,
  ) {
    for (var i = 0; i < 5; i++) {
      final angle = i * math.pi * 2 / 5;
      _oval(
        canvas,
        Rect.fromCenter(
          center:
              center + Offset(math.cos(angle), math.sin(angle)) * radius * .65,
          width: radius * 1.05,
          height: radius * 1.05,
        ),
        petal,
      );
    }
    _oval(
      canvas,
      Rect.fromCenter(
        center: center,
        width: radius * .72,
        height: radius * .72,
      ),
      core,
    );
  }

  void _leafCluster(Canvas canvas, Offset center, Color color, double scale) {
    for (final spec in <(double, double, double)>[
      (-8, 2, -.65),
      (0, -7, -.15),
      (8, 1, .55),
      (1, 8, .95),
    ]) {
      canvas.save();
      canvas.translate(
        center.dx + spec.$1 * scale,
        center.dy + spec.$2 * scale,
      );
      canvas.rotate(spec.$3);
      _roundRect(
        canvas,
        Rect.fromLTWH(-4 * scale, -9 * scale, 8 * scale, 18 * scale),
        4 * scale,
        Paint()..color = color,
      );
      canvas.restore();
    }
  }

  void _leaf(Canvas canvas, Offset base, double direction, Color color) {
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(
        base.dx + 10 * direction,
        base.dy - 9,
        base.dx + 12 * direction,
        base.dy - 16,
      )
      ..quadraticBezierTo(
        base.dx + 2 * direction,
        base.dy - 13,
        base.dx,
        base.dy,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      base,
      Offset(base.dx + 9 * direction, base.dy - 13),
      Paint()
        ..color = const Color(0x5594a083)
        ..strokeWidth = .8,
    );
  }

  void _stem(Canvas canvas, Offset from, Offset to, Color color, double width) {
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void _star(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final r = i.isEven ? radius : radius * .32;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _oval(Canvas canvas, Rect rect, Color color) =>
      canvas.drawOval(rect, Paint()..color = color);

  void _roundRect(Canvas canvas, Rect rect, double radius, Paint paint) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );

  @override
  bool shouldRepaint(covariant _ShareCatPainter oldDelegate) =>
      oldDelegate.kind != kind;
}

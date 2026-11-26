import 'package:material_ui/material_ui.dart';

/// Lightweight native canvas illustration inspired by the web login scene.
class RanchScene extends StatelessWidget {
  const RanchScene({super.key, required this.hideEyes});
  final bool hideEyes;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: AspectRatio(aspectRatio: 2.2, child: RepaintBoundary(child: CustomPaint(painter: _RanchPainter(hideEyes, DateTime.now().hour)))),
  );
}
class _RanchPainter extends CustomPainter {
  _RanchPainter(this.hideEyes, this.hour);
  final bool hideEyes;
  final int hour;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 440, size.height / 200);
    final night = hour < 6 || hour >= 19;
    final p = Paint();
    void fill(Color color) { p.color = color; p.shader = null; p.style = PaintingStyle.fill; }
    p.shader = LinearGradient(colors: night ? [const Color(0xFF243D53), const Color(0xFF526B78)] : [const Color(0xFFB7D8D3), const Color(0xFFFFF0CF)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(const Rect.fromLTWH(0, 0, 440, 200));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 440, 200), p);
    fill(const Color(0xFFFFF3C8));
    canvas.drawCircle(const Offset(88, 43), 23, p);
    if (night) { fill(const Color(0xFF243D53)); canvas.drawCircle(const Offset(98, 35), 20, p); }
    for (var i = 0; i < 3; i++) {
      fill([const Color(0xFF86ADA0), const Color(0xFFA7BC75), const Color(0xFF92AC58)][i]);
      final y = 85.0 + i * 22;
      canvas.drawPath(Path()..moveTo(0, y)..quadraticBezierTo(100, y - 60, 220, y)..quadraticBezierTo(330, y + 30, 440, y - 20)..lineTo(440, 200)..lineTo(0, 200)..close(), p);
    }
    fill(const Color(0xFF8A6844));
    for (var x = 15.0; x < 440; x += 75) { canvas.drawRect(Rect.fromLTWH(x, 103, 5, 38), p); }
    canvas.drawRect(const Rect.fromLTWH(0, 113, 440, 4), p);
    canvas.drawRect(const Rect.fromLTWH(0, 126, 440, 4), p);
    void cow(double x, double y, double scale, Color body) {
      canvas.save(); canvas.translate(x, y); canvas.scale(scale);
      fill(const Color(0xFF765D43));
      for (final leg in [-38.0, 23.0]) { canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(leg, -15, 9, 32), const Radius.circular(3)), p); }
      fill(body);
      canvas.drawOval(const Rect.fromLTWH(-55, -61, 103, 65), p);
      canvas.drawOval(const Rect.fromLTWH(20, -68, 43, 18), p);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(28, -67, 40, 51), const Radius.circular(15)), p);
      fill(const Color(0xFFB8A181));
      canvas.drawOval(const Rect.fromLTWH(32, -35, 33, 20), p);
      fill(const Color(0xFF322C21));
      for (final eye in [40.0, 58.0]) { canvas.drawOval(Rect.fromCenter(center: Offset(eye, -48), width: 5, height: hideEyes ? 1 : 7), p); }
      canvas.restore();
    }
    cow(150, 168, 1.15, const Color(0xFFF6E8CC));
    cow(310, 177, .75, const Color(0xFFBD864F));
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _RanchPainter oldDelegate) => oldDelegate.hideEyes != hideEyes || oldDelegate.hour != hour;
}

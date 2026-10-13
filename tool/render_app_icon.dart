// Renders the Habit Quest app icon PNGs in assets/icon/ from the same
// geometry as the SVG master (assets/icon/icon.svg).
//
// macOS has no SVG rasteriser that keeps transparency (qlmanage paints on
// white), so the layers are drawn with dart:ui instead. Run it with:
//
//   flutter test tool/render_app_icon.dart
//
// It lives outside test/ so the normal `flutter test` run does not rewrite
// the assets. Keep the numbers below in sync with the SVG files.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const double _size = 1024;

const _bgStops = [Color(0xFFFFD45C), Color(0xFFFFAA3F), Color(0xFFFF7F45)];
const _shieldTop = Color(0xFF8A5FFF);
const _shieldBottom = Color(0xFF6A3BF0);
const _shadow = Color(0x47B8441A); // #B8441A at 28 %
const _coral = Color(0xFFFF6B6B);
const _white = Color(0xFFFFFFFF);

const _badgeCenter = Offset(680, 668);

Path _shieldPath() => Path()
  ..moveTo(300, 300)
  ..quadraticBezierTo(300, 272, 328, 270)
  ..cubicTo(400, 264, 462, 246, 512, 214)
  ..cubicTo(562, 246, 624, 264, 696, 270)
  ..quadraticBezierTo(724, 272, 724, 300)
  ..lineTo(724, 480)
  ..cubicTo(724, 630, 630, 730, 512, 800)
  ..cubicTo(394, 730, 300, 630, 300, 480)
  ..close();

Path _checkPath() => Path()
  ..moveTo(404, 494)
  ..lineTo(484, 574)
  ..lineTo(628, 420);

/// Five-point star, outer radius 48 / inner 22, scaled 1.15 around the badge.
Path _starPath() {
  final path = Path();
  for (var k = 0; k < 10; k++) {
    final radius = k.isEven ? 48.0 : 22.0;
    final angle = (-90 + 36 * k) * math.pi / 180;
    final x = 680 + 1.15 * radius * math.cos(angle);
    final y = 670 + 1.15 * radius * math.sin(angle);
    k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  return path..close();
}

Paint _fill(Color c) => Paint()
  ..isAntiAlias = true
  ..color = c;

Paint _stroke(Color c, double width) => Paint()
  ..isAntiAlias = true
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = c;

void _paintBackground(Canvas canvas) {
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, _size, _size),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(_size, _size),
        _bgStops,
        const [0, 0.55, 1],
      ),
  );
}

void _paintStar(Canvas canvas, Paint fill) {
  final star = _starPath();
  canvas.drawPath(star, fill);
  canvas.drawPath(
    star,
    Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11.5
      ..strokeJoin = StrokeJoin.round
      ..color = fill.color
      ..blendMode = fill.blendMode,
  );
}

void _paintMotif(Canvas canvas) {
  final shield = _shieldPath();

  // Soft drop shadows.
  canvas.drawPath(shield.shift(const Offset(0, 24)), _fill(_shadow));
  canvas.drawCircle(_badgeCenter.translate(0, 24), 94, _fill(_shadow));

  // Shield with a lighter left half.
  canvas.drawPath(
    shield,
    Paint()
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(
        const Offset(0, 214),
        const Offset(0, 800),
        const [_shieldTop, _shieldBottom],
      ),
  );
  canvas.save();
  canvas.clipPath(shield);
  canvas.drawRect(
    const Rect.fromLTWH(300, 200, 212, 620),
    _fill(const Color(0x1FFFFFFF)),
  );
  canvas.restore();

  canvas.drawPath(_checkPath(), _stroke(_white, 86));

  // Star badge.
  canvas.drawCircle(_badgeCenter, 94, _fill(_white));
  canvas.drawCircle(_badgeCenter, 72, _fill(_coral));
  _paintStar(canvas, _fill(_white));
}

void _paintMonochrome(Canvas canvas) {
  const bounds = Rect.fromLTWH(0, 0, _size, _size);
  final clear = Paint()
    ..isAntiAlias = true
    ..blendMode = BlendMode.clear;

  canvas.saveLayer(bounds, Paint());
  canvas.drawPath(_shieldPath(), _fill(_white));
  canvas.drawPath(
    _checkPath(),
    _stroke(_white, 86)..blendMode = BlendMode.clear,
  );
  canvas.drawCircle(_badgeCenter, 94, clear);
  canvas.drawCircle(_badgeCenter, 74, _fill(_white));
  _paintStar(canvas, clear);
  canvas.restore();
}

Future<void> _render(String name, void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(
    _size.toInt(),
    _size.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File('assets/icon/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('render app icon PNGs', (tester) async {
    await tester.runAsync(() async {
      await _render('icon_1024.png', (c) {
        _paintBackground(c);
        _paintMotif(c);
      });
      await _render('icon_background.png', _paintBackground);
      await _render('icon_foreground.png', _paintMotif);
      await _render('icon_monochrome.png', _paintMonochrome);
    });
  });
}

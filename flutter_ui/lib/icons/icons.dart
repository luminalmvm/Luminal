// Lumit's icons: the Iconoir set (MIT), ported one-for-one from
// crates/lumit-ui/src/icons.rs (K-085). Same rules as the Rust side: every
// glyph is a real icon from one consistent set, emoji are banned, icons take
// the text colour of their state, and the motion-blur mark is drawn from the
// owner's artwork rather than looked up (Iconoir has no motion-blur glyph).

import 'package:flutter/widgets.dart';
import 'package:iconoir_flutter/regular/align_left.dart' as ic;
import 'package:iconoir_flutter/regular/circle.dart' as ic;
import 'package:iconoir_flutter/regular/color_picker.dart' as ic;
import 'package:iconoir_flutter/regular/cube.dart' as ic;
import 'package:iconoir_flutter/regular/cursor_pointer.dart' as ic;
import 'package:iconoir_flutter/regular/design_nib.dart' as ic;
import 'package:iconoir_flutter/regular/drag_hand_gesture.dart' as ic;
import 'package:iconoir_flutter/regular/ease_curve_control_points.dart' as ic;
import 'package:iconoir_flutter/regular/eye.dart' as ic;
import 'package:iconoir_flutter/regular/eye_closed.dart' as ic;
import 'package:iconoir_flutter/regular/fill_color.dart' as ic;
import 'package:iconoir_flutter/regular/flare.dart' as ic;
import 'package:iconoir_flutter/regular/folder.dart' as ic;
import 'package:iconoir_flutter/regular/frame.dart' as ic;
import 'package:iconoir_flutter/regular/fx.dart' as ic;
import 'package:iconoir_flutter/regular/keyframe.dart' as ic;
import 'package:iconoir_flutter/regular/keyframe_plus.dart' as ic;
import 'package:iconoir_flutter/regular/link.dart' as ic;
import 'package:iconoir_flutter/regular/link_xmark.dart' as ic;
import 'package:iconoir_flutter/regular/lock.dart' as ic;
import 'package:iconoir_flutter/regular/lock_slash.dart' as ic;
import 'package:iconoir_flutter/regular/magnet.dart' as ic;
import 'package:iconoir_flutter/regular/media_video.dart' as ic;
import 'package:iconoir_flutter/regular/movie.dart' as ic;
import 'package:iconoir_flutter/regular/nav_arrow_down.dart' as ic;
import 'package:iconoir_flutter/regular/nav_arrow_left.dart' as ic;
import 'package:iconoir_flutter/regular/nav_arrow_right.dart' as ic;
import 'package:iconoir_flutter/regular/network.dart' as ic;
import 'package:iconoir_flutter/regular/open_new_window.dart' as ic;
import 'package:iconoir_flutter/regular/pause.dart' as ic;
import 'package:iconoir_flutter/regular/play.dart' as ic;
import 'package:iconoir_flutter/regular/refresh_double.dart' as ic;
import 'package:iconoir_flutter/regular/sound_high.dart' as ic;
import 'package:iconoir_flutter/regular/sound_off.dart' as ic;
import 'package:iconoir_flutter/regular/square.dart' as ic;
import 'package:iconoir_flutter/regular/star.dart' as ic;
import 'package:iconoir_flutter/regular/text.dart' as ic;
import 'package:iconoir_flutter/regular/timer.dart' as ic;
import 'package:iconoir_flutter/regular/video_camera.dart' as ic;
import 'package:iconoir_flutter/regular/view_columns_3.dart' as ic;
import 'package:iconoir_flutter/regular/wind.dart' as ic;
import 'package:iconoir_flutter/solid/keyframe.dart' as ics;

/// One icon — the same 44 variants as the Rust `Icon` enum, same names.
enum LumitIcon {
  pointer,
  move,
  rectangle,
  ellipse,
  star,
  pen,
  play,
  pause,
  lock,
  unlock,
  link,
  unlink,
  folder,
  film,
  graphCurve,
  timelineBars,
  nodes,
  footage,
  comp,
  solid,
  sequence,
  text,
  camera,
  eye,
  eyeClosed,
  audio,
  mute,
  popOut,
  prevKeyframe,
  nextKeyframe,
  keyframeAdd,
  keyframe,
  keyframeFilled,
  stopwatch,
  twirlClosed,
  twirlOpen,
  collapse,
  flow,
  cube3d,
  magnet,
  eyedropper,
  reset,
  motionBlur,
  fx,
}

/// Build `icon` at `size` in `color`. The motion-blur mark is drawn, not
/// looked up, exactly as in the Rust frontend.
Widget lumitIcon(LumitIcon icon, {required double size, required Color color}) {
  if (icon == LumitIcon.motionBlur) {
    return CustomPaint(
      size: Size.square(size),
      painter: MotionBlurPainter(color),
    );
  }
  final w = _glyph(icon, color);
  return SizedBox(width: size, height: size, child: w);
}

Widget _glyph(LumitIcon icon, Color color) => switch (icon) {
      LumitIcon.pointer => ic.CursorPointer(color: color),
      LumitIcon.move => ic.DragHandGesture(color: color),
      LumitIcon.rectangle => ic.Square(color: color),
      LumitIcon.ellipse => ic.Circle(color: color),
      LumitIcon.star => ic.Star(color: color),
      LumitIcon.pen => ic.DesignNib(color: color),
      LumitIcon.play => ic.Play(color: color),
      LumitIcon.pause => ic.Pause(color: color),
      LumitIcon.lock => ic.Lock(color: color),
      LumitIcon.unlock => ic.LockSlash(color: color),
      LumitIcon.link => ic.Link(color: color),
      LumitIcon.unlink => ic.LinkXmark(color: color),
      LumitIcon.folder => ic.Folder(color: color),
      LumitIcon.film => ic.Movie(color: color),
      LumitIcon.graphCurve => ic.EaseCurveControlPoints(color: color),
      LumitIcon.timelineBars => ic.AlignLeft(color: color),
      LumitIcon.nodes => ic.Network(color: color),
      LumitIcon.footage => ic.MediaVideo(color: color),
      LumitIcon.comp => ic.Frame(color: color),
      LumitIcon.solid => ic.FillColor(color: color),
      LumitIcon.sequence => ic.ViewColumns3(color: color),
      LumitIcon.text => ic.Text(color: color),
      LumitIcon.camera => ic.VideoCamera(color: color),
      LumitIcon.eye => ic.Eye(color: color),
      LumitIcon.eyeClosed => ic.EyeClosed(color: color),
      LumitIcon.audio => ic.SoundHigh(color: color),
      LumitIcon.mute => ic.SoundOff(color: color),
      LumitIcon.popOut => ic.OpenNewWindow(color: color),
      LumitIcon.prevKeyframe => ic.NavArrowLeft(color: color),
      LumitIcon.nextKeyframe => ic.NavArrowRight(color: color),
      LumitIcon.keyframeAdd => ic.KeyframePlus(color: color),
      LumitIcon.keyframe => ic.Keyframe(color: color),
      LumitIcon.keyframeFilled => ics.KeyframeSolid(color: color),
      LumitIcon.stopwatch => ic.Timer(color: color),
      LumitIcon.twirlClosed => ic.NavArrowRight(color: color),
      LumitIcon.twirlOpen => ic.NavArrowDown(color: color),
      LumitIcon.collapse => ic.Flare(color: color),
      LumitIcon.flow => ic.Wind(color: color),
      LumitIcon.cube3d => ic.Cube(color: color),
      LumitIcon.magnet => ic.Magnet(color: color),
      LumitIcon.eyedropper => ic.ColorPicker(color: color),
      LumitIcon.reset => ic.RefreshDouble(color: color),
      LumitIcon.motionBlur => const SizedBox.shrink(), // handled above
      LumitIcon.fx => ic.Fx(color: color),
    };

/// The motion-blur mark: a ring with speed streaks running into it, from the
/// owner's artwork on a 24×24 grid — coordinates identical to the Rust
/// `draw_motion_blur` so the two frontends paint the same mark.
class MotionBlurPainter extends CustomPainter {
  final Color color;
  const MotionBlurPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final origin = Offset(
      size.width / 2 - 12.0 * s,
      size.height / 2 - 12.0 * s,
    );
    Offset at(double x, double y) => origin + Offset(x * s, y * s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * s
      ..strokeCap = StrokeCap.butt;
    // The ring: a 2-unit stroke on a 4-unit radius, centred at (17, 12).
    canvas.drawCircle(at(17, 12), 4.0 * s, paint);
    // The streaks; two rows broken by a shorter dash further left, which is
    // what makes the mark read as motion rather than a plain arrow.
    const rows = [
      (4.0, 14.0, 8.0),
      (10.0, 13.0, 12.0),
      (8.0, 14.0, 16.0),
      (3.0, 7.0, 12.0),
      (4.0, 5.0, 16.0),
    ];
    for (final (x1, x2, y) in rows) {
      canvas.drawLine(at(x1, y), at(x2, y), paint);
    }
  }

  @override
  bool shouldRepaint(MotionBlurPainter oldDelegate) =>
      oldDelegate.color != color;
}

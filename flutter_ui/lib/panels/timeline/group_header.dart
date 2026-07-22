// A sub-group header inside a layer's twirl (currently just "Transform"): an
// indented disclosure triangle and label over a subtle themed band, ported from
// the egui `group_header_row` (crates/lumit-ui/src/shell/inspector/
// transform_rows.rs). It spans the whole row so the section title reads as its
// own bar; the lane side stays empty.

import 'package:flutter/widgets.dart';

import '../../icons/icons.dart';
import '../../widgets/controls.dart';
import 'layer_row.dart' show kRowHeight;

/// A collapsible group header band. [open] drives the twirl direction; [onTap]
/// toggles it.
class GroupHeaderRow extends StatelessWidget {
  final String label;
  final bool open;
  final double outlineWidth;
  final VoidCallback onTap;

  /// Extra nesting depth (0 = a top-level group like Transform; 1 = a sub-group
  /// such as one effect inside the Effects group). Each step indents the twirl.
  final int indent;

  const GroupHeaderRow({
    super.key,
    required this.label,
    required this.open,
    required this.outlineWidth,
    required this.onTap,
    this.indent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: kRowHeight,
        color: t.surface1,
        child: Row(
          children: [
            SizedBox(
              width: outlineWidth,
              child: Padding(
                padding: EdgeInsets.only(left: 18 + indent * 14),
                child: Row(
                  children: [
                    lumitIcon(
                      open ? LumitIcon.twirlOpen : LumitIcon.twirlClosed,
                      size: 12,
                      color: t.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(label, style: t.small.copyWith(color: t.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

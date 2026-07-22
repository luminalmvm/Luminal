// The graph editor drawn into the timeline's lane area when the graph lens is on
// (07-UI-SPEC; K-070; ported from `crates/lumit-ui/src/shell/graph.rs`). This
// file is the dispatcher: it resolves the selected layer, offers the lens picker
// in a shared header (the set graph.rs offers — the transform *value* graph, and
// for a retimed footage layer the Retime *speed* and *Time* lenses, with the
// Vegas default-lens preference), and hands the plot to the matching lens widget.
//
// The three lenses live in their own files, each under the file-length limit:
//   - graph_value_lens.dart  — the transform property value curve (bezier keys,
//     draggable tangent handles, interp menu).
//   - graph_time_lens.dart   — the Retime source-position curve (boundary drags).
//   - graph_speed_lens.dart  — the Retime speed-% curve (ramp presets, →Rate).
// The pure maths (bezier sampling, handle mapping, snapping, axis ticks) lives in
// graph_maths.dart and is unit-tested.

import 'package:flutter/widgets.dart';

import '../../bridge/bridge.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../widgets/controls.dart';
import 'graph_speed_lens.dart';
import 'graph_time_lens.dart';
import 'graph_value_lens.dart';
import 'lane_scale.dart';

/// The graph editor that replaces the lane rows while `timelineGraphMode` is on.
class GraphEditor extends StatefulWidget {
  final AppStateStub app;
  final BridgeComp comp;
  final String compId;

  /// The shared time↔pixel scale (the ruler's own), so every lens's curve pans
  /// and zooms in step with the lanes.
  final LaneScale scale;

  const GraphEditor({
    super.key,
    required this.app,
    required this.comp,
    required this.compId,
    required this.scale,
  });

  @override
  State<GraphEditor> createState() => _GraphEditorState();
}

class _GraphEditorState extends State<GraphEditor> {
  AppStateStub get app => widget.app;

  @override
  void initState() {
    super.initState();
    // The lenses draw the playhead and a per-frame readout, so the graph tracks
    // the fine-grained playhead notifier itself (its parent no longer rebuilds
    // per frame — the perf pass).
    app.playheadFrame.addListener(_onPlayhead);
  }

  @override
  void didUpdateWidget(GraphEditor old) {
    super.didUpdateWidget(old);
    if (!identical(old.app, widget.app)) {
      old.app.playheadFrame.removeListener(_onPlayhead);
      app.playheadFrame.addListener(_onPlayhead);
    }
  }

  @override
  void dispose() {
    app.playheadFrame.removeListener(_onPlayhead);
    super.dispose();
  }

  void _onPlayhead() {
    if (mounted) setState(() {});
  }

  /// The selected layer, resolved in the front comp, or null.
  BridgeLayer? get _selected {
    final id = app.selectedLayer;
    if (id == null) return null;
    for (final l in widget.comp.layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Whether [layer] carries a Retime, so the speed and Time lenses apply.
  bool _retimeCapable(BridgeLayer layer) =>
      layer.kind == BridgeLayerKind.footage && layer.retime != null;

  /// The lenses valid for [layer] (in picker order): always the value graph,
  /// plus the two Retime lenses when the layer is retimed footage.
  List<String> _availableLenses(BridgeLayer layer) =>
      _retimeCapable(layer) ? const ['value', 'time', 'speed'] : const ['value'];

  /// The effective lens: the stored pick when it is valid for this selection,
  /// else the first valid lens (the value graph). Constraining here mirrors
  /// egui's fall-through when the graphed channel no longer applies.
  String _effectiveLens(BridgeLayer layer) {
    final avail = _availableLenses(layer);
    return avail.contains(app.graphLens) ? app.graphLens : avail.first;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final layer = _selected;
    if (layer == null) {
      return _hint(t, 'Select a layer to edit its curves.');
    }
    final lens = _effectiveLens(layer);
    return Column(
      children: [
        _header(t, layer, lens),
        Expanded(child: _body(t, layer, lens)),
      ],
    );
  }

  Widget _hint(LumitTheme t, String msg) => Container(
        color: t.surface0,
        alignment: Alignment.center,
        child: Text(msg, style: t.small.copyWith(color: t.textMuted)),
      );

  /// The shared header: a left gutter (aligned under the ruler) with the lens
  /// picker, the Retime enable/Vegas controls for a footage layer, and — for the
  /// value lens — the property picker.
  Widget _header(LumitTheme t, BridgeLayer layer, String lens) {
    final avail = _availableLenses(layer);
    final isFootage = layer.kind == BridgeLayerKind.footage;
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          SizedBox(
            width: widget.scale.trackLeft,
            child: Container(
              color: t.surface1,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.centerLeft,
              child: Text('Graph', style: t.small.copyWith(color: t.textMuted)),
            ),
          ),
          Expanded(
            child: Container(
              color: t.surface1,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  // The lens picker (only the lenses valid for this selection).
                  for (final l in avail)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: _LensPill(
                        label: _lensLabel(l),
                        selected: l == lens,
                        onTap: () => app.setGraphLens(l),
                      ),
                    ),
                  const SizedBox(width: 8),
                  // The value lens picks which property it graphs.
                  if (lens == 'value')
                    _propertyPicker(t, layer)
                  // A retimed footage layer carries the Vegas default-lens toggle.
                  else if (_retimeCapable(layer)) ...[
                    LumitTooltip(
                      message:
                          'Open the Retime channel to the speed-% lens by default',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            app.setVegasDefaultLens(!app.vegasDefaultLens),
                        child: Row(
                          children: [
                            IgnorePointer(
                              child: HouseCheckbox(
                                value: app.vegasDefaultLens,
                                onChanged: app.setVegasDefaultLens,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text('Vegas', style: t.small),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Footage with no Retime yet: the Time stopwatch, mirrored, so
                  // enabling it reveals the Speed/Time lenses.
                  if (isFootage && layer.retime == null)
                    LumitTooltip(
                      message: 'Enable Retime to graph its speed and source time',
                      child: Row(
                        children: [
                          HouseCheckbox(
                            value: false,
                            onChanged: (v) => app.setRetimeEnabled(
                                widget.compId, layer.id, v),
                          ),
                          const SizedBox(width: 5),
                          Text('Retime', style: t.small),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _lensLabel(String lens) => switch (lens) {
        'speed' => 'Speed',
        'time' => 'Time',
        _ => 'Value',
      };

  Widget _propertyPicker(LumitTheme t, BridgeLayer layer) {
    final names = graphablePropNames(layer);
    if (names.isEmpty) return const SizedBox.shrink();
    final current = resolveGraphProp(layer, app.graphProp);
    return BareDropdown<String>(
      value: current,
      options: names,
      label: (n) => _propLabel(layer, n),
      onChanged: (n) => app.setGraphProp(n),
    );
  }

  /// A property's picker label: its readable name with a dot when it is animated
  /// (so the value lens's keyed channels stand out).
  String _propLabel(BridgeLayer layer, String name) {
    final animated = layer.transform?[name]?.animated ?? false;
    return animated ? '• $name' : name;
  }

  Widget _body(LumitTheme t, BridgeLayer layer, String lens) {
    switch (lens) {
      case 'speed':
        return GraphSpeedLens(
          app: app,
          compId: widget.compId,
          layer: layer,
          retime: layer.retime!,
          scale: widget.scale,
        );
      case 'time':
        return GraphTimeLens(
          app: app,
          compId: widget.compId,
          layer: layer,
          retime: layer.retime!,
          scale: widget.scale,
          markers: widget.comp.markers,
          fps: widget.comp.fps.fps,
        );
      default:
        final names = graphablePropNames(layer);
        if (names.isEmpty) {
          return _hint(t, 'This layer has no animatable transform to graph.');
        }
        return GraphValueLens(
          app: app,
          compId: widget.compId,
          layer: layer,
          prop: resolveGraphProp(layer, app.graphProp),
          scale: widget.scale,
          fps: widget.comp.fps.fps,
        );
    }
  }
}

/// A lens-picker pill: a small frameless button whose label rings/accents when
/// its lens is the active one.
class _LensPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LensPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return HouseButton(
      small: true,
      frameless: !selected,
      onPressed: onTap,
      child: Text(
        label,
        style: t.small.copyWith(
          color: selected ? t.accent : t.textSecondary,
        ),
      ),
    );
  }
}

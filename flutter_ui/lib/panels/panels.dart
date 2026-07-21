// Phase-F0 panel stubs: every panel present with its real name and chrome so
// the workspace reads like the egui frontend, each stating which phase makes
// it live (docs/flutter-port/05-PARITY-CHECKLIST.md). The Viewer's neutral
// pasteboard and the Scopes graticule are real — those are chrome, not data.

import 'package:flutter/widgets.dart';

import '../bridge/bridge.dart';
import '../icons/icons.dart';
import '../state/app_state.dart';
import '../state/dock.dart';
import '../theme/theme.dart';
import '../widgets/controls.dart';

Widget buildPanelBody(BuildContext context, Panel panel, AppStateStub app) =>
    switch (panel) {
      // The Project panel goes live when the bridge is present: it renders the
      // real document tree instead of the placeholder (phase F1). Without a
      // bridge the placeholder stays.
      Panel.project => (app.bridge != null && app.snapshot != null)
          ? _ProjectPanel(app: app)
          : _PlaceholderPanel(
              icon: LumitIcon.folder,
              title: 'Project',
              hint:
                  'Project items, thumbnails and relink arrive with the engine bridge (phase F1).',
            ),
      Panel.viewer => _ViewerStub(app: app),
      Panel.timeline => _TimelineStub(app: app),
      Panel.effectControls => _PlaceholderPanel(
          icon: LumitIcon.fx,
          title: 'Effect controls',
          hint:
              'Transform and effect property rows arrive in phase F4; select a layer to edit it here.',
        ),
      Panel.effectsAndPresets => _PlaceholderPanel(
          icon: LumitIcon.star,
          title: 'Effects & presets',
          hint:
              'The searchable effect list and .lumfx presets arrive in phase F4.',
        ),
      Panel.scopes => const _ScopesStub(),
      Panel.hierarchy => _PlaceholderPanel(
          icon: LumitIcon.nodes,
          title: 'Hierarchy',
          hint: 'The composition tree arrives in phase F4.',
        ),
    };

class _PlaceholderPanel extends StatelessWidget {
  final LumitIcon icon;
  final String title;
  final String hint;

  const _PlaceholderPanel({
    required this.icon,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          lumitIcon(icon, size: 28, color: t.textDisabled),
          const SizedBox(height: 8),
          Text(title, style: t.body),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(hint, style: t.small, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

/// The live Project panel (phase F1): one row per document item, folders
/// nesting their children. Selection and drag are later slices — a row shows
/// its type icon, its name, and lights on hover. An empty document shows a
/// quiet hint.
class _ProjectPanel extends StatelessWidget {
  final AppStateStub app;
  const _ProjectPanel({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final snapshot = app.snapshot;
        final items = snapshot?.items ?? const <BridgeItem>[];
        if (items.isEmpty) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                'No items yet — import footage or create a composition',
                style: t.small,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final rows = <Widget>[];
        void walk(BridgeItem item, int depth) {
          rows.add(_ProjectRow(item: item, depth: depth));
          for (final child in item.children) {
            walk(child, depth + 1);
          }
        }

        for (final item in items) {
          walk(item, 0);
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: rows,
        );
      },
    );
  }
}

/// One Project panel row: a type icon (tinted with the layer colours where it
/// reads well), the item name, indented 14 px per level. Hover fills with
/// `surface4`.
class _ProjectRow extends StatefulWidget {
  final BridgeItem item;
  final int depth;
  const _ProjectRow({required this.item, required this.depth});

  @override
  State<_ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<_ProjectRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final (icon, tint) = _iconFor(widget.item.kind, t);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 22,
        color: _hover ? t.surface4 : null,
        padding: EdgeInsets.only(left: 6.0 + widget.depth * 14.0, right: 6),
        child: Row(
          children: [
            lumitIcon(icon, size: 14, color: tint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.item.name,
                style: t.body,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The icon and its tint for a kind. Footage/composition/solid take their
  /// layer colours; folders take the muted text colour (they are structure, not
  /// content); an unknown kind falls back to a plain muted dot-style icon.
  (LumitIcon, Color) _iconFor(BridgeItemKind kind, LumitTheme t) => switch (kind) {
        BridgeItemKind.footage => (LumitIcon.footage, t.layer.footage),
        BridgeItemKind.folder => (LumitIcon.folder, t.textMuted),
        BridgeItemKind.composition => (LumitIcon.comp, t.layer.precomp),
        BridgeItemKind.solid => (LumitIcon.solid, t.layer.solid),
        BridgeItemKind.unknown => (LumitIcon.footage, t.textMuted),
      };
}

/// The Viewer: the exactly-neutral pasteboard with a placeholder slate and
/// the transport row. The frame texture arrives in phase F2.
class _ViewerStub extends StatelessWidget {
  final AppStateStub app;
  const _ViewerStub({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Container(
      color: t.viewerSurround,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  lumitIcon(LumitIcon.film, size: 32, color: t.textDisabled),
                  const SizedBox(height: 8),
                  Text(
                    'The composited frame arrives with the shared-texture path (phase F2)',
                    style: t.small,
                  ),
                ],
              ),
            ),
          ),
          ListenableBuilder(
            listenable: app,
            builder: (context, _) => Container(
              height: 28,
              color: t.surface1,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  LumitTooltip(
                    message: app.playing ? 'Pause (Space)' : 'Play (Space)',
                    child: HouseButton(
                      frameless: true,
                      small: true,
                      onPressed: app.togglePlay,
                      child: lumitIcon(
                        app.playing ? LumitIcon.pause : LumitIcon.play,
                        size: 14,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('frame ${app.previewFrame}', style: t.small),
                  const Spacer(),
                  Text('Full', style: t.small),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Timeline strip skeleton: comp tab strip, ruler band and bottom bar
/// with the real zoom / magnet / graph-lens controls (backed by the stub).
class _TimelineStub extends StatelessWidget {
  final AppStateStub app;
  const _TimelineStub({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Column(
        children: [
          Container(
            height: 24,
            color: t.surface2,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Text(
                  app.openComps.isEmpty
                      ? 'No composition open'
                      : app.openComps.join(' · '),
                  style: t.small,
                ),
              ],
            ),
          ),
          Container(height: 18, color: t.surface0),
          Expanded(
            child: Center(
              child: Text(
                'Layer rows, lanes and the graph lens arrive in phase F3.',
                style: t.small,
              ),
            ),
          ),
          Container(
            height: 24,
            color: t.surface2,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                HouseButton(
                  frameless: true,
                  small: true,
                  onPressed: () => app.zoomTimeline(1.4),
                  child: Text('+', style: t.bodyPrimary),
                ),
                HouseButton(
                  frameless: true,
                  small: true,
                  onPressed: () => app.zoomTimeline(1 / 1.4),
                  child: Text('−', style: t.bodyPrimary),
                ),
                Text('${app.timelineZoom.round()}%', style: t.small),
                const SizedBox(width: 10),
                LumitTooltip(
                  message: 'Snapping',
                  child: HouseButton(
                    frameless: true,
                    small: true,
                    onPressed: () {
                      app.snapping = !app.snapping;
                      app.setNotice(
                          app.snapping ? 'snapping on' : 'snapping off');
                    },
                    child: lumitIcon(
                      LumitIcon.magnet,
                      size: 13,
                      color: app.snapping ? t.accent : t.textMuted,
                    ),
                  ),
                ),
                const Spacer(),
                LumitTooltip(
                  message: 'Graph editor (Shift+F3)',
                  child: HouseButton(
                    frameless: true,
                    small: true,
                    onPressed: app.toggleGraphMode,
                    child: lumitIcon(
                      LumitIcon.graphCurve,
                      size: 13,
                      color: app.timelineGraphMode ? t.accent : t.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Scopes stub draws the real graticule on the fixed scope colours —
/// never themed (15-DESIGN §8).
class _ScopesStub extends StatelessWidget {
  const _ScopesStub();

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Container(
      color: ScopeColours.standard.bg,
      child: Column(
        children: [
          Container(
            height: 22,
            color: t.surface2,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.centerLeft,
            child: Text('Waveform (luma)', style: t.small),
          ),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _GraticulePainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraticulePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = ScopeColours.standard.graticule
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

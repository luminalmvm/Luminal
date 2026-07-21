// Phase-F0 panel stubs: every panel present with its real name and chrome so
// the workspace reads like the egui frontend, each stating which phase makes
// it live (docs/flutter-port/05-PARITY-CHECKLIST.md). The Viewer's neutral
// pasteboard and the Scopes graticule are real — those are chrome, not data.

import 'package:flutter/widgets.dart';

import '../icons/icons.dart';
import '../state/app_state.dart';
import '../state/dock.dart';
import '../theme/theme.dart';
import '../widgets/controls.dart';

Widget buildPanelBody(BuildContext context, Panel panel, AppStateStub app) =>
    switch (panel) {
      Panel.project => _PlaceholderPanel(
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

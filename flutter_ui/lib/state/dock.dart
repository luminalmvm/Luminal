// The dock layout model, ported from crates/lumit-ui/src/shell/dock.rs
// (which leans on egui_tiles). A serialisable tree of splits, tab groups and
// panes; the widget layer renders it and the model owns the invariants.
//
// In plain terms: the workspace is a tree. A *split* lays its children side by
// side (or stacked) with weighted shares; a *tabs* node stacks panels behind
// one another with a tab bar; a *pane* is one panel. A pane that sits alone —
// not inside a tabs node — renders bare, with no tab bar (K-086).

/// The dockable panels — glossary names (docs/01-GLOSSARY.md §7).
enum Panel {
  project,
  viewer,
  timeline,
  effectControls,
  effectsAndPresets,
  scopes,
  hierarchy;

  String get title => switch (this) {
        Panel.project => 'Project',
        Panel.viewer => 'Viewer',
        Panel.timeline => 'Timeline',
        Panel.effectControls => 'Effect controls',
        Panel.effectsAndPresets => 'Effects & presets',
        Panel.scopes => 'Scopes',
        Panel.hierarchy => 'Hierarchy',
      };
}

enum DockAxis { horizontal, vertical }

sealed class DockNode {
  Map<String, dynamic> toJson();

  static DockNode fromJson(Map<String, dynamic> j) => switch (j['kind']) {
        'pane' => DockPane(Panel.values.asNameMap()[j['panel']]!),
        'tabs' => DockTabs(
            [for (final c in j['children'] as List) fromJson(c as Map<String, dynamic>) as DockPane],
            active: j['active'] as int? ?? 0,
          ),
        'split' => DockSplit(
            j['axis'] == 'vertical' ? DockAxis.vertical : DockAxis.horizontal,
            [for (final c in j['children'] as List) fromJson(c as Map<String, dynamic>)],
            [for (final s in j['shares'] as List) (s as num).toDouble()],
          ),
        _ => throw FormatException('unknown dock node: ${j['kind']}'),
      };
}

class DockPane extends DockNode {
  final Panel panel;
  DockPane(this.panel);

  @override
  Map<String, dynamic> toJson() => {'kind': 'pane', 'panel': panel.name};
}

/// A tab group. Children are panes (egui_tiles allows nesting, but the
/// shipped frontend only ever tabs panes — the port models what ships).
class DockTabs extends DockNode {
  final List<DockPane> children;
  int active;
  DockTabs(this.children, {this.active = 0});

  DockPane get activePane => children[active.clamp(0, children.length - 1)];

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'tabs',
        'active': active,
        'children': [for (final c in children) c.toJson()],
      };
}

class DockSplit extends DockNode {
  final DockAxis axis;
  final List<DockNode> children;

  /// Weighted shares, same length as children, normalised on use.
  final List<double> shares;

  DockSplit(this.axis, this.children, this.shares)
      : assert(children.length == shares.length);

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'split',
        'axis': axis.name,
        'shares': shares,
        'children': [for (final c in children) c.toJson()],
      };
}

/// The default workspace, matching `default_layout()` share-for-share:
/// a vertical root (upper band 0.68, Timeline 0.32 across the full width);
/// the upper band horizontal (left tab group 0.22, Viewer 0.58, Scopes 0.20);
/// the left group tabs Project (fronted), Effect controls, Effects & presets,
/// Hierarchy. Viewer, Scopes and Timeline sit alone and render bare.
DockSplit defaultLayout() => DockSplit(
      DockAxis.vertical,
      [
        DockSplit(
          DockAxis.horizontal,
          [
            DockTabs([
              DockPane(Panel.project),
              DockPane(Panel.effectControls),
              DockPane(Panel.effectsAndPresets),
              DockPane(Panel.hierarchy),
            ]),
            DockPane(Panel.viewer),
            DockPane(Panel.scopes),
          ],
          [0.22, 0.58, 0.20],
        ),
        DockPane(Panel.timeline),
      ],
      [0.68, 0.32],
    );

/// Every panel present in the tree, in visit order.
List<Panel> panelsIn(DockNode node) => switch (node) {
      DockPane(:final panel) => [panel],
      DockTabs(:final children) => [for (final c in children) c.panel],
      DockSplit(:final children) => [
          for (final c in children) ...panelsIn(c),
        ],
    };

/// Bring `panel`'s tab to the front of whichever tab group holds it (the
/// start-up "always open on Project" rule).
void activatePanelTab(DockNode node, Panel panel) {
  switch (node) {
    case DockPane():
      break;
    case DockTabs(:final children):
      final i = children.indexWhere((c) => c.panel == panel);
      if (i >= 0) node.active = i;
    case DockSplit(:final children):
      for (final c in children) {
        activatePanelTab(c, panel);
      }
  }
}

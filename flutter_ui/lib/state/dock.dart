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

// --- Re-dock operations (dock.rs drag-to-redock, via egui_tiles) ----------

/// Where a dragged panel lands relative to the target pane: stacked into its
/// tab group, or splitting off one of its four sides.
enum DropPosition { left, right, above, below, stack }

/// Move `dragged` so it lands relative to `target`'s pane per `pos`, then
/// simplify (dock.rs::dock_simplification_options). A panel dropped onto
/// itself is a no-op. After the move every panel still appears exactly once,
/// each shares list matches its children length, and all shares are positive.
void movePanel(
  DockSplit root,
  Panel dragged,
  Panel target,
  DropPosition pos,
) {
  if (dragged == target) return;
  final present = panelsIn(root).toSet();
  if (!present.contains(dragged) || !present.contains(target)) return;

  _removePanel(root, dragged);
  final loc = _tileOf(root, target);
  // The target should always survive the removal; bail defensively if not.
  if (loc == null) return;

  final draggedPane = DockPane(dragged);
  if (pos == DropPosition.stack) {
    final tile = loc.tile;
    if (tile is DockTabs) {
      tile.children.add(draggedPane);
      tile.active = tile.children.length - 1;
    } else {
      // A solo pane becomes a two-tab group, the newcomer fronted.
      loc.split.children[loc.index] =
          DockTabs([tile as DockPane, draggedPane], active: 1);
    }
  } else {
    final axis = (pos == DropPosition.left || pos == DropPosition.right)
        ? DockAxis.horizontal
        : DockAxis.vertical;
    final before = pos == DropPosition.left || pos == DropPosition.above;
    final split = loc.split;
    if (split.axis == axis) {
      // Same axis: sit adjacent to the target, each taking half its share.
      final half = split.shares[loc.index] / 2;
      split.shares[loc.index] = half;
      final at = before ? loc.index : loc.index + 1;
      split.children.insert(at, draggedPane);
      split.shares.insert(at, half);
    } else {
      // Cross axis: wrap the target tile in a new split of the other axis.
      final tile = loc.tile;
      split.children[loc.index] = DockSplit(
        axis,
        before ? [draggedPane, tile] : [tile, draggedPane],
        [0.5, 0.5],
      );
    }
  }
  simplify(root);
}

/// The DockSplit directly enclosing `panel`'s tile, that tile (a DockPane when
/// the panel sits alone, else the DockTabs holding it), and its index in the
/// split. Null when the panel is absent.
({DockSplit split, DockNode tile, int index})? _tileOf(
  DockSplit split,
  Panel panel,
) {
  for (var i = 0; i < split.children.length; i++) {
    final child = split.children[i];
    if (!panelsIn(child).contains(panel)) continue;
    if (child is DockSplit) return _tileOf(child, panel);
    return (split: split, tile: child, index: i);
  }
  return null;
}

/// Remove `panel`'s pane wherever it sits, redistributing a split child's
/// share proportionally over its siblings and clamping a tab group's active
/// index. Returns whether it was found.
bool _removePanel(DockNode node, Panel panel) {
  switch (node) {
    case DockPane():
      return false;
    case DockTabs(:final children):
      final i = children.indexWhere((c) => c.panel == panel);
      if (i < 0) return false;
      children.removeAt(i);
      if (children.isNotEmpty) {
        node.active = node.active.clamp(0, children.length - 1);
      }
      return true;
    case DockSplit(:final children):
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        if (child is DockPane && child.panel == panel) {
          _removeSplitChild(node, i);
          return true;
        }
        if (_removePanel(child, panel)) return true;
      }
      return false;
  }
}

/// Drop child `i` from `split`, spreading its share over the survivors so the
/// total is preserved.
void _removeSplitChild(DockSplit split, int i) {
  final freed = split.shares[i];
  split.children.removeAt(i);
  split.shares.removeAt(i);
  if (split.shares.isEmpty) return;
  final total = split.shares.reduce((a, b) => a + b);
  if (total <= 0) {
    final equal = 1.0 / split.shares.length;
    for (var k = 0; k < split.shares.length; k++) {
      split.shares[k] = equal;
    }
  } else {
    for (var k = 0; k < split.shares.length; k++) {
      split.shares[k] += freed * split.shares[k] / total;
    }
  }
}

/// The dock's simplification rules, mirroring egui_tiles' options in
/// dock.rs::dock_simplification_options: prune empty tabs and splits, unwrap a
/// single-child tab group to a bare pane (K-086) and a single-child split to
/// its child, and join a nested split into a same-axis parent (scaling the
/// nested child's shares by its own share). The root always stays a DockSplit;
/// were it to collapse to one child, it keeps a one-child split instead.
void simplify(DockSplit root) {
  final result = _simplifyNode(root);
  if (identical(result, root)) return;
  root.children.clear();
  root.shares.clear();
  if (result != null) {
    root.children.add(result);
    root.shares.add(1.0);
  }
}

/// Simplify a node, returning its replacement: the same node (mutated), a
/// different node (when it unwraps), or null (when it prunes away).
DockNode? _simplifyNode(DockNode node) {
  switch (node) {
    case DockPane():
      return node;
    case DockTabs():
      if (node.children.isEmpty) return null;
      if (node.children.length == 1) return node.children.first;
      node.active = node.active.clamp(0, node.children.length - 1);
      return node;
    case DockSplit():
      final children = <DockNode>[];
      final shares = <double>[];
      for (var i = 0; i < node.children.length; i++) {
        final simplified = _simplifyNode(node.children[i]);
        if (simplified == null) continue;
        if (simplified is DockSplit && simplified.axis == node.axis) {
          // Join a same-axis nested split, scaling its shares by its own.
          final total = simplified.shares.reduce((a, b) => a + b);
          for (var k = 0; k < simplified.children.length; k++) {
            children.add(simplified.children[k]);
            shares.add(node.shares[i] *
                (total <= 0
                    ? 1.0 / simplified.shares.length
                    : simplified.shares[k] / total));
          }
        } else {
          children.add(simplified);
          shares.add(node.shares[i]);
        }
      }
      if (children.isEmpty) return null;
      if (children.length == 1) return children.first;
      node.children
        ..clear()
        ..addAll(children);
      node.shares
        ..clear()
        ..addAll(shares);
      return node;
  }
}

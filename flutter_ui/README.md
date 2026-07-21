# lumit_flutter — the Flutter frontend alternative

The experimental Flutter port of Lumit's interface (decision K-174). The Rust
engine crates are untouched; this package is the chrome, built to one-for-one
parity with the egui frontend before any redesign.

**The plan, the full UI inventory and the living parity checklist live in
[`docs/flutter-port/`](../docs/flutter-port/README.md).** Read
`docs/GUIDE.md` §9 for the plain-English framing.

## Running

Requires the Flutter SDK (stable) and the same VS 2022 C++ tools the Rust
build uses.

```
flutter run -d windows    # launch
flutter test              # the test suite
flutter analyze           # the lint pass (must stay clean)
```

## House rules

- `lib/theme/theme.dart` is the only file where colour hex values may appear.
- Glossary terms bind (docs/01-GLOSSARY.md): layer not track, speed not
  velocity, Retime not time remap, export not render.
- British English, sentence case, no exclamation marks, no emoji.
- Owned widgets over Material chrome — see docs/flutter-port/04-WIDGET-MAP.md.
- Every feature lands with its tests.

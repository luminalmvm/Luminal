import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumit_flutter/main.dart';
import 'package:lumit_flutter/src/rust/api.dart';
import 'package:provider/provider.dart';

class LayerBuilder extends StatefulWidget {
  const LayerBuilder({required this.layer, required this.builder, super.key});

  final LumitLayer layer;
  final Widget Function(BuildContext context) builder;

  @override
  State<LayerBuilder> createState() => _LayerBuilderState();
}

class _LayerBuilderState extends State<LayerBuilder> {
  StreamSubscription? sub;

  @override
  void initState() {
    final store = Provider.of<LumitState>(context, listen: false);
    sub = store.onChange.listen(onChange);
    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: widget.builder(context));
  }

  void onChange(ScopedChange event) {
    if (event.layer == null) return;

    if (event.layer!.equals(layer: widget.layer)) {
      setState(() {});
    }
  }
}

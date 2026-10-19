import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'common.dart';

/// Carrega dados do mês selecionado e recarrega quando o mês ou os dados mudam.
class MonthLoader<T> extends StatefulWidget {
  final Future<T> Function(AppState state) load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  const MonthLoader({super.key, required this.load, required this.builder});

  @override
  State<MonthLoader<T>> createState() => _MonthLoaderState<T>();
}

class _MonthLoaderState<T> extends State<MonthLoader<T>> {
  Future<T>? _future;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    final key = '${state.monthKey}#${state.revision}';
    if (key != _key) {
      _key = key;
      _future = widget.load(state);
    }
  }

  Future<void> _reload() async {
    final state = context.read<AppState>()..clearCache();
    final f = widget.load(state);
    setState(() {
      _future = f;
    });
    // O erro aparece pelo FutureBuilder; aqui só esperamos para o indicador de "atualizando" sumir.
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const _Skeleton();
          return RefreshIndicator(onRefresh: _reload, child: widget.builder(context, snap.data as T, _reload));
        },
      );
}

/// Cartões cinza pulsando no lugar do conteúdo enquanto o mês carrega.
class _Skeleton extends StatefulWidget {
  const _Skeleton();
  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget box(double h) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(20)),
        );
    return FadeTransition(
      opacity: Tween(begin: .45, end: 1.0).animate(_c),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [box(150), box(96), box(120), box(220)],
      ),
    );
  }
}

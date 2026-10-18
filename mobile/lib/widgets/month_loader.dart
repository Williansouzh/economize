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
    final f = widget.load(context.read<AppState>());
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
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(onRefresh: _reload, child: widget.builder(context, snap.data as T, _reload));
        },
      );
}

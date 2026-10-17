import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Vincula o WhatsApp: o app gera um código e o usuário envia "VINCULAR 123456" para o assistente.
class WhatsAppScreen extends StatefulWidget {
  const WhatsAppScreen({super.key});
  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen> {
  late Future<String?> _linked = context.read<AppState>().api.linkedWhatsApp();
  String? _code;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refresh() => setState(() {
        _code = null;
        _linked = context.read<AppState>().api.linkedWhatsApp();
      });

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Assistente no WhatsApp')),
      body: FutureBuilder<String?>(
        future: _linked,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _refresh);
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final phone = snap.data;
          return ListView(padding: const EdgeInsets.all(24), children: [
            Icon(Icons.chat, size: 64, color: cs.primary),
            const SizedBox(height: 12),
            const Text(
              'Registre gastos mandando texto, áudio ou print de comprovante no WhatsApp. '
              'A IA entende, categoriza e lança tudo aqui no app.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (phone != null) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: const Text('Conectado'),
                  subtitle: Text('+$phone'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(() async {
                  await api.unlinkWhatsApp();
                  _refresh();
                }),
                child: const Text('Desconectar'),
              ),
            ] else if (_code == null)
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(() async {
                  final code = await api.whatsAppLinkCode();
                  setState(() => _code = code);
                }),
                icon: const Icon(Icons.link),
                label: const Text('Gerar código de vinculação'),
              )
            else ...[
              Text(
                whatsappBotNumber.isEmpty
                    ? 'Envie esta mensagem para o número do assistente:'
                    : 'Envie esta mensagem para $whatsappBotNumber:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Card(
                color: cs.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText('VINCULAR $_code',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: 'VINCULAR $_code'));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Copiado!')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar'),
              ),
              const Text('O código vale por 10 minutos.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _refresh, child: const Text('Já enviei')),
            ],
          ]);
        },
      ),
    );
  }
}

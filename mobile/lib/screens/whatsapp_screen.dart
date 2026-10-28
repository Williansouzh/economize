import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';

/// Vincula o WhatsApp: o app gera um código e abre a conversa com o assistente já com
/// "VINCULAR 123456" escrito. Copiar o código fica como plano B.
class WhatsAppScreen extends StatefulWidget {
  const WhatsAppScreen({super.key});
  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen> {
  late Future<String?> _linked = context.read<AppState>().api.linkedWhatsApp();
  String? _code;
  bool _busy = false;

  /// Número do assistente só com dígitos, para o link wa.me. Vazio quando o app foi gerado sem ele.
  static final _botDigits = whatsappBotNumber.replaceAll(RegExp(r'\D'), '');

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

  Future<String> _ensureCode() async {
    final code = _code ?? await context.read<AppState>().api.whatsAppLinkCode();
    if (mounted) setState(() => _code = code);
    return code;
  }

  Future<void> _openWhatsApp() => _run(() async {
        final code = await _ensureCode();
        final uri = Uri.parse('https://wa.me/$_botDigits?text=${Uri.encodeComponent('VINCULAR $code')}');
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
          showError(context, 'Não consegui abrir o WhatsApp. Use o código abaixo.');
        }
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
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final phone = snap.data;
          return ListView(padding: const EdgeInsets.all(24), children: [
            const Center(child: MascotAvatar(size: 112, pose: MascotPose.phone)),
            const SizedBox(height: 16),
            Text(
              phone != null ? 'Tudo certo! É só mandar mensagem.' : 'Anote gastos pelo WhatsApp',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Mande texto, áudio ou o print do comprovante: "gastei 30 no almoço". '
              'A IA entende, escolhe a categoria e lança aqui no app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 24),
            if (phone != null) ...[
              Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_rounded, color: context.colors.success),
                  title: const Text('Conectado'),
                  subtitle: Text('+$phone'),
                ),
              ),
              const SizedBox(height: 12),
              if (_botDigits.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://wa.me/$_botDigits'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Abrir a conversa'),
                ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: context.colors.expense),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await api.unlinkWhatsApp();
                          _refresh();
                        }),
                child: const Text('Desconectar'),
              ),
            ] else ...[
              if (_botDigits.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: _busy ? null : _openWhatsApp,
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Abrir no WhatsApp'),
                ),
                const SizedBox(height: 8),
                Text('A mensagem com o código já vai escrita. É só tocar em enviar.',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ] else if (_code == null)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(_ensureCode),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Gerar código de vinculação'),
                ),
              if (_code != null) ...[
                const SizedBox(height: 24),
                Text(
                  _botDigits.isEmpty
                      ? 'Envie esta mensagem para o número do assistente:'
                      : 'Se o WhatsApp não abriu, envie esta mensagem para $whatsappBotNumber:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Card(
                  color: cs.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText('VINCULAR $_code',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: cs.onPrimaryContainer)),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: 'VINCULAR $_code'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado!')));
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copiar'),
                ),
                Text('O código vale por 10 minutos.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: _refresh, child: const Text('Já enviei')),
              ],
            ],
          ]);
        },
      ),
    );
  }
}

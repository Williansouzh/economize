import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// RN-30: exclusão definitiva da conta e de todos os dados, confirmada com a senha.
/// Com [resetOnly] (RN-41), apaga só os dados e mantém o cadastro: "começar do zero".
class DeleteAccountScreen extends StatefulWidget {
  final bool resetOnly;
  const DeleteAccountScreen({super.key, this.resetOnly = false});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _deleting = false;

  bool get _reset => widget.resetOnly;

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      showError(context, 'Digite sua senha para confirmar.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: expenseColor),
        title: Text(_reset ? 'Apagar tudo e recomeçar?' : 'Excluir para sempre?'),
        content: Text(_reset
            ? 'Seus lançamentos, contas, orçamentos e metas serão apagados agora. Isso não pode ser desfeito.'
            : 'Todos os seus dados serão apagados agora. Isso não pode ser desfeito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: expenseColor),
            onPressed: () => Navigator.pop(c, true),
            child: Text(_reset ? 'Apagar' : 'Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _deleting = true);
    try {
      if (_reset) {
        await state.resetData(_password.text);
        navigator.popUntil((r) => r.isFirst);
        messenger.showSnackBar(const SnackBar(content: Text('Pronto! Seus dados foram apagados. Vamos recomeçar.')));
      } else {
        await state.api.deleteAccount(_password.text);
        navigator.popUntil((r) => r.isFirst);
        await state.logout();
        messenger.showSnackBar(const SnackBar(content: Text('Sua conta e seus dados foram excluídos.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget item(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(_reset ? 'Começar do zero' : 'Excluir minha conta')),
      body: ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom), children: [
        Center(child: IconBadge(_reset ? Icons.restart_alt : Icons.delete_forever_outlined, expenseColor, size: 72)),
        const SizedBox(height: 16),
        Text('Isso apaga definitivamente:',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              if (!_reset) item(Icons.person_outline, 'Seu cadastro (nome, e-mail e senha)'),
              item(Icons.account_balance_wallet_outlined,
                  _reset ? 'Contas, cartões, lançamentos e transferências' : 'Contas, lançamentos, transferências e orçamentos'),
              if (_reset) item(Icons.savings_outlined, 'Orçamentos, metas e a sua sequência'),
              item(Icons.category_outlined, _reset ? 'As categorias que você criou ou mudou' : 'Suas categorias'),
              item(Icons.chat_outlined,
                  _reset ? 'O histórico de conversas com o assistente' : 'O vínculo com o WhatsApp e o histórico de conversas com o assistente'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _reset
              ? 'Continuam: seu cadastro, sua senha e o WhatsApp conectado. A conta volta como nova, com a '
                  'Carteira e as categorias padrão. Se quiser guardar uma cópia antes, use "Exportar planilha".'
              : 'Os dados saem do banco na hora. Cópias de segurança antigas são apagadas automaticamente '
                  'em até 14 dias. Não é possível recuperar a conta depois.',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Sua senha', prefixIcon: Icon(Icons.lock_outline)),
          onSubmitted: (_) => _delete(),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: expenseColor, foregroundColor: Colors.white),
          onPressed: _deleting ? null : _delete,
          icon: _deleting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_reset ? Icons.restart_alt : Icons.delete_forever),
          label: Text(_reset ? 'Apagar meus dados' : 'Excluir minha conta'),
        ),
      ]),
    );
  }
}

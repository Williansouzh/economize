import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';

/// "Esqueci minha senha": e-mail → código de 6 dígitos → nova senha. Ao terminar, já entra na conta.
class ForgotPasswordScreen extends StatefulWidget {
  final String email;
  const ForgotPasswordScreen({super.key, this.email = ''});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false, _busy = false, _show = false;

  Future<void> _send() async {
    if (!_email.text.contains('@')) {
      showError(context, 'Digite o e-mail da sua conta.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.forgotPassword(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_code.text.trim().length != 6) {
      showError(context, 'Digite o código de 6 números que chegou no e-mail.');
      return;
    }
    setState(() => _busy = true);
    final state = context.read<AppState>();
    try {
      await state.resetPassword(_email.text.trim(), _code.text.trim(), _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar senha')),
      body: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.paddingOf(context).bottom), children: [
        Text(
          _sent
              ? 'Se existir uma conta com ${_email.text.trim()}, enviamos um código de 6 números. '
                  'Ele vale por 15 minutos. Confira também a caixa de spam.'
              : 'Digite o e-mail da sua conta. Vamos enviar um código para você criar uma nova senha.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          enabled: !_sent,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
        ),
        if (_sent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Código', prefixIcon: Icon(Icons.pin_outlined)),
          ),
          TextField(
            controller: _password,
            obscureText: !_show,
            decoration: InputDecoration(
              labelText: 'Nova senha',
              helperText: 'Pelo menos 8 caracteres',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : (_sent ? _reset : _send),
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_sent ? 'Criar nova senha' : 'Enviar código'),
        ),
        if (_sent)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _sent = false),
            child: const Text('Não chegou? Enviar de novo'),
          ),
      ]),
    );
  }
}

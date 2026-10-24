import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';

/// Botão do topo com o perfil ativo (Pessoal ou a empresa). Toque abre a troca de perfil (RN-47).
class ProfileSwitcher extends StatelessWidget {
  const ProfileSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activeProfile;
    if (active == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Trocar de perfil',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showProfileSheet(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: BoxDecoration(
            color: active.isBusiness ? tinta : cs.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(active.isBusiness ? Icons.storefront_rounded : Icons.person_rounded,
                size: 16, color: active.isBusiness ? lima : cs.onPrimaryContainer),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(active.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: active.isBusiness ? Colors.white : cs.onPrimaryContainer)),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: active.isBusiness ? Colors.white : cs.onPrimaryContainer),
          ]),
        ),
      ),
    );
  }
}

Future<void> showProfileSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        final state = sheet.watch<AppState>();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Qual dinheiro você quer ver?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Cada perfil tem as próprias contas, categorias e lançamentos.',
                  style: TextStyle(color: Theme.of(sheet).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              for (final p in state.profiles)
                Card(
                  child: ListTile(
                    leading: IconBadge(p.isBusiness ? Icons.storefront_rounded : Icons.person_rounded,
                        p.isBusiness ? tinta : mar, size: 40),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(p.isBusiness ? (p.isMei ? 'Empresa · MEI' : 'Empresa · PJ') : 'Pessoa física'),
                    trailing: p.id == state.activeProfile?.id
                        ? const Icon(Icons.check_circle_rounded, color: incomeColor)
                        : p.isBusiness
                            ? IconButton(
                                tooltip: 'Excluir perfil',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _confirmDelete(sheet, p),
                              )
                            : null,
                    onTap: () {
                      Navigator.pop(sheet);
                      if (p.id != state.activeProfile?.id) state.switchProfile(p);
                    },
                  ),
                ),
              if (state.profiles.where((p) => p.isBusiness).length < 2)
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheet);
                    final created = await Navigator.push<Profile>(
                        context, MaterialPageRoute(builder: (_) => const BusinessProfileScreen()));
                    if (created != null && context.mounted) context.read<AppState>().switchProfile(created);
                  },
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Criar perfil de empresa (PJ/MEI)'),
                ),
            ]),
          ),
        );
      },
    );

Future<void> _confirmDelete(BuildContext context, Profile p) async {
  final password = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.delete_forever_outlined),
      title: Text('Excluir "${p.name}"?'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('As contas, categorias e lançamentos da empresa são apagados para sempre. '
            'Seu perfil pessoal não muda.'),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Sua senha'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await context.read<AppState>().deleteBusinessProfile(p, password.text);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Cria o perfil de empresa: nome, CNPJ (opcional) e se é MEI.
class BusinessProfileScreen extends StatefulWidget {
  /// No onboarding a tela não navega: devolve o perfil pelo callback.
  final ValueChanged<Profile>? onCreated;
  final bool embedded;
  const BusinessProfileScreen({super.key, this.onCreated, this.embedded = false});

  @override
  State<BusinessProfileScreen> createState() => BusinessProfileFormState();
}

class BusinessProfileFormState extends State<BusinessProfileScreen> {
  final name = TextEditingController();
  final cnpj = TextEditingController();
  bool isMei = true;
  bool _busy = false;

  bool get valid => name.text.trim().isNotEmpty;

  /// Salva e devolve o perfil criado (null se faltar o nome ou der erro).
  Future<Profile?> save() async {
    if (!valid) return null;
    setState(() => _busy = true);
    try {
      final digits = cnpj.text.replaceAll(RegExp(r'\D'), '');
      return await context
          .read<AppState>()
          .createBusinessProfile(name.text.trim(), cnpj: digits.isEmpty ? null : digits, isMei: isMei);
    } catch (e) {
      if (mounted) showError(context, e);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    cnpj.dispose();
    super.dispose();
  }

  Widget form() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          maxLength: 60,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Nome da empresa',
            hintText: 'Ex.: Doces da Ana',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: cnpj,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
          decoration: const InputDecoration(
            labelText: 'CNPJ (opcional)',
            hintText: 'Só números',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: isMei,
          onChanged: (v) => setState(() => isMei = v),
          title: const Text('É MEI', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Eu acompanho o faturamento do ano e aviso antes do teto de R\$ 81 mil.'),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return form();
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil de empresa')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MascotAvatar(size: 64),
          Expanded(
            child: SpeechBubble(
              tailLeft: true,
              child: Text('Separar o dinheiro da empresa do pessoal é o melhor hábito de quem empreende. 💼',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.4)),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        form(),
        const SizedBox(height: 20),
        ChunkyButton(
          label: 'Criar perfil',
          busy: _busy,
          onPressed: valid
              ? () async {
                  final p = await save();
                  if (p != null && context.mounted) Navigator.pop(context, p);
                }
              : null,
        ),
      ]),
    );
  }
}

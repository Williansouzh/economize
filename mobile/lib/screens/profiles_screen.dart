import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';

/// Chips "Pessoal · Empresa · +" do topo da tela Perfil: troca de perfil num toque (RN-47).
class ProfileChips extends StatelessWidget {
  const ProfileChips({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activeProfile;
    final cs = Theme.of(context).colorScheme;
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final p in state.profiles)
        ChoiceChip(
          label: Text(p.isBusiness ? p.name : 'Pessoal'),
          selected: p.id == active?.id,
          onSelected: (_) {
            if (p.id != active?.id) {
              HapticFeedback.selectionClick();
              state.switchProfile(p);
            }
          },
        ),
      if (state.profiles.where((p) => p.isBusiness).length < 2)
        Tooltip(
          message: 'Criar perfil de empresa',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => createBusinessProfile(context),
            child: Container(
              width: 44,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outline, style: BorderStyle.solid),
              ),
              child: Icon(Icons.add_rounded, color: cs.primary),
            ),
          ),
        ),
    ]);
  }
}

/// Abre a criação do perfil de empresa e, se criar, já troca para ele.
Future<void> createBusinessProfile(BuildContext context) async {
  final created = await Navigator.push<Profile>(context, MaterialPageRoute(builder: (_) => const BusinessProfileScreen()));
  if (created != null && context.mounted) context.read<AppState>().switchProfile(created);
}

/// Folha "Qual dinheiro você quer ver?", aberta pelo nome do perfil no topo das abas.
Future<void> showProfileSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      builder: (sheet) {
        final state = sheet.watch<AppState>();
        final cs = Theme.of(sheet).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Qual dinheiro você quer ver?', style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Cada perfil tem as próprias contas, categorias e lançamentos.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              for (final p in state.profiles)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: IconBadge(p.isBusiness ? Icons.storefront_rounded : Icons.person_rounded, cs.primary),
                  title: Text(p.isBusiness ? p.name : 'Pessoal'),
                  subtitle: Text(p.isBusiness ? (p.isMei ? 'Empresa · MEI' : 'Empresa · PJ') : 'Pessoa física'),
                  trailing: p.id == state.activeProfile?.id
                      ? Icon(Icons.check_circle_rounded, color: context.colors.success)
                      : null,
                  onTap: () {
                    Navigator.pop(sheet);
                    if (p.id != state.activeProfile?.id) state.switchProfile(p);
                  },
                ),
              if (state.profiles.where((p) => p.isBusiness).length < 2) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheet);
                    createBusinessProfile(context);
                  },
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Criar perfil de empresa'),
                ),
              ],
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
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.colors.expense, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Excluir perfil'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await context.read<AppState>().deleteBusinessProfile(p, password.text);
    if (context.mounted) Navigator.pop(context);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Cria ou edita o perfil de empresa: nome, CNPJ (opcional) e se é MEI. Excluir fica aqui dentro,
/// longe da troca de perfil (evita toque acidental).
class BusinessProfileScreen extends StatefulWidget {
  final bool embedded;
  final Profile? editing;
  const BusinessProfileScreen({super.key, this.embedded = false, this.editing});

  @override
  State<BusinessProfileScreen> createState() => BusinessProfileFormState();
}

class BusinessProfileFormState extends State<BusinessProfileScreen> {
  late final name = TextEditingController(text: widget.editing?.name);
  late final cnpj = TextEditingController(text: widget.editing?.cnpj);
  late bool isMei = widget.editing?.isMei ?? true;
  bool _busy = false;

  bool get valid => name.text.trim().isNotEmpty;

  /// Salva e devolve o perfil (null se faltar o nome ou der erro).
  Future<Profile?> save() async {
    if (!valid) return null;
    setState(() => _busy = true);
    try {
      final digits = cnpj.text.replaceAll(RegExp(r'\D'), '');
      final state = context.read<AppState>();
      return widget.editing == null
          ? await state.createBusinessProfile(name.text.trim(), cnpj: digits.isEmpty ? null : digits, isMei: isMei)
          : await state.updateBusinessProfile(widget.editing!, name.text.trim(),
              cnpj: digits.isEmpty ? null : digits, isMei: isMei);
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
          title: const Text('É MEI'),
          subtitle: const Text('Eu acompanho o faturamento do ano e aviso antes do teto de R\$ 81 mil.'),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return form();
    final editing = widget.editing;
    return Scaffold(
      appBar: AppBar(title: Text(editing == null ? 'Perfil de empresa' : 'Editar perfil')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (editing == null) ...[
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
        ],
        form(),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: valid && !_busy
              ? () async {
                  final p = await save();
                  if (p != null && context.mounted) Navigator.pop(context, p);
                }
              : null,
          child: Text(editing == null ? 'Criar perfil' : 'Salvar'),
        ),
        if (editing != null) ...[
          const SizedBox(height: 32),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: context.colors.expense),
            onPressed: () => _confirmDelete(context, editing),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Excluir este perfil'),
          ),
        ],
      ]),
    );
  }
}

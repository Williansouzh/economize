import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/bank_notifications.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'import_screen.dart';

/// Gastos do banco (RN-43): ativa a leitura das notificações e mostra o que foi detectado,
/// agrupado por banco, para revisar e lançar.
class BankNotificationsScreen extends StatefulWidget {
  const BankNotificationsScreen({super.key});
  @override
  State<BankNotificationsScreen> createState() => _BankNotificationsScreenState();
}

class _BankNotificationsScreenState extends State<BankNotificationsScreen> with WidgetsBindingObserver {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Volta das configurações do Android: confere se o acesso foi liberado.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final state = context.read<AppState>();
    final enabled = await state.bankNotifications.isEnabled();
    await state.refreshDetected();
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _review(String package, List<DetectedNotification> items) async {
    final state = context.read<AppState>();
    final accountId = await state.bankAccount(package) ?? state.defaultAccountId;
    if (accountId == null || !mounted) return;
    var usedAccount = accountId;
    final created = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportReviewScreen(
          title: items.first.bankName,
          lines: [for (final d in items) d.line!],
          accountId: accountId,
          onAccountChanged: (id) => usedAccount = id,
        ),
      ),
    );
    if (created == null) return;
    // Revisou: o que lançou e o que deixou de fora saem da fila.
    await state.rememberBankAccount(package, usedAccount);
    await state.bankNotifications.remove([for (final d in items) d.id]);
    await state.refreshDetected();
  }

  Future<void> _discard(List<DetectedNotification> items) async {
    final state = context.read<AppState>();
    await state.bankNotifications.remove([for (final d in items) d.id]);
    await state.refreshDetected();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final groups = <String, List<DetectedNotification>>{};
    for (final d in state.detected) {
      groups.putIfAbsent(d.package, () => []).add(d);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Gastos do banco')),
      body: _enabled == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (!_enabled!) ...[
                  const Center(child: IconBadge(Icons.notifications_active_outlined, Color(0xFF00875A), size: 72)),
                  const SizedBox(height: 16),
                  Text(
                    'Lance seus gastos sem digitar',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quando o app do seu banco avisar uma compra ou um Pix, o Economizze lê o aviso e deixa o '
                    'lançamento pronto. Você só confere e confirma.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sua privacidade', style: TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          const Text(
                            '• Só lemos avisos destes apps de banco; os de outros apps (WhatsApp, e-mail...) são ignorados.',
                          ),
                          const Text(
                            '• Os avisos ficam só no seu celular. Só o lançamento que você confirmar vai para a sua conta.',
                          ),
                          const Text('• Você desliga quando quiser, nas configurações do Android.'),
                          const SizedBox(height: 8),
                          Text(bankApps.values.join(' · '), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      await state.reminders.requestPermission();
                      await state.bankNotifications.openSettings();
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Permitir acesso aos avisos'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Na tela que abrir, toque em "Economizze" e permita. Depois é só voltar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ] else ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.check_circle, color: incomeColor),
                      title: const Text('Ativado'),
                      subtitle: const Text('Novas compras e Pix do banco aparecem aqui'),
                      trailing: TextButton(
                        onPressed: state.bankNotifications.openSettings,
                        child: const Text('Desativar'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'Nada pendente',
                      message: 'Quando o banco avisar uma compra ou um Pix, ele aparece aqui.',
                    )
                  else
                    for (final entry in groups.entries)
                      _BankGroup(
                        entry.value,
                        onReview: () => _review(entry.key, entry.value),
                        onDiscard: () => _discard(entry.value),
                      ),
                ],
              ],
            ),
    );
  }
}

class _BankGroup extends StatelessWidget {
  final List<DetectedNotification> items;
  final VoidCallback onReview, onDiscard;
  const _BankGroup(this.items, {required this.onReview, required this.onDiscard});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dates = DateFormat('dd/MM HH:mm');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(items.first.bankName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final d in items.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.line!.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(dates.format(d.posted), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Text(
                      '${d.line!.amount < 0 ? '-' : '+'}${money(d.line!.amount.abs())}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: d.line!.amount < 0 ? expenseColor : incomeColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            if (items.length > 5) Text('e mais ${items.length - 5}', style: TextStyle(color: cs.onSurfaceVariant)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDiscard, child: const Text('Descartar')),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: onReview,
                  child: Text(items.length == 1 ? 'Revisar e lançar' : 'Revisar ${items.length}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso no Início quando há gastos detectados esperando revisão.
class DetectedBanner extends StatelessWidget {
  const DetectedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.select<AppState, int>((s) => s.detected.length);
    if (count == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BankNotificationsScreen())),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.bolt, color: cs.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    count == 1 ? '1 movimentação do banco para lançar' : '$count movimentações do banco para lançar',
                    style: TextStyle(fontWeight: FontWeight.w800, color: cs.onPrimaryContainer),
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/app_icon.dart';
import '../services/bank_notifications.dart';
import '../services/reminders.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/save_file.dart';
import '../widgets/common.dart';
import 'achievements_screen.dart';
import 'admin_screen.dart';
import 'analysis_screen.dart';
import 'bank_notifications_screen.dart';
import 'categories_screen.dart';
import 'delete_account_screen.dart';
import 'import_screen.dart';
import 'insights_screen.dart';
import 'profiles_screen.dart';
import 'reminders_screen.dart';
import 'whatsapp_screen.dart';

/// Perfil e ajustes: o avatar abre esta página no lugar do antigo menu de 15 itens.
/// Cabeçalho com nome, sequência e perfis; grupos Seu dinheiro · Organização · Trazer dados · App · Conta.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    if (!state.whatsAppChecked) state.loadWhatsApp();
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Future<void> _export() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Gerando a planilha...')));
    try {
      final bytes = await state.api.exportCsv();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await saveFile(bytes, 'economizze-$today.csv', 'text/csv');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _logoutEverywhere() async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.devices_outlined),
        title: const Text('Sair de todos os aparelhos?'),
        content: const Text(
            'Sua conta será desconectada em todos os celulares e navegadores, inclusive neste. '
            'Use se perdeu um aparelho ou entrou em um computador de outra pessoa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sair de todos')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await state.logoutEverywhere();
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pickTheme() async {
    final state = context.read<AppState>();
    final mode = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('Tema', style: Theme.of(c).textTheme.titleLarge),
            ),
            for (final (m, label, icon) in const [
              (ThemeMode.system, 'Automático (o do celular)', Icons.brightness_auto_outlined),
              (ThemeMode.light, 'Claro', Icons.light_mode_outlined),
              (ThemeMode.dark, 'Escuro', Icons.dark_mode_outlined),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: state.themeMode == m ? Icon(Icons.check_rounded, color: Theme.of(c).colorScheme.primary) : null,
                onTap: () => Navigator.pop(c, m),
              ),
          ]),
        ),
      ),
    );
    if (mode != null) state.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final business = state.inBusinessProfile;
    final active = state.activeProfile;
    final themeLabel = switch (state.themeMode) {
      ThemeMode.light => 'Claro',
      ThemeMode.dark => 'Escuro',
      ThemeMode.system => 'Automático',
    };
    final categories = state.categories.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          const _Header(),
          const SizedBox(height: Space.xxl),
          NavGroup(title: 'Seu dinheiro', children: [
            NavRow(
              icon: Icons.monitor_heart_outlined,
              title: business ? 'Situação da empresa' : 'Seu mês e ponto de partida',
              onTap: () => _open(const AnalysisScreen()),
            ),
            if (!business)
              NavRow(
                icon: Icons.person_outline_rounded,
                title: 'Sobre você',
                value: state.about?.completed == true ? 'Respondido' : 'Questionário',
                onTap: () => _open(const AboutScreen()),
              ),
            FutureBuilder<Progress>(
              key: ValueKey(state.revision),
              future: state.progress(),
              builder: (context, snap) {
                final p = snap.data;
                return NavRow(
                  icon: Icons.emoji_events_outlined,
                  title: 'Conquistas',
                  value: p == null ? null : '${p.achievements.where((a) => a.unlocked).length} de ${p.achievements.length}',
                  onTap: () => _open(const AchievementsScreen()),
                );
              },
            ),
          ]),
          const SizedBox(height: Space.xxl),
          NavGroup(title: 'Organização', children: [
            NavRow(
              icon: Icons.category_outlined,
              title: 'Categorias',
              value: categories == 0 ? null : '$categories',
              onTap: () => _open(const CategoriesScreen()),
            ),
            NavRow(
              icon: Icons.storefront_outlined,
              title: business ? 'Editar perfil da empresa' : 'Perfis e empresa',
              value: state.profiles.any((p) => p.isBusiness && p.isMei)
                  ? 'MEI'
                  : state.profiles.any((p) => p.isBusiness)
                      ? 'PJ'
                      : 'Criar',
              onTap: () {
                if (business && active != null) {
                  _open(BusinessProfileScreen(editing: active));
                } else if (state.profiles.any((p) => p.isBusiness)) {
                  showProfileSheet(context);
                } else {
                  createBusinessProfile(context);
                }
              },
            ),
            if (Reminders.supported)
              NavRow(icon: Icons.notifications_outlined, title: 'Lembretes', onTap: () => _open(const RemindersScreen())),
          ]),
          const SizedBox(height: Space.xxl),
          NavGroup(title: 'Trazer dados', children: [
            NavRow(
              icon: Icons.chat_outlined,
              title: 'Assistente no WhatsApp',
              value: state.whatsAppPhone != null ? 'Conectado' : 'Conectar',
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatsAppScreen()));
                state.loadWhatsApp();
              },
            ),
            NavRow(
              icon: Icons.upload_file_outlined,
              title: 'Importar extrato',
              value: 'OFX, CSV, PDF',
              onTap: () => _open(const ImportScreen()),
            ),
            if (BankNotifications.supported)
              NavRow(icon: Icons.bolt_outlined, title: 'Gastos do banco', onTap: () => _open(const BankNotificationsScreen())),
            NavRow(icon: Icons.table_view_outlined, title: 'Exportar planilha', value: 'CSV', onTap: _export),
          ]),
          const SizedBox(height: Space.xxl),
          NavGroup(title: 'App', children: [
            NavRow(icon: Icons.palette_outlined, title: 'Tema', value: themeLabel, onTap: _pickTheme),
            if (AppIcon.supported)
              NavRow(
                icon: Icons.apps_outlined,
                title: 'Ícone que muda com o mês',
                onTap: () => state.setDynamicIcon(!state.dynamicIcon),
                trailing: Switch(value: state.dynamicIcon, onChanged: state.setDynamicIcon),
              ),
            NavRow(
              icon: Icons.lock_outline_rounded,
              title: 'Privacidade e IA',
              onTap: () => showAiPrivacySheet(context),
            ),
            NavRow(
              icon: Icons.shield_outlined,
              title: 'Política de privacidade',
              trailing: Icon(Icons.open_in_new_rounded, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => launchUrl(Uri.parse(privacyPolicyUrl), mode: LaunchMode.externalApplication),
            ),
            if (state.isAdmin)
              NavRow(icon: Icons.insights_outlined, title: 'Painel do admin', onTap: () => _open(const AdminScreen())),
          ]),
          const SizedBox(height: Space.xxl),
          NavGroup(title: 'Conta', children: [
            NavRow(
              icon: Icons.logout_rounded,
              title: 'Sair',
              onTap: () {
                Navigator.popUntil(context, (r) => r.isFirst);
                state.logout();
              },
            ),
            NavRow(icon: Icons.devices_outlined, title: 'Sair de todos os aparelhos', onTap: _logoutEverywhere),
            NavRow(
              icon: Icons.restart_alt_rounded,
              title: 'Começar do zero',
              onTap: () => _open(const DeleteAccountScreen(resetOnly: true)),
            ),
            NavRow(
              icon: Icons.delete_forever_outlined,
              title: 'Excluir minha conta',
              color: context.colors.expense,
              onTap: () => _open(const DeleteAccountScreen()),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final name = (state.userName ?? '').trim();
    final active = state.activeProfile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: cs.primaryContainer,
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: TextStyle(fontSize: 24, color: cs.onPrimaryContainer, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isEmpty ? 'Minha conta' : name, style: Theme.of(context).textTheme.titleLarge),
                FutureBuilder<Progress>(
                  key: ValueKey(state.revision),
                  future: state.progress(),
                  builder: (context, snap) {
                    final p = snap.data;
                    if (p == null) return const SizedBox(height: 18);
                    final unlocked = p.achievements.where((a) => a.unlocked).length;
                    return Text(
                      '${p.streak == 1 ? '1 dia seguido' : '${p.streak} dias seguidos'} · '
                      '$unlocked de ${p.achievements.length} conquistas',
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
              ]),
            ),
            IconButton(
              tooltip: state.inBusinessProfile ? 'Editar perfil da empresa' : 'Editar respostas sobre você',
              icon: Icon(Icons.edit_outlined, color: cs.primary),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => state.inBusinessProfile && active != null
                      ? BusinessProfileScreen(editing: active)
                      : const AboutScreen(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: Space.lg),
          Text('Qual dinheiro você quer ver?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
          const SizedBox(height: Space.sm),
          const ProfileChips(),
        ]),
      ),
    );
  }
}

/// Chip "🔥 12 dias" do topo do Início: a sequência de dias registrando. Toque abre as conquistas.
class StreakPill extends StatelessWidget {
  const StreakPill({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Progress>(
      key: ValueKey(state.revision),
      future: state.progress(),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null) return const SizedBox.shrink();
        final active = p.registeredToday;
        final label = p.streak == 1 ? '1 dia' : '${p.streak} dias';
        return Tooltip(
          message: active ? 'Sequência de $label registrando' : 'Registre algo hoje para manter a sequência',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementsScreen())),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.isDark ? cs.surfaceContainerHighest : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // Chama lima quando já registrou hoje; apagada (contorno) quando falta registrar.
                Icon(active ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
                    size: 18, color: active ? (context.isDark ? lima : const Color(0xFF567700)) : cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cs.onSurface)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Valor exibido com "R$" ou oculto pelo olho do saldo.
String maybeHidden(BuildContext context, double v, {bool short = false}) =>
    context.watch<AppState>().hideBalance ? 'R\$ •••••' : (short ? moneyShort(v) : money(v));

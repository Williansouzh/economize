import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Liga e desliga os lembretes do celular: diário para registrar e véspera das contas.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _loaded = false, _daily = false, _bills = false;
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    final r = context.read<AppState>().reminders;
    r.load().then((_) {
      if (mounted) {
        setState(() {
          _daily = r.daily;
          _bills = r.bills;
          _time = TimeOfDay(hour: r.hour, minute: r.minute);
          _loaded = true;
        });
      }
    });
  }

  Future<void> _apply({bool? daily, bool? bills, TimeOfDay? time}) async {
    final state = context.read<AppState>();
    final turningOn = (daily ?? false) || (bills ?? false);
    if (turningOn && !await state.reminders.requestPermission()) {
      if (mounted) showError(context, 'Permita as notificações do Economizze nas configurações do celular.');
      return;
    }
    setState(() {
      _daily = daily ?? _daily;
      _bills = bills ?? _bills;
      _time = time ?? _time;
    });
    await state.reminders.save(state.api, daily: _daily, bills: _bills, hour: _time.hour, minute: _time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Lembretes')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom), children: [
              Card(
                child: Column(children: [
                  SwitchListTile(
                    secondary: const IconBadge(Icons.edit_note, mar, size: 40),
                    title: const Text('Registrar os gastos do dia'),
                    subtitle: const Text('Um lembrete por dia para manter a sequência'),
                    value: _daily,
                    onChanged: (v) => _apply(daily: v),
                  ),
                  if (_daily)
                    ListTile(
                      leading: const SizedBox(width: 40, child: Icon(Icons.schedule)),
                      title: const Text('Horário'),
                      trailing: Text(_time.format(context), style: const TextStyle(fontWeight: FontWeight.w800)),
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: _time);
                        if (t != null) _apply(time: t);
                      },
                    ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const IconBadge(Icons.event_available, Color(0xFFF5A524), size: 40),
                    title: const Text('Contas a vencer'),
                    subtitle: const Text('Na véspera de cada despesa pendente, às 9h'),
                    value: _bills,
                    onChanged: (v) => _apply(bills: v),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Text(
                'Os lembretes são agendados no próprio celular. Eles podem atrasar alguns minutos '
                'quando o aparelho está economizando bateria.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ]),
    );
  }
}

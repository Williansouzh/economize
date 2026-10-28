import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/transaction_form_screen.dart' show parseAmount;
import '../utils/format.dart';

/// Respostas do questionário enquanto a pessoa preenche (RN-46). Usado no onboarding e em "Sobre você".
class AboutDraft {
  final birthYear = TextEditingController();
  String? state;
  final sources = <String>{};
  int? jobCount;
  final income = TextEditingController();
  String? goal;

  AboutDraft([About? a]) {
    if (a == null) return;
    if (a.birthYear != null) birthYear.text = '${a.birthYear}';
    state = a.state;
    sources.addAll(a.sources);
    jobCount = a.jobCount;
    if (a.monthlyIncome != null) income.text = amountText(a.monthlyIncome!);
    goal = a.mainGoal;
  }

  int? get year => int.tryParse(birthYear.text.trim());
  int? get age => year == null ? null : DateTime.now().year - year!;
  bool get validYear => year == null || (age! >= 14 && age! <= 110);
  double? get monthlyIncome => parseAmount(income.text);

  void dispose() {
    birthYear.dispose();
    income.dispose();
  }
}

const incomeSources = {
  'clt': 'Carteira assinada (CLT)',
  'servidor': 'Servidor público',
  'autonomo': 'Autônomo, freela ou bicos',
  'mei': 'MEI ou empresa (CNPJ)',
  'estagio': 'Estágio ou bolsa',
  'aposentadoria': 'Aposentadoria',
  'beneficio': 'Benefício do governo',
  'pensao': 'Pensão ou mesada',
  'aluguel': 'Aluguel de imóvel',
  'investimentos': 'Investimentos',
  'outros': 'Outra',
};

const mainGoals = {
  'organizar': ('Organizar as contas', Icons.checklist_rounded),
  'dividas': ('Sair das dívidas', Icons.money_off_rounded),
  'reserva': ('Montar uma reserva', Icons.shield_outlined),
  'investir': ('Começar a investir', Icons.trending_up_rounded),
  'sonho': ('Realizar um sonho', Icons.flight_takeoff_rounded),
  'aposentadoria': ('Pensar na aposentadoria', Icons.elderly_rounded),
};

/// Estados pelo nome (a sigla é o que vai para a API).
const brazilStates = {
  'AC': 'Acre', 'AL': 'Alagoas', 'AP': 'Amapá', 'AM': 'Amazonas', 'BA': 'Bahia', 'CE': 'Ceará',
  'DF': 'Distrito Federal', 'ES': 'Espírito Santo', 'GO': 'Goiás', 'MA': 'Maranhão', 'MT': 'Mato Grosso',
  'MS': 'Mato Grosso do Sul', 'MG': 'Minas Gerais', 'PA': 'Pará', 'PB': 'Paraíba', 'PR': 'Paraná',
  'PE': 'Pernambuco', 'PI': 'Piauí', 'RJ': 'Rio de Janeiro', 'RN': 'Rio Grande do Norte',
  'RS': 'Rio Grande do Sul', 'RO': 'Rondônia', 'RR': 'Roraima', 'SC': 'Santa Catarina', 'SP': 'São Paulo',
  'SE': 'Sergipe', 'TO': 'Tocantins',
};

String _plain(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

/// Lista de estados com busca pelo nome ou pela sigla.
Future<String?> pickState(BuildContext context, {String? current}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) {
        var query = '';
        return StatefulBuilder(builder: (c, setSheet) {
          final items = brazilStates.entries
              .where((e) => query.isEmpty || _plain(e.value).contains(_plain(query)) || e.key.toLowerCase() == query.toLowerCase())
              .toList();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Buscar estado', prefixIcon: Icon(Icons.search_rounded)),
                  onChanged: (v) => setSheet(() => query = v.trim()),
                ),
              ),
              Expanded(
                child: ListView(children: [
                  for (final e in items)
                    ListTile(
                      title: Text(e.value),
                      trailing: e.key == current
                          ? Icon(Icons.check_rounded, color: Theme.of(c).colorScheme.primary)
                          : Text(e.key, style: Theme.of(c).textTheme.bodySmall),
                      onTap: () => Navigator.pop(c, e.key),
                    ),
                ]),
              ),
            ]),
          );
        });
      },
    );

/// Renda abaixo de R\$ 500 costuma ser erro de digitação (ex.: "58" no lugar de "5.800").
/// Pergunta antes de salvar; devolve false se a pessoa quiser corrigir.
Future<bool> confirmLowIncome(BuildContext context, AboutDraft draft) async {
  final v = draft.monthlyIncome;
  if (v == null || v <= 0 || v >= 500) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Confere?'),
      content: Text('Você digitou ${money(v)} por mês. Se for ${money(v * 100)}, é só corrigir.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Corrigir')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Está certo')),
      ],
    ),
  );
  return ok == true;
}

/// Idade (pelo ano de nascimento) e estado.
class AgeFields extends StatelessWidget {
  final AboutDraft draft;
  final VoidCallback onChanged;
  const AgeFields(this.draft, {super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final age = draft.validYear ? draft.age : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: draft.birthYear,
        keyboardType: TextInputType.number,
        maxLength: 4,
        onChanged: (_) => onChanged(),
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          labelText: 'Ano em que você nasceu',
          hintText: '1995',
          counterText: '',
          errorText: draft.validYear ? null : 'Confira o ano',
          suffixText: age == null ? null : '$age anos',
        ),
      ),
      const SizedBox(height: 16),
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final uf = await pickState(context, current: draft.state);
          if (uf != null) {
            draft.state = uf;
            onChanged();
          }
        },
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Estado onde você mora',
            prefixIcon: Icon(Icons.place_outlined),
            suffixIcon: Icon(Icons.expand_more_rounded),
          ),
          isEmpty: draft.state == null,
          child: Text(draft.state == null ? '' : brazilStates[draft.state] ?? draft.state!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

/// Fontes de renda (várias) e quantos trabalhos.
class SourcesFields extends StatelessWidget {
  final AboutDraft draft;
  final VoidCallback onChanged;
  const SourcesFields(this.draft, {super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final MapEntry(key: id, value: label) in incomeSources.entries)
          FilterChip(
            label: Text(label),
            selected: draft.sources.contains(id),
            onSelected: (on) {
              on ? draft.sources.add(id) : draft.sources.remove(id);
              onChanged();
            },
          ),
      ]),
      const SizedBox(height: 24),
      Text('Quantos trabalhos ou clientes fixos você tem hoje?',
          style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
      const SizedBox(height: 10),
      SegmentedButton<int>(
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, label: Text('Nenhum')),
          ButtonSegment(value: 1, label: Text('1')),
          ButtonSegment(value: 2, label: Text('2')),
          ButtonSegment(value: 3, label: Text('3 ou +')),
        ],
        selected: {if (draft.jobCount case final n?) n > 3 ? 3 : n},
        onSelectionChanged: (s) {
          draft.jobCount = s.firstOrNull;
          onChanged();
        },
      ),
    ]);
  }
}

/// Renda do mês somando tudo e o objetivo principal.
class IncomeGoalFields extends StatelessWidget {
  final AboutDraft draft;
  final VoidCallback onChanged;
  const IncomeGoalFields(this.draft, {super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: draft.income,
        keyboardType: TextInputType.number,
        inputFormatters: [MoneyInputFormatter()],
        onChanged: (_) => onChanged(),
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        decoration: const InputDecoration(
          labelText: 'Quanto entra por mês, somando tudo',
          prefixText: 'R\$ ',
          hintText: '0,00',
          helperText: 'Pode ser aproximado. Se souber, use o valor antes dos descontos.',
          helperMaxLines: 2,
        ),
      ),
      const SizedBox(height: 24),
      Text('O que você mais quer agora?', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final MapEntry(key: id, value: (label, icon)) in mainGoals.entries)
          ChoiceChip(
            avatar: draft.goal == id ? null : Icon(icon, size: 18),
            label: Text(label),
            selected: draft.goal == id,
            onSelected: (on) {
              draft.goal = on ? id : null;
              onChanged();
            },
          ),
      ]),
    ]);
  }
}

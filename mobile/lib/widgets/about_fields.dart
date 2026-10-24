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

const brazilStates = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA',
  'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
];

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
      DropdownButtonFormField<String>(
        initialValue: draft.state,
        decoration: const InputDecoration(labelText: 'Estado onde você mora', prefixIcon: Icon(Icons.place_outlined)),
        items: [for (final uf in brazilStates) DropdownMenuItem(value: uf, child: Text(uf))],
        onChanged: (v) {
          draft.state = v;
          onChanged();
        },
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
            label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
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
            avatar: Icon(icon, size: 18),
            label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
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

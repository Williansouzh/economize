import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';

/// Apps de banco cujas notificações o Android repassa ao Economizze (RN-43). A mesma lista está em
/// BankNotificationListener.kt: notificações de outros apps nem chegam a ser guardadas.
const bankApps = <String, String>{
  'com.nu.production': 'Nubank',
  'br.com.intermedium': 'Inter',
  'com.itau': 'Itaú',
  'br.com.bb.android': 'Banco do Brasil',
  'com.bradesco': 'Bradesco',
  'br.com.bradesco.next': 'Next',
  'br.com.gabba.Caixa': 'Caixa',
  'com.santander.app': 'Santander',
  'com.c6bank.app': 'C6 Bank',
  'com.picpay': 'PicPay',
  'com.mercadopago.wallet': 'Mercado Pago',
  'br.com.uol.ps.myaccount': 'PagBank',
};

/// Notificação de banco guardada pelo serviço nativo, já interpretada.
class DetectedNotification {
  final String id, package, title, text;
  final DateTime posted;
  final ImportLine? line;
  DetectedNotification(this.id, this.package, this.title, this.text, this.posted)
    : line = parseBankNotification(title, text, posted, 'n:$id');
  String get bankName => bankApps[package] ?? package;
}

/// Lê a notificação do banco e guarda as de compra, Pix e transferência para o usuário revisar.
/// Tudo fica no celular até ele confirmar; o texto das notificações não vai para o servidor.
class BankNotifications {
  static const _channel = MethodChannel('economizze/bank_notifications');

  /// O APK tem o serviço de leitura. O do site sai sem ele (build com sideload=true): o Play Protect
  /// bloqueia a instalação fora da loja de apps que pedem acesso a notificações.
  static bool supported = false;

  static Future<void> detect() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      supported = await _channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      supported = false;
    }
  }

  /// O usuário liberou o "acesso a notificações" para o Economizze nas configurações do Android.
  Future<bool> isEnabled() async => supported && (await _channel.invokeMethod<bool>('isEnabled') ?? false);
  Future<void> openSettings() => _channel.invokeMethod('openSettings');

  /// Desligado ao sair da conta: o serviço para de guardar e a fila é apagada.
  Future<void> setActive(bool active) async {
    if (supported) await _channel.invokeMethod('setActive', active);
  }

  /// Gastos e entradas pendentes de revisão. O que não é movimentação ("sua fatura fechou") sai da fila.
  Future<List<DetectedNotification>> pending() async {
    if (!supported) return [];
    final raw = await _channel.invokeListMethod<Map>('pending') ?? [];
    final all = [
      for (final m in raw)
        DetectedNotification(
          m['id'],
          m['package'],
          m['title'] ?? '',
          m['text'] ?? '',
          DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
        ),
    ];
    final ignored = [
      for (final d in all)
        if (d.line == null) d.id,
    ];
    if (ignored.isNotEmpty) await remove(ignored);
    return all.where((d) => d.line != null).toList()..sort((a, b) => b.posted.compareTo(a.posted));
  }

  Future<void> remove(List<String> ids) async {
    if (supported && ids.isNotEmpty) await _channel.invokeMethod('remove', ids);
  }
}

final _amount = RegExp(r'R\$\s*-?\s*(\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2})');
final _income = RegExp(
  r'(voc[eê] recebeu|recebid[oa]|pix recebido|caiu na sua conta|dep[oó]sito|estorno|reembolso|cr[eé]dito em conta|recebeu um pix|recebeu uma transfer)',
  caseSensitive: false,
);
final _expense = RegExp(
  r'(compra|pagamento|pago com|paga com|pix enviado|enviou|transfer[eê]ncia enviada|transfer[eê]ncia realizada|pix realizado|d[eé]bito|saque|aprovad[oa])',
  caseSensitive: false,
);
final _notMovement = RegExp(
  r'(fatura (fechou|est[aá] fechada|dispon[ií]vel|vence)|limite dispon[ií]vel de|c[oó]digo|senha|oferta|empr[eé]stimo)',
  caseSensitive: false,
);
final _rejected = RegExp(r'(recusad[oa]|negad[oa]|n[aã]o autorizad[oa]|n[aã]o aprovad[oa])', caseSensitive: false);
final _merchant = [
  RegExp(
    r'\b(?:em|no estabelecimento)\s+(?!R\$)(.+?)(?=\s+(?:para|no|com|pelo)\s+(?:o\s+)?cart[aã]o|\s+(?:às?|as)\s+\d|\s+foi\b|[.;!]|,\s|$)',
    caseSensitive: false,
  ),
  RegExp(r'\bpara\s+(?!o\s+cart)(?!R\$)(.+?)(?=[.;!]|,\s|\s+foi\b|$)', caseSensitive: false),
  RegExp(r'\bde\s+(?!R\$)(?!\d)(.+?)(?=[.;!]|,\s|\s+foi\b|$)', caseSensitive: false),
];

/// "Compra de R$ 42,90 APROVADA em PADARIA REAL para o cartão final 1234" → -42,90 "PADARIA REAL".
/// Nulo quando não é uma movimentação (fatura fechou, código de segurança, compra recusada...).
@visibleForTesting
ImportLine? parseBankNotification(String title, String text, DateTime posted, String externalId) {
  final full = '$title. $text'.replaceAll(RegExp(r'\s+'), ' ');
  final amountMatch = _amount.firstMatch(full);
  if (amountMatch == null) return null;
  final income = _income.hasMatch(full);
  final expense = !income && _expense.hasMatch(full);
  if (!income && !expense) return null;
  if (_rejected.hasMatch(full)) return null;
  if (_notMovement.hasMatch(full) && !RegExp(r'compra (de|no|aprovada)|pix', caseSensitive: false).hasMatch(full)) {
    return null;
  }
  final value = double.parse(amountMatch.group(1)!.replaceAll('.', '').replaceAll(',', '.'));
  if (value <= 0) return null;

  // O estabelecimento ou a pessoa vem depois do valor ("de R$ 10,00 em LOJA") ou no texto todo.
  final afterAmount = full.substring(amountMatch.end);
  String? who;
  for (final source in [afterAmount, text]) {
    for (final r in _merchant) {
      final m = r.firstMatch(source)?.group(1)?.trim();
      if (m != null && m.length >= 2 && !m.startsWith('R\$')) {
        who = m;
        break;
      }
    }
    if (who != null) break;
  }
  final fallback = income ? 'Entrada' : (RegExp('pix', caseSensitive: false).hasMatch(full) ? 'Pix enviado' : 'Compra');
  var description = who ?? (title.trim().isEmpty ? fallback : title.trim());
  if (description.length > 60) description = description.substring(0, 60);
  final day = DateTime(posted.year, posted.month, posted.day);
  return ImportLine(
    day,
    description,
    income ? value : -value,
    externalId.length > 100 ? externalId.substring(0, 100) : externalId,
  );
}

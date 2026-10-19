import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import '../utils/format.dart';
import 'api_client.dart';

/// Lembretes locais (RN-39), só no Android: um diário para registrar os gastos e um na véspera de
/// cada conta pendente dos próximos 30 dias. Tudo é agendado no próprio aparelho; o servidor não
/// envia notificações. Horários aproximados (sem alarme exato, que exige permissão especial).
class Reminders {
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final _plugin = FlutterLocalNotificationsPlugin();
  final _storage = const FlutterSecureStorage();
  bool _ready = false;
  Timer? _debounce;

  bool daily = false, bills = false;
  int hour = 20, minute = 0;

  static const _dailyId = 1, _billsFirstId = 1000, _maxBills = 30;
  static const _channel = AndroidNotificationDetails(
    'lembretes',
    'Lembretes',
    channelDescription: 'Lembrete diário de registrar os gastos e contas a vencer',
    importance: Importance.defaultImportance,
  );

  Future<void> _init() async {
    if (_ready || !supported) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
    }
    await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')));
    daily = await _storage.read(key: 'reminder_daily') == '1';
    bills = await _storage.read(key: 'reminder_bills') == '1';
    final time = (await _storage.read(key: 'reminder_time'))?.split(':');
    if (time case [final h, final m]) {
      hour = int.tryParse(h) ?? hour;
      minute = int.tryParse(m) ?? minute;
    }
    _ready = true;
  }

  /// Carrega as preferências salvas (para a tela de lembretes).
  Future<void> load() => _init();

  /// Pede a permissão de notificação do Android 13+. Falso se o usuário negar.
  Future<bool> requestPermission() async {
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> save(ApiClient api, {required bool daily, required bool bills, required int hour, required int minute}) async {
    await _init();
    this.daily = daily;
    this.bills = bills;
    this.hour = hour;
    this.minute = minute;
    await _storage.write(key: 'reminder_daily', value: daily ? '1' : '0');
    await _storage.write(key: 'reminder_bills', value: bills ? '1' : '0');
    await _storage.write(key: 'reminder_time', value: '$hour:$minute');
    await sync(api);
  }

  /// Agenda de novo conforme as preferências e as contas pendentes atuais. Chamado ao abrir o app
  /// e depois de mudanças nos lançamentos (com espera, para não buscar a cada toque).
  void syncSoon(ApiClient api) {
    if (!supported) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => sync(api));
  }

  Future<void> sync(ApiClient api) async {
    if (!supported) return;
    try {
      await _init();
      await _plugin.cancelAll();
      final now = tz.TZDateTime.now(tz.local);
      if (daily) {
        var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
        if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
        await _plugin.zonedSchedule(
          id: _dailyId,
          title: 'Já anotou seus gastos de hoje? 🐷',
          body: 'Leva 5 segundos e mantém sua sequência viva.',
          scheduledDate: at,
          notificationDetails: const NotificationDetails(android: _channel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
      if (bills && api.token != null) {
        final upcoming = await api.upcoming(days: 30);
        var id = _billsFirstId;
        for (final t in upcoming.where((t) => t.type == TxType.expense).take(_maxBills)) {
          // 9h da véspera do vencimento.
          final at = tz.TZDateTime(tz.local, t.date.year, t.date.month, t.date.day, 9).subtract(const Duration(days: 1));
          if (!at.isAfter(now)) continue;
          await _plugin.zonedSchedule(
            id: id++,
            title: 'Conta vence amanhã',
            body: '${t.description.isEmpty ? t.categoryName : t.description}: ${money(t.amount)}',
            scheduledDate: at,
            notificationDetails: const NotificationDetails(android: _channel),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (e) {
      debugPrint('Lembretes: $e');
    }
  }

  /// Ao sair da conta: nada de lembrar contas de outra pessoa.
  Future<void> cancelAll() async {
    if (!supported || !_ready) return;
    await _plugin.cancelAll();
  }
}

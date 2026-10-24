import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ícone do app que muda conforme o mês (RN-49), como o LinkedIn faz com o selo.
/// Não dá para desenhar o ícone na hora: o app traz três ícones prontos e troca entre eles.
/// Android: cada ícone é uma activity-alias (MainActivity.kt). iOS: ícones alternativos (AppDelegate.swift),
/// e o sistema mostra um aviso a cada troca. Por isso é opcional e troca no máximo uma vez por dia.
class AppIcon {
  static const _channel = MethodChannel('economizze/app_icon');

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// No Android a troca é feita ao sair do app: trocar com ele na frente pode fechá-lo em alguns launchers.
  /// No iOS é o contrário: o sistema só aceita com o app aberto.
  static bool get changeOnPause => defaultTargetPlatform == TargetPlatform.android;

  /// padrao (moeda lima, o zz sobe), atencao (âmbar, os dois z no mesmo nível) ou alerta (coral, o zz desce).
  static String variantFor(String status) => switch (status) {
        'atencao' => 'atencao',
        'critico' => 'alerta',
        _ => 'padrao',
      };

  static Future<String> current() async => await _channel.invokeMethod<String>('current') ?? 'padrao';

  static Future<void> set(String variant) => _channel.invokeMethod('set', variant);
}

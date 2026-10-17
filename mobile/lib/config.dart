/// URL do backend .NET.
/// - Emulador Android: http://10.0.2.2:5000
/// - Simulador iOS / desktop: http://localhost:5000
/// - Celular físico: `http://<IP-do-seu-PC>:5000`
/// Pode ser sobrescrita com: flutter run --dart-define=API_URL=http://192.168.0.10:5000
const String apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:5000',
);

/// Número do WhatsApp do assistente (só para exibir na tela de vinculação).
/// flutter run --dart-define=WHATSAPP_BOT=+55 11 99999-9999
const String whatsappBotNumber = String.fromEnvironment('WHATSAPP_BOT');

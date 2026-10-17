/// URL do backend .NET.
/// - Emulador Android: http://10.0.2.2:5000
/// - Simulador iOS / desktop: http://localhost:5000
/// - Celular físico: `http://<IP-do-seu-PC>:5000`
/// Pode ser sobrescrita com: flutter run --dart-define=API_URL=http://192.168.0.10:5000
const String apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:5000',
);

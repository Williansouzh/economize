import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final state = AppState();
  _reportErrors(state);
  runApp(ChangeNotifierProvider(create: (_) => state..init(), child: const FinancasApp()));
}

/// Erros não tratados vão para o log do servidor (só mensagem e pilha, sem dados financeiros).
/// No máximo 5 por abertura do app e sem repetir a mesma mensagem.
void _reportErrors(AppState state) {
  if (kDebugMode) return;
  final sent = <String>{};
  void report(Object error, StackTrace? stack) {
    final message = error.toString();
    if (sent.length >= 5 || !sent.add(message)) return;
    state.api.reportError(message, stack?.toString(), kIsWeb ? 'web' : defaultTargetPlatform.name,
        const String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: '?'));
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    report(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    report(error, stack);
    return true;
  };
}

class FinancasApp extends StatefulWidget {
  const FinancasApp({super.key});
  @override
  State<FinancasApp> createState() => _FinancasAppState();
}

class _FinancasAppState extends State<FinancasApp> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(SplashScreen.minDuration, () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Abertura com dica → apresentação (1ª vez) → login → configuração guiada (conta nova) → início.
    final Widget home = !state.initialized || !_splashDone
        ? const SplashScreen()
        : !state.loggedIn
            ? (state.onboardingSeen ? const LoginScreen() : const OnboardingScreen())
            : (state.needsSetup ? const SetupScreen() : const HomeScreen());
    return MaterialApp(
      title: 'Economizze',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: state.themeMode,
      home: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: home),
    );
  }
}

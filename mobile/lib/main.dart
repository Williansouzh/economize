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
  runApp(ChangeNotifierProvider(create: (_) => AppState()..init(), child: const FinancasApp()));
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
      home: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: home),
    );
  }
}

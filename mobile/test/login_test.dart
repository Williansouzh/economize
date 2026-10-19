import 'package:financas_app/screens/forgot_password_screen.dart';
import 'package:financas_app/screens/login_screen.dart';
import 'package:financas_app/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('a tela de entrar oferece "Esqueci minha senha", e a de cadastro não', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(412, 915) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MaterialApp(home: LoginScreen()),
    ));
    expect(find.text('Esqueci minha senha'), findsOneWidget);

    await tester.ensureVisible(find.text('Ainda não tem conta? Cadastre-se'));
    await tester.tap(find.text('Ainda não tem conta? Cadastre-se'));
    await tester.pump();
    expect(find.text('Esqueci minha senha'), findsNothing);
    expect(find.text('Pelo menos 8 caracteres'), findsOneWidget);

    await tester.ensureVisible(find.text('Já tenho conta'));
    await tester.tap(find.text('Já tenho conta'));
    await tester.pump();
    await tester.ensureVisible(find.text('Esqueci minha senha'));
    await tester.tap(find.text('Esqueci minha senha'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

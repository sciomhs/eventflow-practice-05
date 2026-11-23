import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:eventflow_app/core/adaptive_shell.dart';
import 'package:eventflow_app/core/auth_store.dart';
import 'package:eventflow_app/design/theme.dart';
import 'package:eventflow_app/design/widgets/ef_widgets.dart';
import 'package:eventflow_app/features/auth/auth_screen.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('ru');
    Intl.defaultLocale = 'ru';
  });
  testWidgets('AuthScreen renders without overflow at 360px and 1280px',
      (tester) async {
    final auth = AuthStore();
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpWidget(
        MaterialApp(theme: buildEfTheme(), home: AuthScreen(auth: auth)));
    await tester.pump();
    expect(find.text('Вход в систему'), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(
        MaterialApp(theme: buildEfTheme(), home: AuthScreen(auth: auth)));
    await tester.pump();
    expect(
        find.text('От регистрации\nдо одного честного входа'), findsOneWidget);
    tester.view.resetPhysicalSize();
  });

  testWidgets(
      'EfAdaptiveShell switches NavigationBar (360px) and NavigationRail (1280px)',
      (tester) async {
    final auth = AuthStore();
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final dests = [
      const EfNavDestination(
        label: 'Каталог',
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore,
        page: Center(child: Text('Page 1')),
      ),
      const EfNavDestination(
        label: 'Билеты',
        icon: Icons.confirmation_number_outlined,
        selectedIcon: Icons.confirmation_number,
        page: Center(child: Text('Page 2')),
      ),
    ];

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpWidget(MaterialApp(
      theme: buildEfTheme(),
      home: EfAdaptiveShell(
          auth: auth, destinations: dests, roleLabel: 'Участник'),
    ));
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(MaterialApp(
      theme: buildEfTheme(),
      home: EfAdaptiveShell(
          auth: auth, destinations: dests, roleLabel: 'Участник'),
    ));
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    tester.view.resetPhysicalSize();
  });

  testWidgets('EfPerforatedTicketCard and EfStatusPill render', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEfTheme(),
      home: const Scaffold(
        body: EfPerforatedTicketCard(
          top: EfStatusPill(
            label: 'ДЕЙСТВИТЕЛЕН',
            icon: Icons.check_circle_outline,
            tone: EfTone.positive,
          ),
          bottom: Text('EF-0001'),
        ),
      ),
    ));
    expect(find.text('ДЕЙСТВИТЕЛЕН'), findsOneWidget);
    expect(find.text('EF-0001'), findsOneWidget);
  });
}

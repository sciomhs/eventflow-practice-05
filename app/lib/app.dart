import 'package:flutter/material.dart';
import 'core/adaptive_shell.dart';
import 'core/auth_store.dart';
import 'design/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/controller/scan_journal_screen.dart';
import 'features/controller/scanner_screen.dart';
import 'features/organizer/organizer_dashboard_screen.dart';
import 'features/participant/catalog_screen.dart';
import 'features/participant/my_tickets_screen.dart';

class EventFlowApp extends StatefulWidget {
  final AuthStore? authStore;
  const EventFlowApp({super.key, this.authStore});

  @override
  State<EventFlowApp> createState() => _EventFlowAppState();
}

class _EventFlowAppState extends State<EventFlowApp> {
  late final AuthStore _auth;

  @override
  void initState() {
    super.initState();
    _auth = widget.authStore ?? (AuthStore()..init());
  }

  @override
  void dispose() {
    if (widget.authStore == null) {
      _auth.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EventFlow',
      debugShowCheckedModeBanner: false,
      theme: buildEfTheme(),
      home: ListenableBuilder(
        listenable: _auth,
        builder: (context, _) {
          if (_auth.loading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!_auth.isAuthenticated) {
            return AuthScreen(auth: _auth);
          }
          final role = _auth.user!.role;
          return switch (role) {
            'organizer' => EfAdaptiveShell(
                auth: _auth,
                roleLabel: 'Организатор',
                destinations: [
                  EfNavDestination(
                    label: 'Управление',
                    icon: Icons.dashboard_outlined,
                    selectedIcon: Icons.dashboard_rounded,
                    page: OrganizerDashboardScreen(auth: _auth),
                  ),
                ],
              ),
            'controller' => EfAdaptiveShell(
                auth: _auth,
                roleLabel: 'Контролёр',
                destinations: [
                  EfNavDestination(
                    label: 'Сканер',
                    icon: Icons.qr_code_scanner_outlined,
                    selectedIcon: Icons.qr_code_scanner_rounded,
                    page: ControllerScannerScreen(auth: _auth),
                  ),
                  EfNavDestination(
                    label: 'Журнал',
                    icon: Icons.history_outlined,
                    selectedIcon: Icons.history_rounded,
                    page: ControllerJournalScreen(auth: _auth),
                  ),
                ],
              ),
            _ => EfAdaptiveShell(
                auth: _auth,
                roleLabel: 'Участник',
                destinations: [
                  EfNavDestination(
                    label: 'Каталог',
                    icon: Icons.explore_outlined,
                    selectedIcon: Icons.explore_rounded,
                    page: ParticipantCatalogScreen(auth: _auth),
                  ),
                  EfNavDestination(
                    label: 'Билеты',
                    icon: Icons.confirmation_number_outlined,
                    selectedIcon: Icons.confirmation_number_rounded,
                    page: MyTicketsScreen(auth: _auth),
                  ),
                ],
              ),
          };
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../design/widgets/ef_widgets.dart';
import 'auth_store.dart';

class EfNavDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  const EfNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });
}

class EfAdaptiveShell extends StatefulWidget {
  final AuthStore auth;
  final List<EfNavDestination> destinations;
  final String roleLabel;

  const EfAdaptiveShell({
    super.key,
    required this.auth,
    required this.destinations,
    required this.roleLabel,
  });

  @override
  State<EfAdaptiveShell> createState() => _EfAdaptiveShellState();
}

class _EfAdaptiveShellState extends State<EfAdaptiveShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 768;
    final safeIdx = _index.clamp(0, widget.destinations.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('EventFlow', style: EfTextStyles.display(22)),
              const SizedBox(width: EfSpacing.md),
              EfStatusPill(
                label: widget.roleLabel,
                icon: Icons.verified_user_outlined,
                tone: EfTone.positive,
              ),
            ],
          ),
        ),
        actions: [
          if (isWide)
            Padding(
              padding: const EdgeInsets.only(right: EfSpacing.md),
              child: Center(
                child: Text(
                  widget.auth.user?.name ?? '',
                  style: EfTextStyles.body(13,
                      weight: FontWeight.w600, color: EfColors.mutedSlate),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: () => widget.auth.logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: widget.auth.sse,
            builder: (_, __) => EfConnectionBanner(
              connected: widget.auth.sse.connected,
              reconnecting: widget.auth.sse.reconnecting,
            ),
          ),
          Expanded(
            child: isWide
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: safeIdx,
                        onDestinationSelected: (i) =>
                            setState(() => _index = i),
                        labelType: NavigationRailLabelType.all,
                        destinations: widget.destinations
                            .map((d) => NavigationRailDestination(
                                  icon: Icon(d.icon),
                                  selectedIcon: Icon(d.selectedIcon),
                                  label: Text(d.label),
                                ))
                            .toList(),
                      ),
                      const VerticalDivider(
                          width: 1, color: EfColors.hairlineBorder),
                      Expanded(child: widget.destinations[safeIdx].page),
                    ],
                  )
                : widget.destinations[safeIdx].page,
          ),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: safeIdx,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: widget.destinations
                  .map((d) => NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: d.label,
                      ))
                  .toList(),
            ),
    );
  }
}

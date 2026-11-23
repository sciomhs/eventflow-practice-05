import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth_store.dart';
import '../../design/tokens.dart';
import '../../design/widgets/ef_widgets.dart';

class ControllerJournalScreen extends StatefulWidget {
  final AuthStore auth;
  const ControllerJournalScreen({super.key, required this.auth});

  @override
  State<ControllerJournalScreen> createState() =>
      _ControllerJournalScreenState();
}

class _ControllerJournalScreenState extends State<ControllerJournalScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.auth.api.get('/api/v1/controller/journal');
      if (mounted) {
        setState(() {
          _items = (res['items'] as List<dynamic>).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM, HH:mm:ss');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(EfSpacing.lg),
        children: [
          Text('Журнал проверок', style: EfTextStyles.display(28)),
          const SizedBox(height: EfSpacing.lg),
          if (_error != null) EfErrorBanner(message: _error!, onRetry: _load),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_items.isEmpty)
            const EfEmptyState(
              icon: Icons.history_rounded,
              title: 'Проверок пока нет',
              subtitle:
                  'Отсканированные или введённые билеты отобразятся в этом журнале.',
            )
          else
            ..._items.map((j) {
              final res = j['result'] as String;
              final time = DateTime.parse(j['server_time'] as String).toLocal();
              return Card(
                margin: const EdgeInsets.only(bottom: EfSpacing.sm),
                child: ListTile(
                  title: Text(
                    '${j['event_title'] ?? ''} ${j['ticket_code'] != null ? '• ${j['ticket_code']}' : ''}',
                    style: EfTextStyles.body(14, weight: FontWeight.w600),
                  ),
                  subtitle: Text(df.format(time),
                      style: EfTextStyles.mono(12, color: EfColors.mutedSlate)),
                  trailing: EfStatusPill(
                    label: res,
                    icon: res == 'ACCEPTED'
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    tone: res == 'ACCEPTED'
                        ? EfTone.positive
                        : (res == 'ALREADY_USED'
                            ? EfTone.warning
                            : EfTone.danger),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

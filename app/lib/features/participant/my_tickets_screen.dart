import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/auth_store.dart';
import '../../core/models/models.dart';
import '../../core/sse_client.dart';
import '../../design/tokens.dart';
import '../../design/widgets/ef_widgets.dart';

class MyTicketsScreen extends StatefulWidget {
  final AuthStore auth;
  const MyTicketsScreen({super.key, required this.auth});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  bool _loading = true;
  String? _error;
  List<TicketItem> _tickets = [];
  StreamSubscription<SseMessage>? _sseSub;
  StreamSubscription<void>? _reconnSub;

  @override
  void initState() {
    super.initState();
    _load();
    _sseSub = widget.auth.sse.messages.listen((msg) {
      if (msg.event == 'entry.accepted' ||
          msg.event == 'event.cancelled' ||
          msg.event == 'ticket.issued') {
        _load(silent: true);
      }
    });
    _reconnSub =
        widget.auth.sse.onReconnected.listen((_) => _load(silent: true));
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _reconnSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.auth.api.get('/api/v1/tickets/my');
      final list = (res['items'] as List<dynamic>)
          .map((e) => TicketItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _tickets = list;
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

  Future<void> _cancelTicket(TicketItem ticket) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Отменить регистрацию?', style: EfTextStyles.display(20)),
        content: Text(
          'Билет ${ticket.code} станет недействительным, а место вернётся в общий пул.',
          style: EfTextStyles.body(14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Оставить')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: EfColors.coral),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить билет'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await widget.auth.api.post('/api/v1/tickets/${ticket.id}/cancel');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Билет ${ticket.code} отменён.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM, HH:mm');
    final active = _tickets.where((t) => t.status == 'ISSUED').toList();
    final history = _tickets.where((t) => t.status != 'ISSUED').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(EfSpacing.lg),
        children: [
          Text('Мои билеты', style: EfTextStyles.display(28)),
          const SizedBox(height: EfSpacing.lg),
          if (_error != null) ...[
            EfErrorBanner(message: _error!, onRetry: _load),
            const SizedBox(height: EfSpacing.lg),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(EfSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_tickets.isEmpty)
            const EfEmptyState(
              icon: Icons.confirmation_number_outlined,
              title: 'У вас пока нет билетов',
              subtitle:
                  'Перейдите в каталог мероприятий, чтобы выбрать событие и получить QR-билет.',
            )
          else ...[
            if (active.isNotEmpty) ...[
              Text('Действующие', style: EfTextStyles.display(18)),
              const SizedBox(height: EfSpacing.md),
              ...active.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: EfSpacing.lg),
                    child: EfPerforatedTicketCard(
                      top: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(t.eventTitle ?? '',
                                    style: EfTextStyles.display(20)),
                              ),
                              const EfStatusPill(
                                label: 'ДЕЙСТВИТЕЛЕН',
                                icon: Icons.check_circle_outline,
                                tone: EfTone.positive,
                              ),
                            ],
                          ),
                          const SizedBox(height: EfSpacing.xs),
                          Text(
                            '${t.typeName ?? ''} • ${t.code}',
                            style: EfTextStyles.mono(14,
                                color: EfColors.emeraldDark),
                          ),
                          if (t.eventStartsAt != null)
                            Text(
                              '${df.format(t.eventStartsAt!.toLocal())} (${t.eventTimezone ?? ''}) • ${t.eventLocation ?? ''}',
                              style: EfTextStyles.body(13,
                                  color: EfColors.mutedSlate),
                            ),
                        ],
                      ),
                      bottom: Column(
                        children: [
                          if (t.qrToken != null) ...[
                            QrImageView(
                                data: t.qrToken!,
                                version: QrVersions.auto,
                                size: 190),
                            const SizedBox(height: EfSpacing.sm),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: SelectableText(
                                    t.qrToken!,
                                    style: EfTextStyles.mono(12,
                                        color: EfColors.mutedSlate),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Скопировать код',
                                  icon:
                                      const Icon(Icons.copy_rounded, size: 18),
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: t.qrToken!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Полный код скопирован')),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: EfSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _cancelTicket(t),
                              icon: const Icon(Icons.close_rounded,
                                  color: EfColors.coral),
                              label: Text(
                                'Отменить регистрацию',
                                style: EfTextStyles.body(14,
                                    weight: FontWeight.w600,
                                    color: EfColors.coral),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
            if (history.isNotEmpty) ...[
              const SizedBox(height: EfSpacing.md),
              Text('История', style: EfTextStyles.display(18)),
              const SizedBox(height: EfSpacing.md),
              ...history.map((t) {
                final used = t.status == 'USED';
                return Card(
                  margin: const EdgeInsets.only(bottom: EfSpacing.sm),
                  child: ListTile(
                    title: Text('${t.eventTitle ?? ''} (${t.code})',
                        style: EfTextStyles.body(15, weight: FontWeight.w600)),
                    subtitle: Text(
                      used && t.usedAt != null
                          ? 'Вход зафиксирован: ${df.format(t.usedAt!.toLocal())}'
                          : 'Отменён',
                      style: EfTextStyles.body(13, color: EfColors.mutedSlate),
                    ),
                    trailing: EfStatusPill(
                      label: used ? 'ИСПОЛЬЗОВАН' : 'ОТМЕНЁН',
                      icon: used
                          ? Icons.verified_outlined
                          : Icons.cancel_outlined,
                      tone: used ? EfTone.neutral : EfTone.danger,
                    ),
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

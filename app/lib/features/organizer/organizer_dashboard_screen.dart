import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth_store.dart';
import '../../core/models/models.dart';
import '../../core/sse_client.dart';
import '../../design/tokens.dart';
import '../../design/widgets/ef_widgets.dart';
import 'event_editor_screen.dart';

class OrganizerDashboardScreen extends StatefulWidget {
  final AuthStore auth;
  const OrganizerDashboardScreen({super.key, required this.auth});

  @override
  State<OrganizerDashboardScreen> createState() =>
      _OrganizerDashboardScreenState();
}

class _OrganizerDashboardScreenState extends State<OrganizerDashboardScreen> {
  bool _loading = true;
  String? _error;
  List<EventItem> _events = [];
  String? _selectedEventId;

  OrganizerStats? _stats;
  List<Map<String, dynamic>> _participants = [];
  List<Map<String, dynamic>> _allControllers = [];
  List<Map<String, dynamic>> _assignedControllers = [];
  List<Map<String, dynamic>> _journal = [];
  String _participantSearch = '';
  String _participantStatus = '';

  StreamSubscription<SseMessage>? _sseSub;
  StreamSubscription<void>? _reconnSub;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _sseSub = widget.auth.sse.messages.listen((msg) {
      if (msg.event == 'ticket.issued' ||
          msg.event == 'ticket.cancelled' ||
          msg.event == 'entry.accepted' ||
          msg.event == 'entry.rejected' ||
          msg.event == 'event.updated' ||
          msg.event == 'event.cancelled' ||
          msg.event == 'controller.revoked') {
        _loadSelectedDetails();
        _loadEvents(silent: true);
      }
    });
    _reconnSub = widget.auth.sse.onReconnected.listen((_) {
      _loadEvents(silent: true);
      _loadSelectedDetails();
    });
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _reconnSub?.cancel();
    super.dispose();
  }

  Future<void> _loadEvents({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.auth.api.get('/api/v1/organizer/events');
      final list = (res['items'] as List<dynamic>)
          .map((e) => EventItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final allCtrlRes =
          await widget.auth.api.get('/api/v1/organizer/controllers');
      final allCtrls =
          (allCtrlRes['items'] as List<dynamic>).cast<Map<String, dynamic>>();

      if (mounted) {
        setState(() {
          _events = list;
          _allControllers = allCtrls;
          _selectedEventId ??= list.isNotEmpty ? list.first.id : null;
          _loading = false;
        });
        if (_selectedEventId != null) {
          await _loadSelectedDetails();
        }
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

  Future<void> _loadSelectedDetails() async {
    final eid = _selectedEventId;
    if (eid == null) return;
    try {
      final q = <String, String>{};
      if (_participantSearch.isNotEmpty) q['search'] = _participantSearch;
      if (_participantStatus.isNotEmpty) q['status'] = _participantStatus;

      final results = await Future.wait([
        widget.auth.api.get('/api/v1/organizer/events/$eid/stats'),
        widget.auth.api
            .get('/api/v1/organizer/events/$eid/participants', query: q),
        widget.auth.api.get('/api/v1/organizer/events/$eid/controllers'),
        widget.auth.api.get('/api/v1/organizer/events/$eid/journal'),
      ]);
      if (mounted) {
        setState(() {
          _stats = OrganizerStats.fromJson(results[0]);
          _participants = (results[1]['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          _assignedControllers = (results[2]['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          _journal = (results[3]['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _publishSelected() async {
    if (_selectedEventId == null) return;
    try {
      await widget.auth.api
          .post('/api/v1/organizer/events/$_selectedEventId/publish');
      await _loadEvents(silent: true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _cancelSelected() async {
    if (_selectedEventId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Отменить мероприятие?', style: EfTextStyles.display(20)),
        content: Text(
          'После отмены все выданные билеты станут недействительными для новых входов. История сохранится.',
          style: EfTextStyles.body(14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Назад')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: EfColors.coral),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Подтвердить отмену'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.auth.api
          .post('/api/v1/organizer/events/$_selectedEventId/cancel');
      await _loadEvents(silent: true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggleController(String controllerId, bool assign) async {
    final eid = _selectedEventId;
    if (eid == null) return;
    try {
      if (assign) {
        await widget.auth.api.post('/api/v1/organizer/events/$eid/controllers',
            body: {'controller_id': controllerId});
      } else {
        await widget.auth.api
            .delete('/api/v1/organizer/events/$eid/controllers/$controllerId');
      }
      await _loadSelectedDetails();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return Padding(
          padding: const EdgeInsets.all(16),
          child: EfErrorBanner(message: _error!, onRetry: _loadEvents));

    final selected = _events.where((e) => e.id == _selectedEventId).firstOrNull;
    final df = DateFormat('HH:mm:ss');

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                EfSpacing.lg, EfSpacing.lg, EfSpacing.lg, EfSpacing.sm),
            child: Wrap(
              spacing: EfSpacing.md,
              runSpacing: EfSpacing.sm,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _selectedEventId,
                  items: _events
                      .map((e) => DropdownMenuItem(
                            value: e.id,
                            child: Text('${e.title} (${e.status})',
                                style: EfTextStyles.body(14,
                                    weight: FontWeight.w600)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedEventId = v);
                    _loadSelectedDetails();
                  },
                ),
                Wrap(
                  spacing: EfSpacing.sm,
                  children: [
                    if (selected?.status == 'DRAFT')
                      FilledButton.icon(
                        onPressed: _publishSelected,
                        icon: const Icon(Icons.publish_rounded),
                        label: const Text('Опубликовать'),
                      ),
                    if (selected != null && selected.status != 'CANCELLED')
                      OutlinedButton.icon(
                        onPressed: _cancelSelected,
                        icon: const Icon(Icons.cancel_outlined,
                            color: EfColors.coral),
                        label: Text('Отменить событие',
                            style: EfTextStyles.body(13,
                                weight: FontWeight.w600,
                                color: EfColors.coral)),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final created = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                              builder: (_) =>
                                  EventEditorScreen(auth: widget.auth)),
                        );
                        if (created == true) _loadEvents();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Создать событие'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Обзор'),
              Tab(text: 'Участники'),
              Tab(text: 'Контролёры'),
              Tab(text: 'Журнал'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // 1. Live Stats
                _stats == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.all(EfSpacing.lg),
                        children: [
                          Wrap(
                            spacing: EfSpacing.md,
                            runSpacing: EfSpacing.md,
                            children: [
                              _StatCard(
                                  label: 'Выдано билетов',
                                  value:
                                      '${_stats!.issuedCount} / ${_stats!.capacity}'),
                              _StatCard(
                                  label: 'Вошли в зал',
                                  value: '${_stats!.usedCount}',
                                  accent: EfColors.emeraldDark),
                              _StatCard(
                                  label: 'Свободно мест',
                                  value: '${_stats!.freeSeats}'),
                              _StatCard(
                                  label: 'Отменено',
                                  value: '${_stats!.cancelledCount}',
                                  accent: EfColors.coral),
                              _StatCard(
                                  label: 'Всего сканов',
                                  value: '${_stats!.scansTotal}'),
                              _StatCard(
                                  label: 'Входов за 24 ч',
                                  value: '${_stats!.last24hEntries}'),
                            ],
                          ),
                          const SizedBox(height: EfSpacing.xl),
                          Text('По категориям',
                              style: EfTextStyles.display(18)),
                          const SizedBox(height: EfSpacing.md),
                          ..._stats!.byType.map((t) => Card(
                                margin:
                                    const EdgeInsets.only(bottom: EfSpacing.sm),
                                child: ListTile(
                                  title: Text(t.name,
                                      style: EfTextStyles.body(15,
                                          weight: FontWeight.w600)),
                                  subtitle: Text(
                                      'Занято: ${t.occupied} из ${t.capacity} • Вошли: ${t.usedCount}',
                                      style: EfTextStyles.mono(12)),
                                  trailing: EfStatusPill(
                                    label: 'Осталось ${t.remaining}',
                                    icon: Icons.event_seat_outlined,
                                    tone: t.remaining > 0
                                        ? EfTone.positive
                                        : EfTone.warning,
                                  ),
                                ),
                              )),
                        ],
                      ),
                // 2. Participants
                ListView(
                  padding: const EdgeInsets.all(EfSpacing.lg),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                                labelText: 'Поиск по имени или коду EF-...'),
                            onChanged: (v) {
                              _participantSearch = v.trim();
                              _loadSelectedDetails();
                            },
                          ),
                        ),
                        const SizedBox(width: EfSpacing.md),
                        DropdownButton<String>(
                          value: _participantStatus,
                          items: const [
                            DropdownMenuItem(
                                value: '', child: Text('Все статусы')),
                            DropdownMenuItem(
                                value: 'ISSUED', child: Text('ISSUED')),
                            DropdownMenuItem(
                                value: 'USED', child: Text('USED')),
                            DropdownMenuItem(
                                value: 'CANCELLED', child: Text('CANCELLED')),
                          ],
                          onChanged: (v) {
                            _participantStatus = v ?? '';
                            _loadSelectedDetails();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: EfSpacing.md),
                    if (_participants.isEmpty)
                      const EfEmptyState(
                        icon: Icons.people_outline,
                        title: 'Нет участников',
                        subtitle: 'По текущему фильтру билеты не найдены.',
                      )
                    else
                      ..._participants.map((p) => Card(
                            margin: const EdgeInsets.only(bottom: EfSpacing.sm),
                            child: ListTile(
                              title: Text(
                                  '${p['participant_name']} (${p['code']})',
                                  style: EfTextStyles.body(14,
                                      weight: FontWeight.w600)),
                              subtitle: Text(
                                  '${p['type_name']} • ${p['participant_email']}',
                                  style: EfTextStyles.body(12,
                                      color: EfColors.mutedSlate)),
                              trailing: EfStatusPill(
                                label: p['status'] as String,
                                icon: Icons.confirmation_number_outlined,
                                tone: p['status'] == 'USED'
                                    ? EfTone.positive
                                    : (p['status'] == 'CANCELLED'
                                        ? EfTone.danger
                                        : EfTone.neutral),
                              ),
                            ),
                          )),
                  ],
                ),
                // 3. Controllers
                ListView(
                  padding: const EdgeInsets.all(EfSpacing.lg),
                  children: _allControllers.map((c) {
                    final cid = c['id'] as String;
                    final isAssigned =
                        _assignedControllers.any((a) => a['id'] == cid);
                    return Card(
                      margin: const EdgeInsets.only(bottom: EfSpacing.sm),
                      child: SwitchListTile(
                        title: Text(c['name'] as String,
                            style:
                                EfTextStyles.body(15, weight: FontWeight.w600)),
                        subtitle: Text(c['email'] as String,
                            style: EfTextStyles.body(13,
                                color: EfColors.mutedSlate)),
                        value: isAssigned,
                        onChanged: (val) => _toggleController(cid, val),
                      ),
                    );
                  }).toList(),
                ),
                // 4. Journal
                ListView(
                  padding: const EdgeInsets.all(EfSpacing.lg),
                  children: _journal.isEmpty
                      ? const [
                          EfEmptyState(
                            icon: Icons.history,
                            title: 'Журнал пуст',
                            subtitle:
                                'События регистрации и проверки входа появятся здесь.',
                          )
                        ]
                      : _journal.map((j) {
                          final time =
                              DateTime.parse(j['server_time'] as String)
                                  .toLocal();
                          return Card(
                            margin: const EdgeInsets.only(bottom: EfSpacing.sm),
                            child: ListTile(
                              leading: Text(df.format(time),
                                  style: EfTextStyles.mono(12,
                                      color: EfColors.mutedSlate)),
                              title: Text('${j['action']} -> ${j['result']}',
                                  style: EfTextStyles.body(14,
                                      weight: FontWeight.w600)),
                              subtitle: Text(
                                '${j['actor_name'] ?? 'Система'} ${j['ticket_code'] != null ? '• ${j['ticket_code']}' : ''}',
                                style: EfTextStyles.body(12,
                                    color: EfColors.mutedSlate),
                              ),
                            ),
                          );
                        }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _StatCard({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(EfSpacing.lg),
      decoration: BoxDecoration(
        color: EfColors.pureCard,
        borderRadius: BorderRadius.circular(EfRadii.lg),
        border: Border.all(color: EfColors.hairlineBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: EfTextStyles.body(12, color: EfColors.mutedSlate)),
          const SizedBox(height: EfSpacing.xs),
          Text(value,
              style: EfTextStyles.mono(22,
                  weight: FontWeight.w700, color: accent ?? EfColors.deepInk)),
        ],
      ),
    );
  }
}

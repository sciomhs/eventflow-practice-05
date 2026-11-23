import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../core/date_fmt.dart';
import '../../core/labels.dart';
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
  static const _sections = [
    ('Обзор', Icons.insights_outlined),
    ('Мероприятия', Icons.event_note_outlined),
    ('Участники', Icons.people_outline),
    ('Контролёры', Icons.verified_user_outlined),
    ('Журнал', Icons.history_outlined),
  ];

  int _sectionIdx = 0;
  bool _loading = true;
  String? _error;
  String? _detailsError;
  List<EventItem> _events = [];
  String? _selectedEventId;

  OrganizerStats? _stats;
  List<Map<String, dynamic>> _participants = [];
  List<Map<String, dynamic>> _allControllers = [];
  List<Map<String, dynamic>> _assignedControllers = [];
  List<Map<String, dynamic>> _journal = [];
  String _participantSearch = '';
  String _participantStatus = '';
  String _participantTypeId = '';

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
          if (_selectedEventId == null ||
              !list.any((e) => e.id == _selectedEventId)) {
            _selectedEventId = list.isNotEmpty ? list.first.id : null;
          }
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
      if (_participantTypeId.isNotEmpty) q['type_id'] = _participantTypeId;

      final results = await Future.wait([
        widget.auth.api.get('/api/v1/organizer/events/$eid/stats'),
        widget.auth.api
            .get('/api/v1/organizer/events/$eid/participants', query: q),
        widget.auth.api.get('/api/v1/organizer/events/$eid/controllers'),
        widget.auth.api.get('/api/v1/organizer/events/$eid/journal'),
      ]);
      if (mounted) {
        setState(() {
          _detailsError = null;
          _stats = OrganizerStats.fromJson(results[0]);
          _participants = (results[1]['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          _assignedControllers = (results[2]['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          _journal = (results[3]['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _detailsError = e.toString());
    }
  }

  Future<void> _openCreateEvent() async {
    final createdId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => EventEditorScreen(auth: widget.auth)),
    );
    if (createdId != null) {
      _selectedEventId = createdId;
      _participantTypeId = '';
      await _loadEvents();
    }
  }

  Future<void> _openEditEvent(EventItem ev) async {
    final hasRegs = (ev.capacity - ev.freeSeats) > 0;
    final editedId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EventEditorScreen(
          auth: widget.auth,
          existingEvent: ev,
          existingTypes: _stats?.eventId == ev.id ? _stats!.byType : const [],
          hasRegistrations: hasRegs,
        ),
      ),
    );
    if (editedId != null) {
      await _loadEvents();
    }
  }

  Future<void> _publishEvent(String eventId) async {
    try {
      await widget.auth.api.post('/api/v1/organizer/events/$eventId/publish');
      await _loadEvents(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Событие опубликовано.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(EfSpacing.lg),
        child: Column(
          children: [EfSkeletonCard(height: 120), EfSkeletonCard(height: 200)],
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(EfSpacing.lg),
        child: EfErrorBanner(message: _error!, onRetry: _loadEvents),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 960;
    final selected = _events.where((e) => e.id == _selectedEventId).firstOrNull;

    final bodyContent = _buildSectionContent(wide, selected);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              EfSpacing.lg, EfSpacing.lg, EfSpacing.lg, EfSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: EfColors.pureCard,
                      borderRadius: BorderRadius.circular(EfRadii.md),
                      border: Border.all(color: EfColors.hairlineBorder),
                    ),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedEventId,
                      items: _events
                          .map((e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(
                                  '${e.title} (${EfLabels.eventStatus(e.status)})',
                                  overflow: TextOverflow.ellipsis,
                                  style: EfTextStyles.body(14,
                                      weight: FontWeight.w600),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedEventId = v;
                          _participantTypeId = '';
                        });
                        _loadSelectedDetails();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: EfSpacing.sm),
              FilledButton.tonalIcon(
                onPressed: _openCreateEvent,
                icon: const Icon(Icons.add),
                label: Text(wide ? 'Создать событие' : 'Создать'),
              ),
            ],
          ),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: EfSpacing.lg, vertical: EfSpacing.xs),
            child: Wrap(
              spacing: EfSpacing.sm,
              runSpacing: EfSpacing.xs,
              children: [
                if (selected.status == 'DRAFT')
                  FilledButton.icon(
                    onPressed: () => _publishEvent(selected.id),
                    icon: const Icon(Icons.publish_rounded, size: 18),
                    label: const Text('Опубликовать'),
                  ),
                if (selected.status != 'CANCELLED')
                  OutlinedButton.icon(
                    onPressed: () => _openEditEvent(selected),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Редактировать'),
                  ),
                if (selected.status != 'CANCELLED')
                  OutlinedButton.icon(
                    onPressed: _cancelSelected,
                    icon: const Icon(Icons.cancel_outlined,
                        size: 18, color: EfColors.coral),
                    label: Text('Отменить',
                        style: EfTextStyles.body(13,
                            weight: FontWeight.w600, color: EfColors.coral)),
                  ),
              ],
            ),
          ),
        if (_detailsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: EfSpacing.lg, vertical: EfSpacing.xs),
            child: EfErrorBanner(
                message: _detailsError!, onRetry: _loadSelectedDetails),
          ),
        if (!wide)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: EfSpacing.lg, vertical: EfSpacing.sm),
            child: Row(
              children: List.generate(_sections.length, (i) {
                final (label, icon) = _sections[i];
                final active = _sectionIdx == i;
                return Padding(
                  padding: const EdgeInsets.only(right: EfSpacing.sm),
                  child: ChoiceChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: active,
                    onSelected: (_) => setState(() => _sectionIdx = i),
                  ),
                );
              }),
            ),
          ),
        const Divider(height: 1, color: EfColors.hairlineBorder),
        Expanded(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 210,
                      color: EfColors.pureCard,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(EfSpacing.md),
                        itemCount: _sections.length,
                        itemBuilder: (_, i) {
                          final (label, icon) = _sections[i];
                          final active = _sectionIdx == i;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              selected: active,
                              selectedTileColor: EfColors.emeraldTint,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(EfRadii.md),
                              ),
                              leading: Icon(icon,
                                  color: active
                                      ? EfColors.emeraldDark
                                      : EfColors.mutedSlate),
                              title: Text(
                                label,
                                style: EfTextStyles.body(14,
                                    weight: active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: active
                                        ? EfColors.emeraldDark
                                        : EfColors.deepInk),
                              ),
                              onTap: () => setState(() => _sectionIdx = i),
                            ),
                          );
                        },
                      ),
                    ),
                    const VerticalDivider(
                        width: 1, color: EfColors.hairlineBorder),
                    Expanded(child: bodyContent),
                  ],
                )
              : bodyContent,
        ),
      ],
    );
  }

  Widget _buildSectionContent(bool wide, EventItem? selected) {
    return switch (_sectionIdx) {
      0 => _buildOverview(),
      1 => _buildEventsList(),
      2 => _buildParticipants(wide),
      3 => _buildControllers(),
      _ => _buildJournal(wide),
    };
  }

  Widget _buildOverview() {
    if (_stats == null) {
      return const Padding(
        padding: EdgeInsets.all(EfSpacing.lg),
        child: Column(children: [EfSkeletonCard(height: 150)]),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(EfSpacing.lg),
      children: [
        Wrap(
          spacing: EfSpacing.md,
          runSpacing: EfSpacing.md,
          children: [
            _StatCard(
                label: 'Выдано билетов',
                value: '${_stats!.issuedCount} / ${_stats!.capacity}'),
            _StatCard(
                label: 'Вошли в зал',
                value: '${_stats!.usedCount}',
                accent: EfColors.emeraldDark),
            _StatCard(label: 'Свободно мест', value: '${_stats!.freeSeats}'),
            _StatCard(
                label: 'Отменено',
                value: '${_stats!.cancelledCount}',
                accent: EfColors.coral),
            _StatCard(label: 'Всего сканов', value: '${_stats!.scansTotal}'),
            _StatCard(
                label: 'Входов за 24 ч', value: '${_stats!.last24hEntries}'),
          ],
        ),
        const SizedBox(height: EfSpacing.lg),
        EfCapacityBar(
            occupied: _stats!.issuedCount, capacity: _stats!.capacity),
        const SizedBox(height: EfSpacing.xl),
        Text('Входы по времени', style: EfTextStyles.display(18)),
        const SizedBox(height: EfSpacing.sm),
        _TimelineChart(buckets: _stats!.timeline),
        const SizedBox(height: EfSpacing.xl),
        Text('По категориям', style: EfTextStyles.display(18)),
        const SizedBox(height: EfSpacing.md),
        ..._stats!.byType.map((t) => Card(
              margin: const EdgeInsets.only(bottom: EfSpacing.sm),
              child: ListTile(
                title: Text(t.name,
                    style: EfTextStyles.body(15, weight: FontWeight.w600)),
                subtitle: Text(
                    'Занято: ${t.occupied} из ${t.capacity} • Вошли: ${t.usedCount}',
                    style: EfTextStyles.mono(12)),
                trailing: EfStatusPill(
                  label: 'Осталось ${t.remaining}',
                  icon: Icons.event_seat_outlined,
                  tone: t.remaining > 0 ? EfTone.positive : EfTone.warning,
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildEventsList() {
    if (_events.isEmpty) {
      return EfEmptyState(
        icon: Icons.event_outlined,
        title: 'Нет мероприятий',
        subtitle: 'Создайте первое событие и настройте категории билетов.',
        actionLabel: 'Создать событие',
        onAction: _openCreateEvent,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(EfSpacing.lg),
      itemCount: _events.length,
      itemBuilder: (_, i) {
        final ev = _events[i];
        final occupied = (ev.capacity - ev.freeSeats).clamp(0, ev.capacity);
        return Card(
          margin: const EdgeInsets.only(bottom: EfSpacing.md),
          child: Padding(
            padding: const EdgeInsets.all(EfSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(ev.title, style: EfTextStyles.display(18)),
                    ),
                    EfStatusPill(
                      label: EfLabels.eventStatus(ev.status),
                      icon: ev.status == 'PUBLISHED'
                          ? Icons.check_circle_outline
                          : (ev.status == 'DRAFT'
                              ? Icons.edit_note_rounded
                              : Icons.cancel_outlined),
                      tone: ev.status == 'PUBLISHED'
                          ? EfTone.positive
                          : (ev.status == 'DRAFT'
                              ? EfTone.warning
                              : EfTone.danger),
                    ),
                  ],
                ),
                const SizedBox(height: EfSpacing.xs),
                Text(
                  '${EfDateFmt.shortDateTime(ev.startsAt, timezone: ev.timezone)} • ${ev.city}, ${ev.location}',
                  style: EfTextStyles.body(13, color: EfColors.mutedSlate),
                ),
                const SizedBox(height: EfSpacing.md),
                EfCapacityBar(occupied: occupied, capacity: ev.capacity),
                const SizedBox(height: EfSpacing.md),
                Wrap(
                  spacing: EfSpacing.sm,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedEventId = ev.id;
                          _sectionIdx = 0;
                        });
                        _loadSelectedDetails();
                      },
                      child: const Text('Открыть обзор'),
                    ),
                    if (ev.status != 'CANCELLED')
                      OutlinedButton(
                        onPressed: () => _openEditEvent(ev),
                        child: const Text('Редактировать'),
                      ),
                    if (ev.status == 'DRAFT')
                      FilledButton(
                        onPressed: () => _publishEvent(ev.id),
                        child: const Text('Опубликовать'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildParticipants(bool wide) {
    final types = _stats?.byType ?? const <TicketTypeItem>[];
    return ListView(
      padding: const EdgeInsets.all(EfSpacing.lg),
      children: [
        Wrap(
          spacing: EfSpacing.md,
          runSpacing: EfSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: wide ? 300 : double.infinity,
              child: TextField(
                decoration: const InputDecoration(
                    labelText: 'Поиск по имени или коду EF-...'),
                onChanged: (v) {
                  _participantSearch = v.trim();
                  _loadSelectedDetails();
                },
              ),
            ),
            DropdownButton<String>(
              value: types.any((t) => t.id == _participantTypeId)
                  ? _participantTypeId
                  : '',
              items: [
                const DropdownMenuItem(value: '', child: Text('Все категории')),
                ...types.map(
                    (t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
              ],
              onChanged: (v) {
                _participantTypeId = v ?? '';
                _loadSelectedDetails();
              },
            ),
            DropdownButton<String>(
              value: _participantStatus,
              items: const [
                DropdownMenuItem(value: '', child: Text('Все статусы')),
                DropdownMenuItem(value: 'ISSUED', child: Text('Действителен')),
                DropdownMenuItem(value: 'USED', child: Text('Использован')),
                DropdownMenuItem(value: 'CANCELLED', child: Text('Отменён')),
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
        else if (wide)
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(EfColors.warmStone),
                columns: const [
                  DataColumn(label: Text('Код')),
                  DataColumn(label: Text('Участник')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Категория')),
                  DataColumn(label: Text('Статус')),
                ],
                rows: _participants.map((p) {
                  final st = p['status'] as String;
                  return DataRow(cells: [
                    DataCell(Text(p['code'] as String,
                        style: EfTextStyles.mono(13))),
                    DataCell(Text(p['participant_name'] as String)),
                    DataCell(Text(p['participant_email'] as String)),
                    DataCell(Text(p['type_name'] as String)),
                    DataCell(EfStatusPill(
                      label: EfLabels.ticketStatus(st),
                      icon: Icons.confirmation_number_outlined,
                      tone: st == 'USED'
                          ? EfTone.positive
                          : (st == 'CANCELLED'
                              ? EfTone.danger
                              : EfTone.neutral),
                    )),
                  ]);
                }).toList(),
              ),
            ),
          )
        else
          ..._participants.map((p) {
            final st = p['status'] as String;
            return Card(
              margin: const EdgeInsets.only(bottom: EfSpacing.sm),
              child: ListTile(
                title: Text('${p['participant_name']} (${p['code']})',
                    style: EfTextStyles.body(14, weight: FontWeight.w600)),
                subtitle: Text('${p['type_name']} • ${p['participant_email']}',
                    style: EfTextStyles.body(12, color: EfColors.mutedSlate)),
                trailing: EfStatusPill(
                  label: EfLabels.ticketStatus(st),
                  icon: Icons.confirmation_number_outlined,
                  tone: st == 'USED'
                      ? EfTone.positive
                      : (st == 'CANCELLED' ? EfTone.danger : EfTone.neutral),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildControllers() {
    return ListView(
      padding: const EdgeInsets.all(EfSpacing.lg),
      children: _allControllers.map((c) {
        final cid = c['id'] as String;
        final isAssigned = _assignedControllers.any((a) => a['id'] == cid);
        return Card(
          margin: const EdgeInsets.only(bottom: EfSpacing.sm),
          child: SwitchListTile(
            title: Text(c['name'] as String,
                style: EfTextStyles.body(15, weight: FontWeight.w600)),
            subtitle: Text(c['email'] as String,
                style: EfTextStyles.body(13, color: EfColors.mutedSlate)),
            value: isAssigned,
            onChanged: (val) => _toggleController(cid, val),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildJournal(bool wide) {
    if (_journal.isEmpty) {
      return const EfEmptyState(
        icon: Icons.history,
        title: 'Журнал пуст',
        subtitle: 'События регистрации и проверки входа появятся здесь.',
      );
    }
    if (wide) {
      return ListView(
        padding: const EdgeInsets.all(EfSpacing.lg),
        children: [
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(EfColors.warmStone),
                columns: const [
                  DataColumn(label: Text('Время (сервер)')),
                  DataColumn(label: Text('Операция')),
                  DataColumn(label: Text('Результат')),
                  DataColumn(label: Text('Билет')),
                  DataColumn(label: Text('Инициатор')),
                ],
                rows: _journal.map((j) {
                  final time = DateTime.parse(j['server_time'] as String);
                  return DataRow(cells: [
                    DataCell(Text(EfDateFmt.dateTimeSeconds(time),
                        style: EfTextStyles.mono(12))),
                    DataCell(Text(EfLabels.auditAction(j['action'] as String))),
                    DataCell(Text(EfLabels.auditResult(j['result'] as String))),
                    DataCell(Text((j['ticket_code'] as String?) ?? '—',
                        style: EfTextStyles.mono(12))),
                    DataCell(Text((j['actor_name'] as String?) ?? 'Система')),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(EfSpacing.lg),
      children: _journal.map((j) {
        final time = DateTime.parse(j['server_time'] as String);
        return Card(
          margin: const EdgeInsets.only(bottom: EfSpacing.sm),
          child: ListTile(
            leading: Text(EfDateFmt.timeOnly(time),
                style: EfTextStyles.mono(12, color: EfColors.mutedSlate)),
            title: Text(
              '${EfLabels.auditAction(j['action'] as String)} — ${EfLabels.auditResult(j['result'] as String)}',
              style: EfTextStyles.body(14, weight: FontWeight.w600),
            ),
            subtitle: Text(
              '${j['actor_name'] ?? 'Система'} ${j['ticket_code'] != null ? '• ${j['ticket_code']}' : ''}',
              style: EfTextStyles.body(12, color: EfColors.mutedSlate),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TimelineChart extends StatelessWidget {
  final List<TimelineBucket> buckets;
  const _TimelineChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(EfSpacing.lg),
        decoration: BoxDecoration(
          color: EfColors.pureCard,
          borderRadius: BorderRadius.circular(EfRadii.lg),
          border: Border.all(color: EfColors.hairlineBorder),
        ),
        child: Text(
          'Пока нет зафиксированных входов. График появится после первого сканирования.',
          style: EfTextStyles.body(13, color: EfColors.mutedSlate),
        ),
      );
    }

    final maxCount = buckets.fold<int>(1, (m, b) => b.count > m ? b.count : m);

    return Container(
      padding: const EdgeInsets.all(EfSpacing.lg),
      decoration: BoxDecoration(
        color: EfColors.pureCard,
        borderRadius: BorderRadius.circular(EfRadii.lg),
        border: Border.all(color: EfColors.hairlineBorder),
      ),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: buckets.map((b) {
            final frac = (b.count / maxCount).clamp(0.12, 1.0);
            final hourLabel =
                '${b.bucket.toLocal().hour.toString().padLeft(2, '0')}:00';
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${b.count}', style: EfTextStyles.mono(11)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: frac,
                          child: Container(
                            width: 28,
                            decoration: BoxDecoration(
                              color: EfColors.emerald,
                              borderRadius: BorderRadius.circular(EfRadii.sm),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(hourLabel,
                        style:
                            EfTextStyles.mono(10, color: EfColors.mutedSlate)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
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
      width: 168,
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

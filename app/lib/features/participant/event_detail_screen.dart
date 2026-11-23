import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/auth_store.dart';
import '../../core/models/models.dart';
import '../../design/tokens.dart';
import '../../design/widgets/ef_widgets.dart';

class EventDetailScreen extends StatefulWidget {
  final AuthStore auth;
  final String eventId;

  const EventDetailScreen({
    super.key,
    required this.auth,
    required this.eventId,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  EventItem? _event;
  TicketItem? _myActiveTicket;
  String? _selectedTypeId;
  String? _pendingRequestId;

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
      final evJson =
          await widget.auth.api.get('/api/v1/events/${widget.eventId}');
      final ev = EventItem.fromJson(evJson);

      TicketItem? activeTicket;
      final myRes = await widget.auth.api.get('/api/v1/tickets/my');
      final myList = (myRes['items'] as List<dynamic>)
          .map((e) => TicketItem.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final t in myList) {
        if (t.eventId == widget.eventId &&
            (t.status == 'ISSUED' || t.status == 'USED')) {
          activeTicket = t;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _event = ev;
          _myActiveTicket = activeTicket;
          _selectedTypeId ??=
              ev.ticketTypes.isNotEmpty ? ev.ticketTypes.first.id : null;
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

  Future<void> _register() async {
    if (_selectedTypeId == null || _submitting) return;
    _pendingRequestId ??= const Uuid().v4();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.auth.api
          .post('/api/v1/events/${widget.eventId}/register', body: {
        'type_id': _selectedTypeId,
        'request_id': _pendingRequestId,
      });
      _pendingRequestId = null;
      final outcome = res['outcome'] as String;
      if (!mounted) return;

      if (outcome == 'ISSUED' || outcome == 'ALREADY_REGISTERED') {
        final t = TicketItem.fromJson(res['ticket'] as Map<String, dynamic>);
        setState(() => _myActiveTicket = t);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome == 'ISSUED'
                  ? 'Билет ${t.code} успешно оформлен!'
                  : 'У вас уже есть действующий билет ${t.code}.',
            ),
          ),
        );
        await _load();
      } else {
        final msg = switch (outcome) {
          'SOLD_OUT' => 'Места в выбранной категории закончились (SOLD_OUT).',
          'CLOSED' => 'Регистрация на событие закрыта (CLOSED).',
          'CANCELLED' => 'Событие отменено организатором (CANCELLED).',
          _ => 'Регистрация отклонена: $outcome',
        };
        setState(() => _error = msg);
        await _load();
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'Ошибка связи: $e. Нажмите повторно — запрос безопасен.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMMM yyyy, HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Событие')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _event == null
              ? EfErrorBanner(
                  message: _error ?? 'Не удалось загрузить событие',
                  onRetry: _load)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(EfSpacing.lg),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          EfStatusPill(
                            label: '${_event!.category} • ${_event!.city}',
                            icon: Icons.place_outlined,
                            tone: EfTone.neutral,
                          ),
                          const SizedBox(height: EfSpacing.md),
                          Text(_event!.title, style: EfTextStyles.display(28)),
                          const SizedBox(height: EfSpacing.sm),
                          Text(
                            '${df.format(_event!.startsAt.toLocal())} (${_event!.timezone}) • ${_event!.location}',
                            style: EfTextStyles.body(14,
                                color: EfColors.mutedSlate),
                          ),
                          if (_event!.organizerName != null) ...[
                            const SizedBox(height: EfSpacing.xs),
                            Text(
                              'Организатор: ${_event!.organizerName}',
                              style: EfTextStyles.body(13,
                                  color: EfColors.mutedSlate),
                            ),
                          ],
                          const SizedBox(height: EfSpacing.lg),
                          Text(_event!.description,
                              style: EfTextStyles.body(15)),
                          const SizedBox(height: EfSpacing.xl),
                          if (_error != null) ...[
                            EfErrorBanner(message: _error!, onRetry: _load),
                            const SizedBox(height: EfSpacing.lg),
                          ],
                          if (_myActiveTicket != null)
                            EfPerforatedTicketCard(
                              top: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Ваш билет',
                                          style: EfTextStyles.display(20)),
                                      EfStatusPill(
                                        label:
                                            _myActiveTicket!.status == 'ISSUED'
                                                ? 'ДЕЙСТВИТЕЛЕН'
                                                : 'ИСПОЛЬЗОВАН',
                                        icon:
                                            _myActiveTicket!.status == 'ISSUED'
                                                ? Icons.check_circle_outline
                                                : Icons.verified_outlined,
                                        tone:
                                            _myActiveTicket!.status == 'ISSUED'
                                                ? EfTone.positive
                                                : EfTone.warning,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: EfSpacing.sm),
                                  Text(
                                    '${_myActiveTicket!.typeName ?? ''} • ${_myActiveTicket!.code}',
                                    style: EfTextStyles.mono(15),
                                  ),
                                ],
                              ),
                              bottom: Column(
                                children: [
                                  if (_myActiveTicket!.qrToken != null) ...[
                                    Container(
                                      padding:
                                          const EdgeInsets.all(EfSpacing.md),
                                      decoration: BoxDecoration(
                                        color: EfColors.pureCard,
                                        borderRadius:
                                            BorderRadius.circular(EfRadii.md),
                                        border: Border.all(
                                            color: EfColors.hairlineBorder),
                                      ),
                                      child: QrImageView(
                                        data: _myActiveTicket!.qrToken!,
                                        version: QrVersions.auto,
                                        size: 200,
                                      ),
                                    ),
                                    const SizedBox(height: EfSpacing.md),
                                    SelectableText(
                                      _myActiveTicket!.qrToken!,
                                      style: EfTextStyles.mono(12,
                                          color: EfColors.mutedSlate),
                                      textAlign: TextAlign.center,
                                    ),
                                  ] else
                                    Text(
                                      'Вход уже зафиксирован.',
                                      style: EfTextStyles.body(14,
                                          color: EfColors.mutedSlate),
                                    ),
                                ],
                              ),
                            )
                          else ...[
                            Text('Категории билетов',
                                style: EfTextStyles.display(20)),
                            const SizedBox(height: EfSpacing.md),
                            ..._event!.ticketTypes.map((tt) {
                              final selected = _selectedTypeId == tt.id;
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: EfSpacing.sm),
                                child: RadioListTile<String>(
                                  value: tt.id,
                                  groupValue: _selectedTypeId,
                                  onChanged: tt.remaining > 0
                                      ? (v) =>
                                          setState(() => _selectedTypeId = v)
                                      : null,
                                  tileColor: selected
                                      ? EfColors.emeraldTint
                                      : EfColors.pureCard,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(EfRadii.md),
                                    side: BorderSide(
                                      color: selected
                                          ? EfColors.emerald
                                          : EfColors.hairlineBorder,
                                    ),
                                  ),
                                  title: Text(tt.name,
                                      style: EfTextStyles.body(15,
                                          weight: FontWeight.w600)),
                                  subtitle: Text(
                                    tt.remaining > 0
                                        ? 'Осталось мест: ${tt.remaining} из ${tt.capacity}'
                                        : 'Мест нет',
                                    style: EfTextStyles.mono(12,
                                        color: EfColors.mutedSlate),
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: EfSpacing.lg),
                            FilledButton(
                              onPressed: (_event!.status == 'PUBLISHED' &&
                                      !_submitting &&
                                      _selectedTypeId != null)
                                  ? _register
                                  : null,
                              child: _submitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: EfColors.pureCard),
                                    )
                                  : const Text(
                                      'Зарегистрироваться и получить QR'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}

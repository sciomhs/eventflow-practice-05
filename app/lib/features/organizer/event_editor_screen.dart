import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../core/date_fmt.dart';
import '../../core/models/models.dart';
import '../../core/validators.dart';
import '../../design/tokens.dart';
import '../../design/widgets/ef_widgets.dart';

class _CategoryRow {
  final TextEditingController nameCtrl;
  final TextEditingController capCtrl;
  final int minCapacity;

  _CategoryRow({
    required String name,
    required int capacity,
    this.minCapacity = 1,
  })  : nameCtrl = TextEditingController(text: name),
        capCtrl = TextEditingController(text: '$capacity');

  void dispose() {
    nameCtrl.dispose();
    capCtrl.dispose();
  }
}

class EventEditorScreen extends StatefulWidget {
  final AuthStore auth;
  final EventItem? existingEvent;
  final List<TicketTypeItem> existingTypes;
  final bool hasRegistrations;

  const EventEditorScreen({
    super.key,
    required this.auth,
    this.existingEvent,
    this.existingTypes = const [],
    this.hasRegistrations = false,
  });

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _locCtrl;

  late String _category;
  late String _timezone;
  late DateTime _startsAt;
  late DateTime _endsAt;
  late DateTime _regCloses;
  late DateTime _admOpens;
  late DateTime _admCloses;
  late List<_CategoryRow> _categories;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existingEvent != null;
  bool get _lockedTimes => _isEdit && widget.hasRegistrations;

  @override
  void initState() {
    super.initState();
    final ev = widget.existingEvent;
    final now = DateTime.now();
    _titleCtrl = TextEditingController(text: ev?.title ?? '');
    _descCtrl = TextEditingController(text: ev?.description ?? '');
    _cityCtrl = TextEditingController(text: ev?.city ?? 'Екатеринбург');
    _locCtrl = TextEditingController(text: ev?.location ?? '');
    _category = ev?.category ?? 'Технологии';
    _timezone = ev?.timezone ?? 'Asia/Yekaterinburg';

    _startsAt = (ev?.startsAt ?? now.add(const Duration(hours: 2))).toLocal();
    _endsAt = (ev?.endsAt ?? now.add(const Duration(hours: 6))).toLocal();
    _regCloses = (ev?.registrationClosesAt ??
            now.add(const Duration(hours: 1, minutes: 30)))
        .toLocal();
    _admOpens =
        (ev?.admissionOpensAt ?? now.subtract(const Duration(minutes: 15)))
            .toLocal();
    _admCloses =
        (ev?.admissionClosesAt ?? now.add(const Duration(hours: 5))).toLocal();

    if (widget.existingTypes.isNotEmpty) {
      _categories = widget.existingTypes
          .map((t) => _CategoryRow(
                name: t.name,
                capacity: t.capacity,
                minCapacity: _lockedTimes ? t.capacity : 1,
              ))
          .toList();
    } else {
      _categories = [
        _CategoryRow(name: 'Стандарт', capacity: 40),
        _CategoryRow(name: 'VIP', capacity: 10),
      ];
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _cityCtrl.dispose();
    _locCtrl.dispose();
    for (final c in _categories) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalCapacity {
    int sum = 0;
    for (final c in _categories) {
      sum += int.tryParse(c.capCtrl.text.trim()) ?? 0;
    }
    return sum;
  }

  Future<void> _pickDateTime(
    DateTime current,
    ValueChanged<DateTime> onPicked,
  ) async {
    if (_lockedTimes) return;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    onPicked(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  String? _validateDates() {
    if (!_startsAt.isBefore(_endsAt)) {
      return 'Время начала должно быть раньше времени окончания.';
    }
    if (!_admOpens.isBefore(_admCloses)) {
      return 'Открытие допуска должно быть раньше закрытия допуска.';
    }
    if (_regCloses.isAfter(_startsAt)) {
      return 'Срок регистрации не может быть позже начала события.';
    }
    if (_admOpens.isAfter(_startsAt) || _admCloses.isBefore(_startsAt)) {
      return 'Окно допуска должно включать время начала события.';
    }
    return null;
  }

  Future<void> _save({bool publishAfter = false}) async {
    if (!_formKey.currentState!.validate()) return;
    final dateErr = _validateDates();
    if (dateErr != null) {
      setState(() => _error = dateErr);
      return;
    }
    if (_categories.length < 2) {
      setState(() => _error = 'Требуется минимум две категории билетов.');
      return;
    }

    final typesPayload = <Map<String, dynamic>>[];
    int totalCap = 0;
    for (final c in _categories) {
      final cap = int.parse(c.capCtrl.text.trim());
      if (cap < c.minCapacity) {
        setState(() => _error =
            'После первой регистрации лимит «${c.nameCtrl.text.trim()}» нельзя уменьшить ниже ${c.minCapacity}.');
        return;
      }
      totalCap += cap;
      typesPayload.add({'name': c.nameCtrl.text.trim(), 'capacity': cap});
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      String eventId;
      if (_isEdit) {
        eventId = widget.existingEvent!.id;
        final body = <String, dynamic>{
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'category': _category,
          'city': _cityCtrl.text.trim(),
          'location': _locCtrl.text.trim(),
          'capacity': totalCap,
          'ticket_types': typesPayload,
        };
        if (!_lockedTimes) {
          body['starts_at'] = _startsAt.toUtc().toIso8601String();
          body['ends_at'] = _endsAt.toUtc().toIso8601String();
          body['registration_closes_at'] = _regCloses.toUtc().toIso8601String();
          body['admission_opens_at'] = _admOpens.toUtc().toIso8601String();
          body['admission_closes_at'] = _admCloses.toUtc().toIso8601String();
        }
        await widget.auth.api
            .patch('/api/v1/organizer/events/$eventId', body: body);
      } else {
        final created =
            await widget.auth.api.post('/api/v1/organizer/events', body: {
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'category': _category,
          'city': _cityCtrl.text.trim(),
          'location': _locCtrl.text.trim(),
          'starts_at': _startsAt.toUtc().toIso8601String(),
          'ends_at': _endsAt.toUtc().toIso8601String(),
          'timezone': _timezone,
          'registration_closes_at': _regCloses.toUtc().toIso8601String(),
          'admission_opens_at': _admOpens.toUtc().toIso8601String(),
          'admission_closes_at': _admCloses.toUtc().toIso8601String(),
          'capacity': totalCap,
          'ticket_types': typesPayload,
        });
        eventId = created['id'] as String;
        if (publishAfter) {
          await widget.auth.api
              .post('/api/v1/organizer/events/$eventId/publish');
        }
      }

      if (mounted) Navigator.pop(context, eventId);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Редактирование события' : 'Новое мероприятие'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(EfSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_lockedTimes)
                    Container(
                      margin: const EdgeInsets.only(bottom: EfSpacing.lg),
                      padding: const EdgeInsets.all(EfSpacing.md),
                      decoration: BoxDecoration(
                        color: EfColors.amberTint,
                        borderRadius: BorderRadius.circular(EfRadii.md),
                        border: Border.all(
                            color: EfColors.amber.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_clock_outlined,
                              color: EfColors.amber),
                          const SizedBox(width: EfSpacing.md),
                          Expanded(
                            child: Text(
                              'По событию уже есть регистрации. Перенос времени заблокирован, а лимиты можно только увеличивать.',
                              style: EfTextStyles.body(13,
                                  weight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null) ...[
                    EfErrorBanner(message: _error!),
                    const SizedBox(height: EfSpacing.md),
                  ],
                  TextFormField(
                    controller: _titleCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Название события'),
                    validator: (v) =>
                        EfValidators.requiredText(v, field: 'Название'),
                  ),
                  const SizedBox(height: EfSpacing.md),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'Описание'),
                    maxLines: 3,
                    validator: (v) =>
                        EfValidators.requiredText(v, field: 'Описание'),
                  ),
                  const SizedBox(height: EfSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _category,
                          decoration:
                              const InputDecoration(labelText: 'Категория'),
                          items: const ['Технологии', 'Дизайн', 'Хакатон']
                              .map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _category = v ?? 'Технологии'),
                        ),
                      ),
                      const SizedBox(width: EfSpacing.md),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _timezone,
                          decoration:
                              const InputDecoration(labelText: 'Часовой пояс'),
                          items: const [
                            'Asia/Yekaterinburg',
                            'Europe/Moscow',
                            'Europe/Samara',
                            'Asia/Novosibirsk',
                            'UTC',
                          ]
                              .map((tz) =>
                                  DropdownMenuItem(value: tz, child: Text(tz)))
                              .toList(),
                          onChanged: _lockedTimes
                              ? null
                              : (v) => setState(
                                  () => _timezone = v ?? 'Asia/Yekaterinburg'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: EfSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cityCtrl,
                          decoration: const InputDecoration(labelText: 'Город'),
                          validator: (v) =>
                              EfValidators.requiredText(v, field: 'Город'),
                        ),
                      ),
                      const SizedBox(width: EfSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _locCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Площадка / зал'),
                          validator: (v) =>
                              EfValidators.requiredText(v, field: 'Площадка'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: EfSpacing.xl),
                  Text('Расписание и окна допуска',
                      style: EfTextStyles.display(18)),
                  const SizedBox(height: EfSpacing.sm),
                  _DateTile(
                    label: 'Начало события',
                    value: _startsAt,
                    locked: _lockedTimes,
                    onTap: () => _pickDateTime(
                        _startsAt, (d) => setState(() => _startsAt = d)),
                  ),
                  _DateTile(
                    label: 'Окончание события',
                    value: _endsAt,
                    locked: _lockedTimes,
                    onTap: () => _pickDateTime(
                        _endsAt, (d) => setState(() => _endsAt = d)),
                  ),
                  _DateTile(
                    label: 'Закрытие регистрации',
                    value: _regCloses,
                    locked: _lockedTimes,
                    onTap: () => _pickDateTime(
                        _regCloses, (d) => setState(() => _regCloses = d)),
                  ),
                  _DateTile(
                    label: 'Открытие допуска',
                    value: _admOpens,
                    locked: _lockedTimes,
                    onTap: () => _pickDateTime(
                        _admOpens, (d) => setState(() => _admOpens = d)),
                  ),
                  _DateTile(
                    label: 'Закрытие допуска',
                    value: _admCloses,
                    locked: _lockedTimes,
                    onTap: () => _pickDateTime(
                        _admCloses, (d) => setState(() => _admCloses = d)),
                  ),
                  const SizedBox(height: EfSpacing.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Категории билетов (вместимость: $_totalCapacity)',
                          style: EfTextStyles.display(18)),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _categories.add(_CategoryRow(
                              name: 'Категория ${_categories.length + 1}',
                              capacity: 10));
                        }),
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: EfSpacing.sm),
                  ...List.generate(_categories.length, (i) {
                    final row = _categories[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: EfSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: row.nameCtrl,
                              readOnly: _lockedTimes,
                              decoration: const InputDecoration(
                                  labelText: 'Название категории'),
                              validator: (v) => EfValidators.requiredText(v,
                                  field: 'Название'),
                            ),
                          ),
                          const SizedBox(width: EfSpacing.md),
                          Expanded(
                            child: TextFormField(
                              controller: row.capCtrl,
                              decoration:
                                  const InputDecoration(labelText: 'Лимит'),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              validator: (v) =>
                                  EfValidators.positiveInt(v, field: 'Лимит'),
                            ),
                          ),
                          if (_categories.length > 2 && !_lockedTimes)
                            IconButton(
                              tooltip: 'Удалить категорию',
                              onPressed: () => setState(() {
                                _categories.removeAt(i).dispose();
                              }),
                              icon: const Icon(Icons.delete_outline,
                                  color: EfColors.coral),
                            ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: EfSpacing.xl),
                  if (_isEdit)
                    FilledButton(
                      onPressed: _saving ? null : () => _save(),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: EfColors.pureCard),
                            )
                          : const Text('Сохранить изменения'),
                    )
                  else
                    Wrap(
                      spacing: EfSpacing.md,
                      runSpacing: EfSpacing.sm,
                      children: [
                        OutlinedButton(
                          onPressed:
                              _saving ? null : () => _save(publishAfter: false),
                          child: const Text('Сохранить черновик'),
                        ),
                        FilledButton(
                          onPressed:
                              _saving ? null : () => _save(publishAfter: true),
                          child: const Text('Создать и опубликовать'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime value;
  final bool locked;
  final VoidCallback onTap;

  const _DateTile({
    required this.label,
    required this.value,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: EfSpacing.xs),
      child: ListTile(
        enabled: !locked,
        onTap: onTap,
        title:
            Text(label, style: EfTextStyles.body(14, weight: FontWeight.w600)),
        subtitle: Text(EfDateFmt.fullDateTime(value),
            style: EfTextStyles.mono(12, color: EfColors.mutedSlate)),
        trailing: Icon(
          locked ? Icons.lock_outline : Icons.edit_calendar_outlined,
          size: 20,
          color: locked ? EfColors.mutedSlate : EfColors.emeraldDark,
        ),
      ),
    );
  }
}
